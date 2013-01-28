#!/usr/bin/env perl

############################# MNI Header #####################################
#@NAME       :  main_pipe_simplified.pl  
#@DESCRIPTION:  simplified image processing pipeline
#@COPYRIGHT  :
#              Vladimir S. Fonov  February, 2009
#              Larry Baer         October, 2004
#              Montreal Neurological Institute, McGill University.
#              Permission to use, copy, modify, and distribute this
#              software and its documentation for any purpose and without
#              fee is hereby granted, provided that the above copyright
#              notice appear in all copies.  The author and McGill University
#              make no representations about the suitability of this
#              software for any purpose.  It is provided "as is" without
#              express or implied warranty.
###############################################################################

use strict;
use Getopt::Long;
use File::Basename;
use File::Temp qw/ tempfile tempdir /;
use MNI::Spawn;
#use pipeline_functions;

MNI::Spawn::SetOptions (verbose => 0,execute => 1,strict  => 0);

###################################################################
# Globals
###################################################################
my $verbose = 0;
my $fake    = 0;
my $clobber = 0;
my $file_prefix; 
my $base_dir;
my $dry_run=0;
my $nu_runs=5;
my $model_dir="$ENV{MNI_DATAPATH}/icbm152_model_09c";
my $model='mni_icbm152_t1_tal_nlin_sym_09c';
my $beastlib="$ENV{MNI_DATAPATH}/beast-library-1.1";
my $acr_model;
my $geo_corr_enabled=1;
my $me = basename ($0);
my @scannerID=0;
my $scanner_name='NA';
my $nogeo=0;
my $disable_nonlinear=0;
my $deface_volume=0;
my $fallback=0;
my $geo_t1;
my $geo_t2pd;
my ($b0_t1,$b0_t2,$b0_pd);
my $dbh;
my $manual_dir;
my $benchmark;
my $run_face=0;
my $mri_3t;
# command line options

GetOptions(
	   'verbose'           => \$verbose,
	   'clobber'           => \$clobber,
	   'prefix=s'          => \$file_prefix,
	   'basedir=s'         => \$base_dir,
	   'dry_run'           => \$dry_run,
	   'nu_runs=i'         => \$nu_runs,
	   'model_dir=s'       => \$model_dir,
	   'model=s'           => \$model,
     'nogeo'             => \$nogeo,
     'disable_nonlinear' => \$disable_nonlinear,
     'deface_volume'     => \$deface_volume,
     'geo_t1=s'          => \$geo_t1,
     'geo_t2pd=s'        => \$geo_t2pd,
     'manual=s'          => \$manual_dir,
     'benchmark=s'       => \$benchmark,
     'run-face'          => \$run_face,
     '3t'                => \$mri_3t,
     'beastlib=s'        => \$beastlib,
	   );

my $Help = <<HELP;
  Usage: $me <candID> <visitno> <T1 file> [T2 file] [PD file]
    --verbose be verbose
    --clobber clobber _all_ output files
    --prefix <dir> output directory prefix  ,all data will be in <prefix>/<subject_id>/<visit_label>
    --basedir <dir> put all output into this directory (overrides prefix)
    --dry_run  don't actually execute the commands, just show what will be done
    --nu_runs <n> run Nu correct n times
    --model_dir <dir> use this modeldir, default: $model_dir
    --model <model base> use this model, default: $model
    --nogeo disable geometrical distortion correction (default)
    --deface_volume deface volume prior to processing (will increase processing time)
    --geo_t1 <xfm> geometrical correction for T1 - overrides --geo_dir
    --geo_t2pd <xfm> geometrical correction for T2/PD - overrides --geo_dir
    --disable_nonlinear  disable nonlinear registration and all parts which depend on it
    --manual <dir> manual directory prefix 
    --benchmark <output>
    --run-face run FACE surface extraction algorithm
    --beastlib <dir> - location of BEaST library, default: $beastlib
    --3t use N3 parameters for 3T
  Problems or comments should be sent to: vfonov\@bic.mni.mcgill.ca
HELP

die $Help if $#ARGV < 2;


my ($model_t1,$model_t2,$model_pd,$model_wm,$model_gm,$model_csf,$model_mask)=($model,$model,$model, $model,$model,$model,"${model}_mask.mnc");
$model_t2=~s/_t1/_t2/;
$model_pd=~s/_t1/_pd/;
$model_gm=~s/_t1/_gm/;
$model_wm=~s/_t1/_wm/;
$model_csf=~s/_t1/_csf/;

my ($candid,$visitno,$native_t1w,$native_t2w,$native_pdw) = @ARGV;

$|=1;

die "specify --prefix or --basedir\n" unless $file_prefix || $base_dir;
$base_dir = "${file_prefix}/${candid}/${visitno}" unless $base_dir;

print $base_dir."\n";
`mkdir -p ${base_dir}`;

#my $lockmgr = LockFile::Simple->make(-format => '%f', -max => 1, -delay => 1, -nfs => 1, -autoclean=>1, -hold=>6*3600,-stale=>1);
#$lockmgr->lock("${base_dir}/lock") || die "Dataprocessing is locked\n";

###################################################################
my $bin_dir = dirname($0);

print "CandID: ", $candid, " Visit:",$visitno,"\n";

my $age=0;

my @types, my $native_t1_ID, my $native_t2_ID, my $native_pd_ID;

push @types,'t1w' if $native_t1w ;
push @types,'t2w' if $native_t2w ;
push @types,'pdw' if $native_pdw ;

$native_t1_ID=-1;
$native_t2_ID=-1;
$native_pd_ID=-1;

create_directories($base_dir);
my $tmpdir = &tempdir( "$me-XXXXXXXX", TMPDIR => 1, CLEANUP => 1 );
if($benchmark)
{
  open BENCHMARK,">$benchmark" or die "Can't open $benchmark for writing!\n";
  
}

my $identity_file = "$tmpdir/identity.xfm";
do_cmd('param2xfm',$identity_file);

my %manual_file_list;
%manual_file_list = get_list_files_native_files("${manual_dir}/${candid}/${visitno}", $candid, $visitno, $native_t1w, $native_t2w, $native_pdw ) if $manual_dir;

#fix files!
$native_t1w=fix_sampling($native_t1w);
$native_t2w=fix_sampling($native_t2w);
$native_pdw=fix_sampling($native_pdw);

my %initial_file_list = get_list_files_native_files($base_dir, $candid, $visitno, $native_t1w, $native_t2w, $native_pdw );



# Keep track of database fileID's so we can use them as source ID's for files produced by subsequent stages of the pipe.
my %list_fileIDs = {};
$list_fileIDs{'native_t1w'} = $native_t1_ID;
$list_fileIDs{'native_t2w'} = $native_t2_ID ;
$list_fileIDs{'native_pdw'} = $native_pd_ID;

my $type, my $program, my @inputs, my @outputs, my $parameter, my @output_types, my @fileID;

if($deface_volume)
{
    ####################
    ##pipeline correct for each anatomical
    $program = "$bin_dir/pipeline_deface.pl";
    @inputs = ($initial_file_list{'native_t1w'});
    $parameter = " --model-dir ${model_dir} --model ${model} --keep-real-range --output $initial_file_list{'deface_base'}";
    @outputs = ($initial_file_list{'deface_t1w'});
    @output_types = qw(defaced);
    
    if($native_t2w)
    {
      push @inputs,$initial_file_list{'native_t2w'};
      push @outputs,$initial_file_list{'deface_t2w'};
      push @output_types,'defaced';
    }
    
    if($native_pdw)
    {
      push @inputs,$initial_file_list{'native_pdw'};
      push @outputs,$initial_file_list{'deface_pdw'};
      push @output_types,'defaced';
    }
    print "Outputs: @outputs \n";
    @fileID = create_function($program, \@inputs, $parameter, \@outputs, \@output_types, $type, 'native', '', $list_fileIDs{'native_t1w'}, (1, 1, 1, 1));
    $list_fileIDs{'deface_t1w'} = $fileID[0];
    $list_fileIDs{'deface_t2w'} = $fileID[1] if($native_t2w);
    $list_fileIDs{'deface_pdw'} = $fileID[2] if($native_pdw);
}

foreach $type(@types)
{
    my $native_file_ID;
    
    my $native_current = $deface_volume?"deface_$type":"native_$type";
    my $clp_current    = "clp_$type";
    my ($geo,$b0);
    my $model_spec;
    
    if($type =~ /t1w/) {$native_file_ID = $native_t1_ID; $geo=$geo_t1  ;$b0=$b0_t1; $model_spec=$model_t1;}
    if($type =~ /t2w/) {$native_file_ID = $native_t2_ID; $geo=$geo_t2pd;$b0=$b0_t2; $model_spec=$model_t2;}
    if($type =~ /pdw/) {$native_file_ID = $native_pd_ID; $geo=$geo_t2pd;$b0=$b0_pd; $model_spec=$model_pd;}

    $list_fileIDs{$clp_current} = $native_file_ID;

    ####################
    ##pipeline correct for each anatomical
    $program = "$bin_dir/pipeline_correct.pl";
    @inputs = [$initial_file_list{$native_current}];
    $parameter = "--iterations ${nu_runs} --model ${model_dir}/${model_spec}.mnc --model-mask ${model_dir}/${model}_mask.mnc --stx --verbose";
    $parameter.= ' --3t' if $mri_3t;
    @outputs = [$initial_file_list{$clp_current}];
    @output_types = qw(clp_mnc);
    @fileID = create_function($program, @inputs, $parameter, @outputs, \@output_types, $type, 'native', '', $list_fileIDs{$native_current}, (1, 1, 1,1));
    $list_fileIDs{$clp_current} = $fileID[0];
}

####################
##linear register t1

#do_cmd('ln','-s',$manual_file_list{'tal_xfm_t1w'},$initial_file_list{'tal_xfm_t1w'}) if $manual_dir && -e $manual_file_list{'tal_xfm_t1w'};
$program = "$bin_dir/pipeline_mritotal.pl";
@inputs = [$initial_file_list{'clp_t1w'}];
$parameter = "--model_dir ${model_dir} --model_name ${model} --beastlib $beastlib";
$parameter = $parameter." --initial $manual_file_list{'tal_xfm_t1w'}" if $manual_dir && -e $manual_file_list{'tal_xfm_t1w'};
$parameter=$parameter." --correct $geo_t1 "  if $geo_t1;
@outputs = [$initial_file_list{'tal_xfm_t1w'}, $initial_file_list{'tal_t1w'}];
@output_types = qw(tal_xfm tal_mnc);
@fileID = create_function($program, @inputs, $parameter, @outputs, \@output_types, 't1w', 'linear', '', $list_fileIDs{'clp_t1w'}, (1, 1));
$list_fileIDs{'tal_xfm_t1w'} = $fileID[0];
$list_fileIDs{'tal_t1w'} = $fileID[1];

###################
##linear register t2 (storing the t2-to-Talairach space transform and NOT the t2-to-t1 xform)
if($native_t2w)
{
  $program = "$bin_dir/pipeline_t2tot1.pl";
  @inputs = [$initial_file_list{'tal_xfm_t1w'}, $initial_file_list{'clp_t1w'},$initial_file_list{'clp_t2w'}];
  $parameter = " --model_dir ${model_dir} --model_name ${model}  ";  
  $parameter=$parameter." --correct_t2w $geo_t2pd " if $geo_t2pd;
  $parameter=$parameter." --correct_t1w $geo_t1 "   if $geo_t1;
  @outputs = [$initial_file_list{'tal_xfm_t2w'}, $initial_file_list{'tal_t2w'} ];
  @output_types = qw(tal_xfm tal_mnc);
  @fileID = create_function($program, @inputs, $parameter, @outputs, \@output_types, 't2w', 'linear', '', $list_fileIDs{'clp_t2w'}, (1, 1));
  $list_fileIDs{'tal_xfm_t2w'} = $fileID[0];
  $list_fileIDs{'tal_t2w'} = $fileID[1];
}

###################
##linear register pd
if($native_t2w && $native_pdw)
{
  $program = "$bin_dir/pipeline_pd_t1.pl";
  @inputs = [$initial_file_list{'tal_xfm_t2w'}, $initial_file_list{'clp_pdw'}];
  $parameter = " --model_dir ${model_dir} --model_name ${model} ";
  @outputs = [$initial_file_list{'tal_pdw'} ];
  @output_types = qw(tal_mnc);
  @fileID = create_function($program, @inputs, $parameter, @outputs, \@output_types, 'pdw', 'linear', '', $list_fileIDs{'clp_pdw'}, (1));
  $list_fileIDs{'tal_pdw'} = $fileID[0];
}

###################
## Transform clamped T1 to Talairach without scaling.
$program = "$bin_dir/pipeline_talnoscale.pl";
@inputs = [$initial_file_list{'clp_t1w'}, $initial_file_list{'tal_xfm_t1w'}];
$parameter = " --model_dir ${model_dir} --model_name ${model} ";
@outputs =  [$initial_file_list{'tal_noscale_xfm_t1w'}, $initial_file_list{'tal_noscale_t1w'}];
@output_types = qw(tal_noscale_xfm tal_noscale_mnc);
@fileID = create_function($program, @inputs, $parameter, @outputs, \@output_types, 't1w', 'linear', '', $list_fileIDs{'clp_t1w'}, (1,1));
$list_fileIDs{'tal_noscale_xfm_t1w'} = $fileID[0];
$list_fileIDs{'tal_noscale_t1w'} = $fileID[1];

###################
## Transform clamped T2 to Talairach without scaling.
if($native_t2w)
{
  $program = "$bin_dir/pipeline_talnoscale.pl";
  @inputs = [$initial_file_list{'clp_t2w'}, $initial_file_list{'tal_xfm_t2w'}];
  $parameter = " --model_dir ${model_dir} --model_name ${model} ";
  @outputs =  [$initial_file_list{'tal_noscale_xfm_t2w'}, $initial_file_list{'tal_noscale_t2w'}];
  @output_types = qw(tal_noscale_xfm tal_noscale_mnc);
  @fileID = create_function($program, @inputs, $parameter, @outputs, \@output_types, 't2w', 'linear', '', $list_fileIDs{'clp_t2w'}, (1,1));
  $list_fileIDs{'tal_noscale_xfm_t2w'} = $fileID[0];
  $list_fileIDs{'tal_noscale_t2w'} = $fileID[1];
}
###################
## Transform clamped PD to Talairach without scaling.
if($native_pdw)
{
  $program = "$bin_dir/pipeline_talnoscale.pl";
  @inputs = [$initial_file_list{'clp_pdw'}, $initial_file_list{'tal_xfm_t2w'}];
  $parameter = " --model_dir ${model_dir} --model_name ${model}  ";
  @outputs =  [$initial_file_list{'tal_noscale_xfm_pdw'}, $initial_file_list{'tal_noscale_pdw'}];
  @output_types = qw(tal_noscale_xfm tal_noscale_mnc);
  @fileID = create_function($program, @inputs, $parameter, @outputs, \@output_types, 'pdw', 'linear', '', $list_fileIDs{'clp_t1w'}, (1,1));
  $list_fileIDs{'tal_noscale_xfm_pdw'} = $fileID[0];
  $list_fileIDs{'tal_noscale_pdw'} = $fileID[1];
}

###################
##create linear mask
$program = "$bin_dir/pipeline_iccmask_stx.pl";
@inputs = ($initial_file_list{'tal_t1w'} );
push (@inputs, $initial_file_list{'tal_t2w'}) if $native_t2w;
push (@inputs, $initial_file_list{'tal_pdw'}) if $native_pdw;
$parameter = "--eye_mask ${model_dir}/${model}_eye_mask.mnc --beastlib $beastlib ";
@outputs = [$initial_file_list{'tal_comp_msk'}];
@output_types = qw(tal_comp_msk);
@fileID = create_function($program, \@inputs, $parameter, @outputs, \@output_types, '', 'linear', '', "$list_fileIDs{'tal_t1w'}".($native_t2w?",$list_fileIDs{'tal_t2w'}":'').($native_pdw?",$list_fileIDs{'tal_pdw'}":''), (1));
$list_fileIDs{'tal_comp_msk'} = $fileID[0];

###########################
## face Quality Control...
$program = "$bin_dir/pipeline_qc_face.pl";
@inputs = [$initial_file_list{'clp_t1w'}];
$parameter = "$candid $visitno $age";
#$parameter = "0 V1 $age";
@outputs = [$initial_file_list{'qc_face'}];
@output_types = qw(qc_face);
@fileID = create_function($program, @inputs, $parameter, @outputs,  \@output_types, 't1w', 'native', '', "$list_fileIDs{'clp_t1w'}", (1));
$list_fileIDs{'qc_face'} = $fileID[0];

unless($disable_nonlinear)
{
  ###################
  ##non linear register all three anatomicals
  $program = "$bin_dir/pipeline_nlr.pl ";
  @inputs = [$initial_file_list{'tal_t1w'},$initial_file_list{'tal_comp_msk'}];
  $parameter = " --model_dir ${model_dir} --model_name ${model}";
  @outputs = [$initial_file_list{'nl_grid'}, $initial_file_list{'nl_xfm'}, $initial_file_list{'nl_t1w'}];
  @output_types = qw(nlr_grid nlr_xfm nlr_t1w);

  @fileID = create_function($program, @inputs, $parameter, @outputs, 
              \@output_types, '', 'nonlinear', '', 
              "$list_fileIDs{'tal_xfm_t1w'}, $list_fileIDs{'tal_xfm_t2w'}, $list_fileIDs{'tal_t1w'}, $list_fileIDs{'clp_t1w'}, $list_fileIDs{'clp_t2w'}, $list_fileIDs{'clp_pdw'}, $list_fileIDs{'tal_comp_msk'}",
              (1, 1, 1, 1, 1));

  $list_fileIDs{'nl_grid'} = $fileID[0];
  $list_fileIDs{'nl_xfm'} = $fileID[1];
  
  $program = "$bin_dir/pipeline_jacobian.pl";
  @inputs = [$initial_file_list{'nl_grid'},];
  $parameter = "";
  @outputs = [$initial_file_list{'nl_jacobian'}];
  @output_types = qw(nlr_jacobian);
  @fileID = create_function($program, @inputs, $parameter, @outputs, \@output_types, '', 'nonlinear', '', "$list_fileIDs{'nl_grid'}", (1));
  $list_fileIDs{'nl_jacobian'} = $fileID[0];
}


#$clobber=1;
##########################
##linear classifications
$program = "$bin_dir/pipeline_classify.pl";
@inputs = ($initial_file_list{'tal_t1w'} );
push @inputs, $initial_file_list{'tal_t2w'} if $native_t2w;
push @inputs, $initial_file_list{'tal_pdw'} if $native_pdw;

$parameter = "--mask $initial_file_list{'tal_comp_msk'} ";
$parameter = $parameter." --model_dir ${model_dir} --model_name ${model} ";
$parameter=$parameter." --xfm $initial_file_list{'nl_xfm'}"  unless($disable_nonlinear);

@outputs = [$initial_file_list{'tal_clean'}];
@output_types = qw(lc_clean);
@fileID = create_function($program, \@inputs, $parameter, @outputs, \@output_types, '', 'linear', 'clean',  "$list_fileIDs{'tal_t1w'}".($native_t2w?",$list_fileIDs{'tal_t2w'}":'').($native_pdw?",$list_fileIDs{'tal_pdw'}":''), (1));
$list_fileIDs{'tal_clean'} = $fileID[0];

#$clobber=1;
##########################
##linear segmentations
$program = "$bin_dir/pipeline_segment.pl";
@inputs = [$initial_file_list{'tal_clean'}, $identity_file, $identity_file];
$parameter = " --model-dir ${model_dir} --template ${model}";
@outputs = [$initial_file_list{'tal_clean_lobe'}];
@output_types = qw(linear_segment_lobe);
@fileID = create_function($program, @inputs, $parameter, @outputs, \@output_types, '', 'linear', 'clean', $list_fileIDs{'tal_clean'}, (1, 1));
$list_fileIDs{'tal_clean_lobe'} = $fileID[0];


#########################
##VBM
$program = "$bin_dir/pipeline_smooth.pl";
@inputs = [$initial_file_list{'tal_clean'}];
$parameter = "";
@outputs = [$initial_file_list{'tal_clean_wm'},$initial_file_list{'tal_clean_gm'},$initial_file_list{'tal_clean_csf'}];
@output_types = qw(linear_smooth_wm linear_smooth_gm linear_smooth_csf);
@fileID = create_function($program, @inputs, $parameter, @outputs, \@output_types, '', 'linear', 'clean', $list_fileIDs{'tal_clean'}, (1, 1, 1 ));
$list_fileIDs{'tal_clean_wm'} = $fileID[0];
$list_fileIDs{'tal_clean_gm'} = $fileID[1];
$list_fileIDs{'tal_clean_csf'} = $fileID[2];


unless($disable_nonlinear)
{
  $program = "$bin_dir/pipeline_smooth.pl";
  @inputs = [$initial_file_list{'tal_clean'}];
  $parameter = "--xfm $initial_file_list{'nl_xfm'}";
  @outputs = [$initial_file_list{'modulated_wm'}, $initial_file_list{'modulated_gm'}, $initial_file_list{'modulated_csf'}];
  @output_types = qw(nonlinear_modulated_wm nonlinear_modulated_gm nonlinear_modulated_csf);
  @fileID = create_function($program, @inputs, $parameter, @outputs, \@output_types, '', 'nonlinear', 'clean', $list_fileIDs{'tal_clean'}, (1, 1, 1 ));
  $list_fileIDs{'modulated_csf'} = $fileID[0];
  $list_fileIDs{'modulated_gm'}  = $fileID[1];
  $list_fileIDs{'modulated_wm'}  = $fileID[2];
  
  $program = "$bin_dir/pipeline_dbm.pl";
  @inputs = [$initial_file_list{'nl_xfm'}];
  $parameter = "--model ${model_dir}/${model}.mnc ";
  @outputs = [$initial_file_list{'dbm'}];
  @output_types = qw(nonlinear_dbm);
  @fileID = create_function($program, @inputs, $parameter, @outputs, \@output_types, '', 'nonlinear', '', $list_fileIDs{'nl_xfm'}, ( 1 ));
  $list_fileIDs{'dbm'} = $fileID[0];


  #$clobber=1;
  $program = "$bin_dir/pipeline_segment.pl";
  @inputs = [$initial_file_list{'tal_clean'}, $identity_file, $initial_file_list{'nl_xfm'}];
  $parameter = " --model-dir ${model_dir} --template ${model} --verbose ";
  @outputs = [$initial_file_list{'nl_clean_lobe'}];
  @output_types = qw(nonlinear_segment_lobe);
  @fileID = create_function($program, @inputs, $parameter, @outputs, \@output_types, '', 'nonlinear', 'clean', "$list_fileIDs{'tal_clean'},$list_fileIDs{'nl_xfm'}", (1,1));
  #$list_fileIDs{'nl_clean_segment'} = $fileID[0];
  $list_fileIDs{'nl_clean_lobe'} = $fileID[0];
  
}

#$force_update_db=1;
#$clobber=1;

###########################
## Quality Control...
$program = "$bin_dir/pipeline_qc_mask.pl";
@inputs = [$initial_file_list{'tal_comp_msk'}, $initial_file_list{'tal_t1w'}];
$parameter = "$candid $visitno $age";
@outputs = [$initial_file_list{'qc_tal_t1msk'}];
@output_types = qw(qc_tal_t1msk);
@fileID = create_function($program, @inputs, $parameter, @outputs,  \@output_types, 't1w', 'linear', '', "$list_fileIDs{'tal_comp_msk'},$list_fileIDs{'tal_t1w'}", (1));
$list_fileIDs{'qc_tal_t1msk'} = $fileID[0];


if($native_t2w)
{
  ###########################
  ## Quality Control...
  $program = "$bin_dir/pipeline_qc_t2t1.pl";
  @inputs = [$initial_file_list{'tal_t1w'}, $initial_file_list{'tal_t2w'}];
  $parameter = "$candid $visitno $age";
  @outputs = [$initial_file_list{'qc_tal_t1t2'}];
  @output_types = qw(qc_tal_t1t2);
  @fileID = create_function($program, @inputs, $parameter, @outputs,  \@output_types, 't1w', 'linear', '', "$list_fileIDs{'tal_t1w'},$list_fileIDs{'tal_t2w'}", (1,1));
  $list_fileIDs{'qc_tal_t1t2'} = $fileID[0];
}

##########################
## t1w QC
$program = "$bin_dir/pipeline_qc_t1w.pl";
@inputs = [$initial_file_list{'tal_t1w'}];
$parameter = "$candid $visitno $age --outline ${model_dir}/${model}_outline.mnc ";
@outputs = [$initial_file_list{'qc_t1w_reg'}];
@output_types = qw(qc_tal_t1w);
@fileID = create_function($program, @inputs, $parameter, @outputs,  \@output_types, 't1w', 'linear', '', "$list_fileIDs{'tal_t1w'}", (1));
$list_fileIDs{'qc_t1w_reg'} = $fileID[0];
  
unless($disable_nonlinear) {  
  ###########################
  ## nonlinar registration Quality Control...
#  $program = "$bin_dir/pipeline_qc_reg.pl";
#  @inputs = [$initial_file_list{'nl_t1w'}];
#  $parameter = "$candid $visitno $age";
#  @outputs = [$initial_file_list{'qc_nl_reg'}];
#  @output_types = qw(qc_nl_reg);
#  @fileID = create_function($program, @inputs, $parameter, @outputs,  \@output_types, 't1w', 'nonlinear', '', "$list_fileIDs{'nl_t1w'}", (1));
#  $list_fileIDs{'qc_nl_reg'} = $fileID[0];
  
  #$clobber=1;
  #########################
  # nonlinar quality-control
  $program = "$bin_dir/pipeline_qc_nl.pl";
  @inputs = [$initial_file_list{'tal_t1w'}, $initial_file_list{'tal_clean'}, $initial_file_list{'nl_clean_lobe'}];
  $parameter = "$candid $visitno $age";
  @outputs = [$initial_file_list{'qc_tal_lc_clean'}, $initial_file_list{'qc_nl_segment_lobe'}];
  @output_types = qw(qc_tal_lc_clean qc_nl_segment_lobe);
  @fileID = create_function($program, @inputs, $parameter, @outputs,  \@output_types, '', 'linear', '',"$list_fileIDs{'tal_t1w'},$list_fileIDs{'nl_clean_lobe'}", (1,1,1));
  $list_fileIDs{'qc_tal_lc_clean'} = $fileID[0];
  #$list_fileIDs{'qc_nl_segment'} = $fileID[1];
  $list_fileIDs{'qc_nl_segment_lobe'} = $fileID[1];
}

unless($disable_nonlinear)
{
  $program = "$bin_dir/pipeline_volumes_nl.pl";
  @outputs = [$initial_file_list{'nl_volumes'}];
  #@output_types = qw(clean_volumes);
  @inputs = [$initial_file_list{'tal_comp_msk'}, $initial_file_list{'tal_clean'}, $initial_file_list{'nl_clean_lobe'}, $initial_file_list{'tal_xfm_t1w'} ];
  $parameter = "--age $age --scanner ${scanner_name} --scanner_id ${scannerID[0]}";

  $parameter=$parameter." --t1 $initial_file_list{native_t1w} " if $initial_file_list{native_t1w};
  $parameter=$parameter." --t2 $initial_file_list{native_t2w} " if $initial_file_list{native_t2w};
  $parameter=$parameter." --pd $initial_file_list{native_pdw} " if $initial_file_list{native_pdw};

  @output_types = qw(nl_volumes);
  @fileID = create_function($program, @inputs, $parameter, @outputs,  \@output_types, '', 'nonlinear', 'clean', "$list_fileIDs{'tal_clean'}", (1));
} else {
  $program = "$bin_dir/pipeline_volumes_lin.pl";
  @outputs = [$initial_file_list{'tal_volumes'}];
  #@output_types = qw(clean_volumes);
  @inputs = [$initial_file_list{'tal_comp_msk'}, $initial_file_list{'tal_clean'}, $initial_file_list{'tal_xfm_t1w'} ];
  $parameter = "--age $age --scanner ${scanner_name} --scanner_id ${scannerID[0]}";

  $parameter=$parameter." --t1 $initial_file_list{native_t1w} " if $initial_file_list{native_t1w};
  $parameter=$parameter." --t2 $initial_file_list{native_t2w} " if $initial_file_list{native_t2w};
  $parameter=$parameter." --pd $initial_file_list{native_pdw} " if $initial_file_list{native_pdw};

  @output_types = qw(lin_volumes);
  @fileID = create_function($program, @inputs, $parameter, @outputs,  \@output_types, '', 'nonlinear', 'clean', "$list_fileIDs{'tal_clean'}", (1));
}

if(!$disable_nonlinear && $run_face )
{
  $program = "$bin_dir/pipeline_face.pl";

  @inputs = [$initial_file_list{'tal_t1w'},$initial_file_list{'tal_comp_msk'},
    $initial_file_list{'tal_clean'},$initial_file_list{'nl_clean_lobe'},
    $initial_file_list{'tal_xfm_t1w'},$initial_file_list{'nl_xfm'}];
    
  $parameter = " ";
  @outputs = [ $initial_file_list{'face'} ];
  @output_types = qw(face);
  @fileID = create_function($program, @inputs, $parameter, @outputs,  \@output_types, 't1w', 'linear', '', "$list_fileIDs{'tal_t1w'}", (1));
  $list_fileIDs{'face'} = $fileID[0];
}

###########################
## PVE
## To fit in with create_function, pipeline_pve will have to take dummy output arguments.
#$program = "$bin_dir/pipeline_pve.pl";
#@inputs = [$initial_file_list{'tal_t1w'},$initial_file_list{'tal_clean'} ];
#$parameter = [$initial_file_list{'tal_clean_pve_base'}];
#@outputs = [$initial_file_list{'tal_clean_pve_csf'},$initial_file_list{'tal_clean_pve_gm'},$initial_file_list{'tal_clean_pve_wm'},$initial_file_list{'tal_clean_pve_disc'}];
#@output_types = qw(tal_clean_pve_csf tal_clean_pve_gm tal_clean_pve_wm tal_clean_pve_disc);
#@fileID = create_function($program, @inputs, $parameter, @outputs,  \@output_types, '', 'linear', 'clean', "$list_fileIDs{'tal_t1w'},$list_fileIDs{'tal_clean'}", (1));
#$list_fileIDs{'(tal_clean_pve_csf'} = $fileID[0];
#$list_fileIDs{'(tal_clean_pve_gm'} = $fileID[1];
#$list_fileIDs{'(tal_clean_pve_wm'} = $fileID[2];
#$list_fileIDs{'(tal_clean_pve_disc'} = $fileID[3];


if($benchmark)
{
  my  ($user2,$system2,$cuser2,$csystem2) = times;
  print BENCHMARK "TOTAL,$cuser2\n";
  close BENCHMARK;
}

###################################################################
sub create_directories
{
    my ($base_name) = @_;

    my @dirnames = qw(clp tal nl tal_cls seg lob smooth qc vol deface);
    my $dirname;

    if(!-e $base_name) {` mkdir -p $base_name`;}
    foreach $dirname(@dirnames) {
      my $newdir = "${base_name}/${dirname}";
      if (!-e $newdir){`mkdir $newdir`;}
    }
}

###################################################################
sub get_list_files_native_files
{
    my ($base_name, $candid, $visitno, $t1w, $t2w, $pdw) = @_;
   
    my %list_names = {};

    my @types = ('t1w','t2w','pdw');

    $list_names{'native_t1w'} = $t1w;
    $list_names{'native_t2w'} = $t2w;
    $list_names{'native_pdw'} = $pdw;

    my $type;
    $list_names{'deface_base'} = "$base_name/deface/deface_${candid}_${visitno}";
    foreach $type(@types)
    {

			my ($native_current,$crop_current, $b0correct_current, $nuc_current,
          $nuc_imp_current,$clp_current,$clp_stats_current, $tal_current,
          $tal_xfm_current,$nl_current, $tal_noscale_current, $tal_noscale_xfm_current,
          $tal_mask_current);
					 
			$native_current = "native_$type";
      my $native_deface  = "deface_$type";
			$crop_current = "crop_$type";
			$b0correct_current = "b0correct_$type";
			$nuc_current = "nuc_$type";
			$nuc_imp_current = "nuc_imp_$type";
			$clp_current = "clp_$type";
			$clp_stats_current = "clp_stats_$type";
			$tal_current = "tal_$type";
			$tal_xfm_current = "tal_xfm_$type";
			$tal_mask_current= "tal_mask_$type";
			$nl_current = "nl_$type";
			$tal_noscale_current = "tal_noscale_$type";
			$tal_noscale_xfm_current = "tal_noscale_xfm_$type";
		
      $list_names{$native_deface} = "$list_names{'deface_base'}_${type}.mnc";
      
			$list_names{$crop_current} = "$base_name/crp/crop_${candid}_${visitno}_${type}.mnc";	
			$list_names{$b0correct_current} = "$base_name/b0correct/b0correct_${candid}_${visitno}_${type}.mnc";
			$list_names{$nuc_current} = "$base_name/nuc/nuc_${candid}_${visitno}_${type}.mnc";
			$list_names{$nuc_imp_current} = "$base_name/nuc/nuc_${candid}_${visitno}_${type}.imp";
			$list_names{$clp_current} = "$base_name/clp/clamp_${candid}_${visitno}_${type}.mnc";
			$list_names{$clp_stats_current} = "$base_name/clp/clamp_stats_${candid}_${visitno}_${type}.stats";
				 
			$list_names{$tal_current} = "$base_name/tal/tal_${candid}_${visitno}_${type}.mnc";
			$list_names{$tal_xfm_current} = "$base_name/tal/tal_xfm_${candid}_${visitno}_${type}.xfm";
			$list_names{$tal_mask_current} = "$base_name/tal/tal_mask_${candid}_${visitno}_${type}.mnc";
			$list_names{$nl_current} = "$base_name/nl/nl_${candid}_${visitno}_${type}.mnc";
			
			$list_names{$tal_noscale_current} = "$base_name/tal/tal_noscale_${candid}_${visitno}_${type}.mnc";
			$list_names{$tal_noscale_xfm_current} = "$base_name/tal/tal_noscale_xfm_${candid}_${visitno}_${type}.xfm";
    }
    
    $list_names{'deface_grid'} = "$list_names{'deface_base'}_grid_0.mnc";
    $list_names{'nl_grid'} = "$base_name/nl/nl_xfm_${candid}_${visitno}_grid_0.mnc";
    $list_names{'nl_xfm'} = "$base_name/nl/nl_xfm_${candid}_${visitno}.xfm";
	
    $list_names{'nl_jacobian'} ="$base_name/nl/nl_jacobian_${candid}_${visitno}.mnc";
    $list_names{'nl_t1w'} ="$base_name/nl/nl_${candid}_${visitno}_t1w.mnc";
        
    $list_names{'tal_msk'} = "$base_name/tal/tal_msk_${candid}_${visitno}.mnc";
    $list_names{'tal_comp_msk'} = "$base_name/tal/tal_comp_msk_${candid}_${visitno}.mnc";
    
    $list_names{'tal_clean'} = "$base_name/tal_cls/tal_clean_${candid}_${visitno}.mnc";
    $list_names{'tal_clean_lobe'} = "$base_name/lob/tal_clean_lob_${candid}_${visitno}.mnc";
   
    $list_names{'nl_clean_lobe'} = "$base_name/lob/nl_clean_lob_${candid}_${visitno}.mnc";
		$list_names{'clean_lobe_volumes'} = "$base_name/lob/clean_volumes_${candid}_${visitno}.txt";

    $list_names{'tal_clean_wm'} = "$base_name/smooth/tal_clean_wm_${candid}_${visitno}.mnc";
    $list_names{'tal_clean_gm'} = "$base_name/smooth/tal_clean_gm_${candid}_${visitno}.mnc";
    $list_names{'tal_clean_csf'} = "$base_name/smooth/tal_clean_csf_${candid}_${visitno}.mnc";

    $list_names{'nl_clean_wm'} = "$base_name/smooth/nl_clean_wm_${candid}_${visitno}.mnc";
    $list_names{'nl_clean_gm'} = "$base_name/smooth/nl_clean_gm_${candid}_${visitno}.mnc";
    $list_names{'nl_clean_csf'} = "$base_name/smooth/nl_clean_csf_${candid}_${visitno}.mnc";
	
    $list_names{'modulated_csf'} = "$base_name/smooth/modulated_csf_${candid}_${visitno}.mnc";
    $list_names{'modulated_gm'} = "$base_name/smooth/modulated_gm_${candid}_${visitno}.mnc";
    $list_names{'modulated_wm'} = "$base_name/smooth/modulated_wm_${candid}_${visitno}.mnc";
    
    $list_names{'dbm'}          = "$base_name/smooth/dbm_${candid}_${visitno}.mnc";
	
    $list_names{'qc_tal_t1msk'} = "$base_name/qc/qc_tal_t1msk_${candid}_${visitno}.jpg";
    $list_names{'qc_tal_t1t2'} = "$base_name/qc/qc_tal_t1t2_${candid}_${visitno}.jpg";
    $list_names{'qc_nl_reg'} = "$base_name/qc/qc_nl_reg_${candid}_${visitno}.jpg";
    $list_names{'qc_t1w_reg'} = "$base_name/qc/qc_t1w_${candid}_${visitno}.jpg";
    $list_names{'qc_face'} = "$base_name/qc/qc_face_${candid}_${visitno}.jpg";
    $list_names{'qc_deface'} = "$base_name/qc/qc_deface_${candid}_${visitno}.jpg";

    $list_names{'qc_tal_lc_clean'}= "$base_name/qc/qc_t1w_lc_clean_${candid}_${visitno}.jpg";
    $list_names{'qc_nl_segment_lobe'}= "$base_name/qc/qc_nl_t1w_segment_lobe_${candid}_${visitno}.jpg";

    $list_names{'tal_volumes'}="$base_name/vol/tal_${candid}_${visitno}.txt";
    $list_names{'nl_volumes'}="$base_name/vol/nl_${candid}_${visitno}.txt";

#     $list_names{'clasp'}="$base_name/clasp/${candid}_${visitno}_clasp";
#     $list_names{'clasp3'}="$base_name/clasp/${candid}_${visitno}";
#     
#     $list_names{'face'}="$base_name/face/atlas/lobes_measurements.csv";
	
    #$list_names{'tal_clean_pve_base'} = "$base_name/pve/tal_clean_pve_${candid}_${visitno}.mnc";
    #$list_names{'tal_clean_pve_csf'} = "$base_name/pve/tal_clean_pve_${candid}_${visitno}_csf.mnc";
    #$list_names{'tal_clean_pve_gm'} = "$base_name/pve/tal_clean_pve_${candid}_${visitno}_gm.mnc";
    #$list_names{'tal_clean_pve_wm'} = "$base_name/pve/tal_clean_pve_${candid}_${visitno}_wm.mnc";
    #$list_names{'tal_clean_pve_disc'} = "$base_name/pve/tal_clean_pve_${candid}_${visitno}_disc.mnc";
    
    return %list_names;
}


###################################################################
# Returns an array of fileID's, one entry for each output file.
# An entry will be set to -1 if the file was not added to the database.
sub create_function
{
    my($program, $infiles, $parameters, $outfiles, $output_types_ref, $protocal, $coordinate_space, $classify_algorithm, $source, @addToDB) = @_;

    my @outfileIDList = @addToDB;
    my $program_string = "${program} ";
    my $infile;
    
    foreach (@ {$infiles}) {
      $infile = $_;
      if(!-e $infile)
      {
          $infile = "${infile}.gz";
      }
      $program_string = "$program_string $infile";
    }
    $program_string = "$program_string $parameters";

    print "******** $program_string *********\n\n";

    my $processing_needed = 0;

    my $outfile;
    my $i = -1;
    my @output_list;
    foreach (@ {$outfiles}) {
		++ $i;
		$outfile = $_;;
		$program_string = "$program_string $outfile";
	
		print "Checking existence of $outfile...\n";
		my $delete_file_needed =0;	
		my $filename;
		
		if (-e $outfile ) {
			$filename=$outfile;
			print "\t\tExists.\n";
			if($clobber) {
				$delete_file_needed=1;
				$processing_needed=1;
			}
		} elsif (-e "${outfile}.gz") {
			$filename="${outfile}.gz";
			 print "\t\tExists compressed.\n";
			if($clobber) {
				$delete_file_needed=1;
				$processing_needed=1;
			}
		} else {
			$processing_needed=1;
			 print "\t\tDoes not exist.\n";
		}
		if( !$processing_needed ) 
    {
      # If the outfile already exists, get its fileID from the database
      # since we are still expected to return this value.
      $outfileIDList[$i]=-1;
      
      if ( $outfileIDList[$i] && $outfileIDList[$i]>0 ) 
      {
        $addToDB[$i] = 0;
        print "$filename exists.  Using fileID $outfileIDList[$i]\n";
      } else {
        #$addToDB[$i] = 1;
        print "$filename exists. Will register in DB\n";
      }
		}
    }
    my $index = -1;
    if($processing_needed)
    {
      my $results, my $d, my $outputs ;

      print("EXECUTE $program_string\n\n");
      my  ($user1,$system1,$cuser1,$csystem1) = times;
      Spawn($program_string, stdout => \$results) unless $dry_run;
      my  ($user2,$system2,$cuser2,$csystem2) = times;
      
      my $elapsed=$cuser2-$cuser1;
      my $stage=basename($program);
      
      print BENCHMARK "$stage,$elapsed\n" if $benchmark;
      
      print("---output---\n",$results,"---output---\n");
    
      ($d, $outputs) = split("Files created:", $results);
      @output_list = split(" ", $outputs);
		
    } else {
      print("Outputs found... skipping\n");
    }
    print "Outputs: @output_list\n";
    my ($file,@insert_args);
	  foreach $file(@output_list)
	  {
     unless($ENV{MINC_FORCE_V2})
     {
      if($file =~ /mnc$/) {
        do_cmd('gzip',$file); 
        $file = "$file.gz";
      }
    }
		++ $index;
		$outfileIDList[$index] = -1;
	}
	
  return @outfileIDList;
}

sub do_cmd {
    print STDOUT "@_\n" if $verbose;
    if(!$fake) {
        system(@_) == 0 or die "DIED: @_\n";
    }
}


#make sure that we have a regular sampling
sub fix_sampling {
  my $in_minc=$_[0];
  my $need_fixing=0;
  my $spc;
  foreach $spc(split(/\n/,`mincinfo -attvalue xspace:spacing -attvalue yspace:spacing -attvalue zspace:spacing  $in_minc`))
  {
    $need_fixing=1 if $spc=~/irregular/;
  }
  my $out=$in_minc;
  if($need_fixing)
  {
    $out=$tmpdir.'/'.basename($in_minc,'.gz');
    if($in_minc=~/.gz$/)
    {
      do_cmd("gunzip -c $in_minc >$out");
    } else {
      do_cmd('cp',$in_minc,$out);
    }
    do_cmd('minc_modify_header','-sinsert','xspace:spacing=regular__','-sinsert','zspace:spacing=regular__','-sinsert','yspace:spacing=regular__',$out)
  }
  return $out;
}



sub create_header_info_for_many_parented
{
  my ($child_mnc_file, $parent_mnc_file, $tmpdir) = @_;
    #VF check .gz files

  if(!-e $child_mnc_file) {
    if(-e $child_mnc_file.".gz") {
      $child_mnc_file=$child_mnc_file.".gz";
    } else {
      die "create_header_info_for_many_parented ${child_mnc_file} doesn't exists!\n";
    }
  }

  if(!-e $parent_mnc_file) {
    if(-e $parent_mnc_file.".gz") {
      $parent_mnc_file=$parent_mnc_file.".gz";
    } else {
      die "create_header_info_for_many_parented ${parent_mnc_file} doesn't exists!\n";
    }
  }
      
  my $history = `mincinfo -attvalue :history $child_mnc_file`;

  my $tmp_file = "$tmpdir/temp_modified.mnc";
    
  my $line;
  
    #$tmp_file = $child_mnc_file;
  do_cmd("mincaverage -clobber $child_mnc_file -nocopy_header $tmp_file");

  my  @patient = `mincheader $parent_mnc_file | grep patient:`;
  foreach $line(@patient)
  {
    chomp($line);
    $line =~ s/ //g;
    print("minc_modify_header $tmp_file -sinsert $line\n");
    do_cmd('minc_modify_header',$tmp_file,'-sinsert',$line);
  }
    
  my @dicom_tags = qw(dicom_0x0010:el_0x0010 dicom_0x0008:el_0x0020 dicom_0x0008:el_0x0070 dicom_0x0008:el_0x1090 dicom_0x0018:el_0x1000 dicom_0x0018:el_0x1020 dicom_0x0008:el_0x103e);

  my $tag;
  foreach $tag(@dicom_tags) {
    my @dicom_field = `mincheader $parent_mnc_file | grep $tag`;
    foreach $line(@dicom_field)
    {
        chomp($line);
        $line =~ s/ //g;
        print("minc_modify_header $tmp_file -sinsert $line\n");
        do_cmd('minc_modify_header',$tmp_file,'-sinsert',$line);
    }
  }
    
  do_cmd('minc_modify_header',$tmp_file,'-delete',':history');
  do_cmd('minc_modify_header',$tmp_file,'-sinsert',":history=\"${history}\"");
  if($child_mnc_file =~/\.gz$/) {
    do_cmd("gzip -c ${tmp_file}>${child_mnc_file}");
  } else {
    do_cmd('cp',$tmp_file,$child_mnc_file);
  }
  do_cmd('rm',$tmp_file);
}
