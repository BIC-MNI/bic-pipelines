#! /usr/bin/env perl
use strict;
use File::Basename;
use File::Temp qw/ tempfile tempdir /;
use Getopt::Long;
use POSIX qw(floor);

my $fake=0;
my $verbose=0;
my $clobber=0;
my $mask;
my $me=basename($0);

GetOptions (    
          "verbose"   => \$verbose,
          "clobber"   => \$clobber,
          "mask=s"    => \$mask
          );
          
die "Usage: $me <scan_in> <brain_mask_out> \n[--verbose\n --clobber\n --mask <model_mask>\n]\n" if $#ARGV<1;

my ($in,$out)=@ARGV;

check_file($out) unless $clobber;

my $tmpdir = &tempdir( "$me-XXXXXXXX", TMPDIR => 1, CLEANUP => 1 );

do_cmd('mincbet',$in,"$tmpdir/brain",'-n', '-m', '-f', 0.5, '-h', 1.10);
do_cmd('mincreshape','-byte',"$tmpdir/brain_mask.mnc",$out,'-clobber');

sub do_cmd {
    print STDOUT "@_\n" if $verbose;
    if(!$fake) {
        system(@_) == 0 or die "DIED: @_\n";
}
}

sub check_file {
  die("${_[0]} exists!\n") if -e $_[0];
}
