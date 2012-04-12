#!/usr/bin/env perl
#
# Matthew Kitching
# Script based on original work by Andrew Janke.
# This modified version is used with nihpd database.
#
# Andrew Janke - rotor@bic.mni.mcgill.ca
# Script to crop als Data
#
# Sun Dec  2 00:48:21 EST 2001 - initial version
# Mon Feb 11, 2002 LC - modified to work on MNI_MS data.
# Wed May 1, 2002 LC - modified to work on NIHPD data.

#
######################
##TODO:Add information (lob sizes etc.) to the db
use strict;
use Getopt::Long;
use File::Basename;
use File::Temp qw/ tempfile tempdir /;
use pipeline_functions;

my $me = basename($0);
my $verbose = 0;
my $clobber = 0;
my $fake = 0;
my $model_dir;
my $template;

GetOptions(
	   'verbose'     => \$verbose,
	   'clobber'     => \$clobber,
     'model-dir=s' => \$model_dir,
     'template=s'  => \$template
	   );

#####################
##we want classified file (either linear, or nl) and the xfm files. if its a li
##linear xfm file, then use linear twice... if its non-linear, then use the identity matrix for the linear transform
##output both segmented and lob files.

if ($#ARGV < 3){ die "Usage: $me <in_classified> <infile_lin_xfm>  <infile_nl_xfm> <out_lob> [ --model-dir <atlases_directory> --template <model name> to be used as template]\n"; }

my $infile_cls = $ARGV[0];
my $infile_lin_xfm = $ARGV[1];
my $infile_nl_xfm =$ARGV[2]; 

#$outfile_seg = $ARGV[3];
my $outfile_lob = $ARGV[3];
my @files_to_add_to_db = ();

###################
##First make the segmentation file
if (!( -e $outfile_lob) || $clobber )
{
    my @args = ('lobe_segment', $infile_nl_xfm, $infile_lin_xfm,	   
      $infile_cls, $outfile_lob);

    if($clobber) { push(@args, '-clobber'); }
    if($verbose) { push(@args, '-verbose'); }

    push @args,'-modeldir',"${model_dir}/${template}_atlas/" if $model_dir && $template;
    push @args,'-template',"${model_dir}/${template}.mnc"  if $template;

    do_cmd(@args); 

    # stx_segment does not seem to create a proper header so doing it here - LB, Dec./04
    my $tmpdir = &tempdir( "$me-XXXXXXXX", TMPDIR => 1, CLEANUP => 1 );
    pipeline_functions::create_header_info_for_many_parented($outfile_lob, $infile_cls, $tmpdir);
    @files_to_add_to_db = (@files_to_add_to_db, $outfile_lob);
}
else{print("Found segmented file in db... skipping\n");}

print("Files created:@files_to_add_to_db\n");

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

