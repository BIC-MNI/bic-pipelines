#!/usr/bin/env perl

##############################################################################
# 
# pipeline_stx_thickness.pl
#
# Input:
#      o prefix for output files (including output filepath)
#
# Output:
#      o thickness text file
#
#
# Larry Baer, April, 2005
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

#$SIG{__DIE__} =  sub { &cleanup; die $_[0]; };

####################################################################
my $me;
my $verbose     = 0;
my $clobber     = 0;
my $outfile_prefix = 0;
my @files_to_add_to_db = ();

chomp($me = `basename $0`);

GetOptions(
	   'verbose' => \$verbose,
	   'clobber' => \$clobber
	   );

#if($#ARGV < 1){ die "Usage: $me <output file prefix>\n"; }

#########################
# Get the arguments.
$outfile_prefix = $ARGV[0];

print $outfile_prefix, "\n" if $verbose;

my @args = ('stx_thickness.pl', '-out', $outfile_prefix,'-remove_models', '-clobber', '-verbose');
print STDOUT @args if($verbose);
system(@args) == 0 or die;  


@files_to_add_to_db = (@files_to_add_to_db, "${outfile_prefix}_stx_thickness.txt");

print("Files created:@files_to_add_to_db\n");




