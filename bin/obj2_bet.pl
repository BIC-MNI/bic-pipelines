#! /usr/bin/env perl
use strict;
use File::Basename;
use File::Temp qw/ tempfile tempdir /;
use Getopt::Long;
use POSIX qw(floor);

my $fake=0;
my $verbose=0;
my $clobber=0;
my $mask;
my $me=basename($0);

GetOptions (    
          "verbose"   => \$verbose,
          "clobber"   => \$clobber,
          "mask=s"    => \$mask
          );
          
die "Usage: $me <scan_in> <brain_mask_out> \n[--verbose\n --clobber\n --mask <model_mask>\n]\n" if $#ARGV<1;

my ($in,$out)=@ARGV;

check_file($out) unless $clobber;

my $tmpdir = &tempdir( "$me-XXXXXXXX", TMPDIR => 1, CLEANUP => 1 );

#1 run nomal bet
#do_cmd('mincbet',$in,"$tmpdir/brain",'-m','-n');
#do_cmd('imp_bet.pl',$in,"$tmpdir/brain_mask.mnc");
#do_cmd('itk_g_morph','--exp','E[1]',$in,"$tmpdir/eroded.mnc");
#do_cmd('minccalc','-express','A[0]>0.5?A[0]:0',"$tmpdir/eroded.mnc","$tmpdir/corrected.mnc");
#do_cmd('mincbet',"$tmpdir/corrected.mnc","$tmpdir/brain",'-m','-n');

#2 shift front part forward
#do_cmd('mincreshape','-dimrange','yspace=150,83',"$tmpdir/brain_mask.mnc","$tmpdir/front.mnc");
##do_cmd('param2xfm','-translation',0,2,0,"$tmpdir/shift_y_2mm.xfm");
#do_cmd('mincresample','-transform',"$tmpdir/shift_y_2mm.xfm","$tmpdir/front.mnc",'-like',"$tmpdir/brain_mask.mnc","$tmpdir/front_.mnc",'-nearest');
#do_cmd('minccalc','-express','A[0]>0.5||A[1]>0.5?1:0','-byte',"$tmpdir/brain_mask.mnc","$tmpdir/front_.mnc","$tmpdir/brain.mnc");
#do_cmd('rm','-f',"$tmpdir/brain_mask.mnc","$tmpdir/front.mnc","$tmpdir/front_.mnc");

#if($mask) 
#{
#  #assume that our mask shouldn't be much bigger 
#  do_cmd('itk_morph','--exp','D[2]',$mask,"$tmpdir/mask.mnc");
#  do_cmd('minccalc','-express','A[0]>0.5&&A[1]>0.5?1:0',"$tmpdir/mask.mnc","$tmpdir/brain.mnc","$tmpdir/brain_.mnc");
#  do_cmd('mv',"$tmpdir/brain_.mnc","$tmpdir/brain.mnc");
#}
#3 run the skull segmentation script
#do_cmd('classify_skull.pl',$in,'--mask',"$tmpdir/brain.mnc",$out,'--clobber','--correct');
do_cmd('mincbet',$in,"$tmpdir/brain",'-n', '-m', '-f', 0.5, '-h', 1.10);
do_cmd('mincreshape','-byte',"$tmpdir/brain_mask.mnc",$out,'-clobber');

sub do_cmd {
    print STDOUT "@_\n" if $verbose;
    if(!$fake) {
        system(@_) == 0 or die "DIED: @_\n";
}
}

sub check_file {
  die("${_[0]} exists!\n") if -e $_[0];
}
