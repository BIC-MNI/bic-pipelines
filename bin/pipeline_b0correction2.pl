#!/usr/bin/env perl

##############################################################################
# 
# pipeline_b0correction.pl
#
# Input:
#      o a mnc file of an MR scan
#      o a mnc file representing the correction for B0 field inhomogeneities
#      o an xfm file describing distortions
#
# Output:
#      o the corrected mnc file
#
# Command line interface: 
#      pipeline_b0correction <path to mnc file> <path to B0 correction mnc file> <path to use for corrected file>
#
# Larry Baer, October, 2004
# McConnell Brain Imaging Centre, 
# Montreal Neurological Institute, 
# McGill University
##############################################################################

use strict;
use Getopt::Long;
use File::Basename;
use File::Temp qw/ tempfile tempdir /;
 
my $me;
my $verbose     = 0;
my $clobber     = 0;
my $fake		    = 0;
my $infile;
my $infile_correction;
my $outfile;
my $tmpfile_resampledcorrection;
my $basename;
my $suffix;
my @files_to_add_to_db = ();
my $infile_geo;
my $geo_threshold=1.0; #allow up to 1mm of data to be out of distortion correction field

$me = basename( $0);
my $acr_model=$ENV{'TOPDIR'}."/models/acr_model.mnc";
my ($model,$modeldir,$modelfn);
chomp($model    = `pipeline_constants -model_tal`);
chomp($modeldir = `pipeline_constants -modeldir_tal`);
$modelfn  = "$modeldir/$model.mnc";

GetOptions(
	   'verbose' => \$verbose,
	   'clobber' => \$clobber,
	   'geo=s'   =>  \$infile_geo,
	   'int=s'    => \$infile_correction
	   );

if($#ARGV < 1) { die "Usage: $me <input> [-int <path to B0 correction mnc file>] [-geo <path to geometry correction file>] <output>\n"; }

# Get the arguments.
$infile = $ARGV[0];
$outfile = $ARGV[1];

print $infile, "\n";
print $infile_correction, "\n";
print $outfile, "\n";

check_file( $outfile)  unless $clobber;

my $tmpdir = &tempdir( "$me-XXXXXXXX", TMPDIR => 1, CLEANUP => 1 );

$tmpfile_resampledcorrection="${tmpdir}/b0resampled.mnc";
my $tmpfile_geo="${tmpdir}/b0resampled_geo.mnc";
my $tmpfile_crop="${tmpdir}/b0resampled_geo_crop.mnc";
my $tmp_stats_name="${tmpdir}/stats.txt";

# Resample infile_correction so that it's in the same space as infile
if($infile_correction) {
  do_cmd('mincresample', $infile_correction, $tmpfile_resampledcorrection, '-clobber', '-fill', '-like', $infile);
  do_cmd('minccalc', '-copy_header', '-expression', 'A[0] / A[1]',$infile, $tmpfile_resampledcorrection, $tmpfile_geo);   
} else {
  $tmpfile_geo=$infile;
}

#apply geometry correction

if($infile_geo) {
 
  my @in_dims= get_dimensions($tmpfile_geo);
  my $geo_grid=$infile_geo;
  $geo_grid =~ s/.xfm/_grid_0.mnc/;
  my @geo_dims=get_dimensions($geo_grid);
  #make additional check on the span of the data
  print "in:",join(' ',@in_dims),"\n";
  print "geo:",join(' ',@geo_dims),"\n";
#  if($geo_dims[0]-$in_dims[0]<$geo_threshold &&  # begining of the space
#     $geo_dims[1]-$in_dims[1]<$geo_threshold &&
#     $geo_dims[2]-$in_dims[2]<$geo_threshold &&
#     $geo_dims[3]-$in_dims[3]>$geo_threshold && # end of the space
#     $geo_dims[4]-$in_dims[4]>$geo_threshold &&
#     $geo_dims[5]-$in_dims[6]>$geo_threshold)
#  {
    do_cmd('mincresample', ,'-clobber', '-transform', $infile_geo, $tmpfile_geo, $tmpfile_crop,'-like', $acr_model,'-tricubic','-keep_real_range');
    do_cmd('uniformize_minc.pl','--clobber','--transform',$infile_geo, $tmpfile_geo, $tmpfile_crop,'--resample','tricubic');
#  } else {
#    warn("Data of $infile is outside of the domain of $infile_geo , Skipping distortion correctin!");
#    $tmpfile_crop=$tmpfile_geo;
#  }
} else {
  $tmpfile_crop=$tmpfile_geo;
}


if(1)
{

    my ($max,$bimodalt)=split(/\n/, `mincstats -biModalT -max -q ${tmpfile_crop}`);
	
	####################
	#  do a sanity check
	if($bimodalt > $max/2) {
	  warn "BiType is probably stuffed!\nMax:${max}\nBiTypeT:${bimodalt}\nNew punt:$max/10\n";
	  $bimodalt = $max/10;
	}
	
	###########find bounding box
	my @fbstats=split(/\n/, `mincfbbox -mincreshape -threshold ${bimodalt} -clever -frequency 150 -boundary 10 -one_line ${tmpfile_crop}`);
	
	#$bounds = $fbstats;
	
	###############
	##mincreshape using bounding box
	do_cmd("mincreshape -clobber ${fbstats[$#fbstats]} ${tmpfile_crop} ${outfile}");
} else {
	do_cmd('cp', $tmpfile_crop, $outfile);
}

@files_to_add_to_db = (@files_to_add_to_db, $outfile);

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


sub get_dimensions {
 my ($xspace, $yspace, $zspace, $xstart, $ystart, $zstart, $xstep, $ystep, $zstep)= split(/\n/, `mincinfo  -dimlength xspace -dimlength yspace -dimlength zspace -attvalue xspace:start -attvalue yspace:start -attvalue zspace:start -attvalue xspace:step -attvalue yspace:step -attvalue zspace:step $_[0] `);
  if($xstep<0)
  {
    $xstart+=$xstep*$xspace;
    $xstep= -$xstep;
  }
  
  if($ystep<0)
  {
    $ystart+=$ystep*$yspace;
    $ystep= -$ystep;
  }
  
  if($zstep<0)
  {
    $zstart+=$zstep*$zspace;
    $zstep= -$zstep;
  }
  
  my $xlen=$xstep*$xspace;
  my $ylen=$ystep*$yspace;
  my $zlen=$zstep*$zspace;
  
  #I hate perl!
  $xstart=$xstart*1.0;
  $ystart=$ystart*1.0;
  $zstart=$zstart*1.0;
  
  $xspace*=$xstep;
  $yspace*=$ystep;
  $zspace*=$zstep;
  
  ($xstart,$ystart,$zstart,$xstart+$xspace,$ystart+$yspace,$zstart+$zspace);
}
