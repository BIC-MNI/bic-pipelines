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

#@mriid_list = pipeline_functions::get_selected_files($subject_visit, "mriid");
$imgdir  =  `~/data/qcdir`;

($subject, $visit) = split(":", $subject_visit);
$tmpdir = "/var/tmp/${subject}_${visit}_check";
check_output_dirs($tmpdir);

chomp ($checkdir = pipeline_functions::get_checkdir_from_subject_visit($subject_visit));
check_output_dirs($checkdir);

@checks = split("\n", `./pipeline_constants -all_checks`);
@checks = ('all');
foreach $todo(@checks)
{
    

    $select_criteria = "select concat_ws(' ',  complete_path, mriid, file_type, selected) from mri where CandID = '$subject' and VisitNo = $visit";



    #$select_criteria = "select concat_ws(' ',  complete_path, mriid, file_type, selected) from mri where CandID = '$subject' and VisitNo = $visit and (file_type = 'final/tal_msk_normalized' or file_type = 'final/nl1_msk_normalized')";
    @files = pipeline_functions::make_query($select_criteria);

  
    foreach $line(@files)	
    {
	($infile, $mriid, $file_type, $selected) = split(" ", $line);
	if($infile =~ /scout/){next;}
	if($infile =~/native/ && !$selected){next;}

	if($file_type =~ 'final/tal' || $file_type =~ 'final/nl1')
	{
	    $use_image_range = 1;
	    print("Using image range variable\n");
	}
	else{$use_image_range = 0;}
	

	# check for a .gz
	if (!-e $infile || (grep(/$infile/, @bad_files))){
	    print("#############################################\nError, $infile does not exist or is corrupted\n\n");
	    next;
	}
#	print("line $line\n\n");
#	print("file_type before:$file_type\n\n");
	$file_type =~ s/final\///;
#	print("file_type after:$file_type\n\n");
	print STDOUT "Doing  $infile\n";
	if($infile =~ /gz/)
	{
	    $tmpfile = "$tmpdir/tmp_$mriid.mnc.gz";
	    `cp $infile $tmpfile`;
	    `gunzip $tmpfile`;
	    $infile = $tmpfile;
	    $infile =~ s/\.gz//;
	}
	$outfile = "$checkdir/$mriid.jpg";
	if((!(-e $outfile)) || $clobber)
	{
	    
	    $args = "montage -tile 1x3 -background grey10 ".
		"-geometry $tilesize"."x"."$tilesize+1+1 ";

	
	    if (-e $infile ){
		@cmd = ('mincpik', @mp_options, '-transverse', $infile, "$tmpdir/t.$mriid.miff"); 
		if($use_image_range){@cmd= (@cmd, '-image_range', '20', '90');}
		if ($verbose) { print STDOUT "@cmd \n"; }
		system( @cmd ) == 0 or die;
		
		if($file_type eq 'native' || $file_type eq 'clp' || $file_type eq 'crp' || $file_type eq 'nuc' )
		{
		    print("Native_version\n");
		    @cmd = ('mincpik', @mp_options, '-sagittal',   $infile, "$tmpdir/s.$mriid.miff");	
		    if($use_image_range){@cmd= (@cmd, '-image_range', '20', '90');}
		    if ($verbose) { print STDOUT "@cmd \n"; }
		    system( @cmd ) == 0 or die;
		}
		else
		{
		    @cmd = ('mincpik', @mp_options, '-sagittal',   '-slice', '80', $infile, "$tmpdir/s.$mriid.miff");
		    if($use_image_range){@cmd= (@cmd, '-image_range', '20', '90');}
		    if ($verbose) { print STDOUT "@cmd \n"; }
		    system( @cmd ) == 0 or die;
		}
		@cmd = ('mincpik', @mp_options, '-coronal',    $infile, "$tmpdir/c.$mriid.miff");
		if($use_image_range){@cmd= (@cmd, '-image_range', '20', '90');}
		if ($verbose) { print STDOUT "@cmd \n"; }
		system( @cmd ) == 0 or die;

		$args .= "$tmpdir/t.$mriid.miff $tmpdir/s.$mriid.miff $tmpdir/c.$mriid.miff ";
	    }
	    else{
		$args .= "$imgdir/missing.png $imgdir/missing.png $imgdir/missing.png ";
		print STDOUT "-X";
	    }
	    print STDOUT "\n";
	    
	    $text = "${subject}_${visit} - ${file_type}";
	    
	   # $args .= " MIFF:- | convert -box black -font 7x13bold -pen white ".
	#	"-draw \'text 35,4 \"$text\"\' ".
	#	" MIFF:- $outfile\n";
#	   $args .= " MIFF:- | convert -box black -font 7x13bold -pen white -draw \'text 35,4 \"$text\"\' MIFF:- $outfile\n";


	    $args .= " MIFF:- | convert -box black -pen white ".
		"-draw \'text 35,4 \"$text\"\' ".
                " MIFF:- $outfile\n";
	    
	    print("outputing to $outfile\n");
	    if ($verbose){ print $args; } 
	    system("$args") == 0 or die;
	}
	else{print("File $outfile exists. Use clobber to overwrite\n");}

	if($infile =~ /$tmpdir/)
	{
	    `rm $infile`;
	}

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
