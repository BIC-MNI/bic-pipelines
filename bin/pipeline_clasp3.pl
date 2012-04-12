#!/usr/bin/env perl

##############################################################################
# 
# pipeline_clasp.pl
#
# Input:
#      o classified mnc
#      o T1 Tal mnc
#      o native-to-tal xfm file
#      o prefix for output files (including output filepath)
#
# Output:
#      o *.obj files and a text file for cortical thickness in native space
#        Use brain-view <.obj> <.txt> to view the cortical thickness measures.
#
#
# Larry Baer, March, 2005
# McConnell Brain Imaging Centre, 
# Montreal Neurological Institute, 
# McGill University
##############################################################################

use strict;
use Getopt::Long;
use File::Basename;
use File::Temp qw/ tempfile tempdir /;
use NeuroDB::File;
use NeuroDB::DBI;

####################################################################
my $me = &basename( $0 );
my $verbose     = 0;
my $clobber     = 0;
my $fake        = 0;
my @files_to_add_to_db = ();

GetOptions(
	   'verbose' => \$verbose,
	   'clobber' => \$clobber
	   );

if($#ARGV < 10){ die "Usage: $me <input classified file> <input T1 tal file> <input xfm file> <gray_surface_left> <gray_surface_right> <white_surface_left> <white_surface_right> <left_native_thickness_out> <right_native_thickness_out> <left_stx_thickness_out> <right_stx_thickness_out>\n"; }

#########################
# Get the arguments.
my ($in_cls,$in_t1, $in_xfm, $in_gray_left, $in_gray_right, $in_white_left, $in_white_right, $out_left_native, $out_right_native, $out_left_stx, $out_right_stx) = @ARGV; 

check_existance($in_cls,$in_t1, $in_xfm, $in_gray_left, $in_gray_right, $in_white_left, $in_white_right);

check_nonexistance($out_left_native, $out_right_native, $out_left_stx, $out_right_stx) unless $clobber;

#setup environment for the clasp
my $BINDIR="/data/ipl/proj01/nihpd/analysis_vladimir/data/auto_quarantine";
my $TOPDIR=$ENV{"TOPDIR"};
my $PATH=$ENV{"PATH"};

$ENV{"PATH"}="${BINDIR}/bin:${TOPDIR}/pipeline/bin:${TOPDIR}/pipeline/util:${PATH}:${TOPDIR}/bin2:${PATH}";
$ENV{"PERL5LIB"}="${BINDIR}/perl:${TOPDIR}/pipeline/lib";
$ENV{"MNI_DATAPATH"}="${BINDIR}/share";

my $thickness='-tlink';

do_cmd('cortical_thickness', $thickness, $in_gray_left, $in_white_left, $out_left_stx);
do_cmd('cortical_thickness', $thickness, $in_gray_right, $in_white_right, $out_right_stx);


#put objects back into native space
my $tmpdir = &tempdir( "$me-XXXXXXXX", TMPDIR => 1, CLEANUP => 1 );
do_cmd('xfminvert', $in_xfm, "${tmpdir}/tal_to_native.xfm");


do_cmd("transform_objects", $in_gray_left, "${tmpdir}/tal_to_native.xfm", "${tmpdir}/gray_left.obj");
do_cmd("transform_objects", $in_white_left,  "${tmpdir}/tal_to_native.xfm", "${tmpdir}/white_left.obj");

do_cmd("transform_objects", $in_gray_right, "${tmpdir}/tal_to_native.xfm", "${tmpdir}/gray_right.obj");
do_cmd("transform_objects", $in_white_right, "${tmpdir}/tal_to_native.xfm", "${tmpdir}/white_right.obj");

do_cmd('cortical_thickness', $thickness, "${tmpdir}/white_left.obj", "${tmpdir}/gray_left.obj", $out_left_native);
do_cmd('cortical_thickness', $thickness, "${tmpdir}/white_right.obj", "${tmpdir}/gray_right.obj", $out_right_native);

@files_to_add_to_db = ($in_gray_left, $in_gray_right, $in_white_left, $in_white_right, $out_left_native, $out_right_native, $out_left_stx, $out_right_stx);


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

sub check_existance {
  my $f;
  foreach $f(@_) {
    die "$f doesn't exists!\n" unless -e $f;
  }
}

sub check_nonexistance {
  my $f;
  foreach $f(@_) {
    die "$f exists!\n" unless ! -e $f;
  }
}
