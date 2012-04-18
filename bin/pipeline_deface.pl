#!/usr/bin/env perl

##############################################################################
# 
# pipeline_deface.pl
#
# Input:
#      o native volume
#      o native to tal xfm file
#      o the tal mask
#      o the defacing grid (in talairach space)
#
# Output:
#      o the native volume with face distorted (defaced)
#
# Command line interface: 
#      pipeline_deface.pl <native>  <xfm> <tal mask> <output>
#
# Larry Baer, April, 2006
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

GetOptions(
	   'verbose' => \$verbose,
	   'clobber' => \$clobber,
     'watermark' => \$watermark,
     'model_dir=s' => \$model_dir,
     'smooth=f'    => \$smooth
	   );

if($#ARGV < 3) { die "Usage: $me <native> <xfm> <deface_grid> <output> --watermark --model_dir <dir>\n"; }
die "Please set --model_dir for watermarking!\n" if $watermark && !$model_dir;

# Get the arguments.
my ($native,$xfm,$deface_grid,$output) = @ARGV;

check_file($output) unless $clobber;
my $tmpdir = &tempdir( "$me-XXXXXXXX", TMPDIR => 1, CLEANUP => 1 );

#do_cmd('deface_volume.pl', $native, $face, $mask, $xfm, $output, '--clobber', '--tal_grid', $deface_grid);
do_cmd('xfminvert',$xfm,"$tmpdir/native.xfm");
do_cmd('uniformize_minc.pl',$native,"$tmpdir/scan.mnc",'--step',2);
do_cmd('resample_grid',$deface_grid,"$tmpdir/native.xfm","$tmpdir/deface_grid_0.mnc",'--like',"$tmpdir/scan.mnc");

open XFM,">$tmpdir/deface.xfm" or die;
print XFM "MNI Transform File\nTransform_Type = Grid_Transform;\nDisplacement_Volume = deface_grid_0.mnc;\n";
close XFM;
#modulate scan
if($watermark)
{
  do_cmd('mincresample','-nearest','-transform',"$tmpdir/deface.xfm",$native,"$tmpdir/defaced.mnc",'-clobber','-use_input_sampling');
  do_cmd('pipeline_watermark.pl',"$tmpdir/defaced.mnc",$output,'--model_dir',$model_dir,'--clobber');
}else{
  do_cmd('mincresample','-nearest','-transform',"$tmpdir/deface.xfm",$native,$output,'-clobber','-use_input_sampling');
}


@files_to_add_to_db = (@files_to_add_to_db, $output);
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
