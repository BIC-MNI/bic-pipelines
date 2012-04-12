#!/usr/bin/env perl

# Force all variables to be declared
use strict;

##############################################################################
# 
# Find outlier values given a list of ages and frontal lobe proportions of total volume 
#
# Larry Baer, May, 2005
# McConnell Brain Imaging Centre, 
# Montreal Neurological Institute, 
# McGill University
##############################################################################

my $line, my $age, my $frontal_proportion, my $qsub_line;

# Declare 3 arrays, one to hold the count of each age group, one to hold the mean, one for the stdev
my @counts, @mean, @stdev;

my $numargs = @ARGV;
if ($numargs != 2) {die "Usage: FindVolumeOutliers.pl <path/to/list/of/age/volume/data> <path/to/output>\n";}
my $in_file = $ARGV[0];
my $out_file = $ARGV[1];
if (! -e $in_file) {die "$in_file input file does not exist\n";}

# Check for existing output file.
my $response;
if ( -e $out_file ) {
    print "Output file $out_file exists.  Overwrite? (y//n)\n";
    $response = <STDIN>;
    if( $response ne "y\n" ) {
	exit 1;
    }
}


open (IN_AGEVOLDATA, "<${in_file}") or die "Cannot open $in_file input file: $!";
foreach $line(<IN_AGEVOLDATA>)
{
    chomp($line);
    
    if($line)
    {
	($age, $frontal_proportion) = split(",", $line);
        
        $count[$age] ++;

	$mean[$age] += $frontal_proportion;

    }
}

close(IN_AGEVOLDATA);

# Compute the mean and stdev for each age group.
my $iter;
my $index = 0;
foreach $iter(@mean) {
    $mean[$index] = $mean[$index] / $count[$index];
    ++ $index ;
}

# Print the results.
open (OUT_AGEVOLDATA, ">${out_file}") or die "Cannot open $out_file output file: $!";
$index = 0;
foreach $iter(@mean) {
    $mean[$index] = $mean[$index] / $count[$index];
    ++ $index ;
}
print OUT_AGEVOLDATA

close(OUT_AGEVOLDATA);
