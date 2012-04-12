#!/usr/bin/env perl

##############################################################################
# 
# pipeline_qc.pl
#
# Input:
#      o tal_msk filename
#      o tal T1 filename
#      o tal T2 filename
#      o candID
#      o visit label
#      o age in years
#
# Output:
#      o a jpeg file with the mask overlaid on the T1 image.
#      o a jpeg file with the T1 image overlaid on the T2 image.
#
#
# Larry Baer, May, 2005
# McConnell Brain Imaging Centre, 
# Montreal Neurological Institute, 
# McGill University
##############################################################################

use strict;
use File::Basename;
use File::Temp qw/ tempfile tempdir /;
#use NeuroDB::File;
use Getopt::Long;
use pipeline_functions;

my $me;
my $verbose = 0;
my $fake = 0;
my $clobber = 0;

my $candID;
my $visit_label;
my $age;
my $infile_msk;
my $infile_T1;
my $infile_T2;
my $outfile_T1MskJpg;
my $outfile_T1T2Jpg;
my $file_lut_red;
my $file_lut_green;
my $file_missingsymbol;
my @files_to_add_to_db = ();

chomp($me = `basename $0`);

GetOptions(
	   'verbose' => \$verbose,
	   'fake' => \$fake,
	   'clobber' => \$clobber
	   );

if($#ARGV < 1){ die "Usage: $me  <input tal mask file> <input T1 file> <input T2 file> <candID> <visit> <age in years> <output T1/Msk jpeg file> <output T1/T2 jpeg file>\n"; }

# Get the arguments.
$infile_msk = $ARGV[0];
$infile_T1 = $ARGV[1];
$infile_T2 = $ARGV[2];
$candID = $ARGV[3];
$visit_label = $ARGV[4];
$age = $ARGV[5];
$outfile_T1MskJpg = $ARGV[6];
$outfile_T1T2Jpg = $ARGV[7];
print "Mask: $infile_msk \n" if $verbose;
print "T1: $infile_T1 \n" if $verbose;
print "T2: $infile_T2 \n" if $verbose;
print "T1Msk: $outfile_T1MskJpg \n" if $verbose;
print "T1T2: $outfile_T1T2Jpg \n" if $verbose;

##########################
# Check the arguments.
if (! -e $infile_msk ) { die "$infile_msk does not exist\n"; }
if (! -e $infile_T1 ) { die "$infile_T1 does not exist\n"; }
if (! -e $infile_T2 ) { die "$infile_T2 does not exist\n"; }
if (-e $outfile_T1MskJpg && ! $clobber ) { die "$outfile_T1MskJpg exists.  Use -clobber\n"; }
if (-e $outfile_T1T2Jpg && ! $clobber ) { die "$outfile_T1T2Jpg exists.  Use -clobber\n"; }

# make tmpdir
my $tmpdir = &tempdir( "$me-XXXXXXXX", TMPDIR => 1, CLEANUP => 1 );

# Create T1/Tal_Mask composite
&do_cmd('mincresample','-clobb','-like',$infile_T1,$infile_msk,"$tmpdir/msk.mnc");
&do_cmd('minclookup','-clobb','-lut_string','0.0 0.0 0.0 0.0;1.0 1.0 0.0 0.0',
      "$tmpdir/msk.mnc", "$tmpdir/red.mnc");
&do_cmd('minclookup','-clobb','-grey','-range',10,100,
      $infile_T1, "$tmpdir/grey.mnc");
&do_cmd('mincmath','-clobb','-max','-nocheck_dimensions',"$tmpdir/red.mnc",
      "$tmpdir/grey.mnc","$tmpdir/red_grey.mnc");
my $imagelabel = sprintf "%s/%s/%5.1f years ", $candID,$visit_label,$age; 
&make_multipane("$tmpdir/red_grey.mnc", " $imagelabel ", $outfile_T1MskJpg);

@files_to_add_to_db = (@files_to_add_to_db, $outfile_T1MskJpg);

# Create T1/T2 composite
&do_cmd('mincresample','-clobb','-like',$infile_T1,$infile_T2,"$tmpdir/T1T2.mnc");
&do_cmd('minclookup','-clobb','-lut_string','0.0 0.0 0.0 0.0;1.0 1.0 0.0 0.0','-range',40,50,
      "$tmpdir/T1T2.mnc", "$tmpdir/red.mnc");
&do_cmd('minclookup','-clobb','-lut_string','0.0 0.0 0.0 0.0;1.0 0.0 1.0 0.0','-range',20,25,
      $infile_T1, "$tmpdir/green.mnc");
&do_cmd('mincmath','-clobb','-max','-nocheck_dimensions',"$tmpdir/red.mnc",
      "$tmpdir/green.mnc","$tmpdir/red_green.mnc");
my $imagelabel = sprintf "%s/%s/%5.1f years ", $candID,$visit_label,$age; 
&make_multipane("$tmpdir/red_green.mnc", " $imagelabel ", $outfile_T1T2Jpg);

@files_to_add_to_db = (@files_to_add_to_db, $outfile_T1T2Jpg);

print("Files created:@files_to_add_to_db\n");

#####################################################################
# sub-routine to make a multipane view for mask testing
sub make_multipane{
   my($mncfile, $text, $imgfile, @ext_args) = @_;
   my $smalltilesize = 150;
   my(@args, @mont_args);
   
   # try a .gz if file missing
   $mncfile .= '.gz' if (!-e $mncfile);
   
   foreach  ('30','35','40','45','50','145') {
     @args = ('mincpik', '-scale','1','-transverse','-slice',$_,'-clobber'); #linux:add -clobber
     push(@args, @ext_args) if @ext_args;
     push(@args, $mncfile, "$tmpdir/T$_.miff");
     &do_cmd(@args);
   
     push(@mont_args, "$tmpdir/T$_.miff");
   }

   foreach  ('50','60','70','130','120','110') {
     @args = ('mincpik','-scale','1','-sagittal','-slice',$_,'-clobber');
     push(@args, @ext_args) if @ext_args;
     push(@args, $mncfile, "$tmpdir/S$_.miff");
     &do_cmd(@args);
         
     push(@mont_args, "$tmpdir/S$_.miff");
   }

   foreach  ('60','80','110','120','140','160') {
     @args = ('mincpik','-scale','1','-coronal','-slice',$_,'-clobber');
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
    
#    print STDOUT "JPG-";
      
 }



#####################################################################
sub do_cmd { 
    print STDOUT "@_\n" if $verbose;
    if(!$fake){
	system(@_) == 0 or die;
    }
}

