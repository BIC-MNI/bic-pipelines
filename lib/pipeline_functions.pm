package pipeline_functions;

##################################################
##All of this is pm mumbo jumbo stuff.
use Startup;
use File::Spec;
#use NeuroDB::DBI;
use File::Basename;

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

require Exporter;
&Startup();
@ISA = qw(Exporter AutoLoader);
# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.
@EXPORT = qw(GetDateOfVisit GetCandidateDateOfBirth GetCandidateInfo CalcAgeAtVisit GetSelectedScan);
$VERSION = '0.01';
##end pm stuff
##################################################

sub make_query
{
    my ($dbh,$search_criteria) = @_;
    my @output = ();

    $search_criteria =~ s/complete_path/concat_ws(\'\/\', Data_path, Core_path, File_type, File_name)/;

    #print("DEBUG final search criteria:$search_criteria\n\n");

    my $sth = $dbh->prepare($search_criteria);
    $sth->execute();
    if($sth->rows > 0) 
    {
      @results = "";	
      while(@results = $sth->fetchrow_array()) 
      {	    
        if(@results)
        {	      
          @output = (@output, @results);
        }
      }
    }
  $sth->finish();
  return @output;
}

# Based on create_header_info_for_many_parentedKitching.
# Some scripts don't copy header info from source to target so 
# copy the header info necessary for the mnc to be inserted into the database - Larry
sub create_header_info_for_many_parented
{
  ($child_mnc_file, $parent_mnc_file, $tmpdir) = @_;
    #VF check .gz files

  if(!-e $child_mnc_file) {
    if(-e $child_mnc_file.".gz") {
	    $child_mnc_file=$child_mnc_file.".gz";
    } else {
	    die "pipeline_functions::create_header_info_for_many_parented ${child_mnc_file} doesn't exists!\n";
    }
  }

  if(!-e $parent_mnc_file) {
    if(-e $parent_mnc_file.".gz") {
	    $parent_mnc_file=$parent_mnc_file.".gz";
    } else {
	    die "pipeline_functions::create_header_info_for_many_parented ${parent_mnc_file} doesn't exists!\n";
    }
  }
	    
    $history = `mincinfo -attvalue :history $child_mnc_file`;

    $tmp_file = "$tmpdir/temp_modified.mnc";
    
    #$tmp_file = $child_mnc_file;
    `mincaverage -clobber $child_mnc_file -nocopy_header $tmp_file`;

    @patient = `mincheader $parent_mnc_file | grep patient:`;
    foreach $line(@patient)
    {
      chomp($line);
      $line =~ s/ //g;
      print("minc_modify_header $tmp_file -sinsert $line\n");
      `minc_modify_header $tmp_file -sinsert $line`;
    }
    
    my @dicom_tags = qw(dicom_0x0010:el_0x0010 dicom_0x0008:el_0x0020 dicom_0x0008:el_0x0070 dicom_0x0008:el_0x1090 dicom_0x0018:el_0x1000 dicom_0x0018:el_0x1020 dicom_0x0008:el_0x103e);

    my $tag;
    foreach $tag(@dicom_tags) {
      @dicom_field = `mincheader $parent_mnc_file | grep $tag`;
      foreach $line(@dicom_field)
      {
          chomp($line);
          $line =~ s/ //g;
          print("minc_modify_header $tmp_file -sinsert $line\n");
          `minc_modify_header $tmp_file -sinsert $line`;
      }
    }
    
    do_cmd('minc_modify_header',$tmp_file,'-delete',':history');
    do_cmd('minc_modify_header',$tmp_file,'-sinsert',":history=\"${history}\"");
    if($child_mnc_file =~/\.gz$/) {
      `gzip -c ${tmp_file}>${child_mnc_file}`;
    } else {
      do_cmd('cp',$tmp_file,$child_mnc_file);
    }
    do_cmd('rm',$tmp_file);
}


##############################################################
# GetDateOfVisit( in_CandID, in_VisitLabel)
#
# Returns the acquisition date for the given candidate and visit as a string
# in format yyyy-mm-dd
##############################################################################
sub GetDateOfVisit
{
    my ($dbh,$in_CandID,$in_VisitLabel) = @_;

    my $search_criteria = "select mri_acquisition_dates.AcquisitionDate from session, files, parameter_file, parameter_type, mri_acquisition_dates where session.candID=$in_CandID and session.ID=files.sessionID and files.fileID=parameter_file.fileID and parameter_file.parametertypeID = parameter_type.parametertypeID and parameter_type.Name = \"Selected\" and session.visit_label=\"$in_VisitLabel\" and mri_acquisition_dates.sessionID=session.ID";

    my @DoV = make_query($dbh,$search_criteria) ;
    #print "Date of Visit for visit $in_VisitLabel is $DoV[0]\n";

    if (@DoV == 0 ) {
      warn "GetDateOfVisit: No selected scan for candidate $in_CandID.\n";
    }
    # We assume that all acquisition dates for a visit are the same
    # or at least no more than a few days apart.
    return $DoV[0];
}

##############################################################################
# GetCandidateDateOfBirth( in_CandID )
#
# Returns the birth date for the given candidate as a string in format yyyy-mm-dd
##############################################################################
sub GetCandidateDateOfBirth
{
    my ($dbh,$in_CandID) = @_;

    my @DoB = GetCandidateInfo($dbh, "DoB", $in_CandID );

    return $DoB[0];
}
##############################################################################
# GetCandidateInfo( in_FieldName,  in_CandID )
#
# Returns an array of the requested info.
##############################################################################
sub GetCandidateInfo
{
    my ($dbh,$in_FieldName,$in_CandID) = @_;

    my $search_criteria = "select candidate.$in_FieldName from candidate where candidate.candID=$in_CandID";

    my @Info = pipeline_functions::make_query($dbh,$search_criteria) ;

    if (@Info == 0 ) {
      warn "GetCandidate${in_FieldName}: No selected scan for candidate $in_CandID.\n";
    }
 
    return @Info;
}
##############################################################################
# CalcAge( in_Dob, in_DoVisit)
#
# Returns the age in years.
##############################################################################
sub CalcAge
{
  my $in_Dob = $_[0];
  my $in_DoVisit = $_[1];

  # First convert to years.
  my ($DoBYear, $DoBMonth, $DoBDay) = split('-',$in_Dob);
  my ($DoVisitYear, $DoVisitMonth, $DoVisitDay) = split('-',$in_DoVisit);

  my $age = $DoVisitYear - $DoBYear; 
  my $months = $DoVisitMonth - $DoBMonth;
  my $days = $DoVisitDay - $DoBDay;
  print "Birth: $in_Dob, Visit: $in_DoVisit, Years = $age, Months=$months, Days=$days\n" if $verbose;
  $age = $age + $months/12.0 + $days/365.0;
  
  $age=0 if $age<0;
  print "Age= $age years\n" if $verbose;

  return $age;
}

##############################################################################
# CalcAgeAtVisit( dbh, in_CandID, in_VisitLabel )
#
# Returns the age in years.
##############################################################################
sub CalcAgeAtVisit
{
  my ($dbh,$in_CandID,$in_VisitLabel ) = @_;  

 my $DateOfBirth = GetCandidateDateOfBirth($dbh,$in_CandID);
 my $DateOfVisit = GetDateOfVisit($dbh,$in_CandID, $in_VisitLabel);
 my $AgeAtVisit = CalcAge($DateOfBirth, $DateOfVisit);

 return $AgeAtVisit;
}

##############################################################################
# GetSelectedScan( dbh, in_CandID, in_VisitLabel, in_ScanType)
#
# Returns the name of the selected file for the given candidate, visit_label,
# and scan type.
##############################################################################
sub GetSelectedScan
{
  my ($dbh,$in_CandID,$in_VisitLabel,$in_ScanType) = @_;

    # Get the Selected file for the scan type. Look at obj0, obj1, and obj2 as well.  If the
    # selected scan has the "obj" prefix, it means that the scan's parameters fall strictly within
    # acquisition protocol.

    my $sth = $dbh->prepare("select files.file from session, files, parameter_file, parameter_type where session.candID=$in_CandID and session.ID=files.sessionID and files.fileID=parameter_file.fileID and parameter_file.parametertypeID = parameter_type.parametertypeID and parameter_type.Name = \"Selected\" and session.visit_label=\"$in_VisitLabel\" and parameter_file.Value = \"$in_ScanType\"") or die "Couldn't prepare statement: " . $dbh->errstr;
    $sth->execute();
    
    my $file;
    my @SelectedFile;
    while(($file) = $sth->fetchrow_array()) {
      push @SelectedFile,$file;
    }
    
    if ($#SelectedFile > 0 ) {
        warn "More than one selected $in_ScanType scan for candidate $in_CandID. \n";
        #@SelectedFile = ();
    }
    return $SelectedFile[0];
}



sub do_cmd {
    system(@_) == 0 or die "DIED: @_\n";
}
