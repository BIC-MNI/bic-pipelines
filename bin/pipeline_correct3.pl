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
my $iterations  = 1;
my $mri3t;
my $fake=0;
my $model_mask;
my $keeptmp   = 0;
my $stx;
my $xfm;
my $stx_mask;
my ($model, $modeldir);
my $nuyl;

chomp($model    = `pipeline_constants -model_tal`);
chomp($modeldir = `pipeline_constants -modeldir_tal`);
my $modelfn  = "$modeldir/$model.mnc";

GetOptions(
	   'verbose' => \$verbose,
	   'clobber' => \$clobber,
	   'iterations=i'=> \$iterations,
     'model=s' => \$modelfn,
     'keeptmp' => \$keeptmp,
     '3t'      => \$mri3t,
     'stx'     => \$stx,
     'model-mask=s'  => \$model_mask,
     'xfm=s'         => \$xfm,
     'stx-mask=s'    => \$stx_mask,
     'nuyl'          => \$nuyl
	   );

if($#ARGV < 1) 
{ 
 die <<HELP 
Usage: $me <infile> <outfile_mnc> 
 [
  --iterations <n>, (default $iterations  ) perform so many iterations in nu_correct
  --model <mnc>     use this model for intensity normalization ***NEEED***
  --model-mask <mnc>  use this brain mask
  --3t              assume 3T scanner was used, (default  1.5T)
  --stx             perform preliminary registration to stereotaxic space for masking
  --xfm <xfm>       use this transformation to stereotaxic space
  --stx-mask <mask> use this mask (in stereotaxic space)
  --nuyl            Use Nuyl intensity normalization technique
 ]
HELP
; 
}

die "please specify a model \n" unless $modelfn;
###################
##inputs are croped anatomical scan, outputs are the imp file, and nuc file
my $infile  = $ARGV[0];
my $outfile = $ARGV[1];

check_file($outfile) unless $clobber;

my @files_to_add_to_db = ();

my $normdir = dirname($outfile);
###########################
my $tmpdir = &tempdir( "$me-XXXXXXXX", TMPDIR => 1, CLEANUP => !$keeptmp );

my $compress=$ENV{MINC_COMPRESS};
delete $ENV{MINC_COMPRESS} if $compress;

# convert to float
do_cmd('mincreshape','-float','-normalize', $infile, "$tmpdir/0.mnc");
#fix some broken minc files
my $zspacing=`mincinfo -attvalue zspace:spacing $tmpdir/0.mnc`;
chomp($zspacing);
if($zspacing =~ /irregular/)
{
  do_cmd('minc_modify_header','-sinsert','zspace:spacing=regular__',"$tmpdir/0.mnc");
}


my $mask;

# try to make a brain mask (approximate)
if($stx && $model && $model_mask)
{
  $mask="$tmpdir/mask.mnc";
  unless($xfm)
  {
    my @args=( "nu_correct", "-clobber", "-iter", 100, "-stop", 0.0001, "-fwhm", 0.1,"$tmpdir/0.mnc",  "$tmpdir/1.mnc");
    push @args,'-distance',50 if $mri3t;
    do_cmd(@args);
    
    #do_cmd('volume_pol', '--order', 1, "$tmpdir/1.mnc",$modelfn,'--expfile', "$tmpdir/stats0");
    #do_cmd('minccalc','-expfile',"$tmpdir/stats0","$tmpdir/1.mnc","$tmpdir/1_.mnc");
    
    do_cmd('volume_nuyl',"$tmpdir/1.mnc",$modelfn,"$tmpdir/1_.mnc");
    do_cmd('bestlinreg.pl',"$tmpdir/1_.mnc",$modelfn,"$tmpdir/stx.xfm");
    $xfm="$tmpdir/stx.xfm";
  }
  if($stx_mask)
  {
    do_cmd('mincresample','-nearest','-like',"$tmpdir/0.mnc",$stx_mask,$mask,'-transform',$xfm,'-invert_transform');
  } else {
    do_cmd('mincresample','-nearest','-like',"$tmpdir/0.mnc",$model_mask,$mask,'-transform',$xfm,'-invert_transform');
  }
}


my $i;
# iterative N3
for($i=1;$i<=$iterations;$i++)
{
  my $p=$i-1;
  my @args=( "nu_correct", "-clobber", 
             "-iter", 100, 
             "-stop", 0.0001, 
             "-fwhm", 0.1,
             "$tmpdir/$p.mnc",  "$tmpdir/$i.mnc",
             '-clobber');

  push @args,'-distance',50 if $mri3t;
  push @args,'-mask',$mask if $mask;

  do_cmd(@args);
}

$ENV{MINC_COMPRESS}=$compress if $compress;

# normalize intensity
if($mask && $model_mask)
{
  unless($nuyl)
  {
    do_cmd('volume_pol', '--order', 1, '--min', 0, '--max', 100,  
         "$tmpdir/$iterations.mnc", $modelfn,
         '--expfile', "$tmpdir/stats", 
         '--clobber','--noclamp',
         '--source_mask',$mask,'--target_mask',$model_mask);

    do_cmd('minccalc', "$tmpdir/$iterations.mnc", $outfile, 
           '-expfile', "$tmpdir/stats", '-clobber','-short');

  } else {
    do_cmd('volume_nuyl',"$tmpdir/1.mnc",$modelfn,"$tmpdir/1_.mnc",
           '--source-mask',$mask,
           '--target-mask',$model_mask);
    do_cmd('mincreshape','-short','-clob',"$tmpdir/nuyl.mnc",$outfile);
  }
} else {
  unless($nuyl)
  {
    do_cmd('volume_pol', '--order', 1, 
           '--min', 0, '--max', 100, 
           '--noclamp',
           "$tmpdir/$iterations.mnc", $modelfn,'--expfile', "$tmpdir/stats", '--clobber');
           
    do_cmd('minccalc', "$tmpdir/$iterations.mnc", $outfile, 
           '-expfile', "$tmpdir/stats", '-clobber','-short');
  } else {
    do_cmd('volume_nuyl',"$tmpdir/$iterations.mnc",$modelfn,"$tmpdir/nuyl.mnc",'--fix_zero_padding');
    do_cmd('mincreshape','-short','-clob',"$tmpdir/nuyl.mnc",$outfile);

  }
}

#
#correct for zero padded data
#do_cmd('minccalc','-express','A[0]>0?1:0',"$tmpdir/$iterations.mnc","$tmpdir/signal.mnc");


@files_to_add_to_db = ($outfile);

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

