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

chomp(my $model    =      `pipeline_constants -model_tal`);
chomp(my $modeldir =      `pipeline_constants -modeldir_tal`);
chomp(my $modelheadmask = `pipeline_constants -model_headmask`);
my $modelfn  = "$modeldir/$model.mnc";
$modelheadmask=$modeldir.'/'.$modelheadmask;

#########################
##fallbacks have their own set of targets
chomp(my $model_fall    = `pipeline_constants -model_fallback`);
chomp(my $modeldir_fall = `pipeline_constants -modeldir_fallback`);
my $modelfallback  = "$modeldir_fall/$model_fall.mnc";

GetOptions(
	   'verbose'      => \$verbose,
	   'clobber'      => \$clobber,
	   'fallback'     => \$fallback,
     'correct=s'    => \$correct,
     'model_dir=s'    => \$modeldir,
     'model_name=s'   => \$model,
     'fallback_dir=s' => \$modeldir_fall,
     'fallback_name=s'=> \$model_fall,
	   );

#################
##inputs are the t1 tal file
##outputs are the xfm file, and the output mnc file
if ($#ARGV < 2) { 
  die "Usage: $me <infile> <outfile_xfm> <outfilemnc> [--clobber --fallback --correct <geometrical correction> --model_dir <dir> --model_name <base name> --fallback_dir <dir> --fallback_name <base_name>]\n";
}

my $infile = $ARGV[0];
my $regxfm = $ARGV[1];
my $outfile_mnc = $ARGV[2];
my @args;

print("mritotal: infile = $infile\n");
print("mritotal: regxfm = $regxfm\n");
print("mritotal: outfile_mnc = $outfile_mnc\n");
print "mritotal: correction = $correct\n" if $correct;
if ($fallback) { print "mritotal: fallback scan\n";}

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
  do_cmd('mincresample','-use_input_sampling','-transform',$correct,$input_save,$infile);  
}

#########################
##models are standard models. This will be changed once age
##appropriate models are discovered.

print "Model: ", $modelfn, "\n";


# check for the model and model_mask files
if (!-e $modelfn){ 
    die "$me: The model $modelfn doesn't exist\n";
}

if (!-e $modelfallback){ 
    die "$me: The model $modelfallback doesn't exist\n";
}

my @files_to_add_to_db;
my $fallbackxfm;
###############
##if fallback, do an entire step targeting to a fallback target
if($fallback)
{
  $fallbackxfm = $regxfm;
  $fallbackxfm =~ s/tal_xfm/tal_xfm_fallback/;
  
  if (-e $regxfm && !$clobber) {
     warn "Found regxfm file $regxfm... skipping\n";
  } else {
  
  print STDOUT "Registering fallback stage:\n".
      "Based on   :    T1\n".
      "Model:          $model\n".
      "infile:         $infile\n".
      "xfm(s):         $fallbackxfm\n";
  chomp(my $xfmdir = `dirname $regxfm`);
  
  check_output_dirs( $xfmdir);
  
  my @args = ('mritotal', '-clobber',
     '-model', $model_fall,
     '-modeldir', $modeldir_fall,
     $infile, $fallbackxfm);
  do_cmd(@args);
  }
}


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
    
    #          
    my   @args = ('mritotal', '-clobber',
                  '-model', $model,
                  '-modeldir', $modeldir,
                  $infile, "$tmpdir/tal.xfm");
    

    if($fallback)
    {
       push(@args, '-transformation',$fallbackxfm);
       #push(@args, '-init_xfm',$fallbackxfm);
    }
    do_cmd(@args);  
    if($correct)
    {
      do_cmd('xfmconcat',$correct,"$tmpdir/tal.xfm",$regxfm);
      $infile=$input_save;
    }else {
      do_cmd('cp',"$tmpdir/tal.xfm",$regxfm);
    }
    
    @files_to_add_to_db = (@files_to_add_to_db, $regxfm);
}

##############
##finally make the output if none is made
if(!-e $outfile_mnc || $clobber)
{
    my @args = ('mincresample', '-clobber', '-transformation', $regxfm,
	     '-like', $modelfn, $infile, $outfile_mnc);
    
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
     
