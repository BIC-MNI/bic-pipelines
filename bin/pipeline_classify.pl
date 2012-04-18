#!/usr/bin/env perl
#
#
# Matthew Kitching
#
# Script based on original work by Andrew Janke.
# This modified version is used with nihpd database.
# Also, this script removes WM voxels near the edge of the brain mask
#
# Wed Mar  6 17:13:21 EST 2002 - initial version
# updated Nov 23 2003 - for more inclusion into nihpd Database
#
# Dec. 10, 2004: Added "use strict"!!! (LB)
# Sep.  9, 2005: Switched to current classify/classify_clean programs (VF)
#
########################################

use strict;
use Getopt::Long;
use File::Basename;
use File::Temp qw/ tempfile tempdir /;
use pipeline_functions; 

my $fake = 0;
my $me = basename($0,".pl");
my $verbose = 0;
my $clobber = 0;
my $dummy = "";
my $mask_file = "";
my $topdir=$ENV{TOPDIR};
my $xfmfile=0;
my $classify_algo='-ann';
my $mrf;
my ($modeldir,$modelname);

GetOptions(
	   'verbose' => \$verbose,
	   'clobber' => \$clobber,
	   'mask=s' =>  \$mask_file,
	   'xfm=s' =>   \$xfmfile,
     'mrf'   =>   \$mrf,
     'model_dir=s' => \$modeldir,
     'model_name=s' => \$modelname
	   );

if ($#ARGV < 1){ die "Usage: $me <infile_t1> [infilet2] [infilepd] <outfile_clean_mnc> --model_dir <modeldir> --model_name <model_name> [--mask <mask file> --xfm <nl xfm> --mrf]\n"; }

####################
##infiles are either tal, or nl t1,t2, and pd files as well as output files
my $outfile_clean = pop(@ARGV);
my @files_to_add_to_db = ();

if( -e $outfile_clean &&  !$clobber)
{
    print "Found clean classification files, nothing to do\n";
    exit;
}

my $tmpdir = &tempdir( "${me}-XXXXXXXX", TMPDIR => 1, CLEANUP => 1 );

my @args=('classify_clean', '-clobber', @ARGV, '-verbose',"$tmpdir/cls.mnc",'-clean_tags');#$outfile_clean

if($mask_file && -e $mask_file)
{
  push (@args,'-mask',$mask_file,'-mask_tag','-mask_classified');#,'-mask_source'
}

if($xfmfile && -e $xfmfile) 
{
  push (@args,'-tag_transform',$xfmfile);
}

if($modeldir && $modelname)
{
  push (@args,
        '-tagdir',     $modeldir,
        '-tagfile',   "${modelname}_ntags_1000_prob_90_nobg.tag",
        '-bgtagfile', "${modelname}_ntags_1000_bg.tag");
}

do_cmd(@args);

if($mrf)
{
  
  if($#ARGV>0)
  {
    do_cmd('pve3','-image',"$tmpdir/cls.mnc",'-mask',$mask_file,@ARGV,"$tmpdir/pve");
  } else {
    do_cmd('pve','-image',"$tmpdir/cls.mnc",'-mask',$mask_file,@ARGV,"$tmpdir/pve");
  }

  do_cmd('minccalc','-express','(A[0]>A[1]?(A[0]>A[2]?1:3):(A[1]>A[2]?2:3))*A[3]','-byte',"$tmpdir/pve_csf.mnc","$tmpdir/pve_gm.mnc","$tmpdir/pve_wm.mnc",$mask_file,$outfile_clean,'-clobber');
} else {
  do_cmd('cp',"$tmpdir/cls.mnc",$outfile_clean);
}

@files_to_add_to_db = (@files_to_add_to_db, $outfile_clean);
pipeline_functions::create_header_info_for_many_parented($outfile_clean, $ARGV[0], $tmpdir);

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

