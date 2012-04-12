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
my $model;
my $model_icc;
my $fake    = 0;
GetOptions(
    'verbose'     => \$verbose,
    'clobber'     => \$clobber,
    'model=s'     => \$model,
    'model-icc=s' => \$model_icc
	   );

if ($#ARGV < 1){ die "Usage: $me <infile_t1> [infilet2] [infilepd] <outfile_mnc> --mode <t1 model> --model-icc <icc model>\n"; }

#####################
##infile includes the tal transformed anatomical data
##outfile is the single mask
my $outfile_mnc=pop(@ARGV);

check_file($outfile_mnc) unless($clobber);

my @files_to_add_to_db = ();

my $tmpdir = &tempdir( "${me}-XXXXXXXX", TMPDIR => 1, CLEANUP => 1 );

#do_cmd('minccalc','-express','clamp(A[0],0,100)',$ARGV[0],"$tmpdir/t1.mnc");

# calculate masks for T1, T2 and PD
my $i;
my $j=0;

do_cmd('icc_mask_ants.pl',$ARGV[0],$outfile_mnc,'--model',$model,'--icc-model',$model_icc);

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
