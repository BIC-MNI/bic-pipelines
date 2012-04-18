#!/usr/bin/env perl

# an abbreviated version of mritotal (less options), fitting
# nonlinearly up to and including level 4b, and using the minctracc
# parameters optimised by Steve Robbins. Assumes a volume that starts
# in talairach space.

# Author: Jason Lerch <jason@bic.mni.mcgill.ca>
# Date: August 2003
use strict;
use Getopt::Long;
use File::Basename;
use File::Temp qw/ tempdir /;
use MNI::Spawn;
   
MNI::Spawn::SetOptions (verbose => 0,execute => 1,strict  => 0);  

#my(%opt);
#$opt{verbose} = 1;
#$opt{fake} = 0;
my $fake=0;

my $me= basename($0);
# ======= Global variables =======
my $modelDir ;
my $model;
my ($input_mnc, $input_xfm, $output, $basename);
my ($help, $usage);

#intermediate outputs
my ($blur8, $blur4);
my ($out16, $out8);

# default minctracc parameters
my $weight = 1;
my $stiffness = 1;
my $similarity = 0.3;

my $verbose = 1;
my($clobber) = 0;
my($datamask) = 0;
my($mask) = 0;
my($tal) = 0;

# ======= Argument processing ====

GetOptions(
	  
	   'verbose' => \$verbose,
	   'clobber' => \$clobber,
	   'tal'=> \$tal,
	   'datamask'=> \$datamask,
	   'mask'=> \$mask,
     'model_dir=s'    => \$modelDir,
     'model_name=s'   => \$model
	   );

if ($#ARGV < 4){ die "Usage: $me <input.mnc> <input_lin.xfm> <input_mask.mnc> <output_grid.mnc> <output.xfm> [--tal --datamask --mask --model_dir <dir> --model_name <basename> ] \n"; }

$input_mnc = $ARGV[0];
$input_xfm = $ARGV[1];
my $mask_file = $ARGV[2];
#  HUH? $output_grid is NEVER used.  LB
my $output_grid = $ARGV[3];
my $output_xfm = $ARGV[4];

print "$input_mnc\n$input_xfm\n$mask_file\n$output_grid\n$output_xfm\n" if $verbose;

if(-e $output_grid && -e $output_xfm  && !$clobber)
{
    print("$output_grid and $output_xfm exists");
    exit;
}
# create a basename from the input file
#  HUH? $basename is never used. Commenting it out. LB
#$basename = $input_mnc;
#$basename =~ s|.+/(.+).mnc.*|$1|;

# register the programmes
RegisterPrograms(["mincblur", "mincmask","rm"]);

# make tmpdir
my $me = &basename($0);
my $tmpdir = &tempdir( "$me-XXXXXXXX", TMPDIR => 1, CLEANUP => 1 );
# and temp files
my $blur8_base = "$tmpdir/tmp_8";
my $blur4_base = "$tmpdir/tmp_4";
$blur8 = $blur8_base . "_blur.mnc";
$blur4 = $blur4_base . "_blur.mnc";
$out16 = "$tmpdir/tmp_out16.xfm";
$out8 = "$tmpdir/tmp_out8.xfm";

# ensure that the model files actually exist
my $modelFile_8 = "${model}_8_blur.mnc";
my $modelFile_4 = "${model}_4_blur.mnc";

my @modelmaskFiles = ("${model}_8_mask.mnc", "${model}_4_mask.mnc" );

# ======= The real work starts here ===

# blur the target files
# If you pass mincblur the basename of an output file, 
# it will append _blur.mnc to create the output file.
if($datamask)
{
    #my ($dummy, $masked_tal) = File::Temp::tempfile(TMPDIR => 1, CLEANUP => 0);
    my $masked_tal="${tmpdir}/masked_tal.mnc";
    print("mincmask $input_mnc $mask_file $masked_tal\n");
    print("mincblur -fwhm  8 $masked_tal $blur8_base\n");
    print("mincblur -fwhm  4 $masked_tal $blur4_base\n");

    Spawn(["mincmask", $input_mnc, $mask_file, $masked_tal, '-clob']);
    Spawn(["mincblur", "-fwhm", 8, $masked_tal, $blur8_base, '-clob']);
    Spawn(["mincblur", "-fwhm", 4, $masked_tal, $blur4_base, '-clob']);   

}
else
{
    Spawn(["mincblur", "-fwhm", 8, $input_mnc, $blur8_base, '-clob']);
    Spawn(["mincblur", "-fwhm", 4, $input_mnc, $blur4_base, '-clob']);
}


#############################################################################
print STDOUT "*** level 16 registration\n";
my(@args) = ("minctracc","-nonlinear", "corrcoeff",
       "-debug", "-weight", $weight,
       "-stiffness", $stiffness,
       "-similarity", $similarity,
       "-iterations", 60,
       "-step", 8, 8, 8,
       "-sub_lattice", 6,
       "-lattice_diam", 24, 24, 24,
       $blur8, "$modelDir/$modelFile_8", $out16, '-clobber');

if($mask){ 
    push(@args, '-model_mask', "$modelDir/$modelmaskFiles[0]");
    if (-e $mask_file) {
	push(@args, '-source_mask', $mask_file);
    }
} 

if($tal) { 
    push(@args, '-identity');
}	
else
{
    push(@args, '-transformation',$input_xfm);
}


if($verbose)
{
    print("Level 16 Args\n@args");
}
do_cmd(@args);

################################################################################
print STDOUT "*** level 8 registration\n";
@args = ("minctracc","-nonlinear", "corrcoeff",
       "-debug", "-weight", $weight,
       "-stiffness", $stiffness,
       "-similarity", $similarity,
       "-iterations", 60,
       "-step", 4, 4, 4,
       "-sub_lattice", 6,
       "-lattice_diam", 12, 12, 12,
       $blur8, "$modelDir/$modelFile_8", $out8, '-clobber');

if($mask){ 
    push(@args, '-model_mask', "$modelDir/$modelmaskFiles[0]");
    if (-e $mask_file) {
	push(@args, '-source_mask', $mask_file);
    }
} 


push(@args, '-transformation',$out16);


if($verbose)
{
    print("Level 8 Args\n@args");
}
do_cmd(@args);



###############################################################
# level 4 registration

print STDOUT "*** level 4 registration\n";
@args = ("minctracc","-nonlinear", "corrcoeff",
       "-debug", "-weight", $weight,
       "-stiffness", $stiffness,
       "-similarity", $similarity,
       "-iterations", 20,
       "-step", 2, 2, 2,
       "-sub_lattice", 6,
       "-lattice_diam", 6, 6, 6,
       $blur4, "${modelDir}/${modelFile_4}", $output_xfm, '-clobber', '-verbose', 1);

if($mask){ 
    push(@args, '-model_mask', "$modelDir/$modelmaskFiles[1]");
    if (-e $mask_file) {
	push(@args, '-source_mask', $mask_file);
    }
} 

push(@args, '-transformation',$out8);

if($verbose)
{
    print("Level 4 Args\n@args");
}
do_cmd(@args);

####################################################################
# do_cmd( arg1,argv2,.... )
#
# execute given command
#
#####################################################################
sub do_cmd { 
    print STDOUT "@_\n" if $verbose;
    if(!$fake){
	system(@_) == 0 or die "DIED: @_\n";
    }
}

