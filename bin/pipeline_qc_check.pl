#!/usr/local/bin/perl5 -w
#
# Matthew Kitching
#
# Script based on original work by Andrew Janke.
# This modified version is used with nihpd database.
#
# Mon Dec  3 13:30:08 EST 2001 - initial version
# May 1, 2002 - mods for NIHPD database louis 
# updated Nov 23 2003 - for more inclusion into nihpd Database
#
##############################
##script creates jpeg images of variouse mnc files. This is used for QC and debugging purposes only


$tilesize = 250; 

use Getopt::Tabular;
use pipeline_functions;
use MNI::FileUtilities qw(check_output_dirs);
use File::Basename;
$SIG{__DIE__} =  sub { &cleanup; die $_[0]; };


@bad_files = ("/data/nihpd/nihpd1/data/assembly/113627/1/mri/native/nihpd_113627_v1_unknown_9.mnc.gz", "/data/nihpd/nihpd1/data/assembly/313833/1/mri/native/nihpd_313833_v1_obj1_t2w_1.mnc.gz","/data/nihpd/nihpd1/data/assembly/356616/1/mri/native/nihpd_356616_v1_obj1_t1relx_27.mnc.gz");
$verbose = 0;
$clobber = 0;
$todo    = 'mnc';

@mp_options = ();

@opt_table = (
              ["-verbose", "boolean",  0,         \$verbose, "be verbose"                        ],
              ["-clobber", "boolean",  0,         \$clobber, "clobber existing check files"      ],
              );

# build the option table...
@checks = split("\n", `./pipeline_constants -checks`);

foreach (@checks){
   push(@opt_table, ["-$_", "const", $_, \$todo, "do $_ html check files" ]);
   }
   
# Check arguments
&GetOptions (\@opt_table, \@ARGV) || exit 1;
if($#ARGV < 0){ die "Usage: [options] <subject>\n" }
$subject_visit = $ARGV[0];

@mriid_list = pipeline_functions::get_selected_files($subject_visit, "mriid");


($subject, $visit) = split(":", $subject_visit);

$imgdir = `./pipeline_constants -imgdir`;
$outdir  =  "/data/ipl/ipl9/matthew/qcdir/${subject}_${visit}";
if (!-e $outdir)
{
    `mkdir $outdir`;
}
$tmpdir = "/var/tmp/${subject}_${visit}_check";
check_output_dirs($tmpdir);

chomp ($checkdir = pipeline_functions::get_checkdir_from_subject_visit($subject_visit));
check_output_dirs($checkdir);

@checks = split("\n", `./pipeline_constants -checks`);
 
foreach $todo(@checks)
{
    if($todo eq 'selected'){next;}

    if($todo eq 'mnc')
    {
	$select_criteria = "select concat_ws(' ',  complete_path, mriid) from mri where CandID = '$subject' and VisitNo = $visit and File_type = 'native'";
	@files = pipeline_functions::make_query($select_criteria);
    } 
    
    else
    {
	print("\nInput:$todo\n");
	@files =pipeline_functions::get_processed_files_from_mriid("complete_path, mriid", "final/${todo}", @mriid_list);
	print("\nOutput:@files\n\n");
    }
    
#    if($todo eq 'tal')
#    {
#	@table_types  =pipeline_functions::get_processed_files_from_mriid("complete_path, source_list", "final/$todo", @mriid_list);
#	( $tal_path,  $source_list) = split(" ", $table_types[0]);
#	$fallbackdir = dirname($tal_path);
#	$fallbackdir =~ s/final\/tal/work\/tmp/;
#	$outfile ="$fallbackdir\/T1.${source_list}.tal_fallback.mnc";
#	$out_line = "$outfile NA";
#	@files = (@files, $out_line);

#	print("OUTPUT @files\n\n\n");
#    }
    foreach $line(@files)
	
    {
	
	($infile, $mriid) = split(" ", $line);

	# check for a .gz
	if (!-e $infile || (grep(/$infile/, @bad_files))){
	    print("#############################################\nError, $infile does not exist or is corrupted\n\n");
	    next;
	}

	$file_name = `basename $infile`;
	$file_name =~ s/\.mnc\.gz/\.jpg/;
	chomp($file_name);
	$outfile = "$outdir/$file_name";
	if((!(-e $outfile)) || $clobber)
	{
	    print STDOUT "Doing $infile to $outfile\n";
	    $args = "montage -tile 1x3 -background grey10 ".
		"-geometry $tilesize"."x"."$tilesize+1+1 ";

	    if($todo eq 'tal_msk')
	    {
		@tal_file  =pipeline_functions::get_processed_files_from_mriid_scan_type("complete_path", "final/tal", 'obj1_t1w', @mriid_list);
		$mncfile = $tal_file[0];

		$mskfile = "$infile";
		print("m:$mncfile o:$mskfile\n\n");
		if (-e $mncfile && (-e $mskfile || -e "$mskfile.gz")) {
		    
		    system('minclookup', '-clobber', '-grey', '-range', 10, 120,
			   $mncfile, "$tmpdir/1.mnc") == 0 or die;
		    system('minclookup', '-clobber', '-lookup_table', "/home/bic/rotor/lib/luts/red",
			   $mskfile, "$tmpdir/2.mnc") == 0 or die;
		    system('mincmath', '-clobber', '-nocheck_dimensions','-max', "$tmpdir/1.mnc", 
			   "$tmpdir/2.mnc", "$tmpdir/out.mnc") == 0 or die;
		    
		    $infile = "$tmpdir/out.mnc";
		}            
	    }
	
	    if (-e $infile ){
		@cmd = ('mincpik', @mp_options, '-transverse', $infile, "$tmpdir/t.$mriid.miff"); 
		if ($verbose) { print STDOUT "@cmd \n"; }
		system( @cmd ) == 0 or die;
		
		@cmd = ('mincpik', @mp_options, '-sagittal',   $infile, "$tmpdir/s.$mriid.miff");
		if ($verbose) { print STDOUT "@cmd \n"; }
		system( @cmd ) == 0 or die;
		
		@cmd = ('mincpik', @mp_options, '-coronal',    $infile, "$tmpdir/c.$mriid.miff");
		if ($verbose) { print STDOUT "@cmd \n"; }
		system( @cmd ) == 0 or die;

		$args .= "$tmpdir/t.$mriid.miff $tmpdir/s.$mriid.miff $tmpdir/c.$mriid.miff ";
	    }
	    else{
		$args .= "$imgdir/missing.png $imgdir/missing.png $imgdir/missing.png ";
		print STDOUT "-X";
	    }
	    print STDOUT "\n";
	    
	    $args .= " MIFF:- | convert -box black -pen white ".
		"-draw \'text 35,4 \"$todo\"\' ".
		" MIFF:- $outfile\n";
	    
	    if ($verbose){ print $args; } 
	    system("$args") == 0 or die;
	}
	else{print("File $outfile exists. Use clobber to overwrite\n");}
    }
    
}

&cleanup;

sub cleanup {
  if($verbose){ print STDOUT "Cleaning up....\n"; }
  if(-e $tmpdir)
  {
      `rm -r $tmpdir`;
  }
}
