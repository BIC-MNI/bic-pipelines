#!/usr/bin/env perl

use strict;
use Getopt::Long;
use File::Basename;
use File::Temp qw/ tempdir /;

my $me = basename ($0);
my $verbose=1;
my $clobber=0;
my $fake=0;
my $mask;

GetOptions(
      'verbose'           => \$verbose,
      'clobber'           => \$clobber,
      'mask=s'            => \$mask
	   );

my $Help = <<HELP;
  Usage: $me <input 1> <input 2> .... <output> [--mask <mask>]
    --verbose be verbose
    --clobber clobber _all_ output files
  do T2 relaxometry fitting on all input files
  Problems or comments should be sent to: vfonov\@bic.mni.mcgill.ca
HELP

die $Help if $#ARGV < 2;
my $output=pop @ARGV;
my @files_to_add_to_db = ();

check_file($output) unless $clobber;

my @args=('t2_fit',@ARGV, $output, '--clobber');

push @args,'--mask',$mask if $mask;

do_cmd(@args);
@files_to_add_to_db = ($output);

print("Files created:@files_to_add_to_db\n");

sub check_file {
  die("${_[0]} exists!\n") if -e $_[0];
}


sub do_cmd {
    print STDOUT "@_\n" if $verbose;
    if(!$fake) {
        system(@_) == 0 or die "DIED: ".join(',',@_)."\n";
    }
}