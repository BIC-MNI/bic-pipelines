#!/usr/local/bin/perl5 -w
#
# Matthew Kitching
#
use Getopt::Tabular;
use pipeline_functions;  
use MNI::FileUtilities qw(check_output_dirs);

chomp($me = `basename $0`);
$verbose = 0;
$clobber = 0;
chomp($version = `./pipeline_constants -version`);
$source_list = "";

@opt_table = (
              ["-verbose", "boolean",  0,         \$verbose, "be verbose"                        ],
              ["-clobber", "boolean",  0,         \$clobber, "clobber existing check files"      ],
	      ["-version", "string",  1,           \$version, "pipeline_version"      ],
	      ["-source_list", "string",  1,         \$source_list, "list of input mriid that made the file"      ],
              );

# Check arguments
&GetOptions (\@opt_table, \@ARGV) || exit 1;

if($#ARGV < 3){ die "Usage: $me [options]<subject_visit><file><File_type><scan_type>\n" }
$subject_visit = $ARGV[0];
$infile = $ARGV[1];
$abreviated_file_type = $ARGV[2];
$scan_type = $ARGV[3];

($subject, $visit) = split(":", $subject_visit);

if(($infile =~ /\.mnc/) && !($infile =~ /\.gz/))
{
    @args = ('gzip', '-f', $infile);
    if($verbose){ print STDOUT "@args\n"; }
    system(@args) == 0 or die;
    $infile .= ".gz";
}


$File_type = "final\/$abreviated_file_type";

chomp ($datadir = `./pipeline_constants -datadir`);
chomp ($checkdir = pipeline_functions::get_checkdir_from_subject_visit($subject_visit));

$destination_dir = $checkdir; $destination_dir =~ s/work\/check/$File_type/;
$coredir = $destination_dir; $coredir =~ s/\/$File_type//; $coredir =~ s/${datadir}\///;

if (-e $infile)
{
    
    chomp($File_base = `basename $infile`);
    $File_name = "nihpd_pipe_${version}_${subject}_${visit}_${File_base}";

    
    check_output_dirs($destination_dir);
 
    $destination_file = "$destination_dir\/$File_name";
    if (-e $destination_file)
    {
	print STDOUT "*** File $destination_file already in db... skipping\n"; 
    }
    else{
	print STDOUT "*** Inserting $infile into db\n";

	@args = ("/home/bic/jharlap/projects/neurodb/mri/register_minc_db", $infile, $datadir, $coredir, $File_type, $File_name, "''", $scan_type, $source_list, $version);
	print(@args) if $verbose;
	system(@args) == 0 or die;
	
    }
}

else{print("file $infile does not exist\n");}


            
