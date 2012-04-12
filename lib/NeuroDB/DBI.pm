# ------------------------------ MNI Header ----------------------------------
#@NAME       : NeuroDB::DBI
#@DESCRIPTION: Perform common tasks relating to database connectivity within the NeuroDB system
#@EXPORT     : look at the @EXPORT line below ;P
#@EXPORT_OK  : none
#@EXPORT_TAGS: none
#@USES       : Exporter, DBI (with DBD::mysql)
#@REQUIRES   : 
#@VERSION    : $Id: DBI.pm,v 3.1 2004/05/28 04:24:36 jharlap Exp $
#@CREATED    : 2003/03/18, Jonathan Harlap
#@MODIFIED   : 
#@COPYRIGHT  : Copyright (c) 2003 by Jonathan Harlap, McConnell Brain Imaging
#              Centre, Montreal Neurological Institute, McGill University.
#-----------------------------------------------------------------------------

package NeuroDB::DBI;

use Exporter ();
use DBI;

$VERSION = 0.1;
@ISA = qw(Exporter);

@EXPORT = qw(connect_to_db);
@EXPORT_OK = qw();

# ------------------------------ MNI Header ----------------------------------
#@NAME       : connect_to_db
#@INPUT      : optional: database, username, password, host
#@OUTPUT     : 
#@RETURNS    : DBI database handle
#@DESCRIPTION: connects to database (default: NIH_PD) on host (default ariel) 
#              as username & password (default: mriscript)
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 2003/03/18, Jonathan Harlap
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub connect_to_db
{
    my ($db_name, $db_user, $db_pass, $db_host) = @_;

    my $db_dsn = "DBI:mysql:database=$db_name;host=$db_host;port=$db_port;";

    my $dbh = DBI->connect($db_dsn, $db_user, $db_pass) or die "DB connection failed\nDBI Error: ".$DBI::errstr."\n";

    return $dbh;
}


1;
