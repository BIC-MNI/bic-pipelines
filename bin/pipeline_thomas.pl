#!/usr/bin/env perl
#
#
# Vladimir Fonov
# Pipeline step that will produce data for thomas

use strict;
use Getopt::Long;
use File::Basename;
use File::Temp qw/ tempfile tempdir /;
use pipeline_functions;
      
my $me = basename($0);
my $verbose = 0;
my $clobber = 0;
my $fake=0;

GetOptions(
	   'verbose' => \$verbose,
	   'clobber' => \$clobber
	   );


if ($#ARGV < 5){ die "Usage: $me <in_tal_cls> <in_nl_xfm> <in_jacobian> <out_csf> <out_gm> <out_wm>\n"; }

my $in_cls=$ARGV[0];
my $in_xfm=$ARGV[1];
my $in_jacobian=$ARGV[2];
my @out=( $ARGV[3], $ARGV[4], $ARGV[5]);
my @out_labels = (1,2,3);

die "$out[0] exists\n" if -e $out[0] && !$clobber;
die "$out[1] exists\n" if -e $out[1] && !$clobber;
die "$out[2] exists\n" if -e $out[2] && !$clobber;

my $tmpdir = &tempdir( "$me-XXXXXXXX", TMPDIR => 1, CLEANUP => 1);
my $tmp_cls_file="${tmpdir}/cls.mnc";
do_cmd('mincresample', '-nearest_neighbour', '-use_input_sampling', $in_cls, '-transformation', $in_xfm, $tmp_cls_file);
my $tmp_jacobian="${tmpdir}/jacobian.mnc";

do_cmd('mincresample','-like',$tmp_cls_file,$in_jacobian,$tmp_jacobian);

my $i=0;
my @files_to_add_to_db;
my $file;
foreach $file(@out)
{
	my $label=$out_labels[$i];
	
	my $tmpfile="${tmpdir}/${label}.mnc";
	my $tmpfile2="${tmpdir}/${label}_2.mnc";
	my $tmpfile3="${tmpdir}/${label}_3";
	do_cmd('minclookup', '-discrete', '-lut_string', "$label 1", $tmp_cls_file, $tmpfile);
	do_cmd('minccalc','-expression','A[1]==1?A[0]:0',$tmp_jacobian, $tmpfile, $tmpfile2);
	do_cmd('mincblur','-fwhm',10, $tmpfile2, $tmpfile3);
	$tmpfile3="${tmpfile3}_blur.mnc";
	pipeline_functions::create_header_info_for_many_parented($tmpfile3, $in_cls, $tmpdir);
	do_cmd('cp', $tmpfile3, $file);
	push(@files_to_add_to_db, $file);
	$i+=1;
}

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

