#!/usr/bin/env perl

##############################################################################
# 
# pipeline_b0correction.pl
#
# Input:
#      o an mnc file of an MR scan
#      o an xfm file that transforms the mnc to Taleirach space.
#
# Output:
#      o an xfm file with the scaling removed
#      o the transformed mnc file
#
# Command line interface: 
#      pipeline_talnoscale <path to mnc file> <path to xfm file> <path to transformed mnc file> <path to use for "de-scaled" xfm file>
#
# Larry Baer, October, 2004
# McConnell Brain Imaging Centre, 
# Montreal Neurological Institute, 
# McGill University
##############################################################################

use strict;
use Getopt::Long;
use File::Basename;
use File::Temp qw/ tempfile tempdir /;


my $me=basename($0);
my $verbose     = 0;
my $clobber     = 0;
my $fake=0;
my $infile_mnc;
my $infile_xfm;
my $outfile_mnc;
my $outfile_xfm;
my $program_string;
my $results;
my ($commentline, $center, $translation, $rotation, $scale, $shear);
my ($model, $modeldir, $modelfn);
my @files_to_add_to_db = ();

# Finally, apply the transformation to the minc file.
#########################
##models are standard models. This will be changed once age
##appropriate models are discovered.
chomp($model    = `pipeline_constants -model_tal`);
chomp($modeldir = `pipeline_constants -modeldir_tal`);


GetOptions(
	   'verbose' => \$verbose,
	   'clobber' => \$clobber,
     'model_dir=s'    => \$modeldir,
     'model_name=s'   => \$model,
     );

if($#ARGV < 3){ die "Usage: $me <path to mnc file> <path to xfm file> <path to use for \"de-scaled\" xfm file> <path to transformed mnc file>\n"; }

# Get the arguments.
$infile_mnc = $ARGV[0];
$infile_xfm = $ARGV[1];
$outfile_xfm = $ARGV[2];
$outfile_mnc = $ARGV[3];
print $infile_mnc, "\n" if $verbose;
print $infile_xfm, "\n" if $verbose;
print $outfile_mnc, "\n" if $verbose;
print $outfile_xfm, "\n" if $verbose;

check_file($outfile_mnc) unless $clobber;
#check_file($outfile_xfm) unless $clobber;

#  > Decompose the input xfm.  We can do this if rotations are all less than 90 degrees and done in x, y, z order.
# this is wrong, we should extract scale part, and apply inverse transform !
my $tmpdir = &tempdir( "$me-XXXXXXXX", TMPDIR => 1, CLEANUP => 1 );

unless( -e $outfile_xfm)
{
  my $scale=`xfm2param $infile_xfm|fgrep -- -scale|tr -s ' ' ' '`;
  my @scales=split(/\n/,$scale);
  if($#scales==0) {
    $scale=$scales[0]
  } else {
    die "$me:Can't decide which scale to use\n";
  }
  print "Scale: $scale\n" if $verbose;
  # and construct a new xfm.
  do_cmd("param2xfm $scale $tmpdir/scale.xfm");
  do_cmd("xfminvert","$tmpdir/scale.xfm","$tmpdir/iscale.xfm");
  do_cmd("xfmconcat",$infile_xfm,"$tmpdir/iscale.xfm",$outfile_xfm);

  @files_to_add_to_db = (@files_to_add_to_db, $outfile_xfm);
}

$modelfn  = "$modeldir/$model.mnc";
print "Model: ", $modelfn, "\n" if $verbose;
do_cmd('itk_resample', '--transform', $outfile_xfm, '--like', $modelfn, $infile_mnc, $outfile_mnc,'--clobber','--order',4);
@files_to_add_to_db = (@files_to_add_to_db, $outfile_mnc);
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