#!/usr/bin/env perl
use strict;
use Getopt::Long;
use File::Basename;
use File::Temp qw/ tempdir /;

my $verbose = 0;
my $fake    = 0;
my $clobber = 0;
my $me = basename ($0);
my $level=2;
my $file_prefix='.';
my $model_dir;
my $model;
my @ages;
my $sages;
my $gender='na';
my $nonlinear;
my $pca;
#my $jacobian_step=2;

GetOptions(
	   'verbose'           => \$verbose,
	   'clobber'           => \$clobber,
	   'prefix=s'          => \$file_prefix,
	   'model_dir=s'       => \$model_dir,
	   'model=s'           => \$model,
	   'ages=s'            => \$sages,
	   'gender=s'          => \$gender,
	   'nonlinear'         => \$nonlinear,
	   'pca=s'             => \$pca,
	   );

my $Help = <<HELP;
  Usage: $me <candID> <visit1> [visit2] [visit3]
    --verbose be verbose
    --clobber clobber _all_ output files
    --prefix <dir> output directory prefix  ,all data will be in <prefix>/<subject_id>/<visit_label>
    --model_dir <dir> use this modeldir
    --model <model base> use this model
    --ages <age1>,<age2>....
    --pca <training> use PCA registration (training is expected to be in stereotaxic space
    --gender <male|female>
  Problems or comments should be sent to: vfonov\@bic.mni.mcgill.ca
HELP

die $Help if $#ARGV < 1;

my $candid=shift @ARGV;

my @visits=@ARGV;

@ages=split(/,/,$sages) if $sages;

my $tmpdir = &tempdir( "$me-XXXXXXXX", TMPDIR => 1, CLEANUP => 1 );

die "Specify --prefix \n" unless $file_prefix;

my $base_dir = "${file_prefix}/${candid}" ;

my $model_fn="$model_dir/${model}.mnc";
my $model_mask_fn="$model_dir/${model}_mask.mnc";

#my $model_fn_lr="$model_dir/${model}_8_blur.mnc";
my $model_mask_lr="$tmpdir/${model}_mask_lr.mnc";

my @masks;
my @scans;
my @nl_xfms;
my @lin_xfms;
#will register to the latest visit
my $visit;
my $compress=$ENV{MINC_COMPRESS};

foreach $visit(@visits) {
  my $scan="$base_dir/$visit/clp/clamp_${candid}_${visit}_t1w.mnc";
  $scan=$scan.'.gz' if -e $scan.'.gz';
  my $mask="$base_dir/$visit/tal/tal_comp_msk_${candid}_${visit}.mnc";
  $mask=$mask.'.gz' if -e $mask.'.gz';
  my $lin_xfm="$base_dir/$visit/tal/tal_xfm_${candid}_${visit}_t1w.xfm";
  my $nl_xfm="$base_dir/$visit/nl/nl_xfm_${candid}_${visit}.xfm";
  print "Looking for:\n\t$mask\n\t$scan\n\t$lin_xfm\n" if $verbose;
  warn "$mask is missing\n" unless -e $mask;
  warn "$scan is missing\n" unless -e $scan;
  warn "$lin_xfm is missing\n" unless -e  $lin_xfm;
  warn "$nl_xfm is missing\n" unless -e $nl_xfm;
  if( -e $mask && -e $scan  && -e $lin_xfm && -e $nl_xfm)
  {
    push @masks,$mask;
    push @scans,$scan;
    push @nl_xfms,$nl_xfm;
    push @lin_xfms,$lin_xfm;
  } else {
    warn "No valid data for visit $visit\n";
  }
}
die "not enough valid visits found!\n" if $#scans<1;

print "Ages:".join(',',@ages)."\n";
print "Scans:".join(',',@scans)."\n";

# calculate nonlinear fit to the latest visit
my $i;
my $outdir="$base_dir/analysis";
do_cmd('mkdir','-p',$outdir);

do_cmd('mincmath','-or',@masks,"$outdir/stx_mask.mnc") unless -e "$outdir/stx_mask.mnc";

open OUT,">$outdir/stat.txt" || die "Can't open file $outdir/stat.txt\n";
#print OUT "VISIT,AGE1,AGE2,DIFF,PBVC\n";

for($i=0;$i<=$#scans-1;$i++)
{
  my $src=$i;
  my $trg=$i+1;
  my @step1=split(/\n/,`mincinfo -attvalue xspace:step -attvalue yspace:step -attvalue zspace:step $scans[$src]`);
  my @step2=split(/\n/,`mincinfo -attvalue xspace:step -attvalue yspace:step -attvalue zspace:step $scans[$trg]`);
  my $vx1=abs(1.0*$step1[0]*$step1[1]*$step1[2]);
  my $vx2=abs(1.0*$step2[0]*$step2[1]*$step2[2]);
  # todo: maybe refuse calculations if steps are too different ?
  
  # calculate the positions of the centers of heads
  do_cmd('xfminvert',$lin_xfms[$src],"$tmpdir/inv_src.xfm",'-clobber');
  do_cmd('xfminvert',$lin_xfms[$trg],"$tmpdir/inv_trg.xfm",'-clobber');
  my @tr1=split(/\s+/,`xfm2param $tmpdir/inv_src.xfm|fgrep translation|cut -c 14-`);
  my @tr2=split(/\s+/,`xfm2param $tmpdir/inv_trg.xfm|fgrep translation|cut -c 14-`);

  # 1. produce native space ICC mask
  do_cmd('mincresample', "$outdir/stx_mask.mnc", "$outdir/mask_$visits[$src].mnc",
         '-like',$scans[$src], '-transform',$lin_xfms[$src],'-invert_transformation','-nearest')
         unless -e "$outdir/mask_$visits[$src].mnc";
         
  do_cmd('mincresample', "$outdir/stx_mask.mnc", "$outdir/mask_$visits[$trg].mnc",
         '-like',$scans[$trg], '-transform',$lin_xfms[$trg],'-invert_transformation','-nearest')
         unless -e "$outdir/mask_$visits[$trg].mnc";
  
  # 2. calculate forward and backward linear rigid registration
  unless( -e "$outdir/fw_$visits[$src].xfm")
  {
    #coregister
    do_cmd('bestlinreg.pl',$scans[$src],$scans[$trg], 
          "$tmpdir/fw_$visits[$src].xfm",
          '-source_mask',"$outdir/mask_$visits[$src].mnc",
          '-target_mask',"$outdir/mask_$visits[$trg].mnc",
          '-lsq6');
          
    do_cmd('bestlinreg.pl',$scans[$trg],$scans[$src], 
          "$tmpdir/bw_$visits[$src].xfm",
          '-source_mask',"$outdir/mask_$visits[$trg].mnc",
          '-target_mask',"$outdir/mask_$visits[$src].mnc",
          '-lsq6');
          
    do_cmd('xfminvert',"$tmpdir/bw_$visits[$src].xfm","$tmpdir/inv_bw_$visits[$src].xfm");
    do_cmd('xfminvert',"$tmpdir/fw_$visits[$src].xfm","$tmpdir/inv_fw_$visits[$src].xfm");
    do_cmd('param2xfm',"$tmpdir/identity.xfm") unless -e "$tmpdir/identity.xfm";
    
    do_cmd('xfmavg',"$tmpdir/fw_$visits[$src].xfm",
           "$tmpdir/inv_bw_$visits[$src].xfm","$tmpdir/identity.xfm","$tmpdir/identity.xfm",
           "$outdir/fw_$visits[$src].xfm");
           
    do_cmd('xfmavg',"$tmpdir/bw_$visits[$src].xfm",
           "$tmpdir/inv_fw_$visits[$src].xfm","$tmpdir/identity.xfm","$tmpdir/identity.xfm",
           "$outdir/bw_$visits[$src].xfm");
  }
  
  # need to make 1x1x1 with no direction cosines - for minctracc
  unless( -e "$outdir/$visits[$src]_$visits[$trg].mnc") {
    do_cmd('uniformize_minc.pl','--transform',"$outdir/fw_$visits[$src].xfm",
           $scans[$src],"$outdir/$visits[$src]_$visits[$trg].mnc",
           '--resample','sinc');
  }
  unless( -e "$outdir/$visits[$trg]_$visits[$src].mnc" ) {           
    do_cmd('mincresample','-like',"$outdir/$visits[$src]_$visits[$trg].mnc",
           '-transform',"$outdir/bw_$visits[$src].xfm",
           $scans[$trg],"$outdir/$visits[$trg]_$visits[$src].mnc",'-sinc');
  }
    
  # 3. calcualate nonlinear registration
  unless( -e "$outdir/$visits[$src].xfm")
  {
           
    do_cmd('mincresample','-like',"$outdir/$visits[$src]_$visits[$trg].mnc",
           '-transform',"$outdir/fw_$visits[$src].xfm",
           '-nearest',
           "$outdir/mask_$visits[$src].mnc",
           "$tmpdir/mask_$visits[$src].mnc");
           
    do_cmd('nlfit_s','-level',$level,
         '-source_mask',"$tmpdir/mask_$visits[$src].mnc",
         '-target_mask',"$tmpdir/mask_$visits[$src].mnc",
         "$outdir/$visits[$src]_$visits[$trg].mnc",
         "$outdir/$visits[$trg]_$visits[$src].mnc", 
         "$outdir/$visits[$src].xfm");
  }
  
  
  # 4. calculate mapping from half space back to stereotaxic space 
  unless(-e "$outdir/stx_$visits[$src].xfm")
  {
    do_cmd('xfminvert','-clobber',"$outdir/fw_$visits[$src].xfm",
           "$tmpdir/inv_fw_$visits[$src].xfm");
    do_cmd('xfmconcat',"$tmpdir/inv_fw_$visits[$src].xfm",
           $lin_xfms[$src],"$outdir/stx_$visits[$src].xfm");
  }
  
  # 4.5 do a PCA based registration
  if( $pca && (! -e "$outdir/pca_$visits[$src].xfm"))
  {
    do_cmd('mincresample','-like',"$outdir/$visits[$src]_$visits[$trg].mnc",
           '-transform',"$outdir/fw_$visits[$src].xfm",
           '-nearest',
           "$outdir/mask_$visits[$src].mnc",
           "$tmpdir/mask_$visits[$src].mnc") unless -e "$tmpdir/mask_$visits[$src].mnc";
           
    do_cmd('xfminvert',"$outdir/stx_$visits[$src].xfm",
                       "$tmpdir/inv_stx_$visits[$src].xfm");

    #TODO: should I use intensity based nonlinear registration to initialize PCA reg?           
    do_cmd('pca_reg.pl',
         '--source-mask',"$tmpdir/mask_$visits[$src].mnc",
         '--target-mask',"$tmpdir/mask_$visits[$src].mnc",
         "$outdir/$visits[$src]_$visits[$trg].mnc",
         "$outdir/$visits[$trg]_$visits[$src].mnc", 
         "$outdir/pca_$visits[$src].xfm",
         '--apply',"$tmpdir/inv_stx_$visits[$src].xfm",
         '--step',4,'--train',$pca,'--fast');
  }
  

  # 5. calculate whole nonlinear mapping to stereotaxic space
  unless(-e "$outdir/nl_stx_$visits[$src].xfm")
  {
    delete $ENV{MINC_COMPRESS} if $compress;
    do_cmd('xfmconcat',"$outdir/stx_$visits[$src].xfm",$nl_xfms[$src],"$outdir/nl_stx_$visits[$src].xfm");
    $ENV{MINC_COMPRESS}=$compress if $compress;
  }

  # 6. caculate jacobian in native space
  do_cmd('mincblob', '-determinant', 
    "$outdir/$visits[$src]_grid_0.mnc", 
    "$outdir/j_$visits[$src].mnc")
   unless -e "$outdir/j_$visits[$src].mnc";
  
  # 7. resample jacobian into nonlinear stereotaxic space
  #do_cmd('mincresample',"$outdir/j_$visits[$src].mnc",
  #         "$outdir/stx_j_$visits[$src].mnc",
  #         '-like',$model_fn_lr,'-transform',"$outdir/nl_stx_$visits[$src].xfm") 
           
  do_cmd('itk_resample',"$outdir/j_$visits[$src].mnc",
           "$outdir/stx_j_$visits[$src].mnc",
           '--like',$model_fn,
           '--transform',"$outdir/nl_stx_$visits[$src].xfm",
           '--uniformize',$level)
  unless -e "$outdir/stx_j_$visits[$src].mnc";
  
  # 8. resample mask to match sampling of the jacobian
  unless( -e "$outdir/j_mask_$visits[$src].mnc")
  {
    
    do_cmd('mincresample','-like',"$outdir/$visits[$src]_$visits[$trg].mnc",
             '-transform',"$outdir/fw_$visits[$src].xfm",
             '-nearest', "$outdir/mask_$visits[$src].mnc","$tmpdir/mask_$visits[$src].mnc") 
     unless( -e "$tmpdir/mask_$visits[$src].mnc" );
              
    do_cmd('mincresample','-nearest','-like',"$outdir/j_$visits[$src].mnc","$tmpdir/mask_$visits[$src].mnc",
         "$outdir/j_mask_$visits[$src].mnc");
  }
  
  # 8.5 do the same for PCA based registration
  if( $pca )
  {
    do_cmd('mincblob', '-determinant', 
      "$outdir/pca_$visits[$src]_grid_0.mnc", 
      "$outdir/pca_j_$visits[$src].mnc")
  
    unless -e "$outdir/pca_j_$visits[$src].mnc";

    #do_cmd('mincresample',"$outdir/pca_j_$visits[$src].mnc",
    #       "$outdir/stx_pca_j_$visits[$src].mnc",
    #       '-like',$model_fn_lr,'-transform',"$outdir/nl_stx_$visits[$src].xfm") 
    #       unless -e "$outdir/stx_pca_j_$visits[$src].mnc";
    do_cmd('itk_resample',"$outdir/pca_j_$visits[$src].mnc",
           "$outdir/stx_pca_j_$visits[$src].mnc",
           '--like',$model_fn,
           '--transform',"$outdir/nl_stx_$visits[$src].xfm",'--uniformize',$level) 
           unless -e "$outdir/stx_pca_j_$visits[$src].mnc";
           
   unless( -e "$outdir/pca_j_mask_$visits[$src].mnc")
   {
    
     do_cmd('mincresample','-like',"$outdir/$visits[$src]_$visits[$trg].mnc",
             '-transform',"$outdir/fw_$visits[$src].xfm",
             '-nearest', "$outdir/mask_$visits[$src].mnc","$tmpdir/mask_$visits[$src].mnc") 
     unless( -e "$tmpdir/mask_$visits[$src].mnc" );
              
     do_cmd('mincresample','-nearest','-like',"$outdir/pca_j_$visits[$src].mnc","$tmpdir/mask_$visits[$src].mnc",
         "$outdir/pca_j_mask_$visits[$src].mnc");
   }
  } 
        
  
  if($#ages>-1 && $ages[$src])
  {
    my $diff=$ages[$trg]*1.0-$ages[$src]*1.0;
    
    do_cmd('mincblur',"$outdir/stx_j_$visits[$src].mnc",'-fwhm',10,"$outdir/stx_j_$visits[$src]") unless -e "$outdir/stx_j_$visits[$src]_blur.mnc";
    do_cmd('mincresample','-nearest',$model_mask_fn,$model_mask_lr,'-like',"$outdir/stx_j_$visits[$src]_blur.mnc") unless -e $model_mask_lr;
    do_cmd('minccalc','-express',"A[0]>0.5?A[1]/$diff:0",$model_mask_lr,"$outdir/stx_j_$visits[$src]_blur.mnc","$outdir/stx_d_$visits[$src].mnc") 
          unless -e "$outdir/stx_d_$visits[$src].mnc";
    my $pbvc=`mincstats -mean -q $outdir/j_$visits[$src].mnc -mask $outdir/j_mask_$visits[$src].mnc -mask_binvalue 1`;
    chomp($pbvc);
    $pbvc=$pbvc*100.0;
    my $pbvc_pca=0.0;
    $pbvc_pca=`mincstats -mean -q $outdir/pca_j_$visits[$src].mnc -mask $outdir/pca_j_mask_$visits[$src].mnc -mask_binvalue 1`  if $pca;
    print OUT "$candid,$visits[$src],$gender,$ages[$src],$ages[$trg],$diff,$vx1,$vx2,$tr1[3],$tr2[3],$pbvc,$pbvc_pca\n";
  }
  do_cmd('rm','-f',"$tmpdir/*");
}

close OUT;
sub do_cmd {
    print STDOUT "@_\n" if $verbose;
    if(!$fake) {
        system(@_) == 0 or die "DIED: @_\n";
    }
}
