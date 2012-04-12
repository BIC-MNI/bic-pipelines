#!/usr/bin/env perl

##############################################################################
# 
# pipeline_clasp.pl
#
# Input:
#      o classified mnc
#      o T1 Tal mnc
#      o native-to-tal xfm file
#      o prefix for output files (including output filepath)
#
# Output:
#      o *.obj files and a text file for cortical thickness in native space
#        Use brain-view <.obj> <.txt> to view the cortical thickness measures.
#
#
# Larry Baer, March, 2005
# McConnell Brain Imaging Centre, 
# Montreal Neurological Institute, 
# McGill University
##############################################################################

use strict;
use Getopt::Long;
use File::Basename;
use File::Temp qw/ tempfile tempdir /;
use NeuroDB::File;
use NeuroDB::DBI;

####################################################################
my $me = &basename( $0 );
my $verbose     = 0;
my $clobber     = 0;
my $fake        = 0;
my $infile_classified;
my $infile_T1Tal;
my $infile_xfm;
my $outfile_prefix = 0;
my @files_to_add_to_db = ();

GetOptions(
	   'verbose' => \$verbose,
	   'clobber' => \$clobber
	   );

if($#ARGV < 3){ die "Usage: $me <input classified file> <input T1 tal file> <input xfm file> <output file prefix>\n"; }

#########################
# Get the arguments.
$infile_classified = $ARGV[0];
$infile_T1Tal = $ARGV[1];
$infile_xfm = $ARGV[2];
$outfile_prefix = $ARGV[3];

print $infile_classified, "\n" if $verbose;
print $infile_T1Tal, "\n" if $verbose;
print $infile_xfm, "\n" if $verbose;
print $outfile_prefix, "\n" if $verbose;

##########################
# Check the arguments.
if (! -e $infile_classified ) { die "$infile_classified does not exist\n"; }
if (! -e $infile_T1Tal ) { die "$infile_T1Tal does not exist\n"; }
if (! -e $infile_xfm ) { die "$infile_xfm does not exist\n"; }

# dirty fix to exclude . from the path
my $real_path='/data/nihpd/nihpd3/data/mri_processing/1.2';
my $data_path='/home/bic/vfonov/data/nihpd/subjects';

my $infile_classified_=$infile_classified;
my $infile_T1Tal_=$infile_T1Tal;
my $infile_xfm_=$infile_xfm;
my $outfile_prefix_=$outfile_prefix;
$infile_classified_ =~ s($real_path)($data_path);

$infile_T1Tal_ =~ s($real_path)($data_path);
$infile_xfm_  =~ s($real_path)($data_path);
#$outfile_prefix_  =~ s($real_path)($data_path);

#setup environment for the clasp
my $BINDIR="/data/ipl/proj01/nihpd/analysis_vladimir/data/auto_quarantine";
my $TOPDIR=$ENV{"TOPDIR"};
my $PATH=$ENV{"PATH"};

$ENV{"PATH"}="${BINDIR}/bin:${TOPDIR}/pipeline/bin:${TOPDIR}/pipeline/util:${PATH}:${TOPDIR}/bin2:${PATH}";
$ENV{"PERL5LIB"}="${BINDIR}/perl:${TOPDIR}/pipeline/lib";
$ENV{"MNI_DATAPATH"}="${BINDIR}/share";

print "\n\n***\n", `which clasp`,"\n***\n";

#fix the stupid CLASP 
chomp(my $cwd = `pwd`);
my $base_dir=dirname($outfile_prefix_);

unless(
       (-e "${outfile_prefix}_gray_81920.obj" || -e "${outfile_prefix}_gray_81920.obj.gz") && 
       (-e "${outfile_prefix}_white_81920.obj" || -e "${outfile_prefix}_white_81920.obj.gz") && 
       (-e "${outfile_prefix}_white_cal_81920.obj" || -e "${outfile_prefix}_white_cal_81920.obj.gz")
       )
{
  chdir($base_dir);
  my $output=basename($outfile_prefix_);
  my @args = ('clasp', $infile_classified_, $infile_T1Tal_, '-out', $output,'-clobber', '-verbose','-debug','-remove_models');
  do_cmd(@args);  
  chdir($cwd);
}

do_cmd("gzip ${outfile_prefix}_gray_81920.obj") if -e "${outfile_prefix}_gray_81920.obj";
do_cmd("gzip ${outfile_prefix}_white_81920.obj") if -e "${outfile_prefix}_white_81920.obj";
do_cmd("gzip ${outfile_prefix}_white_cal_81920.obj") if -e "${outfile_prefix}_white_cal_81920.obj";

my $thickness='-tlink';
unless( -e "${outfile_prefix}_stx_thickness.txt" )
{
  do_cmd('cortical_thickness', $thickness,
         "${outfile_prefix}_white_cal_81920.obj.gz",
         "${outfile_prefix}_gray_81920.obj.gz",
         "${outfile_prefix}_stx_thickness.txt");
}

unless( -e "${outfile_prefix}_native_thickness.txt" )
{
  #put objects back into native space
  my $tmpdir = &tempdir( "$me-XXXXXXXX", TMPDIR => 1, CLEANUP => 1 );
  do_cmd('xfminvert', $infile_xfm, "${tmpdir}/tal_to_native.xfm");
  do_cmd("transform_objects", "${outfile_prefix}_white_cal_81920.obj.gz", "${tmpdir}/tal_to_native.xfm","${tmpdir}/native_white.obj");
  do_cmd("transform_objects", "${outfile_prefix}_gray_81920.obj.gz", "${tmpdir}/tal_to_native.xfm", "${tmpdir}/native_gray.obj");

  do_cmd('cortical_thickness', $thickness,
         "${tmpdir}/native_white.obj",
         "${tmpdir}/native_gray.obj",
         "${outfile_prefix}_native_thickness.txt");
}

@files_to_add_to_db = (@files_to_add_to_db, "${outfile_prefix}_gray_81920.obj.gz");
@files_to_add_to_db = (@files_to_add_to_db, "${outfile_prefix}_white_81920.obj.gz");
@files_to_add_to_db = (@files_to_add_to_db, "${outfile_prefix}_white_cal_81920.obj.gz");
#@files_to_add_to_db = (@files_to_add_to_db, "${outfile_prefix}_native_thickness.txt");
@files_to_add_to_db = (@files_to_add_to_db, "${outfile_prefix}_stx_thickness.txt");

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
