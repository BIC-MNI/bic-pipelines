#!/usr/bin/env perl
#
# Vladimir S. Fonov
#
# 2006-06-27
#
#################################################################

use strict;
use Getopt::Long;
use File::Basename;
use File::Temp qw/ tempfile tempdir /;
      
#############################
##user defined variables for clamp
my $me = basename ($0);
my $verbose  = 0;
my $clobber  = 0;
my $fake=0;
my ($model, $modeldir);

chomp($model    = `pipeline_constants -model_tal`);
chomp($modeldir = `pipeline_constants -modeldir_tal`);
my $modelfn  = "$modeldir/$model.mnc";

GetOptions(
	   'verbose' => \$verbose,
	   'clobber' => \$clobber,
     'model=s' => \$modelfn
	   );

if($#ARGV < 2) { die "Usage: $me <infile> <outfile_stats> <outfile_mnc> [--model <model>]\n"; }
my $infile = $ARGV[0];
my $outfile_stats = $ARGV[1];
my $outfile_mnc = $ARGV[2];

##################3
##a list of files to add to the db
my @files_to_add_to_db = ();

#################
##check if everything exists, exit
check_file($outfile_stats) unless $clobber;
check_file($outfile_mnc) unless $clobber;

do_cmd('volume_pol', '--order', 1, '--min', 0, '--max', 100,  $infile, $modelfn,'--expfile', $outfile_stats, '--clobber');
 
@files_to_add_to_db = (@files_to_add_to_db, $outfile_stats);

do_cmd('minccalc', $infile, $outfile_mnc, '-expfile', $outfile_stats, '-clobber');

@files_to_add_to_db = (@files_to_add_to_db, $outfile_mnc);

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
