#!/usr/bin/env perl

##############################################################################
# 
# pipeline_volumes.pl
#
# Input:
#      o classified file
#      o lobe file
#      o xfm file
#
# Output:
#      o a text file containing symbolic labels and associated volumes with the 
#        following format:
#            Line 1: ScaleFactor <scale factor>
#         Line 2-25: <Lobe label> <volume>
#
# Command line interface: 
#      pipeline_volumes <path to output volumes text file>
#
# Larry Baer, November, 2004
# McConnell Brain Imaging Centre, 
# Montreal Neurological Institute, 
# McGill University
##############################################################################

use strict;
use Getopt::Long;
use File::Basename;
use File::Temp qw/ tempfile tempdir /;


#######################################################################
# GetScaleFactor(in_xfmfile)
#
# Returns
#      The scale factor used to go from native T1w space to Taleirach space.
# Divide your volume measure by this factor to get the volume measure in native space.
#
# Larry Baer, November 25, 2004
# McConnell Brain Imaging Centre, 
# Montreal Neurological Institute, 
# McGill University
#######################################################################
sub GetScaleFactor
{
    my $in_xfmfile = $_[0];
    
    my $scale_factor = 1.0;

    if (! -e $in_xfmfile ) { 
	warn "Missing file $in_xfmfile\n"; 
    }
    else {
	my $scale = `xfm2param $in_xfmfile | grep scale`;
	my ($d, $scale_x, $scale_y, $scale_z) = split(" ", $scale);
	$scale_factor = $scale_x * $scale_y * $scale_z;
    }

    return $scale_factor;
}

####################################################################
my $me;
my $verbose     = 1;
my $clobber     = 0;
my $infile_classified;
my $infile_lobes;
my $infile_xfm;
my $outfile_volumes;
my $infile_tal_mask;
my $age=0.0;
#my $infile_seg;
my $scanner='na';
my $scanner_id=-1;
my @files_to_add_to_db = ();
my ($t1,$t2,$pd);

$me = basename($0);

GetOptions(
	   'verbose' => \$verbose,
	   'clobber' => \$clobber,
	   'age=s' => \$age,
	   'scanner=s' => \$scanner,
	   'scanner_id=i' => \$scanner_id,
      't1=s'  => \$t1,
      't2=s'  => \$t2,
      'pd=s'  => \$pd,

	   );

if($#ARGV < 3){ die "Usage: $me <input tal mask> <input classified file>  <input xfm file> <path to output volumes text file> --age <n> --scanner <scanner> --scanner_id <n>\n"; }

# Get the arguments.
$infile_tal_mask = $ARGV[0];
$infile_classified = $ARGV[1];
$infile_xfm = $ARGV[2];
$outfile_volumes = $ARGV[3];

print $infile_tal_mask, "\n" if $verbose;
print $infile_classified, "\n" if $verbose;
print $infile_xfm, "\n" if $verbose;
print $outfile_volumes, "\n" if $verbose;

if(-e $outfile_volumes && !$clobber)
{
    print("$outfile_volumes exists. Use clobber to overwrite.\n");
    exit 0;
}

if (! -e $infile_tal_mask )   { die "$infile_tal_mask does not exist\n"; }
if (! -e $infile_classified ) { die "$infile_classified does not exist\n"; }
if (! -e $infile_xfm )        { die "$infile_xfm does not exist\n"; }


my $wm_range = "2.5 3.5";
my $gm_range = "1.5 2.5";
my $csf_range = "0.5 1.5";
my $total_range = "0.5 3.5";
my @types = ("total", "wm" , "gm", "csf");

open( OUTFILE_VOLUMES, ">$outfile_volumes")or die "Cannot open output file: $!"; 

# Get and print the scale factor.
my $scalefactor = GetScaleFactor($infile_xfm);
print OUTFILE_VOLUMES "ScaleFactor $scalefactor\n";
print OUTFILE_VOLUMES "Age $age\n";
#print OUTFILE_VOLUMES "Scanner ${scanner}\n";
#print OUTFILE_VOLUMES "ScannerID ${scanner_id}\n";

print OUTFILE_VOLUMES "T1_SNR ",`noise_estimate --snr $t1` if $t1;
print OUTFILE_VOLUMES "T2_SNR ",`noise_estimate --snr $t2` if $t2;
print OUTFILE_VOLUMES "PD_SNR ",`noise_estimate --snr $pd` if $pd;

####################################
# Get the ICC volume from the tal mask
my @results = split(/\n/,`print_all_labels $infile_tal_mask`);
# Should only be one label
if (! $#results != 1) { die "$infile_tal_mask has more than one label\n"; }
chomp($results[0]);
my ($dummy1, $dummy2, $value) = split(/\s/, $results[0]);
# Convert to native space
$value = $value / $scalefactor;
#$talDbFile->setParameter("ICC_vol",$value) if (!$test_only);
print "ICC_vol $value\n" if $verbose;
print OUTFILE_VOLUMES "ICC_vol $value\n";

# Get and print the wm, gm, csf volumes.
my @results = split(/\n/,`print_all_labels $infile_classified`);
my $line;
my @classifyLabels = ("CSF_vol", "GM_vol", "WM_vol");
my $labelIndex = -1;
foreach $line(@results) {
	  chomp $line;
    ++ $labelIndex;
    my ($dummy1, $label, $value);
    ($dummy1, $label, $value) = split(/\s/, $line);
    $value = $value / $scalefactor;
    print OUTFILE_VOLUMES "$classifyLabels[$labelIndex] $value\n";
}

close (OUTFILE_VOLUMES);

@files_to_add_to_db = (@files_to_add_to_db, $outfile_volumes);

print("Files created:@files_to_add_to_db\n");

