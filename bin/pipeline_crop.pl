#!/usr/bin/env perl
# 
# Matthew Kitching
# Script based on original work by Andrew Janke.
# This modified version is used with nihpd database.
#
# Sun Dec  2 00:48:21 EST 2001 - initial version
# Mon Feb 11, 2002 LC - modified to work on MNI_MS data.
# Wed May 1, 2002 LC - modified to work on NIHPD data.
# June 1, 2004 - modified for nihpd database
#
# This is a generic crop script


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

#######################]
##infile is the native infile
##outfile the croped value
if ($#ARGV < 1){ die "Usage: $me <infile> <outfile>\n"; }
$infile = $ARGV[0];
$outfile = $ARGV[1];

if(-e $outfile && !$clobber)
{
    print("$outfile exists use clobber to overwrite\n");
    exit 0;
}

@files_to_add_to_db = ();

($dummy, $tmp_stats_name) = File::Temp::tempfile(TMPDIR => 1, UNLINK => 1 , SUFFIX => '.stats');

###################
##grab the stats to find bimodal value... although in future if we keep the stats file, we could just reuse
@stats = split(/\n/, `mincstats $infile`);

foreach (@stats){
    if(s/^Max\:\ *//){
	$max = $_;
    }
    if(s/^BiModalT\:\ *//){
	$bimodalt = $_;
    }
}

####################
#  do a sanity check
if($bimodalt > $max/2){
    print "#######WARNING\nBiType is probably stuffed!\nMax:$max\nBiTypeT:$bimodalt\nNew punt:$max/10\n";
    $bimodalt = $max/10;
}

###########find bounding box
$args = "mincfbbox -mincreshape -threshold $bimodalt -clever -frequency 150 -boundary 10 $infile > $tmp_stats_name\n";

if($verbose){ print STDOUT "*** finding bounds of $infile\n"; print STDOUT $args; }
system($args) == 0 or die;

chomp($bounds = `tail -1 $tmp_stats_name`);

###############
##mincreshape using bounding box
$args = "mincreshape -clobber $bounds $infile $outfile\n";
if($verbose){ print STDOUT $args; }
system($args) == 0 or die;

#Clean up after ourselves.
`rm $tmp_stats_name`;

@files_to_add_to_db = (@files_to_add_to_db, $outfile);
print("Files created:@files_to_add_to_db\n");
