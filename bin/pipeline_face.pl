#!/usr/bin/env perl

use strict;
use Getopt::Long;
use File::Basename;
use File::Temp qw/ tempdir /;


my $me          = basename($0);
my $verbose     = 1;
my $clobber     = 0;
my $fake        = 0;
my $infile_classified;
my $infile_lobes;
my $infile_xfm;
my $outfile_volumes;
my $infile_tal_mask;
my $age=0.0;
#my $infile_seg;
my $scanner='na';
my $scanner_id=-1;
my @files_to_add_to_db = ();


GetOptions(
	   'verbose' => \$verbose,
	   'clobber' => \$clobber,
	   );

if($#ARGV < 6)
{ 
   die "Usage: $me <t1 tal> <brain mask tal> <classified tal> <labels tal>  <xfm tal> <nlxfm tal> <output> \n";
}


my ($t1,$mask,$cls,$lob,$lin_xfm,$nl_xfm,$output)=@ARGV;

my $face_dir=`which FACE.sh`;
chomp($face_dir);
$face_dir=~s/\/bin\/FACE\.sh//;

my $outdir=dirname($output);
$outdir=~s/\/atlas[\/]//;

do_cmd('FACE.sh',$t1,$mask,$cls,$lob,$lin_xfm,$nl_xfm,$outdir,$face_dir,'default');
do_cmd("cd $outdir;make");

#my @files_to_add_to_db = (@files_to_add_to_db, $outfile_volumes);

#print("Files created:@files_to_add_to_db\n");

sub do_cmd { 
    print STDOUT "@_\n" if $verbose;
    if(!$fake){
      system(@_) == 0 or die "DIED: @_\n";
    }
}

sub check_file {
  die("${_[0]} exists!\n") if -e $_[0];
}
