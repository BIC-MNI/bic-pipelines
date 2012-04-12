#!/usr/bin/env perl
#

use Getopt::Long;
use File::Basename;
use File::Temp qw/ tempfile tempdir /;
use MNI::FileUtilities qw(check_output_dirs);
use strict;

my $me = basename($0);
my $verbose  = 0;
my $clobber  = 0;
my $fallback = 0;
my $fake=0;
my $correct;
my $initial;
my $nlmask;

my $model;
my $modeldir;
my $modelheadmask;

GetOptions(
	   'verbose'      => \$verbose,
	   'clobber'      => \$clobber,
	   'fallback'     => \$fallback,
	   'correct=s'    => \$correct,
	   'model_dir=s'    => \$modeldir,
	   'model_name=s'   => \$model,
	   'initial=s'     => \$initial,
     'nlmask'        => \$nlmask
	   );

#################
##inputs are the t1 tal file
##outputs are the xfm file, and the output mnc file
if ($#ARGV < 2) { 
  die "Usage: $me <infile> <outfile_xfm> <outfilemnc> [--clobber --correct <geometrical correction> --model_dir <dir> --model_name <base name> --initial <initial xfm> --nlmask]\n";
}

my $modelfn  = "$modeldir/$model.mnc";
$modelheadmask=$modeldir.'/'.$modelheadmask;

my $model_brain_mask="$modeldir/${model}_mask.mnc";

my $infile = $ARGV[0];
my $regxfm = $ARGV[1];
my $outfile_mnc = $ARGV[2];
my @args;

print("mritotal: infile = $infile\n");
print("mritotal: regxfm = $regxfm\n");
print("mritotal: outfile_mnc = $outfile_mnc\n");
print("mritotal: correction = $correct\n") if $correct;
print("mritotal: initial xfm = $initial\n") if $initial;

if(-e $regxfm && -e $outfile_mnc  && !$clobber)
{
    print("$outfile_mnc or $regxfm exists use clobber to overwrite\n");
    exit 0;
}

my $tmpdir = &tempdir( "$me-XXXXXXXX", TMPDIR => 1, CLEANUP => 1 );
my @files_to_add_to_db = ();

my $input_save=$infile;

if($correct)
{
  #apply correction first time for rough estimation
  $infile="$tmpdir/input.mnc";
  do_cmd('itk_resample','--transform',$correct,$input_save,$infile,'--uniformize',1);  
} else {
  $infile="$tmpdir/input.mnc";
  do_cmd('itk_resample',$input_save,$infile,'--uniformize',1);  
}

#########################
##models are standard models. This will be changed once age
##appropriate models are discovered.

print "Model: ", $modelfn, "\n";


# check for the model and model_mask files
if (!-e $modelfn){ 
    die "$me: The model $modelfn doesn't exist\n";
}

# check for the model and model_mask files
if (!-e $model_brain_mask){ 
    die "$me: The model $model_brain_mask doesn't exist\n";
}

my @files_to_add_to_db;

#####################
##Now make the xfm file
if (-e $regxfm && !$clobber) {
    warn "Found regxfm file $regxfm... skipping\n";
} else {
  print STDOUT "Registering:    \n".
                "Based on   :    T1\n".
                "Model:          $model\n".
                "infile:         $infile\n".
                "xfm(s):         $regxfm\n";
    
    my   @args = ('bestlinreg_s2', '-clobber',
                  $infile, $modelfn,
                  "$tmpdir/tal.xfm");
    
    push @args, '-init_xfm', $initial if $initial;
    do_cmd(@args);
    
    if($correct)
    {
      do_cmd('xfmconcat',$correct,"$tmpdir/tal.xfm","$tmpdir/tal1.xfm");
      $infile=$input_save;
    }else {
      do_cmd('cp',"$tmpdir/tal.xfm","$tmpdir/tal1.xfm");
    }
    
    do_cmd('mincresample',$infile,'-like',$modelfn,'-transform',"$tmpdir/tal1.xfm","$tmpdir/tal1.mnc");
    if($nlmask)
    {
      do_cmd('icc_mask_ants.pl',"$tmpdir/tal1.mnc","$tmpdir/tal1_mask.mnc",'--model',$modelfn,'--icc-model',$model_brain_mask);
    } else {
      do_cmd('mincbet',"$tmpdir/tal1.mnc","$tmpdir/tal1",'-m','-n');
    }
    # second stage
    # map back to the input space
    do_cmd('mincresample','-nearest','-like',$infile,
           "$tmpdir/tal1_mask.mnc","$tmpdir/native_mask.mnc",
           '-transform',"$tmpdir/tal.xfm",'-invert_transformation');

    do_cmd('bestlinreg_s2',$infile,$modelfn,
           '-source_mask',"$tmpdir/native_mask.mnc",
           '-target_mask',$model_brain_mask,
           "$tmpdir/tal_corr.xfm",'-init_xfm',"$tmpdir/tal.xfm");

    if($correct)
    {
      do_cmd('xfmconcat',$correct,"$tmpdir/tal_corr.xfm",$regxfm);
      $infile=$input_save;
    }else {
      do_cmd('cp',"$tmpdir/tal_corr.xfm",$regxfm);
    }
    push @files_to_add_to_db,$regxfm;
}


##############
##finally make the output if none is made
if(!-e $outfile_mnc || $clobber)
{
    my @args = ('itk_resample', '--clobber', '--transform', $regxfm,
	     '--like', $modelfn, $infile, $outfile_mnc,'--order',4);
    
    do_cmd(@args);
    @files_to_add_to_db = (@files_to_add_to_db, $outfile_mnc);
}

print("Files created:@files_to_add_to_db\n");


sub do_cmd { 
  print STDOUT "@_\n" if $verbose;
  if(!$fake){
    system(@_) == 0 or die;
  }
}
