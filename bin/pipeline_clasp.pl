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
my $me;
my $verbose     = 0;
my $clobber     = 0;
my $infile_classified;
my $infile_T1Tal;
my $infile_xfm;
my $outfile_prefix = 0;
my @files_to_add_to_db = ();

chomp($me = `basename $0`);

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
my $real_path='/data/nihpd/nihpd1/data/mri_processing/1.1/subjects';
my $data_path='/home/bic/vfonov/data/nihpd/subjects';

my $infile_classified_=$infile_classified;
my $infile_T1Tal_=$infile_T1Tal;
my $infile_xfm_=$infile_xfm;
my $outfile_prefix_=$outfile_prefix;
$infile_classified_ =~ s($real_path)($data_path);
$infile_T1Tal_ =~ s($real_path)($data_path);
$infile_xfm_  =~ s($real_path)($data_path);
$outfile_prefix_  =~ s($real_path)($data_path);

my @args = ('clasp2.pl', $infile_classified_, $infile_T1Tal_, $infile_xfm_, '-out', $outfile_prefix_,'-clobber', '-verbose','-debug','-remove_models');
print STDOUT @args if($verbose);
system(@args) == 0 or die;  

`gzip ${outfile_prefix}_gray_81920.obj`;
`gzip ${outfile_prefix}_white_81920.obj`;

@files_to_add_to_db = (@files_to_add_to_db, "${outfile_prefix}_gray_81920.obj.gz");
@files_to_add_to_db = (@files_to_add_to_db, "${outfile_prefix}_white_81920.obj.gz");
@files_to_add_to_db = (@files_to_add_to_db, "${outfile_prefix}_native_thickness.txt");
@files_to_add_to_db = (@files_to_add_to_db, "${outfile_prefix}_stx_thickness.txt");

print("Files created:@files_to_add_to_db\n");
