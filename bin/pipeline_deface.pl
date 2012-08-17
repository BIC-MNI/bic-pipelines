#!/usr/bin/env perl

##############################################################################
# 
# pipeline_deface.pl
#
# Input:
#      o native volume
#
# Output:
#      o the native volume with face distorted (defaced)
#
# Command line interface: 
#      pipeline_deface.pl 
#
# Vladimir FONOV 2012
# McConnell Brain Imaging Centre, 
# Montreal Neurological Institute, 
# McGill University
##############################################################################

use strict;
use Getopt::Long;
use File::Basename;
use File::Temp qw/tempdir /;
use pipeline_functions;
 
my $me= &basename($0);
my $verbose     = 0;
my $clobber     = 0;
my $fake        = 0;
my $smooth;
my $watermark;
my $model_dir;
my @files_to_add_to_db = ();

my $dual_echo;
my $no_int_norm=0;
my $watermark=0;
my $t1w_xfm;
my $t2w_xfm;
my $pdw_xfm;
my $brain_mask;
my $keep_real_range;
my $model_dir;
my $model_name;
my $nonlinear=0;
my $keep_tmp=0;
my $output_base;
GetOptions (
  "verbose"       => \$verbose,
  "clobber"       => \$clobber,
  "dual-echo"     => \$dual_echo,
  "model-dir=s"   => \$model_dir,
  "model=s"       => \$model_name,
  "nonlinear"     => \$nonlinear,
  'no-int-norm'   => \$no_int_norm,
  'watermark'     => \$watermark,
  't1w-xfm=s'     => \$t1w_xfm,
  't2w-xfm=s'     => \$t2w_xfm,
  'pdw-xfm=s'     => \$pdw_xfm,
  'brain-mask=s'  => \$brain_mask,
  'keep-tmp'      => \$keep_tmp,
  'keep-real-range' => \$keep_real_range,
  'output=s'        => \$output_base,
); 

die <<HELP
Usage: $me <T1w> [T2w] [PDw]
 --model-dir <model directory>
 --model     <model name>
 --output <output_base>
 [--verbose
  --clobber
  --dual-echo - assume dual echo T2/PD
  --nonlinear  perform quick nonlinear registration to compensate for different head shape (i.e for small kids)
  --watermark watermark output files
  --no-int-norm - don't normalize output file to 0-4095 range, usefull only for watermarking
  --t1w-xfm <t1w.xfm>
  --t2w-xfm <t2w.xfm>
  --pdw-xfm <pdw.xfm>
  --keep-real-range - keep the real range of the data the same 
  ]
HELP
if $#ARGV<1 || ! $output_base || !$model_name || !$model_dir;

my ($t1w,$t2w,$pdw)=@ARGV;

@files_to_add_to_db=("${output_base}_t1w.mnc");

my @args=('deface_minipipe.pl',$t1w,);
if($t2w)
{
  push @args,$t2w;
  push @files_to_add_to_db,"${output_base}_t2w.mnc";
}

if($pdw)
{
  push @args,$pdw;
  push @files_to_add_to_db,"${output_base}_pdw.mnc";
}

push @args,$output_base;

push @args,'--model',$model_name;
push @args,'--model-dir',$model_dir;

push @args,'--nonlinear' if $nonlinear;
push @args,'--brain-mask $brain_mask' if $brain_mask;
push @args,'--keep-real-range' if $keep_real_range;
push @args,'--keep-real-range' if $keep_real_range;
push @args,'--dual-echo' if $dual_echo;
push @args,'--watermark' if $watermark;

push @args,'--t1w-xfm',$t1w_xfm if $t1w_xfm;
push @args,'--t2w-xfm',$t2w_xfm if $t2w_xfm;
push @args,'--pdw-xfm',$pdw_xfm if $pdw_xfm;

do_cmd(@args);

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
