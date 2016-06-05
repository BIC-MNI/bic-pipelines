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
my $dummy = "";
my $model_eye_mask;
my $fake    = 0;
my $nlmask  = 0;
my $model;
my $icc_model;
my $beastlib='';
my $beast_resolution = "default.2mm.conf";

GetOptions(
	   'verbose'    => \$verbose,
	   'clobber'    => \$clobber,
     'eye_mask=s' => \$model_eye_mask,
     'nlmask'     => \$nlmask,
     'model=s'    => \$model,
     'icc_model=s' => \$icc_model,
     'beastlib=s' => \$beastlib,
     'beast_resolution=s' => \$beast_resolution
	   );

if ($#ARGV < 1){ die "Usage: $me <infile_t1> [infilet2] [infilepd] <outfile_mnc> [--eye_mask <eye_mask>] [--nlmask --model model_t1.mnc ---icc_model model_icc.mnc --beastlib <lib>] --beast_resolution <resolution_file>\n"; }

#####################
##infile includes the tal transformed anatomical data
##outfile is the single mask
my $outfile_mnc=pop(@ARGV);

check_file($outfile_mnc) unless($clobber);

my @files_to_add_to_db = ();

my $tmpdir = &tempdir( "${me}-XXXXXXXX", TMPDIR => 1, CLEANUP => 1 );

#do_cmd('minccalc','-express','clamp(A[0],0,100)',$ARGV[0],"$tmpdir/t1.mnc");
my $in_t1w=$ARGV[0];

# calculate masks for T1, T2 and PD
my $i;
my $j=0;

if($nlmask) {
  do_cmd('icc_mask.pl',$in_t1w, "$tmpdir/mri_mask.mnc",'--model',$model,'--icc-model',$icc_model);
} else {
  do_cmd('mincresample','-nearest','-like',"$beastlib/union_mask.mnc",$in_t1w,"$tmpdir/input_t1w.mnc");
  do_cmd('mincbeast', $beastlib, "$tmpdir/input_t1w.mnc", "$tmpdir/mri_mask_.mnc",'-fill','-same_resolution','-median','-configuration',"${beastlib}/${beast_resolution}");
  do_cmd('mincresample','-nearest','-like',$in_t1w,"$tmpdir/mri_mask_.mnc","$tmpdir/mri_mask.mnc");
}

if($model_eye_mask )
{
  do_cmd('mincresample','-like',"$tmpdir/mri_mask.mnc",$model_eye_mask,"$tmpdir/eye_mask.mnc");
  do_cmd('minccalc', '-expression','(A[0]>0.5 && A[1]<=0.5)?1:0',"$tmpdir/mri_mask.mnc" ,"$tmpdir/eye_mask.mnc", $outfile_mnc, '-clobber','-byte');
} else {
  do_cmd('mincreshape',"$tmpdir/mri_mask.mnc",$outfile_mnc,'-byte','-clobber');
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
