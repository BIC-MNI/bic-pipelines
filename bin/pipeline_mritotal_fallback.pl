#!/usr/bin/env perl
#
# Andrew Janke - rotor@bic.mni.mcgill.ca
# Script to register data to model space
# Sat Dec  1 22:50:48 EST 2001 - initial version
# Sat Feb  9 16:07:28 EST 2002 - updated

# Wed Feb 13 - stolen and modified for NIHPD_MNI (LC)
#    the procedure will figure out how to map all data into stereotaxic
#    space for the given patient.
#    if T1 exists, then it is mapped into stx space with MRITOTAL
#                  and the transform is stored
#    else T2 exists, then mapped to T2 avg, and stored,
#    else fail.

use Getopt::Tabular;
use File::Basename;
use pipeline_functions;    
use MNI::FileUtilities qw(check_output_dirs);
use File::Temp qw/ tempdir /;

#$SIG{__DIE__} =  sub { &cleanup; die $_[0]; };

$verbose    = 0;
$clobber    = 0;
$noresample = 0;
@opt_table = (
              ["-verbose",       "boolean", 0, \$verbose,    "be verbose"                    ],
              ["-clobber",       "boolean", 0, \$clobber,    "clobber all existing xfms"     ],
              ["-noresample",    "boolean", 0, \$noresample, "don't do the resampling step"  ],
              );

#chomp($me = `basename $0`);
$me = basename($0);
&GetOptions (\@opt_table, \@ARGV) || exit 1;
if($#ARGV < 0){ die "Usage: $me <subject_visit>\n"; }
$subject_visit = $ARGV[0];

@mriid_list = pipeline_functions::get_selected_files($subject_visit, "mriid");
$t1_native_mriid = $mriid_list[0];

($subject, $visit) = split(":", $subject_visit);
#$tmpdir = "/var/tmp/${subject}_${visit}_tal";
$tmpdir = &tempdir( "$me-XXXXXXXX", TMPDIR => 1, CLEANUP => 1 );

check_output_dirs($tmpdir); 

chomp($model_fall    = `./pipeline_constants -model_fallback`);
chomp($modeldir_fall = `./pipeline_constants -modeldir_fallback`);
$modelfallback  = "$modeldir_fall/$model_fall.mnc";

$search_criteria = "select concat_ws(',',complete_path, objective, selected) from mri  where mriid = $t1_native_mriid";
@native_info = (pipeline_functions::make_query($search_criteria));
($native_path, $objective, $selected) = split(",", $native_info[0]);

##############
##FIX
##
$tmpdir = dirname($native_path);
$tmpdir =~ s/native/work\/tmp/;
if(!-e $tmpdir){`mkdir $tmpdir`;}

$scan_type = pipeline_functions::get_scan_type($selected, $objective);
$native_path =~ s/ //g;
$native_path=~ s/\.gz//;
$native_path=~ s/\.mnc//;
$regxfm_fall   = "$native_path.$t1_native_mriid.clp.mnc";
$regxfm_fall  =~ s/\/tmp\//\/xfms\//;
$regxfm_fall  =~ s/\.mnc$/\.t1fallback\.xfm/;
$regxfm_fall  =~ s/native/work\/xfms/;


@types =pipeline_functions::get_processed_files_from_mriid("complete_path, mriid, source_list", "final/clp", $t1_native_mriid);
($infile) = split(" ",$types[0]);
if(!-e $infile){
	die "$me: Couldn't find $infile\n";
    }

$local_clp = "$tmpdir\/$selected.${t1_native_mriid}.clp.mnc";
if($infile =~ /\.gz/)
{
    $local_clp.= ".gz";
}
`cp $infile $local_clp`;


if (-e $regxfm_fall && !$clobber) {
    warn "Found regxfm_fall file $regxfm_fall... skipping\n";
    }
else {
    
    chomp($xfmdir = `dirname $regxfm_fall`);
    check_output_dirs( $xfmdir);
    
	@args = ('mritotal0.98i', '-clobber',
		 '-model', $model_fall,
		 '-modeldir', $modeldir_fall,
		 $local_clp, $regxfm_fall);
    if($verbose){ print STDOUT "@args\n"; }
    system(@args) == 0 or die "$me: $!";  
}

$outfile ="$tmpdir\/$selected.${t1_native_mriid}.tal_fallback.mnc";
	    
@args = ('mincresample', '-clobber', '-transformation', $regxfm_fall,
	 '-like', $modelfallback, $local_clp, $outfile);
if($verbose){ print STDOUT "@args\n"; }
system(@args) == 0 or die;

#if ($clobber || !($return_val = pipeline_functions::is_type_in_db("final/tal", $t1_native_mriid)))
#{



    chomp($model    = `./pipeline_constants -model_tal`);
    chomp($modeldir = `./pipeline_constants -modeldir_tal`);
    $modelfn  = "$modeldir/$model.mnc";
# check for the model and model_mask files
    if (!-e $modelfn){ 
	die "$me: The model $model doesn't exist\n";
    }

    $search_criteria = "select concat_ws(',',complete_path, objective, selected) from mri  where mriid = $t1_native_mriid";
    @native_info = (pipeline_functions::make_query($search_criteria));
 
    ($native_path, $objective, $selected) = split(",", $native_info[0]);
    $scan_type = pipeline_functions::get_scan_type($selected, $objective);
    $native_path =~ s/ //g;
    $native_path=~ s/\.gz//;
    $native_path=~ s/\.mnc//;
    $regxfm   = "$native_path.$t1_native_mriid.clp.mnc";
    $regxfm  =~ s/\/tmp\//\/xfms\//;
    $regxfm  =~ s/\.mnc$/\.t1tal_with_fall\.xfm/;
    $regxfm  =~ s/native/work\/xfms/;


    @types =pipeline_functions::get_processed_files_from_mriid("complete_path, mriid, source_list", "final/clp", $t1_native_mriid);

    ($infile) = split(" ",$types[0]);


    if(!-e $infile){
	die "$me: Couldn't find $infile\n";
    }

    $local_clp = "$tmpdir\/$selected.${t1_native_mriid}.clp.mnc";
    if($infile =~ /\.gz/)
    {
	$local_clp.= ".gz";
    }
    `cp $infile $local_clp`;


    if (-e $regxfm && !$clobber) {
	warn "Found regxfm file $regxfm... skipping\n";
    }
    else {
	
	
	print STDOUT "Registering:    $subject_visit\n".
	    "Based on   :    T1\n".
	    "Model:          $model\n".
	    "infile:         $infile\n".
	    "xfm(s):         $regxfm\n";
	
	chomp($xfmdir = `dirname $regxfm`);
	
	check_output_dirs( $xfmdir);
	
	@args = ('mritotal0.98i', '-clobber',
		 '-model', $model,
		 '-modeldir', $modeldir,
		 '-transformation', $regxfm_fall,
		 $local_clp, $regxfm);
	if($verbose){ print STDOUT "@args\n"; }
	system(@args) == 0 or die "$me: $!";  }
    
    
    
    if($noresample){
	print STDOUT "Skipping resampling\n";
    }
    else{
	
	$outfile ="$tmpdir\/$selected.${t1_native_mriid}.tal.mnc";
	    
	@args = ('mincresample', '-clobber', '-transformation', $regxfm,
		 '-like', $modelfn, $local_clp, $outfile);
	if($verbose){ print STDOUT "@args\n"; }
	system(@args) == 0 or die;

#	@args = ('./pipeline_insert_file_into_db', $subject_visit,  $outfile, 'tal', $scan_type,'-source_list', $t1_native_mriid);
#	if($verbose){ print STDOUT @args; }
#	system(@args) == 0 or die;

    }
#}
#else{print("Found tal file $return_val in db with source list of $t1_native_mriid... skipping\n");}
#&cleanup;

sub cleanup {
  if($verbose){ print STDOUT "Cleaning up....\n"; }
}  
