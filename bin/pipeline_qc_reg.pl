#!/usr/bin/env perl

use strict;
use File::Basename;
use File::Temp qw/ tempfile tempdir /;
use File::Path;
use Getopt::Long;       
use pipeline_functions;

my $me = basename($0);
my $verbose = 0;
my $fake = 0;
my $clobber = 0;

GetOptions(
	   'verbose' => \$verbose,
	   'fake'    => \$fake,
	   'clobber' => \$clobber
	   );

die "Program usage: ${me} <nl_t1w> <candID> <visit_label>  <age>  <out_nl>" if $#ARGV < 4 ;

my $outline="$ENV{TOPDIR}/models/icbm_avg_152_t1_tal_nlin_symmetric_VI_outline.mnc.gz";

my ($nl_t1w,$candID,$VisitLabel,$age,$nl_img) = @ARGV;
my @files_to_add_to_db;

    die "$nl_t1w does not exists!" if (!$nl_t1w)  || (! -e $nl_t1w);
   
    # make tmpdir
    my $tmpdir = &tempdir( "$me-XXXXXXXX", TMPDIR => 1, CLEANUP => 1 );

    my $imagelabel = sprintf "%s/%s/%5.1f years ", $candID,$VisitLabel,$age;
        
    if ( (!-e $nl_img) || $clobber) {
	if(-e $nl_img) {
	    &do_cmd("rm","-f",$nl_img);
	}

	
	do_cmd('minclookup', '-spectral', '-range', 25, 75, $nl_t1w , "$tmpdir/t1w_spect.mnc",'-byte');
	do_cmd('mincmath','-max',"$tmpdir/t1w_spect.mnc", $outline,"$tmpdir/t1w_outline.mnc");
  	#make_multipane($tmpdir,$nl_t1w,"NL T1W ".$imagelabel,$nl_img);
	make_multipane($tmpdir,"$tmpdir/t1w_outline.mnc","NL T1W ".$imagelabel,$nl_img);

	@files_to_add_to_db = (@files_to_add_to_db, $nl_img);
    }
    

print("Files created:@files_to_add_to_db\n");

    
######################################################################
# make_multiplace(tmpDir,text,imgfile[, extra arguments for mincpik])
#
# will create an image file with several slices , and label text
######################################################################
sub make_multipane
{
   my ($tmpdir,$mncfile, $text, $imgfile, @ext_args) = @_;
   my $smalltilesize = 150;
   my (@args, @mont_args);
   
   # try a .gz if file missing
   $mncfile .= '.gz' if (!-e $mncfile);
   
   # make the link if if doesn't exist
   if(!-e $mncfile){
      die "Missing input file!\n";
      return;
  }
   # do the real thing
   else{
     foreach  ('30','35','40','45','50','145') {
	 @args = ('mincpik', '-scale','1','-transverse','-slice',$_,'-clobber');# -clob
	 push(@args, @ext_args) if @ext_args;
         push(@args, $mncfile, "$tmpdir/T$_.miff");
         &do_cmd(@args);
         
         push(@mont_args, "$tmpdir/T$_.miff");
         }

     foreach  ('50','60','70','130','120','110') {
	 @args = ('mincpik', '-scale','1','-sagittal','-slice',$_,'-clobber');# -clob
	 push(@args, @ext_args) if @ext_args;
         push(@args, $mncfile, "$tmpdir/S$_.miff");
         &do_cmd(@args);
         
         push(@mont_args, "$tmpdir/S$_.miff");
         }

     foreach  ('60','80','110','120','140','160') {
	 @args = ('mincpik', '-scale','1','-coronal','-slice',$_,'-clobber');# -clob
	 push(@args, @ext_args) if @ext_args;
         push(@args, $mncfile, "$tmpdir/C$_.miff");
         &do_cmd(@args);
         
         push(@mont_args, "$tmpdir/C$_.miff");
         }
   
      # do the montage
      &do_cmd('montage',
              '-tile', '3x6',
              '-background', 'grey10',
              '-geometry', $smalltilesize . 'x' . $smalltilesize . '+1+1',
              @mont_args,
              "$tmpdir/mont.miff");
               
      # Add the title
      @args = ('convert', '-box', 'white', 
	       #'-font', '7x13bold', 
	       #'-fill', 'white',
	       '-draw', "text 2,15 \"$text\"");
      #push(@args, @more_args) if @more_args;
      &do_cmd(@args,"$tmpdir/mont.miff", $imgfile);
      
 #     print STDOUT "JPG-";
      }
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

