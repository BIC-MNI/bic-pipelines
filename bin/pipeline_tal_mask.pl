#!/usr/bin/env perl

##############################################################################
# 
# pipeline_eyemask.pl
#
# Input:
#      o the tal mask
#
# Output:
#      o the tal mask with the eye mask subtracted
#
# Command line interface: 
#      pipeline_eyemask.pl <path to tal mask>  <path to composite mask>
#
# Larry Baer, June, 2005
# McConnell Brain Imaging Centre, 
# Montreal Neurological Institute, 
# McGill University
##############################################################################

use strict;
use Getopt::Long;
use File::Basename;
use File::Temp qw/ tempfile tempdir /;
use pipeline_functions;
 
my $me= &basename($0);;
my $verbose     = 0;
my $clobber     = 0;
my $fake        = 0;
my @files_to_add_to_db = ();

GetOptions(
	   'verbose' => \$verbose,
	   'clobber' => \$clobber
	   );

if($#ARGV < 6) { die "Usage: $me <composite mask> <t1tal> <t2tal> <pd2tal> <t1tal_masked> <t2tal_masked> <pd2tal_masked> \n"; }

# Get the arguments.
my ($mask, $in_t1, $in_t2, $in_pd, $out_t1, $out_t2, $out_pd) = @ARGV;

die "$out_t1 exists. Use clobber to overwrite.\n" if -e $out_t1 && !$clobber;
die "$out_t2 exists. Use clobber to overwrite.\n" if -e $out_t2 && !$clobber;
die "$out_pd exists. Use clobber to overwrite.\n" if -e $out_pd && !$clobber;

#Build the temporary filenames.

# Composite the eye mask with the tal mask
do_cmd('minccalc','-copy_header', '-expression', 'A[1]==1 ? A[0] : 0', $in_t1, $mask, $out_t1, '-clobber');
@files_to_add_to_db = (@files_to_add_to_db, $out_t1);
do_cmd('minccalc','-copy_header', '-expression', 'A[1]==1 ? A[0] : 0', $in_t2, $mask, $out_t2, '-clobber');
@files_to_add_to_db = (@files_to_add_to_db, $out_t2);
do_cmd('minccalc','-copy_header', '-expression', 'A[1]==1 ? A[0] : 0', $in_pd, $mask, $out_pd, '-clobber');
@files_to_add_to_db = (@files_to_add_to_db, $out_pd);

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

