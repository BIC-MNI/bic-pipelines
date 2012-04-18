#!/usr/bin/env perl
#
# Matthew Kitching
# Script based on original work by Andrew Janke.
# This modified version is used with nihpd database.
#
# Andrew Janke - rotor@bic.mni.mcgill.ca
# Script to register intra-subject data for a given time point
# Wed Feb 13 14:00 2002 - initial version(LC)

#    the procedure will  compute the T2 to T1 registration

use strict;
use Getopt::Long;
use File::Basename;
use File::Temp qw/ tempfile tempdir /;
      
my $me = basename($0);
my $verbose = 0;
my $clobber = 0;
my $dummy = "";
my $fake=0;
my $correct_t1w;
my $correct_t2w;

#############
##get models from constants file.
## Don't worry: Even if inputs are fallback images, it's OK.
## The model isn't actually used.  mritoself just uses
## the modeldir to find a mask.
my ($model,$modeldir,$modelfn);


GetOptions(
	   'verbose'            => \$verbose,
	   'clobber'            => \$clobber,
	   'correct_t1w=s'      => \$correct_t1w,
	   'correct_t2w=s'      => \$correct_t2w,
     'model_dir=s'        => \$modeldir,
     'model_name=s'       => \$model,
     );

#############################
##this program linearly registers t2/pd data to the tal t1 scans.
##we need a lot. the t1 xfm scan, the t1,t2,and pd scan
##as output we create a transform, and 
if ($#ARGV < 3){ die "Usage: $me <infilexfm> <infile_t1> <infilet2> <outfile.xfm> <outfile_t2> --model_name <model> --model_dir <dir> --correct_t1w <geocorr_t1w> --correct_t2w <geocorr_t2w>\n"; }

my $talxfm      = $ARGV[0];
my $infile_t1   = $ARGV[1];
my $infile_t2   = $ARGV[2];
my $outfile_xfm = $ARGV[3];
my $outfile_t2  = $ARGV[4];

check_file($outfile_xfm) unless $clobber;
check_file($outfile_t2)  unless $clobber;

$modelfn  = "$modeldir/${model}_mask.mnc";
if (!-e $modelfn){ 
    die "$me: The model $model doesn't exist (can't mask)\n";
}
my $tmpdir = &tempdir( "$me-XXXXXXXX", TMPDIR => 1, CLEANUP => 1 );

my @files_to_add_to_db = ();

my $tmp_xfm="$tmpdir/tmp_xfm.xfm";
my $tal_lin_xfm=$talxfm;

if($correct_t2w) # we have to strip T1 correction and put T2 correction
{
  $tal_lin_xfm="$tmpdir/lin_t1.xfm";
  my @lin=split(/\n/,`xfm2param $talxfm | grep "\\-scale\\|\-shear\\|\\-rotation\\|\\-translation\\|\\-center"`);
  do_cmd("param2xfm $tal_lin_xfm ".join(' ',@lin));
}
##################
##mritoself call

my $t1=$infile_t1;
my $t2=$infile_t2;


if($correct_t1w)
{
  $t1="$tmpdir/t1.mnc";
  do_cmd('itk_resample',$infile_t1,$t1,'--transform',$correct_t1w);
}


if($correct_t2w)
{
  $t2="$tmpdir/t2.mnc";
  do_cmd('itk_resample',$infile_t2,$t2,'--transform',$correct_t2w);
} 

  do_cmd('mritoself', '-clobber','-close', 
     '-nocrop',
     '-mask','target',
     '-model'    , $model,  
     '-modeldir' , $modeldir,
     '-target_talxfm', $tal_lin_xfm,
     $t2, 
     $t1, 
     $tmp_xfm);


if($correct_t2w) # we have to strip T1 correction and put T2 correction
{
  do_cmd('xfmconcat', $correct_t2w, $tmp_xfm, $tal_lin_xfm, $outfile_xfm);
} else {
  do_cmd('xfmconcat', $tmp_xfm, $talxfm, $outfile_xfm);
}

@files_to_add_to_db = (@files_to_add_to_db, $outfile_xfm);

###################
##Now actually create the t2/pd images
do_cmd('itk_resample', '--clobber', '--transform', $outfile_xfm,
   '--like', $modelfn, $infile_t2, $outfile_t2,'--order',4);

@files_to_add_to_db = (@files_to_add_to_db, $outfile_t2);

print("Files created:@files_to_add_to_db\n");
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

sub check_file {
  die("${_[0]} exists!\n") if -e $_[0];
}