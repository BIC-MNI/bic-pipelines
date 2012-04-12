package Candidate;
use English;
use Carp;

=pod

=head1 NAME

NeuroDB::Candidate -- Provides an interface to the MRI file management subsystem of NeuroDB

=head1 SYNOPSIS

 use Candidate;
 use NeuroDB::File;
 use NeuroDB::DBI;

 my $dbh = NeuroDB::DBI::connect_to_db();

 my $file = NeuroDB::File->new(\$dbh);

 my $fileID = $file->findFile('/path/to/some/file');
 $file->loadFile($fileID);

 my $acquisition_date = $file->getParameter('acquisition_date');
 my $parameters_hashref = $file->getParameters();

 my $coordinate_space = $file->getFileDatum('CoordinateSpace');
 my $filedata_hashref = $file->getFileData();


 # less common to use methods, available mainly for register_db...
 my $dbh_copy = $file->getDatabaseHandleRef();

 $file->loadFileFromDisk('/path/to/some/file');
 $file->setFileData('CoordinateSpace', 'nonlinear');
 $file->setParameter('patient_name', 'Larry Wall');

 my $parameterTypeID = $file->getParameterTypeID('patient_name');
 my $parameterTypeCategoryID = $file->getParameterTypeCategoryID('MRI Header');

=head1 DESCRIPTION

This class defines a BIC MRI (or related) file (minc, bicobj, xfm,
etc) as represented within the NeuroDB database system.

B<Note:> if a developer does something naughty (such as leaving out
the database handle ref when instantiating a new object or so on) the
class will croak.

=head1 METHODS

=cut


use strict;

my $VERSION = sprintf "%d.%03d", q$Revision: 1.1.1.1 $ =~ /: (\d+)\.(\d+)/;

=pod
B<new( \$dbh )> (constructor)

Create a new instance of this class.  The parameter C<\$dbh> is a
reference to a DBI database handle, used to set the object's database
handle, so that all the DB-driven methods will work.

Returns: new instance of this class.

=cut

sub new {
    my $params = shift;
    my ($dbhr) = @_;
    unless(defined $dbhr) {
	croak("Usage: ".$params."->new(\$databaseHandleReference)");
    }

    my $self = {};
    $self->{'dbhr'} = $dbhr;
    return bless $self, $params;
}

=pod

B<load_from_candidate_visit( C<$fileID>C<$visit> )>

Load file from candidate and visitno.

=cut
sub load_from_candidate_visit
{
    my $this = shift;
    my ($candID, $visitno) = @_;
    my $query = "SELECT * FROM session WHERE CandID=$candID and VisitNo=$visitno";
    my $sth = ${$this->{'dbhr'}}->prepare($query);
    $sth->execute();

    if($sth->rows == 0) {
	return 0;
    }
    $this->{'session_data'} = {};
    while(my $paramref = $sth->fetchrow_hashref()) 
    {
	$this->{'session_data'} = $paramref;
    }

    $query = "SELECT Name, Value FROM parameter_session left join parameter_type USING (ParameterTypeID) WHERE SessionID=$this->{'session_data'}->{'ID'}";
    $sth = ${$this->{'dbhr'}}->prepare($query);
    $sth->execute();
    
    if($sth->rows == 0) {
	return 0;
    }
    
    $this->{'parameters'} = {};
    #print("SessionID=$this->{'session_data'}->{'ID'}\n");
    while(my $paramref = $sth->fetchrow_hashref()) 
    {
	$this->{'parameters'}->{$paramref->{'Name'}} = $paramref->{'Value'};
#	print("parameterinfo  $paramref->{'Name'}= $paramref->{'Value'}\n");
    }

    $query = "SELECT * FROM files WHERE SessionID=$this->{'session_data'}->{'ID'}";
    $sth = ${$this->{'dbhr'}}->prepare($query);
    $sth->execute();
    
    if($sth->rows == 0) {
	return 0;
    }
    
    $this->{'files'} = {};
    while(my $paramref = $sth->fetchrow_hashref()) 
    {
	$this->{'parameters'}->{$paramref->{'FileID'}} = $paramref->{'Value'};
    }


    return 1;
}
    

=pod

B<getParameters( )>

Gets the set of parameters for the loaded file (data from the C<parameter_file> table in the database).

Returns: hashref of the records in the C<parameter_file> table for the loaded file.

=cut
sub getParameters {
    my $this = shift;
    return $this->{'parameters'};
}

=pod
B<getParameter( C<$parameterName> )>

Gets one element from the file's parameters (data from the C<parameter_file> table in the database).

Returns: scalar of the particular parameter requested pertaining to the loaded file.

=cut

sub getParameter {
    my $this = shift;
    my ($paramName) = @_;

    return $this->{'parameters'}->{$paramName};
}
=pod

B<getSessionInfo( )>

Gets the set of parameters for the loaded file (data from the C<parameter_file> table in the database).

Returns: hashref of the records in the C<parameter_file> table for the loaded file.

=cut
sub getSessionInfo {
    my $this = shift;
    return $this->{'session_data'};
}
=pod
B<getSessionParameter( C<$parameterName> )>

Gets one element from the file's parameters (data from the C<parameter_file> table in the database).

Returns: scalar of the particular parameter requested pertaining to the loaded file.

=cut

sub getSessionParameter {
    my $this = shift;
    my ($paramName) = @_;

    return $this->{'session_data'}->{$paramName};
}

=pod
B<findSelectedFileID( $filename )>

Finds the FileID pertaining to a file as defined by
parameter C<$filename>, which is a full /path/to/file.

Returns: (int) FileID or undef if no file was found.

=cut

sub findSelectedFileID {
    my $this = shift;
    my ($coordinate_space, $classify_Algorithm, $output_type, $selected) = @_;
    my $query = "";
    if($selected)
    {
	
	my $query = "SELECT FileID FROM parameter_file inner join files on parameter_file.fileid = files.fileid inner join parameter_type on parameter_file.parametertypeid = parameter_type.parametertypeid WHERE sessionID= $this->{'session_data'}->{'ID'} and coordinatespace = '$coordinate_space' and classifyalgorithm =  '$classify_Algorithm' and outputtype = '$output_type' and name = 'selected' and value = $selected";
    }
    else
    {
	my $query = "SELECT FileID FROM files WHERE sessionID= $this->{'session_data'}->{'ID'} and coordinatespace = '$coordinate_space' and classifyalgorithm =  '$classify_Algorithm' and outputtype = '$output_type'";
    }

    my $sth = ${$this->{'dbhr'}}->prepare($query);
    $sth->execute();

    if($sth->rows == 0) {
	return undef;
    } else {
	my $row = $sth->fetchrow();
	return $row;
    }
}

sub findSelectedFilePath {
    my $this = shift;
    my ($coordinate_space, $classify_Algorithm, $output_type, $selected) = @_;
    my $query = "";

    if($selected)
    {
	my $query = "SELECT File FROM parameter_file inner join files on parameter_file.fileid = files.fileid inner join parameter_type on parameter_file.parametertypeid = parameter_type.parametertypeid WHERE sessionID= $this->{'session_data'}->{'ID'} and coordinatespace = '$coordinate_space' and classifyalgorithm =  '$classify_Algorithm' and outputtype = '$output_type' and name = 'selected' and value = $selected";
    }
    else
    {
	my $query = "SELECT File FROM files WHERE sessionID= $this->{'session_data'}->{'ID'} and coordinatespace = '$coordinate_space' and classifyalgorithm =  '$classify_Algorithm' and outputtype = '$output_type'";
    }

    my $sth = ${$this->{'dbhr'}}->prepare($query);
    $sth->execute();

    if($sth->rows == 0) {
	return undef;
    } else {
	my $row = $sth->fetchrow();
	return $row;
    }
}

sub returnPath
{

    my $this = shift;
    my ($coordinate_space, $classify_Algorithm, $output_type, $selected) = @_;
    my $candid = $this->{'session_data'}->{'CandID'};
    my $visit = $this->{'session_data'}->{'VisitNo'};
    
    my $return_string = "";

##TODO change this all
    if($coordinate_space eq 'native')
    {
	return "/data/nihpd/nihpd1/data/assembly/$candid/$visit/mri/final/$output_type/nihpd_pipe_v1_${candid}_${visit}_obj1_${selected}.mnc"
    }
    if($classify_Algorithm)
    {
	return "/data/nihpd/nihpd1/data/assembly/$candid/$visit/mri/final/$output_type/nihpd_pipe_v1_${candid}_${visit}_obj1_${selected}.mnc";
    }
    else
    {
return "/data/nihpd/nihpd1/data/assembly/$candid/$visit/mri/final/$output_type/nihpd_pipe_v1_${candid}_${visit}_obj1_${selected}.mnc";	
    }
    return $return_string;
}
