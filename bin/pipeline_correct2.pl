#!/usr/bin/env perl
#
# Matthew Kitching
# Script based on original work by Andrew Janke.
# This modified version is used with nihpd database.
#
# Andrew Janke - rotor@bic.mni.mcgill.ca
# Script to int correct data
#
# Sun Dec  2 00:48:21 EST 2001 - initial version
# Sat Feb  9 11:51:43 EST 2002 - much improved
# May 1, 2002 - mods to apply to NIHPD DB - louis

use strict;
use Getopt::Long;
use File::Basename;
use File::Temp qw/ tempfile tempdir /;
 
my $me = basename ($0);
my $verbose     = 0;
my $clobber     = 0;
my $iterations  = 5;
my $mask;
my $fake=0;
my $distance;

GetOptions(
	   'verbose' => \$verbose,
	   'clobber' => \$clobber,
	   'iterations=i'=> \$iterations,
	   'mask=s'      => \$mask,
	   'distance=f'  => \$distance
	   );

if($#ARGV < 1) { die "Usage: $me <infile> <outfile_mnc> [--iterations <n> --mask <mask.mnc>]\n"; }

###################
##inputs are croped anatomical scan, outputs are the imp file, and nuc file
my $infile = $ARGV[0];
my $outfile_nuc = $ARGV[1];

check_file($outfile_nuc) unless $clobber;

my @files_to_add_to_db = ();

my $normdir = dirname($outfile_nuc);
###########################
my $tmpdir = &tempdir( "$me-XXXXXXXX", TMPDIR => 1, CLEANUP => 1 );

# convert to float
do_cmd('mincreshape','-float','-normalize', $infile, "$tmpdir/0.mnc");
my $i;

for($i=1;$i<=$iterations;$i++)
{
  my $p=$i-1;
  my @args=( "nu_correct", "-clobber", "-iter", 100, "-stop", 0.0001, "-fwhm", 0.1,"$tmpdir/$p.mnc",  "$tmpdir/$i.mnc");
  push @args,'-mask',$mask  if $mask;
  push @args,'-distance',$distance if $distance;
  do_cmd(@args);
}

do_cmd('mincreshape','-short', "$tmpdir/$iterations.mnc", $outfile_nuc, '-clobber');
#do_cmd('cp',"$tmpdir/$iterations.mnc",$outfile_nuc);

@files_to_add_to_db = ($outfile_nuc);

print("Files created:@files_to_add_to_db\n");

sub do_cmd { 
    print STDOUT "@_\n" if $verbose;
    if(!$fake){
      system(@_) == 0 or die "DIED: @_\n";
    }
}

sub check_file {
  die("${_[0]} exists!\n") if -e $_[0];
}

