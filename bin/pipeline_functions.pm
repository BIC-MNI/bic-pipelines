package pipeline_functions;

##################################################
##All of this is pm mumbo jumbo stuff.
use MNI::Startup;
use File::Spec;
use File::Basename;

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

require Exporter;
#MNI::Startup();
@ISA = qw(Exporter AutoLoader);
# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.
@EXPORT = qw();
$VERSION = '0.01';
##end pm stuff
##################################################


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
      #print("minc_modify_header $tmp_file -sinsert $line\n");
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
          #print("minc_modify_header $tmp_file -sinsert $line\n");
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


sub do_cmd {
    system(@_) == 0 or die "DIED: @_\n";
}
