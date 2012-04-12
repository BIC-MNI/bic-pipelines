#!/usr/bin/env perl

##############################################################################
# 
# pipeline_deface_grid.pl
#
# Input:
#      none
#
# Output:
#      o the distortion grid
#
# Command line interface: 
#      pipeline_deface_grid.pl <output>
#
# Vladimir S Fonov, April, 2006
# McConnell Brain Imaging Centre, 
# Montreal Neurological Institute, 
# McGill University
##############################################################################


use strict;
use Getopt::Long;
use File::Basename;
use File::Temp qw/tempdir /;
use pipeline_functions;
my $amp=12;
my $fwhm=6;
 
my $me= &basename($0);
my $verbose     = 0;
my $clobber     = 0;
my $fake        = 0;
my $keep_tmp=0;
my @files_to_add_to_db = ();

my ($face_mask,$model_dir);
chomp($model_dir    = `pipeline_constants -modeldir_tal`);
chomp($face_mask    = `pipeline_constants -face_mask_lr`);
my $face=$model_dir.'/'.$face_mask;

GetOptions(
	   'verbose' => \$verbose,
	   'clobber' => \$clobber,
     'face_mask=s'=> \$face
	   );

if($#ARGV < 1) { die "Usage: $me <brain_mask> <output_grid> [--face_mask <file>]\n"; }
my ($brain,$output)=@ARGV;

check_file($output) unless $clobber;
my $tmpdir = &tempdir( "$me-XXXXXXXX", TMPDIR => 1, CLEANUP => !$keep_tmp );



do_cmd('make_random_grid.pl', '--clobber', '--mask', $face, $face, "$tmpdir/grid.mnc",'--amplitude', $amp, '--fwhm', $fwhm);

do_cmd('mincmorph','-successive','DD',$brain,"$tmpdir/brain.mnc");
do_cmd('mincmorph','-successive','D',$face,"$tmpdir/face.mnc");
do_cmd('mincresample',"$tmpdir/brain.mnc","$tmpdir/brain2.mnc",'-like',"$tmpdir/face.mnc",'-nearest','-clobber');
do_cmd('minccalc','-expression','A[0]==1&&A[1]==0?1:0', "$tmpdir/face.mnc", "$tmpdir/brain2.mnc", "$tmpdir/face2.mnc",'-clobber');
do_cmd('rm','-f',"$tmpdir/brain.mnc","$tmpdir/brain2.mnc");
do_cmd('mincresample',"$tmpdir/face2.mnc","$tmpdir/face.mnc",'-like',"$tmpdir/grid.mnc",'-nearest','-clobber');
do_cmd('mincconcat', '-clobber', '-concat_dimension', 'vector_dimension', '-coordlist',"0,1,2", "$tmpdir/face.mnc","$tmpdir/face.mnc","$tmpdir/face.mnc", "$tmpdir/face2.mnc",'-clobber');
do_cmd('minccalc', '-expression', 'A[0]*A[1]',"$tmpdir/face2.mnc", "$tmpdir/grid.mnc", $output,'-clobber');

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
