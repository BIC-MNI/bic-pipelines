#!/usr/bin/env perl
#
# Matthew Kitching
# Script based on original work by Andrew Janke.
# This modified version is used with nihpd database.
#
# Andrew Janke - rotor@bic.mni.mcgill.ca
# Script to register data to model space
# Sat Dec  1 22:50:48 EST 2001 - initial version
# Sat Feb  9 16:07:28 EST 2002 - updated

# Wed Feb 13 - stolen and modified for NIHPD_MNI (LC)
#    the procedure will figure out how to map all data into stereotaxic
#    space for the given patient.
#    if T1 exists, then it is mapped into stx space with MRITOTAL
#                  and the transform is stored
#    else T2 exists, then mapped to T2 avg, and stored,
#    else fail.
use Getopt::Long;
use File::Basename;
use File::Temp qw/ tempfile tempdir /;
      
$me = basename($0);
$verbose = 0;
$clobber = 0;


GetOptions(
	   'verbose' => \$verbose,
	   'clobber' => \$clobber
	   );


############################
##We are smoothing the brain matter probability maps
##as input we need the classified scan (either linear, or non-linear)
##and we produce three output_scans
if ($#ARGV < 3){ die "Usage: $me <infile_cls> <outfile_wm> <outfile_gm> <outfile_csf>\n"; }


$infile_cls = $ARGV[0];
$outfile_wm = $ARGV[1];
$outfile_gm = $ARGV[2];
$outfile_csf = $ARGV[3];

if(-e $outfile_wm && -e $outfile_gm && -e $outfile_csf)
{
    print("outfiles exists use clobber to overwrite\n");
    exit 0;
}

@files_to_add_to_db = ();
###############
##wm
if (!(-e $outfile_wm) || $clobber)	
{
    print STDOUT "*** Doing smoothmatter()\n";
    @args = ('smooth_mask','-binvalue', '3', '-fwhm', '10', '-clobber', $infile_cls,$outfile_wm);
    print ("@args\n\n");
    system(@args) == 0 or die;

    @files_to_add_to_db = (@files_to_add_to_db, $outfile_wm);
}
else{print("$outfile_wm exists, use clobber to overwrite\n");}

###################
##gm
if (!(-e $outfile_gm) || $clobber)	
{
    print STDOUT "*** Doing smoothmatter()\n";
    @args = ('smooth_mask','-binvalue', '2', '-fwhm', '10', '-clobber',$infile_cls,$outfile_gm);
    system(@args) == 0 or die;

    @files_to_add_to_db = (@files_to_add_to_db, $outfile_gm);
}
else{print("$outfile_gm exists, use clobber to overwrite\n");}

###################
##csf
if (!(-e $outfile_csf) || $clobber)	
{
    print STDOUT "*** Doing smoothmatter()\n";
    @args = ('smooth_mask','-binvalue', '1', '-fwhm', '10', '-clobber',$infile_cls,$outfile_csf);
    if($clobber){ push(@args, '-clobber'); }
    system(@args) == 0 or die;

    @files_to_add_to_db = (@files_to_add_to_db, $outfile_csf);
}
else{print("$outfile_csf exists, use clobber to overwrite\n");}

print("Files created:@files_to_add_to_db\n");
