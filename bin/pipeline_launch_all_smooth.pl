#!/usr/bin/env perl -w
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

use Getopt::Tabular;
use pipeline_functions;
use MNI::FileUtilities qw(check_output_dirs);

$SIG{__DIE__} =  sub { &cleanup; die $_[0]; };

$verbose    = 0;
$clobber    = 0;
$noresample = 0;

@opt_table = (
              ["-verbose",       "boolean", 0, \$verbose,    "be verbose"                    ],
              ["-clobber",       "boolean", 0, \$clobber,    "clobber all existing xfms"     ],
              ["-noresample",    "boolean", 0, \$noresample, "don't do the resampling step"  ],
              );

chomp($me = `basename $0`);
&GetOptions (\@opt_table, \@ARGV) || exit 1;
if($#ARGV < 0){ die "Usage: $me <subject_visit>\n"; }
$subject_visit = $ARGV[0];


print STDOUT "*** Smoothing linear $subject_visit\n";
@args = ('pipeline_smooth', "$subject_visit");
if($clobber){ push(@args, '-clobber'); }
if($verbose){ push(@args, '-verbose'); }
system(@args) == 0 or die;

print STDOUT "*** Smoothing non linear $subject_visit\n";
@args = ('pipeline_smooth', "$subject_visit", '-nl1');
if($clobber){ push(@args, '-clobber'); }
if($verbose){ push(@args, '-verbose'); }
system(@args) == 0 or die
    
print STDOUT "*** Smoothing linear with clean $subject_visit\n";
@args = ('pipeline_smooth', "$subject_visit", '-cls_algorithm', 'clean_cls');
if($clobber){ push(@args, '-clobber'); }
if($verbose){ push(@args, '-verbose'); }
system(@args) == 0 or die;

print STDOUT "*** Smoothing non linear with clean $subject_visit\n";
@args = ('pipeline_smooth', "$subject_visit", '-nl1', '-cls_algorithm', 'clean_cls');
if($clobber){ push(@args, '-clobber'); }
if($verbose){ push(@args, '-verbose'); }
system(@args) == 0 or die
