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


use Getopt::Long;
use File::Basename;
use File::Temp qw/ tempfile tempdir /;
      
$me = basename($0);
$verbose = 0;
$clobber = 0;
$dummy = "";


GetOptions(
	   'verbose' => \$verbose,
	   'clobber' => \$clobber
	   );

#############################
##this program linearly registers t2/pd data to the tal t1 scans.
##we need a lot. the t1 xfm scan, the t1,t2,and pd scan
##as output we create a transform, and 
if ($#ARGV < 3){ die "Usage: $me <infilexfm> <infile_t1> <infilet2> <outfile.xfm> <outfile_t2>\n"; }
$talxfm = $ARGV[0];
$infile_t1 = $ARGV[1];
$infile_t2 = $ARGV[2];
$outfile_xfm = $ARGV[3];
$outfile_t2 = $ARGV[4];

if(-e $outfile_xfm && -e $outfile_t2 && !$clobber)
{
    print("$outfile_xfm and $outfile_t2 exists use clobber to overwrite\n");
    exit 0;
}

#############
##get models from constants file.
## Don't worry: Even if inputs are fallback images, it's OK.
## The model isn't actually used.  mritoself just uses
## the modeldir to find a mask.
chomp($model    = `pipeline_constants -model_tal`);
chomp($modeldir = `pipeline_constants -modeldir_tal`);

$modelfn  = "$modeldir/${model}_mask.mnc";
if (!-e $modelfn){ 
    die "$me: The model $model doesn't exist (can't mask)\n";
}

@files_to_add_to_db = ();

if(!-e $outfile_xfm || $clobber)
{
    ($dummy, $tmp_xfm) = File::Temp::tempfile(TMPDIR => 1, UNLINK => 1 , SUFFIX => '.xfm');
    
    ##################
    ##mritoself call
    
    @args = ('mritoself', '-clobber','-close', 
	     '-nocrop',
	     '-mask','target',
	     '-model', $model,  
	     '-modeldir', $modeldir,
	     '-target_talxfm', $talxfm,
	     $infile_t2, $infile_t1, $tmp_xfm);
    if($verbose){ print STDOUT "@args\n"; }
    system(@args) == 0 or die;
    
    @args = ('xfmconcat', $tmp_xfm, $talxfm, $outfile_xfm);
    if($verbose){ print STDOUT "@args\n"; }
    system(@args) == 0 or die;

    `rm $tmp_xfm`;

    @files_to_add_to_db = (@files_to_add_to_db, $outfile_xfm);
}

###################
##Now actually create the t2/pd images
if(!-e $outfile_t2)
{
    @args = ('mincresample', '-clobber', '-transformation', $outfile_xfm,
	     '-like', $modelfn, $infile_t2, $outfile_t2);
    if($verbose){ print STDOUT "@args\n"; }
    system(@args) == 0 or die;

    @files_to_add_to_db = (@files_to_add_to_db, $outfile_t2);
}


print("Files created:@files_to_add_to_db\n");
