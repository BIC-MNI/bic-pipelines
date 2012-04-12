#!/usr/bin/env perl
#
# Matthew Kitching
# Script based on original work by Andrew Janke.
# This modified version is used with nihpd database.
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
#
# Oct. 26, 2004: Modifications by Louis Collins for the nihpd pipeline.
# Nov. 2, 2004: Mods by Larry Baer to use the T2 native-to-tal xfm as the 
#               basis of the transform from native T2 to non-linear Tal 
#               (previously using the T1 native to tal even for T2)
# Nov. 23 2005: VF: Cleaning UP
# 

use strict;
use Getopt::Long;
use File::Basename;
use File::Temp qw/ tempfile tempdir /;
use pipeline_functions;

my $me= basename($0);
my ($verbose, $clobber, $dummy);
my ($infile_xfm_t1, $infile_xfm_t2, $infile_t1, $clamp_t1, $clamp_t2, $clamp_pd, $infile_msk, $outfile_grid, $outfile_xfm, $outfile_t1, $outfile_t2, $outfile_pd);
my ($model, $modeldir, $model_mask, $modelfn, $model_mask_file);
my @args;
my @files_to_add_to_db = ();
my ($tmp_model_mask,$tmp_tal_mask_t1,$tmp_tal_mask_t2,$tmp_tal_mask_pd, $concated_xfm_t1, $concated_xfm_t2);  

$verbose = 0;
$clobber = 0;
$dummy = "";
my $fake=0;

chomp($model         = `pipeline_constants -model_nl`);
chomp($model_mask    = `pipeline_constants -model_nl_mask`);
chomp($modeldir      = `pipeline_constants -modeldir_nl`);

my $model_name;

GetOptions(
	   'verbose'        => \$verbose,
	   'clobber'        => \$clobber,
     'model_dir=s'    => \$modeldir,
     'model_name=s'   => \$model_name
	   );
     
if($model_name)
{
  $model=$model_name;
  $model_mask=$model_name."_mask";
}

####################
##Wow - a lot of arguments. we require the t1,t2,pd cliped data. the tal transformation, and the tal mask
##we output the grid file, the xfm file, and the three non-linear transformed anatomicals

if ($#ARGV < 9){ die "Usage: $me <infile_xfm T1> <infile_xfm T2> <infile_t1> infilet2> <infilepd> <infile_msk> <outfile_grid> <outfile_xfm> <outfile_t1> <outfile_t2> <outfile_pd> [--model_dir <dir> --model_name <base name>]\n"; }

$modelfn  = "$modeldir/$model.mnc";

$infile_xfm_t1 = $ARGV[0];		# the t1 native to Talairach transformation
$infile_xfm_t2 = $ARGV[1];		# the t2 native to Talairach transformation
$infile_t1 =     $ARGV[2];		# the linearly transformed T1 data in stereotaxic space
$clamp_t1 =      $ARGV[3];		# the native clamped T1 data
$clamp_t2 =      $ARGV[4];		# the native clamped T2 data
$clamp_pd =      $ARGV[5];		# the native clamped PD data
$infile_msk =    $ARGV[6];    # mask 

$outfile_grid = $ARGV[7];	# this is the output transformation grid volume representing the deformation field
$outfile_xfm  = $ARGV[8];	# this is the output transformation (from linear Talairach to nonlinear Talairach)
				#   note: this does not contain the native-to-talairach linear xform
$outfile_t1 = $ARGV[9];		# the nonlinearly transformed T1 data in stereotaxic space
$outfile_t2 = $ARGV[10];		# the nonlinearly transformed T2 data in stereotaxic space
$outfile_pd = $ARGV[11];	# the nonlinearly transformed PD data in stereotaxic space


############
##if we have everything return
if(-e $outfile_t1 && -e $outfile_t2 && -e $outfile_pd && -e $outfile_grid && -e $outfile_xfm && ! $clobber)
{
	print STDERR "outfiles exist... clobber to overwrite\n";
	exit 0;
}

###########
##the model files are found in pipeline constants file

# check for the model and model_mask files
if (!-e $modelfn){ 
   die "$me: The model $modelfn doesn't exist\n";
}

my $tmpdir = &tempdir( "$me-XXXXXXXX", TMPDIR => 1, CLEANUP => 1 );

###############
##if xfm does not exist, then create it.
if (-e $outfile_xfm && !$clobber) 
{
    print "Found $outfile_xfm... skipping\n";

}
else {   
      # this will compute a non-liner def
      # between the linearly transformed T1
      # data and the stereotaxic model.

      # DLC and VF (8/24/2005) added the -tal option
      # to the line below, since  the data being used 
      # to compute the non-linear transform is in (linear) 
      # Talairach space and is used in the pipeline_nlfit_smr 
      # script to compute the non linear 'grid' only.  
      # this grid will be concatenated with the linear 
      # transform for use in downstream procesing steps. 
 
    @args = ('pipeline_nlfit_smr.pl', $infile_t1,  $infile_xfm_t1, $infile_msk, $outfile_grid, $outfile_xfm, 
             '-mask','-tal','--model_dir',$modeldir,'--model_name',$model);
    if($clobber) { push(@args, '-clobber'); }
    do_cmd(@args);

    # VF: Fix headers in a grid file
    pipeline_functions::create_header_info_for_many_parented($outfile_grid, $infile_t1, $tmpdir);

    @files_to_add_to_db = (@files_to_add_to_db, $outfile_grid);
    @files_to_add_to_db = (@files_to_add_to_db, $outfile_xfm);
}


$model_mask_file = "$modeldir/${model_mask}.mnc";

$tmp_model_mask  = "${tmpdir}/model_mask.mnc";
$tmp_tal_mask_t1 = "${tmpdir}/tal_mask_t1.mnc";
$tmp_tal_mask_t2 = "${tmpdir}/tal_mask_t2.mnc";
$tmp_tal_mask_pd = "${tmpdir}/tal_mask_pd.mnc";

##next, mask the target
do_cmd('mincmask',$modelfn, $model_mask_file, $tmp_model_mask, '-clobber');
$modelfn = $tmp_model_mask;


# $outfile_xfm is from linear stx to non-linear stx. We need from
# native to non-linear stx.  We need to concat the native-to-stx with
# the nonlinear transform.  i.e., concated_xfm = xfmconcat ( infile_xfm, outfile_xfm )

$concated_xfm_t1 ="${tmpdir}/concated_xfm_t1.xfm";

if (-e $infile_xfm_t1 && -e $outfile_xfm) {
    @args = ('xfmconcat',$infile_xfm_t1, $outfile_xfm, $concated_xfm_t1);
    do_cmd(@args);
}
else {
    die "can't find needed $infile_xfm_t1 or $outfile_xfm";
}

# and do the same for T2
$concated_xfm_t2 ="${tmpdir}/concated_xfm_t2.xfm";

if (-e $infile_xfm_t2 && -e $outfile_xfm) {
    @args = ('xfmconcat',$infile_xfm_t2, $outfile_xfm, $concated_xfm_t2);
    do_cmd(@args);
}
else {
    warn "can't find needed $infile_xfm_t2 or $outfile_xfm";
}


if(!-e $outfile_t1 || $clobber)
{
################
##resample the t1
##with the grid file
    @args = ('mincresample', '-transformation', $concated_xfm_t1,
	     '-like', $modelfn, $clamp_t1, $tmp_tal_mask_t1, '-clobber');
    do_cmd(@args);
    
    do_cmd('mincmask', $tmp_tal_mask_t1, $model_mask_file, $outfile_t1, '-clobber');
    @files_to_add_to_db = (@files_to_add_to_db, $outfile_t1);
}

if($infile_xfm_t2 && -e $infile_xfm_t2 && ( !-e $outfile_t2 || $clobber))
{
################
##resample the t2
##with the grid file
    @args = ('mincresample', '-transformation', $concated_xfm_t2,
	     '-like', $modelfn, $clamp_t2, $tmp_tal_mask_t2, '-clobber');
    do_cmd(@args);
    
    do_cmd('mincmask', $tmp_tal_mask_t2, $model_mask_file, $outfile_t2, '-clobber');
    @files_to_add_to_db = (@files_to_add_to_db, $outfile_t2);
}

if($infile_xfm_t2 && -e $infile_xfm_t2 && (!-e $outfile_pd || $clobber))
{
################
##resample the pd
##with the grid file
    @args = ('mincresample', '-transformation', $concated_xfm_t2,
	     '-like', $modelfn, $clamp_pd, $tmp_tal_mask_pd, '-clobber');
    do_cmd(@args);
    
    do_cmd('mincmask', $tmp_tal_mask_pd, $model_mask_file, $outfile_pd, '-clobber');
    @files_to_add_to_db = (@files_to_add_to_db, $outfile_pd);
}

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


