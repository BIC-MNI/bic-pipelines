#!/usr/bin/env perl
#
use Getopt::Long;
use File::Basename;
use File::Temp qw/ tempfile tempdir /;
use strict;
      
my $me = basename($0);
my $verbose = 0;
my $clobber = 0;
my $fwhm=8;
my $fake=0;
my $xfm;

GetOptions(
	   'verbose' => \$verbose,
	   'clobber' => \$clobber,
     'fwhm=f'  => \$fwhm,
     'xfm=s'   => \$xfm
	   );


############################
##We are smoothing the brain matter probability maps
##as input we need the classified scan (either linear, or non-linear)
##and we produce three output_scans
die <<HELP 
Usage: 
$me <infile_cls> <outfile_wm> <outfile_gm> <outfile_csf> [outfile_lj]
    [ --fwhm <f> blurring kernel , default $fwhm
      --xfm <xfm file> for improved VBM
      --verbose be verbose
      --clobber clobber output files
    ]
HELP
if $#ARGV < 3;


my $infile_cls = $ARGV[0];
my $outfile_wm = $ARGV[1];
my $outfile_gm = $ARGV[2];
my $outfile_csf = $ARGV[3];
my $outfile_j  = $ARGV[4];

check_file($outfile_wm,$outfile_gm,$outfile_csf) unless $clobber;

check_file($outfile_j) unless $clobber || !$outfile_j;

my $tmpdir = &tempdir( "$me-XXXXXXXX", TMPDIR => 1, CLEANUP => 1 );

my $compress=$ENV{MINC_COMPRESS};
delete $ENV{MINC_COMPRESS} if $compress;

my @files_to_add_to_db = ();



if($xfm)
{
  do_cmd('xfm_normalize.pl',$xfm,'--like',$infile_cls,'--exact',"$tmpdir/nl.xfm");
  do_cmd('mincreshape','-dimorder','vector_dimension,xspace,yspace,zspace',"$tmpdir/nl_grid_0.mnc","$tmpdir/nl_grid_0_.mnc");
  do_cmd('mincblob','-determinant',"$tmpdir/nl_grid_0_.mnc","$tmpdir/jacobian.mnc");

  resample_modulate($infile_cls,1 ,$xfm,"$tmpdir/jacobian.mnc","$tmpdir/nl_csf.mnc");
  resample_modulate($infile_cls,3 ,$xfm,"$tmpdir/jacobian.mnc","$tmpdir/nl_wm.mnc");
  resample_modulate($infile_cls,2 ,$xfm,"$tmpdir/jacobian.mnc","$tmpdir/nl_gm.mnc");

  $ENV{MINC_COMPRESS}=$compress if $compress;
  do_cmd('minccalc','-short','-express','clamp(A[0],0,10)',"$tmpdir/nl_csf.mnc",$outfile_csf,'-clobber');
  do_cmd('minccalc','-short','-express','clamp(A[0],0,10)',"$tmpdir/nl_gm.mnc",$outfile_gm,'-clobber');
  do_cmd('minccalc','-short','-express','clamp(A[0],0,10)',"$tmpdir/nl_wm.mnc",$outfile_wm,'-clobber');
  
  #do_cmd('minccalc','-express','A[0]>-1?log(A[0]+1.0):0',"$tmpdir/jacobian.mnc",$outfile_lj) ;
  if( $outfile_j )
  {
    delete $ENV{MINC_COMPRESS}  if $compress;
    do_cmd('xfm_normalize.pl',$xfm,'--like',$infile_cls,"$tmpdir/inl.xfm",'--step',2,'--invert');
    do_cmd('mincreshape','-dimorder','vector_dimension,xspace,yspace,zspace',"$tmpdir/inl_grid_0.mnc","$tmpdir/inl_grid_0_.mnc");
    do_cmd('mincblob','-determinant',"$tmpdir/inl_grid_0_.mnc","$tmpdir/inl_grid_det.mnc");
    $ENV{MINC_COMPRESS}=$compress if $compress;
    do_cmd('mincreshape','-short',"$tmpdir/inl_grid_det.mnc",$outfile_j,'-clob');
    @files_to_add_to_db = (@files_to_add_to_db, $outfile_j);
  }

} else {
  blur_label($infile_cls,1,"$tmpdir/csf.mnc");
  blur_label($infile_cls,2,"$tmpdir/gm.mnc");
  blur_label($infile_cls,3,"$tmpdir/wm.mnc");
  $ENV{MINC_COMPRESS}=$compress if $compress;
  do_cmd('minccalc','-short','-express','clamp(A[0],0,1)',"$tmpdir/csf.mnc",$outfile_csf,'-clobber');
  do_cmd('minccalc','-short','-express','clamp(A[0],0,1)',"$tmpdir/gm.mnc",$outfile_gm,'-clobber');
  do_cmd('minccalc','-short','-express','clamp(A[0],0,1)',"$tmpdir/wm.mnc",$outfile_wm,'-clobber');
}

@files_to_add_to_db = (@files_to_add_to_db, $outfile_wm);
@files_to_add_to_db = (@files_to_add_to_db, $outfile_gm);
@files_to_add_to_db = (@files_to_add_to_db, $outfile_csf);

print("Files created:@files_to_add_to_db\n");


sub blur_label {
  my ($in,$label,$out)=@_;
  do_cmd('minccalc','-express',"abs(A[0]-$label)<0.5?1:0",'-float',$in,"$tmpdir/$label.mnc",'-clobber');
  do_cmd('fast_blur','--fwhm',$fwhm,"$tmpdir/$label.mnc",$out,'--clobber');
}

sub resample_modulate {
  my ($in,$label,$xfm,$jacobian,$out)=@_;
  do_cmd('minccalc','-float','-express',"(abs(A[0]-$label)<0.5&&A[1]>-1)?1.0/(1.0+A[1]):0",
         $in,$jacobian,"$tmpdir/modulate.mnc",'-clobber');

  do_cmd('mincresample','-transform',$xfm,"$tmpdir/modulate.mnc","$tmpdir/modulate_r.mnc",'-clobber','-use_input_sampling');
  do_cmd('fast_blur','--fwhm',$fwhm,"$tmpdir/modulate_r.mnc",$out,'--clobber');
}

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

sub check_file {
  my $i;
  foreach $i(@_) {
    die("$i exists!\n") if -e $i;
  }
}