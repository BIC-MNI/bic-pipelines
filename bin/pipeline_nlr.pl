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

if ($#ARGV < 3){ die "Usage: $me <infile_tal_t1> <infile_msk> <outfile_grid> <outfile_xfm> <outfile_t1> [--model_dir <dir> --model_name <base name>]\n"; }

$modelfn  = "$modeldir/$model.mnc";
$model_mask = "$modeldir/${model}_mask.mnc";

$infile_t1 =     $ARGV[0];		# the linearly transformed T1 data in stereotaxic space
$infile_msk =    $ARGV[1];    # mask 

$outfile_grid = $ARGV[2];	# this is the output transformation grid volume representing the deformation field
$outfile_xfm  = $ARGV[3];	# this is the output transformation (from linear Talairach to nonlinear Talairach)
				#   note: this does not contain the native-to-talairach linear xform
        
$outfile_t1  = $ARGV[4];	# this is the output transformation (from linear Talairach to nonlinear Talairach)
        

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
    @args = ('nlfit_s', $infile_t1, $modelfn,$outfile_xfm, '-source_mask',$infile_msk,'-target_mask',$model_mask,'-level',2);
    if($clobber) { push(@args, '-clobber'); }
    do_cmd(@args);

    # VF: Fix headers in a grid file
    pipeline_functions::create_header_info_for_many_parented($outfile_grid, $infile_t1, $tmpdir);

    @files_to_add_to_db = (@files_to_add_to_db, $outfile_grid);
    @files_to_add_to_db = (@files_to_add_to_db, $outfile_xfm);
}

if( !-e $outfile_t1 || $clobber)
{
  do_cmd('itk_resample', '--clobber', '--transform', $outfile_xfm,
	     '--like', $modelfn, $infile_t1, $outfile_t1,'--order',4);
  
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


