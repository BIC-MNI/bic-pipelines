#!/usr/bin/env perl

##############################################################################
# 
# pipeline_register_volumes.pl
#
# This pipeline script is unusual because it's the only one that accesses the 
# database itself.  The other pipeline scripts are independent of the database.
#
# Input:
#      o volumes file
#
# Output:
#      o no files but database parameters attached to the volumes file
##############################################################################

use strict;
use Getopt::Long;
use File::Basename;
use File::Temp qw/ tempfile tempdir /;
use NeuroDB::File;
use NeuroDB::DBI;

####################################################################
my $me;
my $verbose      = 0;
my $clobber      = 0;
my $test_only    = 0;
my $input_gi;
my $dbh          = 0;
my $nihpd_user;
my $nihpd_passwd;

$me = basename($0);

GetOptions(
      'verbose'   => \$verbose,
      'clobber'   => \$clobber,
      'test_only' => \$test_only,
      'user=s'    => \$nihpd_user,
      'passwd=s'  => \$nihpd_passwd,
	   );

if($#ARGV < 1){ die "Usage: $me <gi index file> <left|right>\n [--user <user> --passwd <passwd>]\n"; }

#########################
# Get the arguments.
$input_gi = $ARGV[0];
my $side=$ARGV[1];

##########################
# Check the arguments.
if (! -e $input_gi ) { die "$input_gi does not exist\n"; }

##########################
# Connect to the database. 
$dbh = NeuroDB::DBI::connect_to_db('NIH_PD',$nihpd_user,$nihpd_passwd);
if (!$dbh) { die "Cannot connect to db\n"; }

##########################
# Get the fileID's
my $volDbFile = NeuroDB::File->new(\$dbh);
my $volFileId = $volDbFile->findFile($input_gi);
if (! $volFileId ) { $dbh->disconnect(); die "Cannot find $input_gi in database\n"; }

print "$input_gi - $volFileId\n";
$volDbFile->loadFile($volFileId);


if(!open (IN_VOLUMES, "<${input_gi}")) {die "Cannot open $input_gi input file: $!\n" }
my $line;
my $i;

foreach $line(<IN_VOLUMES>)
{
  chomp $line;
  my ($id,$val)=split (':',$line);
  
  $id=~s/\s+/_/g;
  $id="${id}_${side}";
  print "$id => $val\n";
  $volDbFile->setParameter($id,$val); 
}
close(IN_VOLUMES);


#################################
# Close the connection to the db.
$dbh->disconnect();


