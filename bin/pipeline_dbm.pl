#!/usr/bin/env perl
#
use Getopt::Long;
use File::Basename;
use File::Temp qw/ tempfile tempdir /;
use strict;
      
my $me = basename($0);
my $verbose = 0;
my $clobber = 0;
my $fwhm=8;
my $fake=0;
my $xfm;
my $model;

GetOptions(
	   'verbose' => \$verbose,
	   'clobber' => \$clobber,
     'fwhm=f'  => \$fwhm,
     'model=s' => \$model
	   );


############################
##We are smoothing the brain matter probability maps
##as input we need the classified scan (either linear, or non-linear)
##and we produce three output_scans
die <<HELP 
Usage: 
$me <infile_xfm>  <outfile_dbm>
    [ --fwhm <f> blurring kernel , default $fwhm
      --model <model.mnc>
      --verbose be verbose
      --clobber clobber output files
    ]
HELP
if $#ARGV < 1;


my $infile_xfm = $ARGV[0];
my $outfile_dbm = $ARGV[1];

check_file($outfile_dbm) unless $clobber;

my $tmpdir = &tempdir( "$me-XXXXXXXX", TMPDIR => 1, CLEANUP => 1 );

my $compress=$ENV{MINC_COMPRESS};
delete $ENV{MINC_COMPRESS} if $compress;

my @files_to_add_to_db = ();


#do_cmd('xfminvert',$infile_xfm,"$tmpdir/inv.xfm");
do_cmd('xfm_normalize.pl',$infile_xfm,'--like',$model,'--step',2,"$tmpdir/inv_norm.xfm",'--invert');
do_cmd('grid_proc','--det',"$tmpdir/inv_norm_grid_0.mnc","$tmpdir/inv_norm_det.mnc");
$ENV{MINC_COMPRESS}=$compress if $compress;
do_cmd('fast_blur','--fwhm',$fwhm,"$tmpdir/inv_norm_det.mnc",$outfile_dbm,'--clobber');

@files_to_add_to_db = (@files_to_add_to_db, $outfile_dbm);

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
  my $i;
  foreach $i(@_) {
    die("$i exists!\n") if -e $i;
  }
}
