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

GetOptions(
	   'verbose' => \$verbose,
	   'clobber' => \$clobber
	   );

#############################
##this program linearly registers t2/pd data to the tal t1 scans.
##we need a lot. the t1 xfm scan, the t1,t2,and pd scan
##as output we create a transform, and 
if ($#ARGV < 3){ die "Usage: $me <infilexfm> <infile_t1> <infilet2> <outfile.xfm> <outfile_t2>\n"; }
my $talxfm = $ARGV[0];
my $infile_t1 = $ARGV[1];
my $infile_t2 = $ARGV[2];
my $outfile_xfm = $ARGV[3];
my $outfile_t2 = $ARGV[4];


check_file($outfile_xfm) unless $clobber;
check_file($outfile_t2) unless $clobber;

#############
##get models from constants file.
## Don't worry: Even if inputs are fallback images, it's OK.
## The model isn't actually used.  mritoself just uses
## the modeldir to find a mask.
my ($model,$modeldir,$modelfn);
chomp($model    = `pipeline_constants -model_tal`);
chomp($modeldir = `pipeline_constants -modeldir_tal`);

$modelfn  = "$modeldir/${model}_mask.mnc";
if (!-e $modelfn){ 
    die "$me: The model $model doesn't exist (can't mask)\n";
}
my $tmpdir = &tempdir( "$me-XXXXXXXX", TMPDIR => 1, CLEANUP => 1 );

my @files_to_add_to_db = ();

my $tmp_xfm="$tmpdir/tmp_xfm.xfm";
    
##################
##mritoself call

do_cmd('mritoself', '-clobber','-close', 
   '-nocrop',
   '-mask','target',
   '-model', $model,  
   '-modeldir', $modeldir,
   '-target_talxfm', $talxfm,
   $infile_t2, $infile_t1, $tmp_xfm);

do_cmd('xfmconcat', $tmp_xfm, $talxfm, $outfile_xfm);

@files_to_add_to_db = (@files_to_add_to_db, $outfile_xfm);

###################
##Now actually create the t2/pd images
do_cmd('mincresample', '-clobber', '-transformation', $outfile_xfm,
   '-like', $modelfn, $infile_t2, $outfile_t2);

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