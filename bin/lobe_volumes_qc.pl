#!/usr/bin/env perl
#

# Intersect the labels of the volume lobar segmentation with the 
# cortical surfaces and produce verify images for quality control 
# of the segmentation. Are the lobes where they should be and are
# their volumes meaningful? Images are produce in stereotaxic 
# space in which the segmentation and surfaces are defined.

use strict;
use warnings "all";
use File::Temp qw/ tempfile tempdir /;
use Getopt::Tabular;
use File::Basename;

#use MNI::Startup;
#use MNI::FileUtilities qw(check_output_dirs);
my $me = basename($0,".pl");
my $verbose=0;
my $fake=0;
my $clobber=0;

my $xfm1;
my $xfm2;

my $title;
# --- set the help & usage strings ---
my $help = <<HELP;
Produce a verify image for the volume lobar segmentation by
intersecting the surfaces with the segmented image.
HELP

my $usage = <<USAGE;
Usage: $me left_surface.obj right_surface.obj stx_labels.mnc stx_t1w.mnc output_image.png
       $me -help to list options

USAGE

my @options =
  ( 
    ["-verbose", "boolean", 0, \$verbose,
      "be verbose" ],
      
    ["-clobber", "boolean", 0, \$clobber,
      "clobber existing check files" ],
      
    ["-fake", "boolean", 0, \$fake,
      "do a dry run, (echo cmds only)" ],
      
    ["-xfm-jk", "string", 1, \$xfm1,
      "Junki's xfm" ],
      
    ["-xfm-stx", "string", 1, \$xfm2,
      "Native to stereotactic xfm" ],
      
    ["-title","string",1,\$title,"Picture title"]
);

Getopt::Tabular::SetHelp( $help, $usage );

GetOptions( \@options, \@ARGV )
  or exit 1;
die "$usage\n" unless @ARGV == 5;

# define input variables:

my $left_surf=$ARGV[0];             # input - left surface in stx space
my $right_surf=$ARGV[1];            # input - right surface in stx space
my $labels=$ARGV[2];                # input - volume labels in stx space
my $t1w=$ARGV[3];                   # input - volume labels in stx space
my $output=$ARGV[4];                # input - output image (.png)

my $tilesize = 300;
my $debug = 1;
my $quiet = 0;
my @mont_args = ();
my @DrawText = ( "-font", "Helvetica" );

my $xpos = 2*$tilesize;
my $ypos = 15;
my $num_rows = 2;

# Directory for temporary files.

#MNI::FileUtilities::check_output_dirs($TmpDir)
#or exit 1;
my $TmpDir= &tempdir( "${me}-XXXXXXXX", TMPDIR => 1, CLEANUP => 1 );

# Lobe definitions from CIVET surface parcellation.
my $medial_cut_lobe = 0;
my $parietal_lobe = 1;
my $occipital_lobe = 2;
my $frontal_lobe = 3;
my $lymbic_parietal_lobe = 4;
my $lymbic_temporal_lobe = 5;
my $lymbic_frontal_lobe = 6;
my $temporal_lobe = 7;
my $insula_lobe = 8;
#additional structures

my $caudate_left_out = 9;
my $caudate_right_out = 10;
my $putamen_left_out = 11;
my $putamen_right_out = 12;
my $thalamus_left_out = 13;
my $thalamus_right_out = 14;

my $cerebellum_left_out = 15;
my $cerebellum_right_out = 16;
my $lateral_ventricle_left_out = 17;
my $lateral_ventricle_right_out = 19;
my $third_ventricle_out = 19;
my $fourth_ventricle_out = 20;

my $undefined_lobe = 0;


# Lobe definitions from NIHPD2 segmentation template (Vladimir).
my $frontal_left_wm = 30;
my $frontal_left_gm = 210;
my $frontal_right_wm = 17;
my $frontal_right_gm = 211;
my $temporal_left_wm = 83;
my $temporal_left_gm = 218;
my $temporal_right_wm = 59;
my $temporal_right_gm = 219;
my $parietal_left_wm = 57;
my $parietal_left_gm = 6;
my $parietal_right_wm = 105;
my $parietal_right_gm = 2;
my $occipital_left_wm = 73;
my $occipital_left_gm = 8;
my $occipital_right_wm = 45;
my $occipital_right_gm = 4;
my $cerebellum_left = 67;
my $cerebellum_right = 76;
my $brainstem = 20;
my $lateral_ventricle_left = 3;
my $lateral_ventricle_right = 9;
my $third_ventricle = 232;
my $fourth_ventricle = 233;
my $extracerebral_CSF = 255;

my $caudate_left = 39;
my $caudate_right = 53;
my $putamen_left = 14;
my $putamen_right = 16;
my $thalamus_left = 102;
my $thalamus_right = 203;
my $subthalamic_nucleus_left = 33;
my $subthalamic_nucleus_right = 23;
my $globus_pallidus_left = 12;
my $globus_pallidus_right = 11;
my $fornix_left = 29;
my $fornix_right = 254;

my $lut_string = "0 0;" .
                 "$frontal_left_wm $frontal_lobe;" .
                 "$frontal_left_gm $frontal_lobe;" .
                 "$frontal_right_wm $frontal_lobe;" .
                 "$frontal_right_gm $frontal_lobe;" .
                 "$temporal_left_wm $temporal_lobe;" .
                 "$temporal_left_gm $temporal_lobe;" .
                 "$temporal_right_wm $temporal_lobe;" .
                 "$temporal_right_gm $temporal_lobe;" .
                 "$parietal_left_wm $parietal_lobe;" .
                 "$parietal_left_gm $parietal_lobe;" .
                 "$parietal_right_wm $parietal_lobe;" .
                 "$parietal_right_gm $parietal_lobe;" .
                 "$occipital_left_wm $occipital_lobe;" .
                 "$occipital_left_gm $occipital_lobe;" .
                 "$occipital_right_wm $occipital_lobe;" .
                 "$occipital_right_gm $occipital_lobe;" .
                 "$cerebellum_left $undefined_lobe;" .
                 "$cerebellum_right $undefined_lobe;" .
                 "$brainstem $medial_cut_lobe;" .
                 "$lateral_ventricle_left $undefined_lobe;" .
                 "$lateral_ventricle_right $undefined_lobe;" .
                 "$third_ventricle $undefined_lobe;" .
                 "$fourth_ventricle $undefined_lobe;" .
                 "$extracerebral_CSF $undefined_lobe;" .
                 "$caudate_left $medial_cut_lobe;" .
                 "$caudate_right $medial_cut_lobe;" .
                 "$putamen_left $medial_cut_lobe;" .
                 "$putamen_right $medial_cut_lobe;" .
                 "$thalamus_left $medial_cut_lobe;" .
                 "$thalamus_right $medial_cut_lobe;" .
                 "$subthalamic_nucleus_left $medial_cut_lobe;" .
                 "$subthalamic_nucleus_right $medial_cut_lobe;" .
                 "$globus_pallidus_left $medial_cut_lobe;" .
                 "$globus_pallidus_right $medial_cut_lobe;" .
                 "$fornix_left $medial_cut_lobe;" .
                 "$fornix_right $medial_cut_lobe;" .
                 "255 0";


my $lut_string_vol = "0 0;" .
                 "$frontal_left_wm $frontal_lobe;" .
                 "$frontal_left_gm $frontal_lobe;" .
                 "$frontal_right_wm $frontal_lobe;" .
                 "$frontal_right_gm $frontal_lobe;" .
                 "$temporal_left_wm $temporal_lobe;" .
                 "$temporal_left_gm $temporal_lobe;" .
                 "$temporal_right_wm $temporal_lobe;" .
                 "$temporal_right_gm $temporal_lobe;" .
                 "$parietal_left_wm $parietal_lobe;" .
                 "$parietal_left_gm $parietal_lobe;" .
                 "$parietal_right_wm $parietal_lobe;" .
                 "$parietal_right_gm $parietal_lobe;" .
                 "$occipital_left_wm $occipital_lobe;" .
                 "$occipital_left_gm $occipital_lobe;" .
                 "$occipital_right_wm $occipital_lobe;" .
                 "$occipital_right_gm $occipital_lobe;" .
                 "$cerebellum_left $cerebellum_left_out;" .
                 "$cerebellum_right $cerebellum_right_out;" .
                 "$brainstem $undefined_lobe;" .
                 "$lateral_ventricle_left $lateral_ventricle_left_out;" .
                 "$lateral_ventricle_right $lateral_ventricle_right_out;" .
                 "$third_ventricle $third_ventricle_out;" .
                 "$fourth_ventricle $fourth_ventricle_out;" .
                 "$extracerebral_CSF $undefined_lobe;" .
                 "$caudate_left $caudate_left_out;" .
                 "$caudate_right $caudate_right_out;" .
                 "$putamen_left $putamen_left_out;" .
                 "$putamen_right $putamen_right_out;" .
                 "$thalamus_left $thalamus_left_out;" .
                 "$thalamus_right $thalamus_right_out;" .
                 "$subthalamic_nucleus_left $undefined_lobe;" .
                 "$subthalamic_nucleus_right $undefined_lobe;" .
                 "$globus_pallidus_left $undefined_lobe;" .
                 "$globus_pallidus_right $undefined_lobe;" .
                 "$fornix_left $undefined_lobe;" .
                 "$fornix_right $undefined_lobe;" .
                 "255 0";

# Dilation of the segmented volume. Make csf 255 to be 0.

my $minc_compress=$ENV{MINC_COMPRESS};
delete $ENV{MINC_COMPRESS};


my $mapped_labels = "${TmpDir}/mapped_labels.mnc";
my $fixed_labels = "${TmpDir}/fixed_labels.mnc";
my $fixed_labels_vol = "${TmpDir}/fixed_labels_vol.mnc";
my $dilated_labels = "${TmpDir}/dilated_labels.mnc";
my $final_labels = "${TmpDir}/final_labels.mnc";

# Merge wm/gm labels and remap labels for plotting purposes.


run( "minclookup", "-quiet", "-clobber", "-byte", "-discrete", '-valid_range',0,255,
      "-lut_string", "${lut_string_vol}", $labels, $fixed_labels_vol );


if( -e $left_surf && -e $right_surf )
{
  if($xfm1 && $xfm2)
  {
    print "Transforming surfaces\n\n";
    
    run('xfminvert',$xfm1,"${TmpDir}/xfm1_inv.xfm");
    run('xfmconcat',"${TmpDir}/xfm1_inv.xfm",$xfm2,"${TmpDir}/to_stx.xfm");
    run('transform_objects',$left_surf,"${TmpDir}/to_stx.xfm","${TmpDir}/left.obj");
    run('transform_objects',$right_surf,"${TmpDir}/to_stx.xfm","${TmpDir}/right.obj");
    $left_surf="${TmpDir}/left.obj";
    $right_surf="${TmpDir}/right.obj";
    
  }
  
  
run( "minclookup", "-quiet", "-clobber", "-byte", "-discrete", '-valid_range',0,255,
      "-lut_string", "${lut_string}", $labels, $mapped_labels );


#run( "mincreshape", "-quiet", "-clobber", "-byte", "-valid_range", 0, 255,
#      "-image_range", 0, 255, $fixed_labels, $mapped_labels );

# Dilate segmentation in a nice way.

run( "mincmorph", "-clobber", "-3D06", "-successive", "DDDDD",
      $mapped_labels, $dilated_labels );
      
run( "minccalc", "-quiet", "-clobber", "-byte",
      "-expression", 'if(A[0]<0.5){A[1]}else{A[0]}', $mapped_labels, 
      $dilated_labels, $final_labels );
      
run( "mincreshape", "-quiet", "-clobber", "-byte", "-valid_range", 0, 255,
      "-image_range", 0, 255, $final_labels, $fixed_labels );
      
run( "mv", "-f", $fixed_labels, $final_labels );
  
# Intersect left/right surfaces with labels.

my $tmp_left_surface_labels = "${TmpDir}/lobar_left_surface_labels.txt";
run( "volume_object_evaluate", "-nearest_neighbour", $final_labels, 
      $left_surf, $tmp_left_surface_labels );

my $tmp_right_surface_labels = "${TmpDir}/lobar_right_surface_labels.txt";
run( "volume_object_evaluate", "-nearest_neighbour", $final_labels, 
      $right_surf, $tmp_right_surface_labels );

# Create the figures.

my $labeled_left_surf = "${TmpDir}/lobar_left_surface.obj";
run( "colour_object", $left_surf, $tmp_left_surface_labels, $labeled_left_surf, "spectral", -1, 8 );

my $labeled_right_surf = "${TmpDir}/lobar_right_surface.obj";
run( "colour_object", $right_surf, $tmp_right_surface_labels, $labeled_right_surf, "spectral", -1, 8 );

foreach my $pos ('default', 'left', 'right') {
  make_hemi( $labeled_left_surf, "${TmpDir}/left_surf_$pos.rgb", $pos );
  push(@mont_args, "${TmpDir}/left_surf_$pos.rgb");
}

foreach my $pos ('top', 'bottom') {
  make_surface( $labeled_left_surf, $labeled_right_surf, "${TmpDir}/full_surf_${pos}.rgb", $pos );
  push(@mont_args, "${TmpDir}/full_surf_${pos}.rgb");
}

foreach my $pos ('default', 'right', 'left') {
  make_hemi( $labeled_right_surf, "${TmpDir}/right_surf_$pos.rgb", $pos );
  push(@mont_args, "${TmpDir}/right_surf_$pos.rgb");
}

foreach my $pos ('front', 'back') {
  make_surface( $labeled_left_surf, $labeled_right_surf, "${TmpDir}/full_surf_${pos}.rgb", $pos );
  push(@mont_args, "${TmpDir}/full_surf_${pos}.rgb");
}


# do the montage
run( "montage", "-tile", "5x${num_rows}", "-background", "white",
          "-geometry", "${tilesize}x${tilesize}+1+1",
          @mont_args, "${TmpDir}/mont.miff" );
          
run( "convert", "-box", "white", "-stroke", "green", "-pointsize", 16,
      @DrawText, "${TmpDir}/mont.miff", "${TmpDir}/mont_text.miff" );
          
}  else { 
  run('convert','-background','white',"-stroke", "green", "-pointsize", 16,
      @DrawText,'label:No Surfaces',"${TmpDir}/mont_text.miff");

}

run('minc_qc2.pl',$t1w,'--mask',$fixed_labels_vol,'--spectral-mask','--image-range',0,100,'--horizontal','--big','--avg','-bg','white',
    "${TmpDir}/volume.miff");

my @args=('montage','-tile','1x2',"${TmpDir}/mont_text.miff","${TmpDir}/volume.miff",'-geometry','+1+1');
push @args,'-title',$title if $title;
push @args,$output;

run(@args);

sub make_hemi {
  my ($surface, $temp_output, $pos) = @_;

  my $cmd = "";
  my $viewdir = "";
  if ($pos eq 'default') {
    $viewdir = "";
  } else {
    $viewdir = "-$pos";
  }

  $cmd = "ray_trace -shadows -output ${temp_output} ${surface} -bg white -crop ${viewdir}";
  print "$cmd\n" if $debug; `$cmd`;
}

sub make_surface {
  my ($left_hemi, $right_hemi, $temp_output, $pos) = @_;

  my $cmd = "";
  my $viewdir = "";
  if ($pos eq 'default') {
    $viewdir = "";
  } else {
    $viewdir = "-$pos";
  }

  $cmd = "ray_trace -shadows -output ${temp_output} ${left_hemi} ${right_hemi} -bg white -crop ${viewdir}";
  print "$cmd\n" if $debug; `$cmd`;
}



#Execute a system call.

sub run {
  print "@_\n";
  system(@_)==0 or die "Command @_ failed with status: $?";
}

