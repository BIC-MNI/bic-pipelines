#!/usr/bin/env perl

use strict;
use Getopt::Long;
use File::Basename;
use File::Temp qw/ tempdir /;

my $me = basename ($0);
my $verbose=1;
my $clobber=0;
my $fake=0;
my $mask;
my $age=20;
my $base=dirname($0);
my $atlas;
my $xfm;
my $atlas_gm;
my $atlas_wm;
my $atlas_csf;
my $blur=4;
my $tmpdir;

GetOptions(
      'verbose'       => \$verbose,
      'clobber'       => \$clobber,
      'mask=s'        => \$mask,
      'atlas=s'       => \$atlas,
      'atlas_gm=s'    => \$atlas_gm,
      'atlas_wm=s'    => \$atlas_wm,
      'atlas_csf=s'   => \$atlas_csf,
      'xfm=s'         => \$xfm,
      'age=f'         => \$age,
      'blur=f'        => \$blur,
      'tmpdir=s'      => \$tmpdir
	   );

my $Help = <<HELP;
  Usage: $me <t1> <t2> <output_cls> 
    --verbose be verbose
    --clobber clobber _all_ output files
    --age <subject age in months>
    --atlas <atlas>
    --atlas_gm <atlas_gm>
    --atlas_wm <atlas_wm>
    --atlas_csf <atlas_csf>
    --xfm <xfm>
    --mask <mask>
    --tmpdir <dir>
    --blur <fwhm>
  do T2 relaxometry tissue classification
  Problems or comments should be sent to: vfonov\@bic.mni.mcgill.ca
HELP

die $Help if $#ARGV < 2;

my ($t1w,$t2w,$output)=@ARGV;

check_file($output) unless $clobber;
$tmpdir = &tempdir( "$me-XXXXXXXX", TMPDIR => 1, CLEANUP => 1 ) unless $tmpdir;

# 1 customize atlas
do_cmd('mincresample','-like',$t1w,'-nearest','-transform',$xfm,'-invert_transform',$atlas,"$tmpdir/atlas.mnc");

do_cmd('mincresample','-like',$t1w,'-transform',$xfm,'-invert_transform',$atlas_gm, "$tmpdir/atlas_gm_.mnc");
do_cmd('mincresample','-like',$t1w,'-transform',$xfm,'-invert_transform',$atlas_wm, "$tmpdir/atlas_wm_.mnc");
do_cmd('mincresample','-like',$t1w,'-transform',$xfm,'-invert_transform',$atlas_csf,"$tmpdir/atlas_csf_.mnc");

do_cmd('fast_blur','--fwhm',$blur,"$tmpdir/atlas_gm_.mnc","$tmpdir/atlas_gm.mnc");
do_cmd('fast_blur','--fwhm',$blur,"$tmpdir/atlas_wm_.mnc","$tmpdir/atlas_wm.mnc");
do_cmd('fast_blur','--fwhm',$blur,"$tmpdir/atlas_csf_.mnc","$tmpdir/atlas_csf.mnc");

do_cmd('em_classify',$t1w,$t2w,'--classes',5,'--train',"$tmpdir/atlas.mnc",
   '--priors',"$tmpdir/atlas_csf.mnc,$tmpdir/atlas_csf.mnc,$tmpdir/atlas_gm.mnc,$tmpdir/atlas_wm.mnc,$tmpdir/atlas_wm.mnc",
   $output,'--clobber','--mask',$mask,'--verbose','--iter',100);

sub check_file {
  die("${_[0]} exists!\n") if -e $_[0];
}


sub do_cmd {
    print STDOUT "@_\n" if $verbose;
    if(!$fake) {
        system(@_) == 0 or die "DIED: ".join(',',@_)."\n";
    }
}