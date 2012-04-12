#!/usr/bin/env perl
####################
# this will produce the jacobian mapuse strict;
use Getopt::Long;
use File::Basename;
use File::Temp qw/ tempfile tempdir /;
use pipeline_functions;


my $me = basename($0);
my $verbose = 0;
my $clobber = 0;
my $fake = 0;


GetOptions(
	   'verbose' => \$verbose,
	   'clobber' => \$clobber
	   );

if ($#ARGV < 1){ die "Usage: $me <in_nl_grid> <out_jacobian>\n"; }

my $infile_grid = $ARGV[0];
my $outfile_jacobian = $ARGV[1];


my @args=('mincblob','-determinant',$infile_grid,$outfile_jacobian);
if($clobber) { push(@args, '-clobber'); }
do_cmd(@args);
my $tmpdir = &tempdir( "$me-XXXXXXXX", TMPDIR => 1, CLEANUP => 1 );
pipeline_functions::create_header_info_for_many_parented($outfile_jacobian, $infile_grid, $tmpdir);
my @files_to_add_to_db = ($outfile_jacobian);

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

