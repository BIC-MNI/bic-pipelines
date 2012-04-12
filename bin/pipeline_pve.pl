#!/usr/bin/env perl
#
#
# Matthew Kitching
#
# Script based on original work by Andrew Janke.
# This modified version is used with nihpd database.
#
# Wed Mar  6 17:13:21 EST 2002 - initial version
# updated Nov 23 2003 - for more inclusion into nihpd Database
#
# January, 2005: Updated to work with new database structure and 
# simplified to only process the classified file passed as a 
# command line argument rather than figure out the filename from
# the classification parameters passed as options.  Now the caller 
# will have to name the file appropriate to the classification 
# algorithm. - Larry Baer
#
# To fit in with main_pipe.pl, this script now takes 4 dummy parameters
# which are the output filenames (normally, we should only have to pass
# the basename to pve) and puts them in the files_to_add_to_db array to
# pass back to the caller. - LB
#
########################################

use strict;

use File::Temp qw/ tempfile tempdir /;
use File::Basename;
use Getopt::Tabular;  
use MNI::FileUtilities qw(check_output_dirs);

$SIG{__DIE__} =  sub { &cleanup; die $_[0]; };

my $me;				  
$me  = basename ($0);
my $verbose   = 0;
my $clobber   = 0;
my $tmp_cortex_file = 0;
my $tmp_mask_file = 0;
my $tmp_maskD_file = 0;
my @opt_table = (
	      ["-verbose", "boolean", 0, \$verbose, "be verbose"            ],
	      ["-clobber", "boolean", 0, \$clobber, "clobber existing mask" ],
	      );

&GetOptions(\@opt_table, \@ARGV) || exit 1;
if($#ARGV < 0){ die "Usage: $me <T1 tal> <Classified> <Base dir and name for pve output>\n" }

# Get the input args
my $in_t1tal_file = $ARGV[0];
my $in_classify_file = $ARGV[1];
my $in_pve_base = $ARGV[2];

my @files_to_add_to_db = ();

# Create the tmp files
my $dummy;
($dummy, $tmp_cortex_file) = File::Temp::tempfile(TMPDIR => 1, UNLINK => 1 , SUFFIX => '.mnc');
($dummy, $tmp_mask_file) = File::Temp::tempfile(TMPDIR => 1, UNLINK => 1 , SUFFIX => '.mnc');
($dummy, $tmp_maskD_file) = File::Temp::tempfile(TMPDIR => 1, UNLINK => 1 , SUFFIX => '.mnc');

my @args = ('cortical_surface', $in_classify_file, $tmp_cortex_file, '1.5');
print STDOUT @args if($verbose);
system(@args) == 0 or die;  

@args = ('msd_masks', $in_t1tal_file, $tmp_cortex_file, $tmp_mask_file, '-clobber', '-dilated_mask', $tmp_maskD_file);
print STDOUT @args if($verbose);
system(@args) == 0 or die;  

@args = ('pve', '-image', $in_t1tal_file,  $tmp_mask_file,$in_pve_base,$in_classify_file);
print STDOUT @args if($verbose);
system(@args) == 0 or die;

@files_to_add_to_db = (@files_to_add_to_db, "${in_pve_base}_csf.mnc");
@files_to_add_to_db = (@files_to_add_to_db, "${in_pve_base}_gm.mnc");
@files_to_add_to_db = (@files_to_add_to_db, "${in_pve_base}_wm.mnc");
@files_to_add_to_db = (@files_to_add_to_db, "${in_pve_base}_disc.mnc");

&cleanup;

print("Files created:@files_to_add_to_db\n");

sub cleanup {
  if($verbose){ print STDOUT "Cleaning up....\n"; }
  if(-e $tmp_cortex_file)
  {
      `rm $tmp_cortex_file`;
  }
  if(-e $tmp_mask_file)
  {
      `rm $tmp_mask_file`;
  }
  if(-e $tmp_maskD_file)
  {
      `rm $tmp_maskD_file`;
  }
}
