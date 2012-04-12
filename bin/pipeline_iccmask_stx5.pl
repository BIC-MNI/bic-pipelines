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
GetOptions(
	   'verbose'    => \$verbose,
	   'clobber'    => \$clobber,
     'eye_mask=s' => \$model_eye_mask,
	   );

if ($#ARGV < 1){ die "Usage: $me <infile_t1> [infilet2] [infilepd] <outfile_mnc> [--eye_mask <eye_mask>]\n"; }

#####################
##infile includes the tal transformed anatomical data
##outfile is the single mask
my $outfile_mnc=pop(@ARGV);

check_file($outfile_mnc) unless($clobber);

my @files_to_add_to_db = ();

my $tmpdir = &tempdir( "${me}-XXXXXXXX", TMPDIR => 1, CLEANUP => 1 );

do_cmd('minccalc','-express','clamp(A[0],0,100)',$ARGV[0],"$tmpdir/t1.mnc");

# calculate masks for T1, T2 and PD
my $i;
my $j=0;

#if($#ARGV > 1)
#{
  # we are trying to get ICC mask
#  do_cmd('mincaverage',@ARGV,"$tmpdir/avg.mnc");
  #do_cmd('imp_bet.pl', "$tmpdir/avg.mnc", "$tmpdir/mri_mask.mnc");
#  do_cmd('mincbet', "$tmpdir/avg.mnc", "$tmpdir/mri",'-m','-n','-h',1.15);
#} else {
  #do_cmd('imp_bet.pl', $ARGV[0], "$tmpdir/mri_mask.mnc");
  do_cmd('mincbet', "$tmpdir/t1.mnc", "$tmpdir/mri",'-m','-n');
#}

if($model_eye_mask )#&& $#ARGV > 1
{
  do_cmd('mincresample','-like',"$tmpdir/mri_mask.mnc",$model_eye_mask,"$tmpdir/eye_mask.mnc");
  #correct EYE mask using T1w modality
  #do_cmd('imp_bet.pl', $ARGV[0], "$tmpdir/t1_mask.mnc");
  #do_cmd('mincbet', $ARGV[0], "$tmpdir/t1",'-m','-n','-h',1.15);
  #do_cmd('minccalc', '-expression','A[1]<=0.5?A[0]:0',"$tmpdir/eye_mask.mnc","$tmpdir/t1_mask.mnc","$tmpdir/eye_custom.mnc");
  #do_cmd('minccalc', '-expression','(A[0]>0.5 && A[1]<=0.5)?1:0',"$tmpdir/mri_mask.mnc" ,"$tmpdir/eye_custom.mnc", $outfile_mnc, '-clobber','-byte');
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
