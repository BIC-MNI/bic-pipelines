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
my $input_volumes;
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

if($#ARGV < 0){ die "Usage: $me <input volumes>\n [--user <user> --passwd <passwd>]"; }

#########################
# Get the arguments.
$input_volumes = $ARGV[0];

##########################
# Check the arguments.
if (! -e $input_volumes ) { die "$input_volumes does not exist\n"; }

##########################
# Connect to the database. 
$dbh = NeuroDB::DBI::connect_to_db('NIH_PD',$nihpd_user,$nihpd_passwd);
if (!$dbh) { die "Cannot connect to db\n"; }

##########################
# Get the fileID's
my $volDbFile = NeuroDB::File->new(\$dbh);
my $volFileId = $volDbFile->findFile($input_volumes);
if (! $volFileId ) { $dbh->disconnect(); die "Cannot find $input_volumes in database\n"; }

print "$input_volumes - $volFileId\n";
$volDbFile->loadFile($volFileId);

open (IN_VOLUMES, "<${input_volumes}") or die "Cannot open $input_volumes input file: $!";
my $line;

foreach $line(<IN_VOLUMES>)
{
  chomp $line;
  my ($id,$val)=split (/\s/,$line);
  print $id,"->",$val,"\n";
  #add information into DB
  $volDbFile->setParameter($id,$val); 
}

#################################
# Close the connection to the db.
$dbh->disconnect();


