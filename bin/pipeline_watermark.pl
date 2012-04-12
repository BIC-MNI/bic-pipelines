#!/usr/bin/env perl
#
# Vladimir S. Fonov 
#
# Script to apply a watermark to a scan 
#
# Uses 3 additional files:  watermark_posterior.mnc watermark_inferior.mnc watermark_left.mnc
#
##################################
use strict;
use Getopt::Long;
use File::Basename;
use File::Temp qw/ tempdir /;


my $me = basename ($0,'.pl');
my $verbose     = 0;
my $clobber     = 0;
my $model_dir;
my $fake=0;
my $no_int_norm=0;
GetOptions(
	   'verbose'     => \$verbose,
	   'clobber'     => \$clobber,
     'model_dir=s' => \$model_dir,
     'no_int_norm' => \$no_int_norm
	   );

if($#ARGV < 1) { die "Usage: $me <infile> <outfile_mnc> --model_dir <model_dir> --no_int_norm \n"; }

die "please set --model_dir !\n" unless $model_dir;

my $posterior = "$model_dir/watermark_posterior.mnc";
my $inferior  = "$model_dir/watermark_inferior.mnc";
my $left      = "$model_dir/watermark_left.mnc";

###################
my $infile = $ARGV[0];
my $outfile = $ARGV[1];

check_file($outfile) unless $clobber;

my @files_to_add_to_db = ();

###########################
my $tmpdir = &tempdir( "$me-XXXXXXXX", TMPDIR => 1, CLEANUP =>1 );

my $compress=$ENV{MINC_COMPRESS};
delete $ENV{MINC_COMPRESS} if $compress;

my %info=minc_info($infile);
#print join(' ',%info),"\n";
#abjust slices, otherwise minc behaves strangely sometimes

do_cmd('mincreshape','-dimorder','xspace,zspace,yspace',$infile,"$tmpdir/sample.mnc");
reshape_like($posterior,"$tmpdir/sample.mnc","$tmpdir/posterior.mnc");
reshape_like($inferior ,"$tmpdir/sample.mnc","$tmpdir/inferior.mnc");
reshape_like($left     ,"$tmpdir/sample.mnc","$tmpdir/left.mnc");

my $avg=`mincstats -biModalT -q $infile`;
chomp($avg);
$avg*=0.8;
$avg=int($avg);

do_cmd('mincmath','-nocheck_dimensions','-max',"$tmpdir/posterior.mnc","$tmpdir/inferior.mnc","$tmpdir/left.mnc","$tmpdir/tmp.mnc",'-clobber');
do_cmd('minccalc','-expression',"A[0]*$avg","$tmpdir/tmp.mnc","$tmpdir/combined.mnc",'-short');

do_cmd('mincmath','-clobber','-add',"$tmpdir/sample.mnc","$tmpdir/combined.mnc","$tmpdir/out.mnc",'-copy_header','-short','-nocheck_dimensions');

$ENV{MINC_COMPRESS}=$compress if $compress;
my @arg=('mincreshape','-dimorder',$info{dimnames},'-clobber',"$tmpdir/out.mnc",$outfile);
push @arg,'-valid_range',0,4095 unless $no_int_norm;
do_cmd(@arg);

@files_to_add_to_db = ($outfile);#'-nocheck_dimensions'

#print("Files created:@files_to_add_to_db\n");

sub do_cmd { 
    print STDOUT "@_\n" if $verbose;
    if(!$fake){
      system(@_) == 0 or die "DIED: @_\n";
    }
}

sub check_file {
  die("${_[0]} exists!\n") if -e $_[0];
}

sub minc_info {
   my ($input)=@_;
   my %info = (
   'dimnames' => undef,
   'xspace'   => undef,
   'yspace'   => undef,
   'zspace'   => undef,
   'xstart' => undef,
   'ystart' => undef,
   'zstart' => undef,
   'xstep' => undef,
   'ystep' => undef,
   'zstep' => undef,
   );   
   ($info{dimnames},
    $info{xspace},$info{yspace},$info{zspace},
    $info{xstart},$info{ystart},$info{zstart},
    $info{xstep},$info{ystep},$info{zstep})= 
    split(/\n/, `mincinfo -vardims image -dimlength xspace -dimlength yspace -dimlength zspace -attvalue xspace:start -attvalue yspace:start -attvalue zspace:start -attvalue xspace:step -attvalue yspace:step -attvalue zspace:step $input`);
    for (values %info) 
    {  
      
      if( /space/ ) 
      { 
        s/\s/,/g; 
      } else  {
        $_*=1.0;
      }
    } #convert to floats
  chop($info{dimnames}); #remove last comma
  #print join(' ',%info);
  return %info;
}

# makes a minc file with the same dimension order and step sign
sub reshape_like {
  my ($in,$sample,$out)=@_;
  my %info=minc_info($sample);
  
  do_cmd('mincreshape',$in,"$tmpdir/tmp.mnc",
    '-dimrange',"xspace=0,$info{xspace}",
    '-dimrange',"yspace=0,$info{yspace}",
    '-dimrange',"zspace=0,$info{zspace}",
    '-dimorder',$info{dimnames},
    '-clobber'
  );
         
  do_cmd('mincreshape',"$tmpdir/tmp.mnc",$out,#"$tmpdir/tmp.mnc",
    '-dimorder',$info{dimnames},
    '-dimsize', 'xspace=-1',
    '-dimsize', 'yspace=-1',
    '-dimsize', 'zspace=-1', 
    $info{xstep}>0?'+xdirection':'-xdirection',
    $info{ystep}>0?'+ydirection':'-ydirection',
    $info{zstep}>0?'+zdirection':'-zdirection',
    '-clobber');
}


#resample like another minc file
sub resample_like {
  my ($in,$sample,$out)=@_;

  my %info=minc_info($sample);
  
  if($info{xstep}<0)
  {
    $info{xstart}+=$info{xstep}*$info{xspace};
    $info{xstep}= -$info{xstep};
  }

  if($info{ystep}<0)
  {
    $info{ystart}+=$info{ystep}*$info{yspace};
    $info{ystep}= -$info{ystep};
  }

  if($info{zstep}<0)
  {
    $info{zstart}+=$info{zstep}*$info{zspace};
    $info{zstep}= -$info{zstep};
  }

  $info{xlen}=$info{xstep}*$info{xspace};
  $info{ylen}=$info{ystep}*$info{yspace};
  $info{zlen}=$info{zstep}*$info{zspace};
  
  my @att=split(/\n/,`mincinfo -attvalue xspace:direction_cosines -attvalue yspace:direction_cosines -attvalue zspace:direction_cosines $sample`);
  
  my @cosx=split(/\s/,$att[0]);
  my @cosy=split(/\s/,$att[1]);
  my @cosz=split(/\s/,$att[2]);
  
  do_cmd('mincreshape',$in,"$tmpdir/tmp.mnc",'-clobber');
  do_cmd('minc_modify_header',
         '-dappend',"xspace:direction_cosines=$cosx[0]",
         '-dappend',"xspace:direction_cosines=$cosx[1]",
         '-dappend',"xspace:direction_cosines=$cosx[2]",

         '-dappend',"yspace:direction_cosines=$cosy[0]",
         '-dappend',"yspace:direction_cosines=$cosy[1]",
         '-dappend',"yspace:direction_cosines=$cosy[2]",

         '-dappend',"zspace:direction_cosines=$cosz[0]",
         '-dappend',"zspace:direction_cosines=$cosz[1]",
         '-dappend',"zspace:direction_cosines=$cosz[2]",

         '-dinsert',"xspace:start=$info{xstart}",
         '-dinsert',"yspace:start=$info{ystart}",
         '-dinsert',"zspace:start=$info{zstart}",
         
         '-dinsert',"xspace:step=$info{xstep}",
         '-dinsert',"yspace:step=$info{ystep}",
         '-dinsert',"zspace:step=$info{zstep}",
         "$tmpdir/tmp.mnc");
  do_cmd('mincresample','-like',$sample,'-clobber','-nearest',"$tmpdir/tmp.mnc",$out);
}
