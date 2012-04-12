#!/usr/bin/env perl
#
# Matthew Kitching
# Script based on original work by Andrew Janke.
# This modified version is used with nihpd database.
#
# Andrew Janke - rotor@bic.mni.mcgill.ca
# Script to register intra-subject data for a given time point
# Wed Feb 13 14:00 2002 - initial version(LC)

#    the procedure will  compute the PD to T1 registration


use Getopt::Long;
use File::Basename;
use File::Temp qw/ tempfile tempdir /;
use strict;

my ($me,$verbose,$clobber);

chomp($me = basename($0));
$verbose = 0;
$clobber = 0;

my ($model,$modeldir,$modelfn);

##get models from constants file
chomp($model    = `pipeline_constants -model_tal`);
chomp($modeldir = `pipeline_constants -modeldir_tal`);

GetOptions(
	   'verbose' => \$verbose,
	   'clobber' => \$clobber,
     'model_dir=s'    => \$modeldir,
     'model_name=s'   => \$model,
     );

#############################
##this program linearly registers t2/pd data to the tal t1 scans.
##we need a lot. the t1 xfm scan, the t1,t2,and pd scan
##as output we create a transform, and 
if ($#ARGV < 2){ die "Usage: $me <t2_t1xfm> <infile_pd> <outfile_pd> --model_dir <dir> --model_name <name>\n"; }
my $infile_xfm = $ARGV[0];
my $infile_pd  = $ARGV[1];
my $outfile_pd = $ARGV[2];


if(-e $outfile_pd && !$clobber)
{
    print("$outfile_pd exists use clobber to overwrite\n");
    exit 0;
}


$modelfn  = "$modeldir/${model}_mask.mnc";
if (!-e $modelfn){ 
    die "$me: The model $model doesn't exist (can't mask)\n";
}

my @files_to_add_to_db = ();

if(!-e $outfile_pd)
{
    my @args = ('itk_resample', '--clobber', '--transform', $infile_xfm,
	     '--like', $modelfn, $infile_pd, $outfile_pd,'--order',4);
    if($verbose){ print STDOUT "@args\n"; }
    system(@args) == 0 or die;

    @files_to_add_to_db = (@files_to_add_to_db, $outfile_pd);
}

print("Files created:@files_to_add_to_db\n");
