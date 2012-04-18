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

die "Program usage: ${me} <tal_t1w> <lc_clean> <nonlinear_segment_lobe> <candID> <visit label> <age> <out_lc_clean> <out_nl_segment_lobe>" if $#ARGV < 6 ;

my ($tal_t1w, $lc_clean, $nonlinear_segment_lobe, $candID, $VisitLabel, $age, $t1w_lc_clean_img, $nl_t1w_segment_lobe_img) = @ARGV;
my @files_to_add_to_db;


    
    die "$tal_t1w does not exists!" if (!$tal_t1w)  || (! -e $tal_t1w);
    die "$lc_clean does not exists!" if (!$lc_clean) || (! -e $lc_clean);
    die "$nonlinear_segment_lobe does not exists!" if (!$nonlinear_segment_lobe) || (! -e $nonlinear_segment_lobe);

    
    # make tmpdir
    my $tmpdir = &tempdir( "$me-XXXXXXXX", TMPDIR => 1, CLEANUP => 1 );

    my $imagelabel = sprintf "%s/%s/%5.1f years ", $candID,$VisitLabel,$age;
        
    if ( (!-e $t1w_lc_clean_img) || $clobber) {
	if(-e $t1w_lc_clean_img) {
	    &do_cmd("rm","-f",$t1w_lc_clean_img);
	}

  do_cmd('mincresample','-nearest','-like',$tal_t1w,$lc_clean,"${tmpdir}/lc_clean_resample.mnc");
  $lc_clean="${tmpdir}/lc_clean_resample.mnc";

    #   make overlayed lc_clean and tal_t1w    
        &do_cmd('minclookup','-clobb','-grey'    ,$tal_t1w , "${tmpdir}/t1w.mnc");
        &do_cmd('minclookup','-clobb','-spectral',$lc_clean, "${tmpdir}/lc_clean.mnc", '-range', 0, 3.5);
        &do_cmd('mincmath','-clobb','-max','-nocheck_dimensions',"${tmpdir}/t1w.mnc","${tmpdir}/lc_clean.mnc","${tmpdir}/t1w_lc_clean.mnc");
        make_multipane($tmpdir,"${tmpdir}/t1w_lc_clean.mnc","lc_clean ".$imagelabel,$t1w_lc_clean_img);
	@files_to_add_to_db = (@files_to_add_to_db, $t1w_lc_clean_img);
    }
    
    if( (!-e $nl_t1w_segment_lobe_img) || $clobber) {
		if(-e $nl_t1w_segment_lobe_img ) {
			&do_cmd("rm","-f",$nl_t1w_segment_lobe_img);
		}
	
	&do_cmd('mincresample','-nearest','-like',$tal_t1w,$nonlinear_segment_lobe,"${tmpdir}/nonlinear_segment_lobe_resample.mnc");
	$nonlinear_segment_lobe="${tmpdir}/nonlinear_segment_lobe_resample.mnc";
	
		#   make overlayed t1w and nonlinear_segment_lobe
		&do_cmd('minclookup','-clobb','-grey'    ,$tal_t1w , "${tmpdir}/t1w.mnc") unless -e "${tmpdir}/t1w.mnc";
		&do_cmd('minclookup','-clobb','-spectral',$nonlinear_segment_lobe, "${tmpdir}/nonlinear_segment_lobe.mnc");
		&do_cmd('mincmath','-clobb','-max','-nocheck_dimensions',"${tmpdir}/t1w.mnc","${tmpdir}/nonlinear_segment_lobe.mnc","${tmpdir}/nlr_t1w_segment_lobe.mnc");
		make_multipane($tmpdir,"${tmpdir}/nlr_t1w_segment_lobe.mnc","nlr_segment_lobe ".$imagelabel,$nl_t1w_segment_lobe_img);
	#       &do_cmd("register_minc_db",$nl_t1w_segment_lobe_img,"qc_nl_t1w_segment_lobe","-pipeline","v1.1","-coordspace","nonlinear","-source",$nonlinear_segment_lobe_id); 
		@files_to_add_to_db = (@files_to_add_to_db,$nl_t1w_segment_lobe_img);
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
	 @args = ('mincpik', '-scale','1','-transverse','-slice',$_,'-clob');
	 push(@args, @ext_args) if @ext_args;
         push(@args, $mncfile, "$tmpdir/T$_.miff");
         &do_cmd(@args);
         
         push(@mont_args, "$tmpdir/T$_.miff");
         }

     foreach  ('50','60','70','130','120','110') {
	 @args = ('mincpik', '-scale','1','-sagittal','-slice',$_,'-clob');
	 push(@args, @ext_args) if @ext_args;
         push(@args, $mncfile, "$tmpdir/S$_.miff");
         &do_cmd(@args);
         
         push(@mont_args, "$tmpdir/S$_.miff");
         }

     foreach  ('60','80','110','120','140','160') {
	 @args = ('mincpik', '-scale','1','-coronal','-slice',$_,'-clob');
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

