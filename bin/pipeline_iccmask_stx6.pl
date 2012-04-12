#!/usr/bin/env perl
# 
# Vladimir S. Fonov
#
# Script to generate a mask using BET & Eye mask
#

use strict;
use Getopt::Long;
use File::Basename;
use File::Temp qw/ tempdir /;
use pipeline_functions;
      
my $me = basename($0);
my $verbose = 0;
my $clobber = 0;
my $dummy   = "";
my $fake    = 0;
my $model;
my $icc_model;
my $model_eye_mask;

GetOptions(
    'verbose'    => \$verbose,
    'clobber'    => \$clobber,
    'eye_mask=s' => \$model_eye_mask,
    'model=s'    => \$model,
    'icc-model=s' => \$icc_model
	   );

if ($#ARGV < 1){ die "Usage: $me <infile_t1> [infilet2] [infilepd] <outfile_mnc> [--eye_mask <eye_mask> --model <T1w model> --icc-model <icc mask model>]\n"; }

#####################
##infile includes the tal transformed anatomical data
##outfile is the single mask
my $outfile_mnc=pop(@ARGV);

check_file($outfile_mnc) unless($clobber);

my @files_to_add_to_db = ();

my $tmpdir = &tempdir( "${me}-XXXXXXXX", TMPDIR => 1, CLEANUP => 1 );

# calculate masks for T1, T2 and PD
my $i;
my $j=0;

my $compress=$ENV{MINC_COMPRESS};
delete $ENV{MINC_COMPRESS} if $compress;

if($#ARGV > 1)
{
  # we are trying to get ICC mask
  do_cmd('mincaverage',@ARGV,"$tmpdir/avg.mnc");
  do_cmd('mincbet', "$tmpdir/avg.mnc", "$tmpdir/mri", '-m', '-n','-f', 0.5);
} else {
  do_cmd('mincbet', $ARGV[0], "$tmpdir/mri", '-m', '-n','-f', 0.5);
}

if($model_eye_mask && $#ARGV > 1)
{
  do_cmd('mincresample','-like',"$tmpdir/mri_mask.mnc",$model_eye_mask,"$tmpdir/eye_mask.mnc");
  #correct EYE mask using T1w modality
  do_cmd('mincbet', $ARGV[0], "$tmpdir/t1", '-m', '-n','-f', 0.5);
  do_cmd('minccalc', '-expression','A[1]<=0.5?A[0]:0',"$tmpdir/eye_mask.mnc","$tmpdir/t1_mask.mnc","$tmpdir/eye_custom.mnc");
  $ENV{MINC_COMPRESS}=$compress if $compress;
  do_cmd('minccalc', '-expression','(A[0]>0.5 && A[1]<=0.5)?1:0',"$tmpdir/mri_mask.mnc" ,"$tmpdir/eye_custom.mnc", "$tmpdir/bet.mnc", '-clobber','-byte');
} else {
  $ENV{MINC_COMPRESS}=$compress if $compress;
  do_cmd('mincreshape',"$tmpdir/mri_mask.mnc","$tmpdir/bet.mnc",'-byte','-clobber');
}

if($model && $icc_model) #apply non-linear registration
{
  delete $ENV{MINC_COMPRESS} if $compress;

  do_cmd('mincANTS',3,'-m',"CC[$ARGV[0],$model,1,4]",'-i','20x0x0','-t','SyN[0.25]','-o',"$tmpdir/reg.xfm");
  do_cmd('mincresample','-nearest','-like',$ARGV[0],$icc_model,'-transform',"$tmpdir/reg.xfm",'-invert_transformation',"$tmpdir/nlmask.mnc",'-clob');
  do_cmd('itk_morph','--exp','D[4]',"$tmpdir/nlmask.mnc","$tmpdir/nlmask_d4.mnc");
  
  $ENV{MINC_COMPRESS}=$compress if $compress;
  do_cmd('minccalc', '-byte', '-express','A[0]>0.5&&A[1]>0.5?1:0',"$tmpdir/nlmask_d4.mnc","$tmpdir/bet.mnc", $outfile_mnc);
} else {
  do_cmd('cp',"$tmpdir/bet.mnc",$outfile_mnc);
}

pipeline_functions::create_header_info_for_many_parented($outfile_mnc, $ARGV[0], $tmpdir);

@files_to_add_to_db = (@files_to_add_to_db, $outfile_mnc);
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
