#!/usr/bin/env perl

use strict;
use File::Basename;
use File::Temp qw/ tempfile tempdir /;
use File::Path;
use Getopt::Long;       
use pipeline_functions;

my $me = basename($0);
my $verbose = 0;
my $fake = 0;
my $clobber = 0;
my $keep_tmp=0;
my $stx_xfm;

GetOptions(
	   'verbose' => \$verbose,
	   'fake'    => \$fake,
	   'clobber' => \$clobber,
     'stx=s'   => \$stx_xfm
	   );

die "Program usage: ${me} <native> <candID> <visit_label> <age> <output> [--stx <xfm>]\n" if $#ARGV < 4 ;

my ($in,$candID,$VisitLabel,$age,$out) = @ARGV;
my @files_to_add_to_db;

check_file($out) unless $clobber;
   
my $tmpdir = &tempdir( "$me-XXXXXXXX", TMPDIR => 1, CLEANUP => !$keep_tmp );

my $imagelabel = sprintf "%s/%s/%5.1f years ", $candID,$VisitLabel,$age;

if($stx_xfm)
{
  do_cmd('make_face.pl',$in,"$tmpdir/face_1.miff",'--threshold',0.8,'--rotate',-10,'--stx',$stx_xfm);
  do_cmd('make_face.pl',$in,"$tmpdir/face_2.miff",'--threshold',0.8,'--stx',$stx_xfm);
  do_cmd('make_face.pl',$in,"$tmpdir/face_3.miff",'--threshold',0.8,'--rotate',10,'--stx',$stx_xfm);
} else {
  do_cmd('make_face.pl',$in,"$tmpdir/face_1.miff",'--threshold',0.8,'--rotate',-10);
  do_cmd('make_face.pl',$in,"$tmpdir/face_2.miff",'--threshold',0.8);
  do_cmd('make_face.pl',$in,"$tmpdir/face_3.miff",'--threshold',0.8,'--rotate',10);
}

my $geo=`identify -format "%wx%h" $tmpdir/face_2.miff`;
chomp($geo);
#my @args = ('convert', '-box', 'white', 
#	       '-font', '7x13bold', 
	       #'-fill', 'white',
#	       '-draw', "text 2,15 \"$imagelabel\"");

#do_cmd(@args,$tmp_out, $out);
do_cmd('montage','-geometry',$geo,"$tmpdir/face_1.miff","$tmpdir/face_2.miff","$tmpdir/face_3.miff",$out);


@files_to_add_to_db = (@files_to_add_to_db, $out);
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
