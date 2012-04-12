#!/usr/bin/env perl 
#
#
# Matthew Kitching
#
# Script based on original work by Andrew Janke.
# This modified version is used with nihpd database.
#
# Wed Mar  6 17:13:21 EST 2002 - initial version

########################################
##script classifies data. presently it uses classify_clean,
##chris cocosco's version. TODO add EM


use Getopt::Tabular;
use pipeline_functions;    
use MNI::FileUtilities qw(check_output_dirs);

# $SIG{__DIE__} =  sub { &cleanup; die $_[0]; };
				  
chomp($me  = `basename $0`);
$verbose   = 0;
$clobber   = 0;

@opt_table = (
   ["-verbose", "boolean", 0, \$verbose, "be verbose"            ],
   ["-clobber", "boolean", 0, \$clobber, "clobber existing mask" ],
   );

&GetOptions(\@opt_table, \@ARGV) || exit 1;
if($#ARGV < 0){ die "Usage: $me <selected files>\n" }
$selected_files_t1 = $ARGV[0];
$selected_files_t2 = $ARGV[1];
$selected_files_pd = $ARGV[2];
$source_list = $ARGV[3];
$t1_tal = $ARGV[4];

$selected_files = "$selected_files_t1 $selected_files_t2 $selected_files_pd";

print("hmmm...$source_list\n\n\n");
@sources = split(",", $source_list);
$source_list_period = join(".", @sources);


$tmpdir  = "/var/tmp/${source_list_period}_em";
if(!-e $tmpdir){`mkdir $tmpdir`;}

$outfile_em = "$tmpdir/$source_list_period.em.cls";
$outfilemasked_em = "$tmpdir/$source_list_period.em.cls.masked.mnc";

@types =pipeline_functions::get_processed_files_from_mriid("complete_path", "final/tal_msk", "'$source_list'");
$maskfile = $types[0];

###############################################################################
##em_classification section
if ($clobber || !($return_val = pipeline_functions::is_type_in_db("final/cls", $source_list, "em_cls")))
{
    $em_arg = "/data/ipl/ipl4/lenezet/EM/EM -mask $maskfile $selected_files $outfile_em"; 
    @em_arg = ('/data/ipl/ipl4/lenezet/EM/EM' ,$maskfile,$selected_files,'-mask' ,$maskfile,$outfile_em);
    if($verbose){ print STDOUT "@em_arg\n"; }
    system(@em_arg) == 0 or die "$me: can't classify";
    die;
    pipeline_functions::create_header_info_for_many_parented($outfile_em, $t1_tal, $tmpdir);
    @args = ('./pipeline_insert_file_into_db', $subject_visit,  $outfile_em, 'cls',"em_cls" , '-source_list', $source_list);
    if($verbose){ print STDOUT @args; }
    system(@args) == 0 or die;
}

else{print("Found em cls file $return_val in db with source list of $source_list... skipping\n");}
die;
  
if ($clobber || !($return_val = pipeline_functions::is_type_in_db("final/cls_msk", "'$source_list'", "em_cls")))
{
    @types =pipeline_functions::get_processed_files_from_mriid_scan_type("complete_path", "final/cls", "em_cls", "'$source_list'");
    @args = ('mincmask','-clobber',$types[0] ,$maskfile,$outfilemasked_em);
    if ($verbose) {
	print STDOUT "*** generating masked cls for $subject_visit\n";
	print STDOUT "@args\n"; 
    }
    system(@args) == 0 or die "Can't mask the classified data";
    
    pipeline_functions::create_header_info_for_many_parented($outfilemasked_em, $t1_tal, $tmpdir);
    @args = ('./pipeline_insert_file_into_db', $subject_visit,  $outfilemasked_em, 'cls_msk', "em_cls", '-source_list', $source_list);
    if($verbose){ print STDOUT @args; }
    system(@args) == 0 or die;
}
else{print("Found em cls_msk file $return_val in db with source list of $source_list... skipping\n");}


&cleanup;  
  
sub cleanup {
  if($verbose){ print STDOUT "Cleaning up....\n"; }
  if(-e $tmpdir)
  {
 #     `rm -r $tmpdir`;
  }
}




