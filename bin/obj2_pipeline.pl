#!/usr/bin/env perl

use strict;
use Getopt::Long;
use File::Basename;
use File::Temp qw/ tempdir /;
#use NeuroDB::DBI;

my $verbose=1;
my $clobber=0;
my $fake=0;
my $prefix='./';
my $manual;
my $model;
my $me = basename ($0);
my $deface;
my $relx;
my $dbh;
my $update_db;
my %file_id;
my $nonlinear=0;
my $age=0;
my $t1_mask;
my $t2_mask;
my $ants=0;
my $nihpd=0;
my $nihpd_secret=0;

GetOptions(
      'verbose'           => \$verbose,
      'clobber'           => \$clobber,
      'prefix=s'          => \$prefix,
      'manual=s'          => \$manual,
      'model=s'           => \$model,
      'deface'            => \$deface,
      'relx'              => \$relx,
      'nonlinear'         => \$nonlinear,
      'age=f'             => \$age,
      't1_mask=s'         => \$t1_mask,
      't2_mask=s'         => \$t2_mask,
      'ants'             => \$ants,
	   );

my $Help = <<HELP;
  Usage: $me <subject_id> <visit_label> <T1 file> [T2 file] [PD file] [T2 echo 2] [T2 echo 3] ....
    --verbose be verbose
    --clobber clobber _all_ output files
    --prefix <dir> output directory prefix  ,all data will be in <prefix>/<subject_id>/<visit_label>
    --manual <dir> prefix to the place with manual input, should be in  <subject_id>/<visit_label>
    --model <model> - t1w model, others will be created by replacing _t1w with appropriate suffix
    --deface to do defacing, based on the face mask
    --relx  do relaxometry data processing
    --nonlinear
    --age <age in months>
    --t2_mask <brain mask in t2 space>
    --t1_mask <brain mask in t1 space>
    --ants - use mincants for nonlinear registration
  Problems or comments should be sent to: vladimir.fonov\@gmail.com
HELP

die $Help if $#ARGV < 2;

#find all the input files
$update_db=0;
my $in;

my ($candid,$visitno,$native_t1w,$native_t2w,$native_pdw);

$candid = shift @ARGV;
$visitno= shift @ARGV;

foreach $in(@ARGV)
{
  $file_id{$in}=get_file_id($in);
}


$native_t1w=shift @ARGV;
$native_t2w=shift @ARGV;
$native_pdw=shift @ARGV;

my @more_t2=@ARGV;


chomp($model=`realpath $model`);

my $base_dir="$prefix/$candid/$visitno/";
my ($model_t1w,$model_t2w,$model_pdw,$model_mask,$model_bigmask,$model_face,$model_outline,$model_final,$model_total)=($model,$model,$model,$model,$model,$model,$model,$model,$model,$model);
my $model_mask2=$model;
my $model_mask_cb=$model;


my $model_atlas=dirname($model)."/nihpd_asym_44-60_cls_wm_gm_blood.mnc";#hack, fix it
my $model_atlas_gm=dirname($model)."/nihpd_asym_44-60_gm.mnc";#hack, fix it
my $model_atlas_wm=dirname($model)."/nihpd_asym_44-60_wm.mnc";#hack, fix it
my $model_atlas_csf=dirname($model)."/nihpd_asym_44-60_csf.mnc";#hack, fix it
my $lobe_atlas=dirname($model)."/atlas_44_60/";#hack, fix it

$model_t2w     =~ s/_t1w/_t2w/;
$model_pdw     =~ s/_t1w/_pdw/;
$model_mask    =~ s/_t1w/_mask/;
$model_mask2   =~ s/_t1w/_mask2/;
$model_bigmask =~ s/_t1w/_bigmask/;
$model_face    =~ s/_t1w/_face/;
$model_outline =~ s/_t1w/_outline/;
$model_mask_cb =~ s/_t1w/_mask_cb/;

$model_final   =~ s/_t1w\.mnc/_final_ants_double.xfm/;
$model_total   =~ s/_t1w\.mnc/_t1w_tal.xfm/;

#$model_c1     =~ s/_t1w/_c1/;

my %models = ( 't1w' => $model_t1w, 't2w' => $model_t2w, 'pdw' => $model_pdw );

my $minc_compress=$ENV{'MINC_COMPRESS'};
my $minc2=$ENV{'MINC_FORCE_V2'};

my $tmpdir = &tempdir( "$me-XXXXXXXX", TMPDIR => 1, CLEANUP => 1 );

create_directories($base_dir);

my %initial_file_list = get_list_files_native_files($base_dir, $candid, $visitno, $native_t1w, $native_t2w, $native_pdw );
my %manual_file_list;
%manual_file_list = get_list_files_native_files("$manual/$candid/$visitno/", $candid, $visitno, $native_t1w, $native_t2w, $native_pdw ) if $manual;


#create symbolic links for models
do_cmd('ln','-sf',$model_t1w,$initial_file_list{"model_t1w"}) 
 unless -e $initial_file_list{"model_t1w"};
 
do_cmd('ln','-sf',$model_t2w,$initial_file_list{"model_t2w"}) 
 unless -e $initial_file_list{"model_t2w"};
 
do_cmd('ln','-sf',$model_pdw,$initial_file_list{"model_pdw"}) 
 unless -e $initial_file_list{"model_pdw"};
 
do_cmd('ln','-sf',$model_mask,$initial_file_list{"model_mask"}) 
 unless -e $initial_file_list{"model_mask"};
 
do_cmd('ln','-sf',$model_face,$initial_file_list{"model_face"}) 
 unless -e $initial_file_list{"model_face"};

do_cmd('ln','-sf',$model_total,$initial_file_list{"model_total"}) 
 unless -e $initial_file_list{"model_total"};

do_cmd('ln','-sf',$model_mask_cb,$initial_file_list{"model_mask_cb"}) 
 unless -e $initial_file_list{"model_total"};


#do_cmd('ln','-sf',$model_c1,$initial_file_list{"model_c1"}) 
# unless -e $initial_file_list{"model_c1"};

my ($have_t2,$have_pd);
$have_t2=1 if $initial_file_list{"native_t2w"};
$have_pd=1 if $initial_file_list{"native_pdw"};

# correct for intensity nonuniformity, clamp intensity range using the model
my $mod;
foreach $mod('t1w','t2w','pdw') {

  next unless $initial_file_list{"native_$mod"};
  
  do_cmd('pipeline_correct3.pl',$initial_file_list{"native_$mod"},
         $initial_file_list{"clp_$mod"},
         '--model',$models{$mod},
         '--iterations',5)
    unless -e $initial_file_list{"clp_$mod"};
  $file_id{$initial_file_list{"clp_$mod"}}=register_in_db($initial_file_list{"clp_$mod"},'clamp_mnc',$mod,'native','',$file_id{$initial_file_list{"native_$mod"}}) if $nihpd_secret;

}
# register t2/pd to t1 using mutual information
if($initial_file_list{"native_t2w"})
{
  if($manual && -e $manual_file_list{'t2t1'})
  {
   do_cmd('cp',$manual_file_list{'t2t1'},$initial_file_list{'t2t1'}) 
    unless -e $initial_file_list{'t2t1'};
  }else {
   #do_cmd('mritoself','-mi',$initial_file_list{'clp_t2w'},$initial_file_list{'clp_t1w'},$initial_file_list{'t2t1'}) 
   do_cmd('mritoself','-mi','-lsq6','-close','-nothreshold',
          $initial_file_list{'clp_t2w'},$initial_file_list{'clp_t1w'},
          $initial_file_list{'t2t1'})
    unless -e $initial_file_list{'t2t1'};
  }
}

if($t2_mask) #resample to t1 space
{
  do_cmd('mincresample','-nearest',$t2_mask,'-like',$initial_file_list{'clp_t1w'}, $initial_file_list{'native_t1w_mask'},'-transform',$initial_file_list{'t2t1'})
   unless -e $initial_file_list{'native_t1w_mask'};
}

if($t1_mask) #resample to t1 space
{
  do_cmd('mincresample','-nearest',$t1_mask,'-like',$initial_file_list{'clp_t1w'}, $initial_file_list{'native_t1w_mask'})
   unless -e $initial_file_list{'native_t1w_mask'};
}

if($manual && -e $manual_file_list{'stx1_xfm_t1w'})
{
 do_cmd('cp',$manual_file_list{'stx1_xfm_t1w'}, $initial_file_list{'stx1_xfm_t1w'}) 
  unless -e  $initial_file_list{'stx1_xfm_t1w'};
}else{
	# 1st linear registration using quaternions
  if($t1_mask||$t2_mask)
  {
    do_cmd('bestlinreg.pl','-quaternion',
      $initial_file_list{'clp_t1w'},
      $model_t1w,
      $initial_file_list{'stx1_xfm_t1w'},
      '-source_mask',$initial_file_list{'native_t1w_mask'},
      '-target_mask',$initial_file_list{"model_mask"})
        unless -e $initial_file_list{'stx1_xfm_t1w'};
  } else { 
    do_cmd('bestlinreg.pl','-quaternion',
      $initial_file_list{'clp_t1w'},
      $model_t1w,
      $initial_file_list{'stx1_xfm_t1w'})
       unless -e $initial_file_list{'stx1_xfm_t1w'};
 }
}

do_cmd('itk_resample',
       '--order',4,$initial_file_list{'clp_t1w'},
			 '--transform',$initial_file_list{'stx1_xfm_t1w'},
       '--like',$model_t1w,$initial_file_list{'stx1_t1w'}) 
    unless -e $initial_file_list{'stx1_t1w'};
    
if($t1_mask||$t2_mask)
{
  do_cmd('mincresample','-nearest',
         $initial_file_list{'native_t1w_mask'},
         '-transform',$initial_file_list{'stx1_xfm_t1w'},
         '-like',$model_t1w,$initial_file_list{'stx_msk_temp'}) 
    unless -e $initial_file_list{'stx_msk_temp'};
} else {
  do_cmd('obj2_bet.pl',$initial_file_list{'stx1_t1w'},$initial_file_list{'stx_msk_temp'},'--dilate',2)
   unless -e $initial_file_list{'stx_msk_temp'};
}

# 1st preliminary nonlinear registration
do_cmd('nlfit_o2','-level',8,
       $initial_file_list{'stx1_t1w'},$model_t1w,
       '-threshold',5, $initial_file_list{'nl1_xfm'},
       '-source_mask',$initial_file_list{'stx_msk_temp'},
       '-target_mask',$model_mask) 
     unless -e $initial_file_list{'nl1_xfm'}; 

# approximate  1st nonlinar registration using LTS fitting
do_cmd('grid_to_xfm',$initial_file_list{'nl1_grid'},
       '--mask',$model_mask,
       '--keep',0.9,
       $initial_file_list{'nl_lin'})
  unless -e $initial_file_list{'nl_lin'};

do_cmd('xfmconcat',
       $initial_file_list{'stx1_xfm_t1w'},
       $initial_file_list{'nl_lin'},
       $initial_file_list{'stx2_xfm_t1w'})
       unless -e $initial_file_list{'stx2_xfm_t1w'};

#do_cmd('bestlinreg.pl','-lsq12',
#   $initial_file_list{'clp_t1w'},
#   $model_t1w,
#   '-source_mask',$initial_file_list{'msk_t1w'},
#   '-target_mask',$model_mask,
#   '-init_xfm',$initial_file_list{'stx1_xfm_t1w'},
#   $initial_file_list{'stx2_xfm_t1w'})
#   unless -e $initial_file_list{'stx2_xfm_t1w'};

do_cmd('itk_resample',$initial_file_list{'clp_t1w'},
	$initial_file_list{'stx2_t1w'},'--like', $model_t1w, 
	'--transform', $initial_file_list{'stx2_xfm_t1w'},'--order',4) 
	unless -e $initial_file_list{'stx2_t1w'};
	
# calculate 2nd linear approximation
#do_cmd('xfmconcat',$initial_file_list{'stx1_xfm_t1w'},$initial_file_list{'nl_lin'},$initial_file_list{'stx2_xfm_t1w'}) 
#  unless -e $initial_file_list{'stx2_xfm_t1w'};
  
$file_id{$initial_file_list{'stx2_xfm_t1w'}}=register_in_db($initial_file_list{'stx2_xfm_t1w'},'tal_xfm','t1w','linear','',$file_id{$initial_file_list{'native_t1w'}}) ;

do_cmd('itk_resample',$initial_file_list{'clp_t1w'},'--like',$model_t1w,
  '--transform',$initial_file_list{'stx2_xfm_t1w'},
   $initial_file_list{'stx2_t1w'},'--order',4) 
  unless -e $initial_file_list{'stx2_t1w'};

$file_id{$initial_file_list{'stx2_t1w'}}=register_in_db($initial_file_list{'stx2_t1w'},'tal_mnc','t1w','linear','',$file_id{$initial_file_list{'clp_t1w'}}) if $nihpd_secret;
       
do_cmd('minc_qc.pl',$initial_file_list{'stx2_t1w'},$initial_file_list{'qc_stx'},
       '--mask',$model_outline,'--title',"${candid}_${visitno}",'--image-range',5,100) 
  unless -e $initial_file_list{'qc_stx'};
$file_id{$initial_file_list{'qc_stx'}}=register_in_db($initial_file_list{'qc_stx'},'qc_tal_t1w','t1w','linear','',$file_id{$initial_file_list{'stx2_t1w'}}) if $nihpd_secret;

if($have_t2)
{
  do_cmd('xfmconcat',$initial_file_list{'t2t1'},$initial_file_list{'stx2_xfm_t1w'},$initial_file_list{'stx2_xfm_t2w'}) 
    unless -e  $initial_file_list{'stx2_xfm_t2w'};

  $file_id{$initial_file_list{'stx2_xfm_t2w'}}=register_in_db($initial_file_list{'stx2_xfm_t2w'},'tal_xfm','t2w','linear','',$file_id{$initial_file_list{'native_t2w'}});

  do_cmd('itk_resample',$initial_file_list{'clp_t2w'},'--like',$model_t1w,'--transform',$initial_file_list{'stx2_xfm_t2w'},$initial_file_list{'stx2_t2w'},'--order',4) 
    unless -e $initial_file_list{'stx2_t2w'};

  $file_id{$initial_file_list{'stx2_t2w'}}=register_in_db($initial_file_list{'stx2_t2w'},'tal_mnc','t2w','linear','',$file_id{$initial_file_list{'clp_t2w'}}) if $nihpd_secret;

  do_cmd('minc_qc_t2t1.pl',$initial_file_list{'stx2_t1w'},$initial_file_list{'stx2_t2w'},$initial_file_list{'qc_t2t1'},
         '--title',"${candid}_${visitno}") 
    unless -e $initial_file_list{'qc_t2t1'};

  $file_id{$initial_file_list{'qc_t2t1'}}=register_in_db($initial_file_list{'qc_t2t1'},'qc_tal_t1t2','t2w','linear','',$file_id{$initial_file_list{'stx2_t2w'}}) if $nihpd_secret;
}

if($have_pd) {
  do_cmd('itk_resample',$initial_file_list{'clp_pdw'},'--like',$model_t1w,'--transform',$initial_file_list{'stx2_xfm_t2w'},$initial_file_list{'stx2_pdw'},'--order',4) 
    unless -e $initial_file_list{'stx2_pdw'};
  $file_id{$initial_file_list{'stx2_pdw'}}=register_in_db($initial_file_list{'stx2_pdw'},'tal_mnc','pdw','linear','',$file_id{$initial_file_list{'clp_pdw'}}) if $nihpd_secret;
}

#if( $have_t2 && $have_pd ) #do a first time, for brain extraction
#{
#  do_cmd('pca_contrast.pl',$initial_file_list{'stx2_t1w'},$initial_file_list{'stx2_t2w'},
#       $initial_file_list{'stx2_pdw'},$initial_file_list{'stx2_c1_'}) 
#         unless -e $initial_file_list{'stx2_c1_'};
#}

if($manual && -e $manual_file_list{'stx_msk'})
{
  unless( -e  $initial_file_list{'stx_msk'})
  {
    do_cmd('cp',$manual_file_list{'stx_msk'}, $initial_file_list{'stx_msk'});
  }
}else{

#  if( $have_t2 && $have_pd )
#  {
#    do_cmd('obj2_bet.pl',$initial_file_list{'stx2_c1_'},$initial_file_list{'stx_msk'},
#           '--mask',$model_mask2,'--t2') unless -e $initial_file_list{'stx_msk'};
#
#  } else {

  unless(-e $initial_file_list{'stx_msk'})
  {
    if($t1_mask||$t2_mask)
    {
      do_cmd('mincresample','-nearest',
            $initial_file_list{'native_t1w_mask'},
            '-transform',$initial_file_list{'stx2_xfm_t1w'},
            '-like',$model_t1w,$initial_file_list{'stx_msk'}) ;
    } else {

    do_cmd('obj2_bet.pl',$initial_file_list{'stx2_t1w'},$initial_file_list{'stx_msk'},
          '--mask',$model_mask_cb,'--model',$model_t1w,'-nl')
    }
  }
}
create_header_info_for_many_parented($initial_file_list{'stx_msk'}, $initial_file_list{'stx2_t1w'});
$file_id{$initial_file_list{'stx_msk'}}=register_in_db($initial_file_list{'stx_msk'},'tal_comp_msk','','linear','',$file_id{$initial_file_list{'stx2_t1w'}}) if $nihpd_secret;

#if( $have_t2 && $have_pd )#do a second time
#{
#  do_cmd('pca_contrast.pl',$initial_file_list{'stx2_t1w'},$initial_file_list{'stx2_t2w'},
#       $initial_file_list{'stx2_pdw'},$initial_file_list{'stx2_c1'},
#       '--mask',$initial_file_list{'stx_msk'}) 
#         unless -e $initial_file_list{'stx2_c1'};
#}


# 2nd nonlinar nonlinear registration
#do_cmd('nlfit_o2','-level',4,
#      $initial_file_list{'stx2_t1w'},
#      $model_t1w,
#      '-source_mask',$initial_file_list{'stx_msk'},
#      '-target_mask',$model_mask,
#      $initial_file_list{'nl2_xfm'}) 
#  unless -e $initial_file_list{'nl2_xfm'};

do_cmd('minc_qc.pl',$initial_file_list{'stx2_t1w'},$initial_file_list{'qc_brain'},
       '--mask',$initial_file_list{'stx_msk'},'--title',"${candid}_${visitno}",'--image-range',5,100) 
  unless -e $initial_file_list{'qc_brain'};
$file_id{$initial_file_list{'qc_brain'}}=register_in_db($initial_file_list{'qc_brain'},'qc_mask','t1w','linear','',$file_id{$initial_file_list{'stx2_t1w'}}) if $nihpd_secret;

#tissue classification
#do_cmd('mrfseg.pl','--lowres',$initial_file_list{'stx2_t1w'},'--mask',$initial_file_list{'stx_msk'},$initial_file_list{'stx_cls'}) 
#  unless -e $initial_file_list{'stx_cls'};
#$file_id{$initial_file_list{'stx_cls'}}=register_in_db($initial_file_list{'qc_brain'},'qc_mask','t1w','linear','',$file_id{$initial_file_list{'stx2_t1w'}});

#if($initial_file_list{"native_pdw"} && $initial_file_list{"native_t2w"})
#{
#  do_cmd('pve3','-mask',$initial_file_list{'stx_msk'},'-image',$initial_file_list{'stx_cls'},
#        $initial_file_list{'stx2_t1w'},
#        $initial_file_list{'stx2_t2w'},
#        $initial_file_list{'stx2_pdw'},
#        $initial_file_list{'stx_pve'}) 
#    unless -e $initial_file_list{'stx_pve_csf'};
#} else {
#  do_cmd('pve','-mask',$initial_file_list{'stx_msk'},'-image',$initial_file_list{'stx_cls'},
#        $initial_file_list{'stx2_t1w'},
#        $initial_file_list{'stx_pve'}) 
#    unless -e $initial_file_list{'stx_pve_csf'};
#}

# create a brain mask in the native space
#do_cmd('mincresample',$initial_file_list{'stx_msk'},'-like',$initial_file_list{'clp_t1w'},'-transform',$initial_file_list{'stx2_xfm_t1w'},
#       '-invert_transform',$initial_file_list{'msk_t1w'},'-nearest')
#  unless -e $initial_file_list{'msk_t1w'};
  
#do_cmd('mincresample',$initial_file_list{'stx_msk'},'-like',$initial_file_list{'clp_t2w'},'-transform',$initial_file_list{'stx2_xfm_t2w'},
#       '-invert_transform',$initial_file_list{'msk_t2w'},'-nearest')
#  unless -e $initial_file_list{'msk_t2w'};

       
#delete $ENV{'MINC_COMPRESS'} if $minc_compress;
if($nonlinear)
{
#  if( $have_pd && $have_t2 )
#  {
#    do_cmd('nlfit_o2','-level',2,
#        $initial_file_list{'stx2_c1'},$model_c1,
#        '-source_mask',$model_mask,'-target_mask',$initial_file_list{'stx_msk'},
#        $initial_file_list{'nl3_xfm'}) 
#      unless -e $initial_file_list{'nl3_xfm'};
#  } else {

  unless($ants)
  {
    do_cmd('nlfit_o2','-level',2,
        $initial_file_list{'stx2_t1w'},$model_t1w,
        '-source_mask',$model_mask,'-target_mask',$initial_file_list{'stx_msk'},
        $initial_file_list{'nl3_xfm'}) 
      unless -e $initial_file_list{'nl3_xfm'};
  } else {
      do_cmd('nlfit_ants2','-level',2,
        $initial_file_list{'stx2_t1w'},$model_t1w,
        $initial_file_list{'stx2_t2w'},$model_t2w,
        '-source_mask',$model_mask,
        '-target_mask',$initial_file_list{'stx_msk'},
        $initial_file_list{'nl3_xfm'},'-mi') 
      unless -e $initial_file_list{'nl3_xfm'};
  }


#  }
  $file_id{$initial_file_list{'nl3_xfm'}}=register_in_db($initial_file_list{'nl3_xfm'},'nlr_xfm','','nonlinear','',$file_id{$initial_file_list{'stx2_t1w'}}) if $nihpd_secret;
}

unless(-e $initial_file_list{'stx_face'} || !$nonlinear )
{
  #quick fix to make  sure that brain is not included
  do_cmd('mincresample',$model_face,"$tmpdir/face.mnc",'-like',$model_t1w,
       '-transform',$initial_file_list{'nl3_xfm'},'-nearest','-invert_transformation'); 
  do_cmd('minccalc','-byte','-express','A[0]>0.5&&A[1]>0.5?0:A[0]',"$tmpdir/face.mnc",$initial_file_list{'stx_msk'},$initial_file_list{'stx_face'});
}
create_header_info_for_many_parented($initial_file_list{'stx_face'}, $initial_file_list{'stx2_t1w'});

$file_id{$initial_file_list{'stx_face'}}=register_in_db($initial_file_list{'stx_face'},'tal_face_msk','','linear','',$file_id{$initial_file_list{'stx2_t1w'}}) if $nihpd_secret;

if($nonlinear)
{
do_cmd('minc_qc.pl',$initial_file_list{'stx2_t1w'},$initial_file_list{'qc_face'},
       '--mask',$initial_file_list{'stx_face'},'--title',"${candid}_${visitno}",'--image-range',5,100) 
  unless -e $initial_file_list{'qc_face'};
$file_id{$initial_file_list{'qc_face'}}=register_in_db($initial_file_list{'qc_face'},'qc_face','t1w','linear','',$file_id{$initial_file_list{'stx2_t1w'}}) if $nihpd_secret;
}

# QC      
do_cmd('pipeline_qc_face.pl',$initial_file_list{'clp_t1w'},$candid,$visitno,0,
      $initial_file_list{'qc_face_render'},'--stx',$initial_file_list{'stx2_xfm_t1w'})
      unless -e $initial_file_list{'qc_face_render'};
$file_id{$initial_file_list{'qc_face_render'}}=register_in_db($initial_file_list{'qc_face_render'},'qc_face','','linear','',$file_id{$initial_file_list{'native_t1w'}}) if $nihpd_secret;

if($nonlinear)
{
 unless( -e $initial_file_list{'nl_final_xfm'})
 {
   do_cmd('xfmconcat',$initial_file_list{'nl3_xfm'},$model_final,
          "$tmpdir/final.xfm");
          
   do_cmd('xfm_normalize.pl',"$tmpdir/final.xfm",
          $initial_file_list{'nl_final_xfm'},
          '--like',$initial_file_list{'nl3_grid'},'--exact');
 }
 $file_id{$initial_file_list{'nl_final_xfm'}}=register_in_db($initial_file_list{'nl_final_xfm'},'nlr_xfm','','nonlinear','',$file_id{$initial_file_list{'stx2_t1w'}}) if $nihpd_secret;
}
#$ENV{'MINC_COMPRESS'}=$minc_compress if $minc_compress;

if($relx)
{
  # coregister additional echos 
  my @relx_mri=($initial_file_list{'native_pdw'},$initial_file_list{'native_t2w'});
  
  do_cmd('cp',$initial_file_list{'t2t1'},$initial_file_list{"relx_t1_xfm_0"}) 
    unless -e $initial_file_list{"relx_t1_xfm_0"};
    
  do_cmd('cp',$initial_file_list{'t2t1'},$initial_file_list{"relx_t1_xfm_1"}) 
    unless -e $initial_file_list{"relx_t1_xfm_1"};
  
  push @relx_mri,@more_t2;
  # resample the relaxometry data into stereotaxic space
  my @stx_relx_mri;
  my @nl_relx_mri;
  my $r;
  
  for $r(0.. $#relx_mri)
  {
    do_cmd('mritoself','-lsq6','-mi','-close','-nothreshold',
           $relx_mri[$r], $initial_file_list{'native_t1w'}, $initial_file_list{"relx_t1_xfm_$r"}) 
           unless -e $initial_file_list{"relx_t1_xfm_$r"};
           
    if( ! -e $initial_file_list{"relx_stx_t2"} || ! -e $initial_file_list{"relx_nl_t2"})
    {
           
     delete $ENV{'MINC_COMPRESS'} if $minc_compress;
    
     do_cmd('xfmconcat',$initial_file_list{"relx_t1_xfm_$r"},
           $initial_file_list{'stx2_xfm_t1w'},
           $initial_file_list{"relx_stx_xfm_$r"}) 
           unless -e $initial_file_list{"relx_stx_xfm_$r"};
           
     $ENV{'MINC_COMPRESS'}=$minc_compress if $minc_compress;
    
     do_cmd('itk_resample',$relx_mri[$r],
      '--like',$model_t1w,
      '--transform',
      $initial_file_list{"relx_stx_xfm_$r"},$initial_file_list{"relx_stx_mri_$r"},
      '--order',4)
      unless -e $initial_file_list{"relx_stx_mri_$r"};
    }       
    push @stx_relx_mri,$initial_file_list{"relx_stx_mri_$r"};
    
    if($nonlinear && !-e $initial_file_list{"relx_nl_t2"})
    {
      delete $ENV{'MINC_COMPRESS'} if $minc_compress;
      
      do_cmd('xfmconcat',$initial_file_list{"relx_t1_xfm_$r"},
             $initial_file_list{'stx2_xfm_t1w'},$initial_file_list{'nl_final_xfm'},
             $initial_file_list{"relx_nl_xfm_$r"}) 
         unless -e $initial_file_list{"relx_nl_xfm_$r"};
						
      $ENV{'MINC_COMPRESS'}=$minc_compress if $minc_compress;
	
      do_cmd('itk_resample',$relx_mri[$r],
        '--like',$model_t1w,
        '--transform',$initial_file_list{"relx_nl_xfm_$r"},
        $initial_file_list{"relx_nl_mri_$r"},
        '--order',4)
        unless -e $initial_file_list{"relx_nl_mri_$r"};
						
						
      push @nl_relx_mri,$initial_file_list{"relx_nl_mri_$r"};
    }
  }

  do_cmd('pipeline_relx.pl',@stx_relx_mri,$initial_file_list{"relx_stx_t2"},'--mask',$initial_file_list{'stx_msk'}) 
          unless -e $initial_file_list{"relx_stx_t2"};

  create_header_info_for_many_parented($initial_file_list{'relx_stx_t2'}, $initial_file_list{'stx2_t2w'});
  

  $file_id{$initial_file_list{'relx_stx_t2'}}=
     register_in_db($initial_file_list{'relx_stx_t2'},
                    'stx_t2','t2','linear','',$file_id{$initial_file_list{'stx2_t2w'}}) if $nihpd_secret;

  if($nonlinear)
  {
    do_cmd('pipeline_relx_cls.pl',
           $initial_file_list{'stx2_t1w'},
           $initial_file_list{'stx2_t2w'},
           $initial_file_list{'stx2_pdw'},
           $initial_file_list{"relx_stx_t2"},
           $initial_file_list{"stx_cls"},
           '--mask',$initial_file_list{'stx_msk'},
           '--xfm',$initial_file_list{'nl_final_xfm'},
           '--atlas',$model_atlas,
           '--atlas_gm',$model_atlas_gm,
           '--atlas_wm',$model_atlas_wm,
           '--atlas_csf',$model_atlas_csf)
      unless -e $initial_file_list{"stx_cls"};

#  create_header_info_for_many_parented($initial_file_list{'stx_cls'}, $initial_file_list{'stx2_t1w'});

#  $file_id{$initial_file_list{'stx_cls'}}=
#     register_in_db($initial_file_list{'stx_cls'},
#        'stx_cls','','linear','',$file_id{$initial_file_list{'relx_stx_t2'}});
        
    

  do_cmd('minclookup','-lut_string','0 0;1 1;2 1;3 2;4 3;5 3','-discrete', '-byte',
       $initial_file_list{'stx_cls'},$initial_file_list{'stx_cls_std'})
     unless -e $initial_file_list{'stx_cls_std'} ;
     
  create_header_info_for_many_parented($initial_file_list{'stx_cls_std'}, $initial_file_list{'stx2_t1w'});

  $file_id{$initial_file_list{'stx_cls_std'}}=
     register_in_db($initial_file_list{'stx_cls_std'},
                    'stx_cls','','linear','em',$file_id{$initial_file_list{'stx2_t1w'}}) if $nihpd_secret;

  do_cmd('param2xfm',"$tmpdir/identity.xfm") unless -e "$tmpdir/identity.xfm";
  
  do_cmd('lobe_segment', $initial_file_list{'nl_final_xfm'},"$tmpdir/identity.xfm",
         $initial_file_list{"stx_cls_std"},$initial_file_list{"stx_lob"},
         '-modeldir',$lobe_atlas,'-template',$model_t1w) 
   unless -e $initial_file_list{"stx_lob"};

  create_header_info_for_many_parented($initial_file_list{'stx_lob'}, $initial_file_list{'stx2_t1w'});

  $file_id{$initial_file_list{'stx_lob'}}=
     register_in_db($initial_file_list{'stx_lob'},
                    'stx_lob','','linear','em',$file_id{$initial_file_list{'stx2_t1w'}}) if $nihpd_secret;

  do_cmd('pipeline_volumes_original2.pl',
      $initial_file_list{'stx_msk'},
      $initial_file_list{"stx_cls_std"},
      $initial_file_list{"stx_lob"},
      $initial_file_list{'stx2_xfm_t1w'},
      '--age',$age,
      '--t1', $initial_file_list{"native_t1w"},
      '--t2', $initial_file_list{"native_t2w"},
      $initial_file_list{"vol"})
      unless -e $initial_file_list{"vol"};

  print "\n\n\n\nLobe segment\n\n";

  $file_id{$initial_file_list{'vol'}}=
     register_in_db($initial_file_list{'vol'},
                    'nl_volumes','','linear','em',$file_id{$initial_file_list{'native_t1w'}});
  
  #register volumes in database
  
  put_selected_volumes_in_db($initial_file_list{'vol'},$file_id{$initial_file_list{'vol'}}) if $nihpd ; 
  print "\n\n\n\ndone\n\n";
  
     
  do_cmd('minc_qc.pl',$initial_file_list{'stx2_t1w'},$initial_file_list{'qc_cls'},
      '--mask',$initial_file_list{'stx_cls_std'},'--title',"${candid}_${visitno}",
      '--image-range',0,100,'--spectral-mask','--mask-range', 0, 3.5 ) 
  unless -e $initial_file_list{'qc_cls'};
     
      
  do_cmd('mincresample',$initial_file_list{'stx_msk'},
        '-like',$model_t1w,
        '-transform',$initial_file_list{'nl_final_xfm'},
        $initial_file_list{"relx_nl_msk"},'-nearest')
      unless -e $initial_file_list{"relx_nl_msk"};
      
  do_cmd('pipeline_relx.pl',@nl_relx_mri,$initial_file_list{"relx_nl_t2"},'--mask',$initial_file_list{"relx_nl_msk"}) 
        unless -e $initial_file_list{"relx_nl_t2"};
  
  do_cmd('minc_qc.pl', $initial_file_list{"relx_nl_t2"}, $initial_file_list{"qc_nl_t2"},'--spectral','--image-range',0,0.3)
       unless -e $initial_file_list{"qc_nl_t2"};

  create_header_info_for_many_parented($initial_file_list{'relx_nl_t2'}, $initial_file_list{'stx2_t2w'});


  $file_id{$initial_file_list{'relx_nl_t2'}}=
      register_in_db($initial_file_list{'relx_nl_t2'},
                    'nlr_t2','t2','nonlinear','',$file_id{$initial_file_list{'stx2_t2w'}}) if $nihpd_secret;  
  }
}

if($nihpd) #register additional files from CIVET
{
  my $i;
  foreach $i(keys(%initial_file_list)) 
  {
    next unless $i=~/^civet/;

    next unless -e $initial_file_list{$i};

    $file_id{$initial_file_list{$i}}= register_in_db($initial_file_list{$i},
                      $i,'','linear','clean',$file_id{$initial_file_list{'native_t1w'}});
  }

  put_gi_index_in_db($initial_file_list{'civet_gyrification_index_left'},'left',$file_id{$initial_file_list{'civet_gyrification_index_left'}}) if -e $initial_file_list{'civet_gyrification_index_left'};
  put_gi_index_in_db($initial_file_list{'civet_gyrification_index_right'},'right',$file_id{$initial_file_list{'civet_gyrification_index_right'}}) if -e $initial_file_list{'civet_gyrification_index_right'};
  
}

if($deface && $nonlinear)
{
	print "Performing defacing...\n";
# deface
  do_cmd('deface_volume.pl',$initial_file_list{'native_t1w'},
         '--face',$initial_file_list{'stx_face'},
         '--brain',$initial_file_list{'stx_msk'},
         '--tal_xfm',$initial_file_list{'stx2_xfm_t1w'},
         $initial_file_list{'deface_t1w'},
         '--save_grid',$initial_file_list{'deface_grid'},
         '--edge_smooth',2) 
       unless -e $initial_file_list{'deface_t1w'} && -e $initial_file_list{'deface_grid'};
  create_header_info_for_many_parented($initial_file_list{'deface_grid'}, $initial_file_list{'stx2_t1w'});
  
  $file_id{$initial_file_list{'deface_grid'}}=register_in_db($initial_file_list{'deface_grid'},'deface_grid','','linear','',$file_id{$initial_file_list{'stx2_t1w'}});

  $file_id{$initial_file_list{'deface_t1w'}}=register_in_db($initial_file_list{'deface_t1w'},'deface_t1w','t1w','native','',$file_id{$initial_file_list{'native_t1w'}});  

  do_cmd('deface_volume.pl',$initial_file_list{'native_t2w'},'--face',$initial_file_list{'stx_face'},'--brain',$initial_file_list{'stx_msk'},
       '--tal_xfm',$initial_file_list{'stx2_xfm_t2w'},$initial_file_list{'deface_t2w'},'--tal_grid',$initial_file_list{'deface_grid'},
       '--edge_smooth',2) 
       unless -e $initial_file_list{'deface_t2w'};
  $file_id{$initial_file_list{'deface_t2w'}}=register_in_db($initial_file_list{'deface_t2w'},'deface_t2w','t2w','native','',$file_id{$initial_file_list{'native_t2w'}});  

  do_cmd('deface_volume.pl',$initial_file_list{'native_pdw'},'--face',$initial_file_list{'stx_face'},'--brain',$initial_file_list{'stx_msk'},
       '--tal_xfm',$initial_file_list{'stx2_xfm_t2w'},$initial_file_list{'deface_pdw'},'--tal_grid',$initial_file_list{'deface_grid'},
       '--edge_smooth',2) 
       unless -e $initial_file_list{'deface_pdw'};
       
  $file_id{$initial_file_list{'deface_pdw'}}=register_in_db($initial_file_list{'deface_pdw'},'deface_pdw','pdw','native','',$file_id{$initial_file_list{'native_pdw'}});  

  do_cmd('pipeline_qc_face.pl',$initial_file_list{'deface_t1w'},$candid,$visitno,0,
        $initial_file_list{'qc_deface_render'},'--stx',$initial_file_list{'stx2_xfm_t1w'})
        unless -e $initial_file_list{'qc_deface_render'};
  $file_id{$initial_file_list{'qc_deface_render'}}=register_in_db($initial_file_list{'qc_deface_render'},'qc_deface','','linear','',$file_id{$initial_file_list{'deface_t1w'}});

  my $r;
  for $r(0..$#more_t2)
  {
    my $i=$r+2;
    do_cmd('deface_volume.pl',$more_t2[$r],'--face',$initial_file_list{'stx_face'},'--brain',$initial_file_list{'stx_msk'},
       '--tal_xfm',$initial_file_list{"relx_stx_xfm_$i"},$initial_file_list{"deface_t2relx_$r"},
       '--tal_grid',$initial_file_list{'deface_grid'},'--edge_smooth',2) 
       unless -e $initial_file_list{"deface_t2relx_$r"};
    $file_id{$initial_file_list{"deface_t2relx_$r"}}=register_in_db($initial_file_list{"deface_t2relx_$r"},"deface_t2relx_$r",'t2w','native','',$file_id{$more_t2[$r]});  
 }
 #deface stx
 if(!$nihpd_secret)
 {
  do_cmd('deface_volume.pl',$initial_file_list{'native_t2w'},'--face',$initial_file_list{'stx_face'},'--brain',$initial_file_list{'stx_msk'},
       '--tal_xfm',$initial_file_list{'stx2_xfm_t2w'},$initial_file_list{'deface_t2w'},'--tal_grid',$initial_file_list{'deface_grid'},
       '--edge_smooth',2) 
       unless -e $initial_file_list{'deface_t2w'};
  $file_id{$initial_file_list{'deface_t2w'}}=register_in_db($initial_file_list{'deface_t2w'},'deface_t2w','t2w','native','',$file_id{$initial_file_list{'native_t2w'}});  

  do_cmd('deface_volume.pl',$initial_file_list{'native_pdw'},'--face',$initial_file_list{'stx_face'},'--brain',$initial_file_list{'stx_msk'},
       '--tal_xfm',$initial_file_list{'stx2_xfm_t2w'},$initial_file_list{'deface_pdw'},'--tal_grid',$initial_file_list{'deface_grid'},
       '--edge_smooth',2) 
       unless -e $initial_file_list{'deface_pdw'};
       
  $file_id{$initial_file_list{'deface_pdw'}}=register_in_db($initial_file_list{'deface_pdw'},'deface_pdw','pdw','native','',$file_id{$initial_file_list{'native_pdw'}});  

  do_cmd('pipeline_qc_face.pl',$initial_file_list{'deface_t1w'},$candid,$visitno,0,
        $initial_file_list{'qc_deface_render'},'--stx',$initial_file_list{'stx2_xfm_t1w'})
        unless -e $initial_file_list{'qc_deface_render'};
  $file_id{$initial_file_list{'qc_deface_render'}}=register_in_db($initial_file_list{'qc_deface_render'},'qc_deface','','linear','',$file_id{$initial_file_list{'deface_t1w'}});

  do_cmd('param2xfm',"$tmpdir/identity.xfm") unless -e "$tmpdir/identity.xfm";

  do_cmd('deface_volume.pl',
         '--face',$initial_file_list{'stx_face'},
         '--brain',$initial_file_list{'stx_msk'},
         '--tal_xfm',"$tmpdir/identity.xfm",
         '--tal_grid',$initial_file_list{'deface_grid'},
         $initial_file_list{'stx2_t1w'},
         $initial_file_list{'deface_stx_t1w'}, 
       '--edge_smooth',2) 
       unless -e $initial_file_list{'deface_stx_t1w'};

  $file_id{$initial_file_list{'deface_stx_t1w'}}=register_in_db($initial_file_list{'deface_stx_t1w'},'tal_mnc','t1w','linear','',$file_id{$initial_file_list{'native_t1w'}}) if !$nihpd_secret;

  if($have_t2)
  {
    do_cmd('deface_volume.pl',
          '--face',$initial_file_list{'stx_face'},
          '--brain',$initial_file_list{'stx_msk'},
          '--tal_xfm',"$tmpdir/identity.xfm",
          '--tal_grid',$initial_file_list{'deface_grid'},
          $initial_file_list{'stx2_t2w'},
          $initial_file_list{'deface_stx_t2w'}, 
        '--edge_smooth',2) 
        unless -e $initial_file_list{'deface_stx_t2w'};
  
    $file_id{$initial_file_list{'deface_stx_t2w'}}=register_in_db($initial_file_list{'deface_stx_t2w'},'tal_mnc','t1w','linear','',$file_id{$initial_file_list{'native_t2w'}}) if !$nihpd_secret;
  }

  if($have_pd)
  {
    do_cmd('deface_volume.pl',
          '--face',$initial_file_list{'stx_face'},
          '--brain',$initial_file_list{'stx_msk'},
          '--tal_xfm',"$tmpdir/identity.xfm",
          '--tal_grid',$initial_file_list{'deface_grid'},
          $initial_file_list{'stx2_pdw'},
          $initial_file_list{'deface_stx_pdw'}, 
        '--edge_smooth',2) 
        unless -e $initial_file_list{'deface_stx_pdw'};
  
    $file_id{$initial_file_list{'deface_stx_pdw'}}=register_in_db($initial_file_list{'deface_stx_pdw'},'tal_mnc','t1w','linear','',$file_id{$initial_file_list{'native_pdw'}}) if !$nihpd_secret;
  }

  
 }
 
} #deface

sub do_cmd {
    print STDOUT "@_\n" if $verbose;
    if(!$fake) {
        system(@_) == 0 or die "DIED: ".join(',',@_)."\n";
    }
}

sub create_directories
{
  my ($base_name) = @_;

  my @dirnames = qw(clp stx nl deface qc relx up models vol lob);
  my $dirname;

  if(!-e $base_name) {` mkdir -p $base_name`;}
  foreach $dirname(@dirnames) {
    my $newdir = "${base_name}/${dirname}";
    if (!-e $newdir){`mkdir $newdir`;}
  }
  if($nihpd) {
    my $newdir = "${base_name}/civet";
    if (!-e $newdir){`mkdir -p $newdir`;}
  }
}

sub get_list_files_native_files
{
  my ($base_name, $candid, $visitno, $t1w, $t2w, $pdw) = @_;
 
  my %list_names = {};

  my @types = ('t1w','t2w','pdw');

  $list_names{'native_t1w'} = $t1w;
  $list_names{'native_t2w'} = $t2w;
  $list_names{'native_pdw'} = $pdw;

  $list_names{"model_t1w"}   = "$base_name/models/model_t1w.mnc";
  $list_names{"model_t2w"}   = "$base_name/models/model_t2w.mnc";
  $list_names{"model_pdw"}   = "$base_name/models/model_pdw.mnc";
  $list_names{"model_mask"}  = "$base_name/models/model_mask.mnc";
  $list_names{"model_mask_cb"}  = "$base_name/models/model_mask_cb.mnc";
  $list_names{"model_face"}  = "$base_name/models/model_face.mnc";
  $list_names{"model_total"} = "$base_name/models/model_total.xfm";
  #$list_names{"model_c1"} = "$base_name/models/model_c1.mnc";
   
  my $type;
  foreach $type(@types)
  {
    my ($native_current,$clp_current,$stx_current,$stx_xfm_current,$nl_current);
    $list_names{"up_$type"}  =      "$base_name/up/up_${candid}_${visitno}_${type}.mnc";
    $list_names{"clp_$type"} =      "$base_name/clp/clamp_${candid}_${visitno}_${type}.mnc";
    
    $list_names{"native_${type}_mask"} = "$base_name/clp/mask_${candid}_${visitno}_${type}.mnc";
    
    $list_names{"msk_$type"} =      "$base_name/clp/msk_${candid}_${visitno}_${type}.mnc";
    $list_names{"stx1_$type"} =     "$base_name/stx/stx_${candid}_${visitno}_${type}.mnc";
    $list_names{"stx1_xfm_$type"} = "$base_name/stx/stx_xfm_${candid}_${visitno}_${type}.xfm";
    $list_names{"nl1_$type"} =      "$base_name/nl/nl_${candid}_${visitno}_${type}.mnc";
    $list_names{"stx2_$type"} =     "$base_name/stx/stx2_${candid}_${visitno}_${type}.mnc";
    $list_names{"stx2_xfm_$type"} = "$base_name/stx/stx2_xfm_${candid}_${visitno}_${type}.xfm";
    $list_names{"nl2_$type"} =      "$base_name/nl/nl2_${candid}_${visitno}_${type}.mnc";
    $list_names{"deface_$type"} =   "$base_name/deface/deface_${candid}_${visitno}_${type}.mnc";
    $list_names{"deface_stx_$type"} = "$base_name/deface/deface_stx_${candid}_${visitno}_${type}.mnc";
  }

  $list_names{"stx2_c1"} =     "$base_name/stx/stx2_${candid}_${visitno}_c1.mnc";
  $list_names{"stx2_c1_"} =     "$base_name/stx/stx2_${candid}_${visitno}_c1_.mnc";
  
  $list_names{"deface_grid"}=   "$base_name/deface/deface_${candid}_${visitno}_grid.mnc";
  $list_names{'t2t1'} =     "$base_name/stx/t2t1_xfm_${candid}_${visitno}.xfm";
  $list_names{'nl1_grid'} =  "$base_name/nl/nl_xfm_${candid}_${visitno}_grid_0.mnc";
  $list_names{'nl1_xfm'} =   "$base_name/nl/nl_xfm_${candid}_${visitno}.xfm";
  $list_names{'nl_lin'} =   "$base_name/nl/nl_lin_${candid}_${visitno}.xfm";
  $list_names{'nl2_grid'} = "$base_name/nl/nl2_xfm_${candid}_${visitno}_grid_0.mnc";
  $list_names{'nl2_xfm'} =  "$base_name/nl/nl2_xfm_${candid}_${visitno}.xfm";
  $list_names{'nl3_grid'} = "$base_name/nl/nl3_xfm_${candid}_${visitno}_grid_0.mnc";
  $list_names{'nl3_xfm'} =  "$base_name/nl/nl3_xfm_${candid}_${visitno}.xfm";
  $list_names{'nl_final_xfm'} = "$base_name/nl/nl_final_xfm_${candid}_${visitno}.xfm";
  
  $list_names{'stx_msk_temp'} =   "$base_name/stx/stx_temp_${candid}_${visitno}.mnc";
  $list_names{'stx_msk'} =   "$base_name/stx/stx_msk_${candid}_${visitno}.mnc";
  $list_names{'stx_cls'} =   "$base_name/stx/stx_cls_${candid}_${visitno}.mnc";
  $list_names{'stx_cls_std'} =   "$base_name/stx/stx_scls_${candid}_${visitno}.mnc";
  $list_names{'stx_lob'} =   "$base_name/lob/lob_${candid}_${visitno}.mnc";


  $list_names{'stx_pve'} =   "$base_name/stx/stx_pve_${candid}_${visitno}";
  $list_names{'stx_pve_wm'} = $list_names{'stx_pve'}."_wm.mnc";
  $list_names{'stx_pve_gm'} = $list_names{'stx_pve'}."_gm.mnc";
  $list_names{'stx_pve_csf'} = $list_names{'stx_pve'}."_csf.mnc";
  
  $list_names{'stx_face'} =  "$base_name/stx/stx_face_${candid}_${visitno}.mnc";
#VOLUMES  
  $list_names{'vol'} =  "$base_name/vol/nl_${candid}_${visitno}.txt";
#QC  
  $list_names{'qc_stx'} =   "$base_name/qc/stx_${candid}_${visitno}.jpg";
  $list_names{'qc_cls'} =   "$base_name/qc/cls_${candid}_${visitno}.jpg";
  $list_names{'qc_t2t1'} =  "$base_name/qc/t2t1_${candid}_${visitno}.jpg";
  $list_names{'qc_nl_t2'} =  "$base_name/qc/nl_t2_${candid}_${visitno}.jpg";
  $list_names{'qc_brain'} = "$base_name/qc/mask_${candid}_${visitno}.jpg";
  $list_names{'qc_brain2'} = "$base_name/qc/cmask_${candid}_${visitno}.jpg";
  $list_names{'qc_face'} =  "$base_name/qc/face_${candid}_${visitno}.jpg";
  $list_names{'qc_face_render'} =  "$base_name/qc/render_face_${candid}_${visitno}.jpg";
  $list_names{'qc_deface_render'} =  "$base_name/qc/render_deface_${candid}_${visitno}.jpg";
  
  $list_names{"relx_stx_t2"}="$base_name/relx/stx_t2_${candid}_${visitno}.mnc";
  $list_names{"relx_nl_t2"}  ="$base_name/relx/nl_t2_${candid}_${visitno}.mnc";
  $list_names{"relx_nl_msk"}="$base_name/relx/nl_mask_${candid}_${visitno}.mnc";
  
  my $r;
  for $r(0.. 10)  {
    $list_names{"relx_stx_mri_$r"}="$tmpdir/stx_relx_${candid}_${visitno}_e$r.mnc";
    $list_names{"relx_t1_xfm_$r"} ="$base_name/relx/reg_t1_${candid}_${visitno}_e$r.xfm";
    $list_names{"relx_stx_xfm_$r"}="$tmpdir/stx_relx_${candid}_${visitno}_e$r.xfm";
    
    $list_names{"relx_nl_mri_$r"}="$tmpdir/nl_relx_${candid}_${visitno}_e$r.mnc";
    $list_names{"relx_nl_xfm_$r"}="$tmpdir/nl_relx_${candid}_${visitno}_e$r.xfm";
    
    $list_names{"deface_t2relx_$r"} =   "$base_name/deface/deface_t2relx_${candid}_${visitno}_${r}.mnc";
  }

  if($nihpd)
  {
    $list_names{"civet_gyrification_index_left"}="$base_name/civet/nihpd_${candid}_${visitno}_gi_left.dat";
    $list_names{"civet_gyrification_index_right"}="$base_name/civet/nihpd_${candid}_${visitno}_gi_right.dat";

    $list_names{"civet_outer_cortical_surface_left"}="$base_name/civet/nihpd_${candid}_${visitno}_gray_surface_rsl_left_81920.obj";
    $list_names{"civet_outer_cortical_surface_right"}="$base_name/civet/nihpd_${candid}_${visitno}_gray_surface_rsl_right_81920.obj";

    $list_names{"civet_inner_cortical_surface_left"}="$base_name/civet/nihpd_${candid}_${visitno}_white_surface_rsl_left_calibrated_81920.obj";
    $list_names{"civet_inner_cortical_surface_right"}="$base_name/civet/nihpd_${candid}_${visitno}_white_surface_rsl_right_calibrated_81920.obj";

    $list_names{"civet_mean_curvature_left"} ="$base_name/civet/nihpd_${candid}_${visitno}_native_mc_rsl_20mm_mid_left.txt";
    $list_names{"civet_mean_curvature_right"}="$base_name/civet/nihpd_${candid}_${visitno}_native_mc_rsl_20mm_mid_right.txt";

    $list_names{"civet_cortical_thickness_left"} ="$base_name/civet/nihpd_${candid}_${visitno}_native_rms_rsl_tlink_20mm_left.txt";
    $list_names{"civet_cortical_thickness_right"}="$base_name/civet/nihpd_${candid}_${visitno}_native_rms_rsl_tlink_20mm_right.txt";

    $list_names{"civet_stx_xfm"}="$base_name/civet/nihpd_${candid}_${visitno}_t1_tal.xfm";
  }
  return %list_names;
}

## register file in database
# register_in_db(filename,outputtype,protocol,coord space,classify,sourceId) will return an ID
sub register_in_db
{
  return 0 unless $dbh;
  my ($file,$output_type,$protocol,$coordinate_space,$classify_algorithm,$source)=@_;
  $file=`realpath $file`; chomp($file);
  my $id=get_file_id($file);
  #print "ID:$id\n";

  if($id)
  {
    print "Found $file in the Database ID: $id\n";
    return $id;
  } else {
    
    my @insert_args = ('register_minc_db',$file,$output_type, '-pipeline', 'v1.4' );

    if($protocol)          { push(@insert_args, '-protocol', $protocol); }
    if($coordinate_space)  { push(@insert_args, '-coordspace', $coordinate_space); }
    if($classify_algorithm){ push(@insert_args, '-classifyalg', $classify_algorithm); }
    if($source)            { push(@insert_args, '-source', $source); }

    push @insert_args,'-user',"'$nihpd_user'",'-passwd',"'$nihpd_passwd'";

    my $line = join(" ",  @insert_args);
    #print("\n\ninsert_line:$line\n\n");
    my $dbresults;
    $dbresults = `$line`;
    print "DBResults: ", $dbresults;
    my ($d,$newfileID) = split("Registered with FileID: ", $dbresults);
    chomp($newfileID);
    return $newfileID;
  }
}

sub get_file_id
{
  return 0 unless $dbh;
  my $in=$_[0];
  print "file:$in\n";
  my $file = NeuroDB::File->new(\$dbh);
  return  $file->findFile($in);
}

# Based on create_header_info_for_many_parentedKitching.
# Some scripts don't copy header info from source to target so 
# copy the header info necessary for the mnc to be inserted into the database - Larry
sub create_header_info_for_many_parented
{
  my ($child_mnc_file, $parent_mnc_file) = @_;

  my @patient = `mincheader $parent_mnc_file | grep patient:`;
  my $line;
  foreach $line(@patient)
  {
    chomp($line);
    $line =~ s/ //g;
    do_cmd("minc_modify_header $child_mnc_file -sinsert $line");
  }
  
  my @dicom_tags = qw(dicom_0x0010:el_0x0010 dicom_0x0008:el_0x0020 dicom_0x0008:el_0x0070 dicom_0x0008:el_0x1090 dicom_0x0018:el_0x1000 dicom_0x0018:el_0x1020 dicom_0x0008:el_0x103e);

  my $tag;

  foreach $tag(@dicom_tags) {
    my @dicom_field = `mincheader $parent_mnc_file | grep $tag`;
    foreach $line(@dicom_field)
    {
      chomp($line);
      $line =~ s/ //g;
      do_cmd("minc_modify_header $child_mnc_file -sinsert $line");
    }
  }
}

sub put_all_volumes_in_db
{
  my ($input_volumes,$volFileId)=@_;
  ##########################
  # Get the fileID's
  if (! $volFileId ) { warn "Cannot find $input_volumes in database\n"; return; }
  
  my $volDbFile = NeuroDB::File->new(\$dbh);
  print "$input_volumes - $volFileId\n";
  $volDbFile->loadFile($volFileId);
  
  if(!open (IN_VOLUMES, "<${input_volumes}")) {warn "Cannot open $input_volumes input file: $!" ; return;}
  my $line;
  
  foreach $line(<IN_VOLUMES>)
  {
    chomp $line;
    my ($id,$val)=split (/\s/,$line);
    print $id,"->",$val,"\n";
    #add information into DB
    $volDbFile->setParameter($id,$val); 
  }
  close(IN_VOLUMES);
}


sub put_selected_volumes_in_db
{
  my ($input_volumes,$volFileId)=@_;
  ##########################
  # Get the fileID's
  if (! $volFileId ) { warn "Cannot find $input_volumes in database\n"; return; }
  
  my $volDbFile = NeuroDB::File->new(\$dbh);
  print "$input_volumes - $volFileId\n";
  $volDbFile->loadFile($volFileId);
  
  if(!open (IN_VOLUMES, "<${input_volumes}")) {warn "Cannot open $input_volumes input file: $!" ; return;}
  my $line;
  my %in_values;
  my $i;

  foreach $line(<IN_VOLUMES>)
  {
    chomp $line;
    my ($id,$val)=split (/\s/,$line);
    $in_values{$id}=$val;
  }
  #remap values
  my @keys = qw(CSF_vol ScaleFactor lateral_ventricle_left lateral_ventricle_right cerebellum_left cerebellum_right);
  foreach $i(@keys){    
    $volDbFile->setParameter($i,$in_values{$i}); 
    print "$i => $in_values{$i}\n";
  }
  my @lobes= qw(frontal_left frontal_right occipital_left occipital_right parietal_left parietal_right temporal_left temporal_right );

  $volDbFile->setParameter('Parenchyma_vol',$in_values{'GM_vol'}+$in_values{'WM_vol'}); 
  print "Parenchyma_vol => ",$in_values{'GM_vol'}+$in_values{'WM_vol'},"\n";

  foreach $i(@lobes){
    $volDbFile->setParameter($i,$in_values{"${i}_gm"}+$in_values{"${i}_wm"}); 
    print "$i => ",$in_values{"${i}_gm"}+$in_values{"${i}_wm"},"\n";
  }
  close(IN_VOLUMES);
}


sub put_gi_index_in_db
{
  my ($input,$side,$volFileId)=@_;
  ##########################
  # Get the fileID's
  if (! $volFileId ) { warn "Cannot find $input in database\n"; return; }
  
  my $volDbFile = NeuroDB::File->new(\$dbh);
  print "$input - $volFileId\n";
  $volDbFile->loadFile($volFileId);
  
  if(!open (IN_VOLUMES, "<${input}")) {warn "Cannot open $input input file: $!" ; return;}
  my $line;
  my $i;

  foreach $line(<IN_VOLUMES>)
  {
    chomp $line;
    my ($id,$val)=split (':',$line);
    
    $id=~s/\s+/_/g;
    $id="${id}_${side}";
    print "$id => $val\n";
    $volDbFile->setParameter($id,$val); 
  }
  close(IN_VOLUMES);
}
