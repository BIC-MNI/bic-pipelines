# ------------------------------ MNI Header ----------------------------------
#@NAME       : NeuroDB::BVL
#@DESCRIPTION: Perform common tasks relating to uploaded behavioural instruments,
#              specifically for the NeuroDB system
#@EXPORT     : look at the @EXPORT line below ;P
#@EXPORT_OK  : none
#@EXPORT_TAGS: none
#@USES       : Exporter
#@REQUIRES   : 
#@VERSION    : $Id: BVL.pm,v 3.0 2004/03/25 20:32:15 jharlap Exp $
#@CREATED    : 2003/02/25, Jonathan Harlap (from the older upload_handler.pl)
#@MODIFIED   : 
#@COPYRIGHT  : Copyright (c) 2003 by Jonathan Harlap, McConnell Brain Imaging
#              Centre, Montreal Neurological Institute, McGill University.
#-----------------------------------------------------------------------------

package NeuroDB::BVL;

use Exporter ();
use NeuroDB::Mail;

$VERSION = 0.1;
@ISA = qw(Exporter);

@EXPORT = qw(db_determine_test error_mail happy_mail file_basename core_path queue_query run_queue cantab_verify cantab_imp carey_verify carey_determine_test carey_imp cbcl_verify cbcl_determine_test cbcl_imp cvlt2_verify cvlt2_imp cvltc_verify cvltc_imp das_verify das_imp dps4_verify dps4_imp disc_verify disc_imp psi_verify psi_imp wj3_verify wj3_imp global_queue);

@EXPORT_OK = qw(instrument_is_locked);

@global_queue = ();

# ------------------------------ MNI Header ----------------------------------
#@NAME       : db_determine_test
#@INPUT      : $CommentID, $dbhr (database handle reference)
#@OUTPUT     : 
#@RETURNS    : string test name
#@DESCRIPTION: Finds the name of the test associated with $CommentID
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 2003/03/25, Jonathan Harlap
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub db_determine_test {
    my ($CommentID, $dbhr) = @_;
    
    my $query = "SELECT Test_name FROM flag WHERE CommentID='$CommentID'";
    my $sth = $${dbhr}->prepare($query);
    $sth->execute();

    my $retval = 'unknown';
    if($sth->rows>0) {
        my @results = $sth->fetchrow_array();
        $retval = $results[0];
    }
    $sth->finish();

    return $retval;
}

# ------------------------------ MNI Header ----------------------------------
#@NAME       : parse_file_into_array
#@INPUT      : $file, $field_terminator, $line_terminator, $field_enclosed_by
#@OUTPUT     : 
#@RETURNS    : array of strings, one list element per row, string is
#              comma separated with surrounding quotes
#@DESCRIPTION: replaces LOAD DATA IN FILE by accepting the file and parameters
#              generating valid INSERT rows.
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 2003/10/23, Jonathan Harlap
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub parse_file_into_array {
    my ($file, $expected_num_fields, $field_terminator, $line_terminator, $field_enclosed_by) = @_;

    # load the entire file as one string
    my $contents;
    open FILE, $file;
    while(my $line = <FILE>) {
	$contents .= $line;
    }
    close FILE;

    # split the string into rows
    my @rows;
    if(defined($line_terminator)) {
	@rows = split(/$line_terminator/, $contents);
    } else {
	push @rows, $contents;
    }

    my @output;
    foreach my $row (@rows) {
	# split each row into fields
	my @fields = split(/$field_terminator/, $row);
	my @out_fields = ();

	foreach my $i (0..($expected_num_fields-1)) {
	    if(defined($field_enclosed_by)) {
		# clean the enclosures off of the fields
		$fields[$i] =~ s/^$field_enclosed_by//;
		$fields[$i] =~ s/$field_enclosed_by$//;
	    }
	    
	    # escape any single quotes, as we will be using single quotes for the inserts
	    $fields[$i] =~ s/'/\\'/g;

	    # nuke newline chars
	    $fields[$i] =~ s/\n/\\n/g;
	    $fields[$i] =~ s/\r//g;
	    
	    $out_fields[$i] = sprintf("'%s'", $fields[$i]);
	}
	
	push @output, join(",", @out_fields);
    }

    return @output;
}

# ------------------------------ MNI Header ----------------------------------
#@NAME       : error_mail
#@INPUT      : $psc (site name), message string, $test_type, $filename, database handle reference
#@OUTPUT     : 
#@RETURNS    : 
#@DESCRIPTION: Sends error messages to the site specified by $psc
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 2003/03/25, Jonathan Harlap
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub error_mail {
    my ($psc, $message, $test_type, $file_name, $dbhr) = @_;

    # check if we've already sent an error about this file.//
    my $sth = $${dbhr}->prepare("SELECT file_name FROM bvlup_skip WHERE psc='$psc' AND test_type='$test_type' AND file_name='$file_name' AND (message=".$${dbhr}->quote($message)." OR message='')");
    $sth->execute();

    # don't send a message if we already have once before
    return if $sth->rows > 0;
    $sth->finish();

    # register this error ( so it doesn't repeat! )
    $${dbhr}->do("INSERT INTO bvlup_skip (psc, test_type, file_name, message, skip_time) VALUES ('$psc', '$test_type', '$file_name', ".$${dbhr}->quote($message).", NOW())");

    my @to;
    my @cc;

    # continue assuming we haven't sent this error message before
    if($psc eq 'nihpdbo1' || $psc eq 'nihpdbo2') {
        @to = ('michael.rivkin@tch.harvard.edu','jacki.marmor@tch.harvard.edu');
    } elsif($psc eq 'nihpdcin') {
        @to = ('ball@athena.chmcc.org','wbommer@athena.chmcc.org','April.Ramsey@cchmc.org','miller@athena.cchmc.org');
    } elsif($psc eq 'nihpdhou') {
        @to = ('Kathleen.M.Hebert@uth.tmc.edu', 'Ashley.B.Cranford@uth.tmc.edu');
    } elsif($psc eq 'nihpdphi') {
        @to = ('wangd@email.chop.edu','lyonsa@email.chop.edu');
    } elsif($psc eq 'nihpdst1') {
        @to = ('botteronk@mir.wustl.edu','billw@twins.wustl.edu','mckinstryb@mir.wustl.edu');
    } elsif($psc eq 'nihpdst2') {
        @to = ('wilbera@msnotes.wustl.edu','almlir@msnotes.wustl.edu','mckinstryb@mir.wustl.edu');
    } elsif($psc eq 'nihpducl') {
        @to = ('jmccracken@mednet.ucla.edu','LHeinichen@mednet.ucla.edu');
    }

    push @cc, 'dmilovan@bic.mni.mcgill.ca';

    $message .= "\n\n-----\nThis is an automated message.  Please do not reply.  Direct questions to Alex Zijdenbos at alex\@bic.mni.mcgill.ca.\n";

    my $spooldir = '/data/nihpd/nihpd1/temp/bvlup_spool';
    
    my $CURDATE = `date +%Y%m%d`;
    open LOG, ">>$spooldir/$psc.errors.$CURDATE";
    print "MAIL to $psc: $message\n";
    print LOG "$message\n";
    close LOG;

    &NeuroDB::Mail::mail(\@to, 'Error in the upload of electronic tests', $message, \@cc);
}

# ------------------------------ MNI Header ----------------------------------
#@NAME       : happy mail
#@INPUT      : $psc (site name), message string
#@OUTPUT     : 
#@RETURNS    : 
#@DESCRIPTION: Spools messages to be sent to the site specified by $psc
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 2003/03/27, Jonathan Harlap
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub happy_mail {
    my ($psc, $message) = @_;

    my $spooldir = '/data/nihpd/nihpd1/temp/bvlup_spool';

    open SPOOL, ">>$spooldir/$psc.spool";
    print "MAIL to $psc (and denise): $message\n";
    print SPOOL "$message\n";
    close SPOOL;
}

# ------------------------------ MNI Header ----------------------------------
#@NAME       : instrument_is_locked
#@INPUT      : $CommentID for instrument to check and $dbhr (db handle ref)
#@OUTPUT     : 
#@RETURNS    : true if there exists no open feedback on this instrument, false otherwise
#@DESCRIPTION: checks if there is open feedback for an instrument
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 2003/03/25, Jonathan Harlap
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub instrument_is_locked {
    my ($CommentID, $dbhr) = @_;

    my $sth = $${dbhr}->prepare("SELECT COUNT(*) FROM feedback_bvl_thread WHERE CommentID='$CommentID' AND Active='Y' AND Status='opened'");
    $sth->execute();

    my @results = $sth->fetchrow_array();
    return 0 if($results[0] > 0);
    return 1;
}

# ------------------------------ MNI Header ----------------------------------
#@NAME       : file_basename
#@INPUT      : $file filename with full path
#@OUTPUT     : 
#@RETURNS    : string filename
#@DESCRIPTION: returns the last element of the / separated string $file
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 2003/03/25, Jonathan Harlap
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub file_basename {
    my ($file) = @_;
    my @bits = split(/\//, $file);
    my $filebase = $bits[$#bits];
    
    return $filebase;
}

# ------------------------------ MNI Header ----------------------------------
#@NAME       : core_path
#@INPUT      : hashref \%real_ids
#@OUTPUT     : 
#@RETURNS    : string core_path
#@DESCRIPTION: constructs a valid core path (DCCID/VisitNo/behavioural)
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 2003/03/25, Jonathan Harlap
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub core_path { my $real_ids = shift; return "$${real_ids{'CandID'}}/$${real_ids{'VisitNo'}}/behavioural"; }

# ------------------------------ MNI Header ----------------------------------
#@NAME       : queue_query
#@INPUT      : list of valid SQL queries to be run (inserts/updates/deletes only)
#@OUTPUT     : 
#@RETURNS    : 
#@DESCRIPTION: Queues the list of queries to be run (splits on ";\n")
#@METHOD     : 
#@GLOBALS    : @global_queue
#@CALLS      : 
#@CREATED    : 2003/03/25, Jonathan Harlap
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub queue_query {
    while(my $query = shift) {
        my @subqueries = split(";\n", $query);
        while(my $subquery = shift(@subqueries)) {
            push @global_queue, $subquery unless $subquery =~ /^\s*$/;
        }
    }
}

# ------------------------------ MNI Header ----------------------------------
#@NAME       : run_queue
#@INPUT      : $dbhr (database handle ref), $psc (site name)
#@OUTPUT     : 
#@RETURNS    : 
#@DESCRIPTION: Executes all queries in the queue
#@METHOD     : 
#@GLOBALS    : @global_queue
#@CALLS      : 
#@CREATED    : 2003/03/25, Jonathan Harlap
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub run_queue {
    my ($dbhr, $psc) = @_;
    #open OUTPUT, ">>/data/nihpd/nihpd1/temp/bvlup/$psc.sql";
    while(my $query = shift(@global_queue)) {
        # print "$query;\n";
        unless($query =~ /^(--)?\s*$/) {
            $${dbhr}->do($query) or die "MYSQL ERROR DURING \"$query\": ".$${dbhr}->errstr."\n";
        }
    }
    #close OUTPUT;
}

# ------------------------------ MNI Header ----------------------------------
#@NAME       : cantab_verify
#@INPUT      : $file (cantab html file), \%real_ids, $DATA_DIR, $dbhr (database handle reference)
#@OUTPUT     : 
#@RETURNS    : 1 or 0
#@DESCRIPTION: Verifies that the cantab $file can be imported
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 2003/03/25, Jonathan Harlap
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub cantab_verify { 
    my ($file, $real_ids, $DATA_DIR, $dbhr, $psc, $no_mail) = @_;
    if($file=~/\.htm$/i) {
        my $localfile;
        my %local_ids;
        open FILE, $file;
        while(<FILE>) {
            $localfile .= $_;
        }
        close FILE;

        $localfile =~ m(<TH>PSC-ID:</TH><TD>([a-zA-Z0-9]{7})</TD><TH>DCC-ID:</TH><TD>([0-9]{6}))m;
        $local_ids{'PSCID'} = lc($1);
        $local_ids{'CandID'} = $2 + 0;

        if($local_ids{'CandID'} == $$real_ids{'CandID'} && 
           $local_ids{'PSCID'} eq $$real_ids{'PSCID'} &&
           !($localfile =~ /<script.*>/im) &&
           $localfile =~ m(<TR><TH>Name:</TH><TD></TD>)im)
        {
            print "CANTAB OK\n";
            return 1;
        }

        # we're missing valid ids...
        &error_mail($psc, "Cantab file ".file_basename($file)." has an ID problem inside the file, please correct the IDs on this dataset, reexport and resend this data.", 'cantab', file_basename($file), $dbhr)
            if(($local_ids{'CandID'} != $$real_ids{'CandID'} 
               || $local_ids{'PSCID'} ne $$real_ids{'PSCID'})
               && !$no_mail
               );
        return -1;
    }
    return 0;
}

# ------------------------------ MNI Header ----------------------------------
#@NAME       : cantab_imp
#@INPUT      : $file (cantab file), \%real_ids, $DATA_DIR, $dbhr (database handle ref), $psc (site name)
#@OUTPUT     : 
#@RETURNS    : 
#@DESCRIPTION: Imports the data from the cantab file into the database
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 2003/03/25, Jonathan Harlap
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub cantab_imp {
    my ($file, $real_ids, $DATA_DIR, $dbhr, $psc, $no_mail) = @_;
    # settings
    my $new_subtest_marker = 'NEWSUBTESTMARKER!!!';
    
    my $localfile;
    open FILE, $file;
    while(<FILE>) {
        $localfile .= $_;
    }
    close FILE;
    
# check that there are no scripts or names
    if($localfile =~ /<script.*>/i) { 
        &error_mail($psc, "Cantab file ".file_basename($file)." was exported with the wrong settings: Please re-export and resend this data.  Make sure to choose \"Static HTML (*.htm; *.html)\" when doing \"Save as Type\".", 'cantab', file_basename($file), $dbhr) unless $no_mail;
        return;
    }
    
    unless($localfile =~ m(<TR><TH>Name:</TH><TD></TD>)i) {
        &error_mail($psc, "Cantab file ".file_basename($file)." has a name in it.  Please re-export and resend this data after removing any names.", 'cantab', file_basename($file), $dbhr) unless $no_mail;
        return;
    }
    
# nuke scripts and styles
    $localfile =~ s/<script.*>.*<\/script>//igm;
    $localfile =~ s/<style.*>.*<\/style>//igm;
    
# get ids and common vars
    ##### TODO: name: (PSC-ID=[a-zA-Z]{2}[a-zA-Z0-9]{1}[0-9]{4})? -> if empty, will that cause problems for $common_name?
    $localfile =~ m(<TABLE CLASS=subject><TR><TH>Name:</TH><TD></TD><TH>Age:</TH><TD>([0-9]+)</TD></TR><TR><TH>NART:</TH><TD>([0-9]+)</TD><TH>Sex:</TH><TD>([MF])</TD></TR><TR><TH>PSC-ID:</TH><TD>([a-zA-Z0-9]{7})</TD><TH>DCC-ID:</TH><TD>([0-9]{6})</TD></TR><TR><TH>Date:</TH><TD>([0-9]{1,2}/[0-9]{1,2}/[0-9]{2,4})</TD><TH>Time:</TH><TD>([0-9A-Z :]+)</TD></TR><TR><TH>Battery:</TH><TD>(nihp0)</TD><TH>Mode:</TH><TD>(Clinical)</TD></TR></TABLE>);
    
    #### my ($common_name, $common_age, $common_nart, $common_sex, $common_pscid, $common_dccid, $common_date, $common_time, $common_battery, $common_mode) = ($1, $2, $3, $4, $5, $6, $7, $8, $9);
    my ($common_age, $common_nart, $common_sex, $common_pscid, $common_dccid, $common_date, $common_time, $common_battery, $common_mode) = ($1, $2, $3, $4, $5, $6, $7, $8, $9);
    
# here is where we'll validate $dccid & $pscid vs. the filename & the db.
# ...
    
# replace head table with new subtest marker
    $localfile =~ s#<TABLE CLASS=subject><TR><TH>Name:</TH><TD></TD><TH>Age:</TH><TD>([0-9]+)</TD></TR><TR><TH>NART:</TH><TD>([0-9]+)</TD><TH>Sex:</TH><TD>([MF])</TD></TR><TR><TH>PSC-ID:</TH><TD>([a-zA-Z0-9]{7})</TD><TH>DCC-ID:</TH><TD>([0-9]{6})</TD></TR><TR><TH>Date:</TH><TD>([0-9]{1,2}/[0-9]{1,2}/[0-9]{2,4})</TD><TH>Time:</TH><TD>([0-9A-Z :]+)</TD></TR><TR><TH>Battery:</TH><TD>nihp0</TD><TH>Mode:</TH><TD>Clinical</TD></TR></TABLE>#$new_subtest_marker\n#igm;
    
# debug only
#print "Age: $age\nNART: $nart\nSex: $sex\nPSCID: $pscid\nDCCID: $dccid\nDate: $date\nTime: $time\n";
    
    
# nuke head
    $localfile =~ s/^.*<body>//igm;
    
# nuke hr's
    $localfile =~ s/<HR CLASS=pagebreak>//igm;
    
# keep warnings and summary/trial/etc lines
    $localfile =~ s/<P CLASS=warning>(.*?)<BR><\/P>/\nWARN $1\n/igm;
    $localfile =~ s/<P><H2>Summary<\/H2><P>/\nSummary\n/igm;
    $localfile =~ s/<H2>Trial by Trial Results<\/H2>/\nTrial by trial\n/igm;
    
# nuke all header cells
    $localfile =~ s/<th.*?>.*?<\/th>//igm;
    
# insert newline at row end
    $localfile =~ s/<\/tr>/\n/igm;
# nuke row tags
    $localfile =~ s/<tr.*?>//igm;
    
# cheap hacks to make it all work
    $localfile =~ s/<\/td><td>/,/igm;
    $localfile =~ s/<\/?STRONG>//igm;
    
# replace all sets of tags with a comma
    $localfile =~ s/(<.+?>)+/,/gm;
    
# get rid of commas at beginning and end of lines
    $localfile =~ s/^,//gm;
    $localfile =~ s/,$//gm;
    
# now we're good to parse...


    my %type_map;
    $type_map{'Intra/Extra Dimensional Set Shift'} = 'nedi';
    $type_map{'Big/Little Circle'} = 'larg';
    $type_map{'Spatial Working Memory'} = 'morm';
    $type_map{'Spatial Span'} = 'span';
    $type_map{'Motor Screening'} = 'mosc';
    
    my @blocks = reverse split(/$new_subtest_marker/, $localfile);
    my $block;
    my $first_block = 1;
    
    foreach $block (@blocks)
    {
        # split the block into lines
        my @lines = split(/\n/, $block);
        
        # identify subtest
        my $block_type = $lines[1];
        chomp($block_type);
        $block_type = $type_map{$block_type};
        
#        unless($first_block || $block_type) {
#            print "Failed handling block type '$block_type'\n";
#            return;
#        }
        
        # check for failure
        my $outcome = '';
        $outcome = $1 if $lines[2] =~ /^WARN Test (.*)$/;
        if($outcome eq '') {
            $outcome = 'Y';
        } elsif($outcome =~ /failed/) {
            $outcome = 'F';
        } elsif ($outcome =~ /not completed/) {
            $outcome = 'N';
        } elsif ($outcome =~ /aborted/) {
            $outcome = 'A';
        } else {
            $outcome = '';
        }
        
        # start subtest-specific blocks
        if($first_block) {
            # Update age/etc
            print "handling first block\n";
            
            # clean up date
            $common_date =~ /([0-9]{1,2})\/([0-9]{1,2})\/([0-9]{2,4})/;
            my ($day, $month, $year) = ($1+0, $2+0, $3+0);
            
            $day = "0$day" if $day<10;
            $month = "0$month" if $month<10;
            $year+=2000 if $year<100;
            my $date = "$year-$month-$day";
            my $filebase = &file_basename($file);
            my $update = "UPDATE cantab SET 
Age='$common_age',
NART='$common_nart',
Battery='$common_battery',
Mode='$common_mode',
Date_taken='$date',

Data_dir='".$DATA_DIR."',
Status='assembly',
Core_path='".&core_path($real_ids)."',
File_type='cantab',
File_name='$filebase'
WHERE CommentID='$${real_ids{'CommentID'}}';
";
            &queue_query($update);
            
            # fill in file references
            #-- ORIGINAL RESULT FILES 
            #File_nedi    varchar(200) not null,     -- intra/extra, .dat
            #File_larg    varchar(200) not null,     -- big/litle circle, .dat
            #File_morm    varchar(200) not null,     -- spatial working memory, .dat
            #File_span    varchar(200) not null,     -- spatial span, .dat
            #File_mosc    varchar(200) not null,     -- motor screening, .dat
            
        }
        
        if($block_type eq 'nedi') {
            # Intra/Extra Dimensional Set Shift
            print "handling nedi\n";
            
            my ($mode, $stage, @stages, @nedi_summary);
            foreach $i (2..$#lines) {
                my $line = $lines[$i];
                chomp($line);
                next if $line =~ /^$/;
                next if $line =~ /^WARN Test/;
                
                if($line =~ /(Summary|Trial by trial)/) {
                    $mode = $1;
                    next;
                }
                
                if($mode eq 'Summary') {
                    push @nedi_summary, $line;
                } elsif($mode eq 'Trial by trial') {
                    if($line =~ /Stage ([0-9]+) Shape/) {
                        $stage = $1;
                        push @stages, $stage;
                    } else {
                        push @{'Nedi_stage'.$stage}, $line;
                    }
                }
                
            }
            
            $update = "UPDATE cantab SET\nNedi_outcome='$outcome',\nNedi_original_dimension='$nedi_summary[0]',\nNedi_initial_shift='$nedi_summary[1]',\nNedi_stages_completed='$nedi_summary[2]'\n";
            
            $stage = 0;
            foreach $i (3..$#nedi_summary) {
                $stage++;
                next if $stage>10; #TODO: possibly remove this, in any case this should never actually happen.
                my $label = $stage;
                $label = '_all' if $i==$#nedi_summary;
                
                my @bits = split(/,/, $nedi_summary[$i]);
                $update .= ",Nedi_stage${label}_trial='$bits[0]',\nNedi_stage${label}_error='$bits[1]',\nNedi_stage${label}_latency='$bits[2]'\n";
            }
            
            $update .= "WHERE CommentID='$${real_ids{'CommentID'}}';\n";

            &queue_query("DELETE FROM cantab_nedi WHERE CommentID='$${real_ids{'CommentID'}}';");
            
            my $global_num = 1;
            foreach $stage (@stages) {
                my $local_num = 1;
                my $line;
                my $insert;
                foreach $line (@{'Nedi_stage'.$stage}) {
                    my @bits = split(/,/, $line);
                    next if $#bits==0;
                    $insert = "INSERT INTO cantab_nedi SET CommentID='$${real_ids{'CommentID'}}', Nedi_stage='$stage', Nedi_trial='$local_num', Nedi_order='$global_num', Nedi_response='$bits[0]', Nedi_shape='$bits[1]', Nedi_line='$bits[2]', Nedi_latency='$bits[3]';\n";
                    $local_num++;
                    $global_num++;
                    
                    #print $insert;
                    &queue_query($insert);
                }
            }
            
            #print $update;
            &queue_query($update);
            
        } elsif ($block_type eq 'larg') {
            # Big/Little Circle
            print "handling larg\n";
            
            my ($mode, @larg_summary, @larg_trial);
            my $set = 'Little Set 1';
            foreach $i (2..$#lines) {
                my $line = $lines[$i];
                chomp($line);
                
                $set = 'Big Set 2' if ($line =~ /^$/) && ($#larg_trial > 0);
                next if $line =~ /^$/;
                next if $line =~ /^WARN Test/;
                
                if($line =~ /(Summary|Trial by trial)/) {
                    $mode = $1;
                    next;
                }
                
                if($mode eq 'Summary') {
                    push @larg_summary, $line;
                } elsif($mode eq 'Trial by trial') {
                    push @larg_trial, $set.','.$line;
                }
                
            }
            
            
            $update = "UPDATE cantab SET\n";
            
            my @larg_summary_map = ('no', 'amean', 'gmean', 'stdev');
            my $row;
            foreach $row (0..4) {
                my $rowname = $larg_summary_map[$row];
                my @bits = split(/,/, $larg_summary[$row]);
                next if $#bits<5;
                $update .= "Larg_${rowname}_correct_left='${bits[0]}',\n";
                $update .= "Larg_${rowname}_correct_right='${bits[1]}',\n";
                $update .= "Larg_${rowname}_correct_total='${bits[2]}',\n";
                $update .= "Larg_${rowname}_incorrect_left='${bits[3]}',\n";
                $update .= "Larg_${rowname}_incorrect_right='${bits[4]}',\n";
                $update .= "Larg_${rowname}_incorrect_total='${bits[5]}',\n";
                
            }
            
            $update .= "Larg_outcome='$outcome' WHERE CommentID='$${real_ids{'CommentID'}}';\n";
            
            &queue_query("DELETE FROM cantab_larg WHERE CommentID='$${real_ids{'CommentID'}}';");

            my $local_num = 1;
            my $line;
            my $insert;
            foreach $line (@larg_trial) {
                my @bits = split(/,/, $line);
                next if $#bits<3;
                $insert = "INSERT INTO cantab_larg SET CommentID='$${real_ids{'CommentID'}}', Larg_set='$bits[0]', Larg_num='$local_num', Larg_response='$bits[1]', Larg_side='$bits[2]', Larg_latency='$bits[3]';\n";
                $local_num++;
                $local_num = 1 if $local_num == 21;
                
                #print $insert;
                &queue_query($insert);
            }
            
            #print $update;
            &queue_query($update);
            
            
        } elsif ($block_type eq 'morm') {
            # Spatial Working Memory
            print "handling morm\n";
            
            my ($mode, @morm_summary, @morm_trial, $set);
            my $local_num;
            foreach $i (2..$#lines) {
                my $line = $lines[$i];
                chomp($line);
                
                next if $line =~ /^$/;
                next if $line =~ /^WARN Test/;
                
                if($line =~ /^(Summary|Trial by trial)/) {
                    $mode = $1;
                    next;
                }
                
                if($mode eq 'Summary') {
                    push @morm_summary, $line;
                } elsif($mode eq 'Trial by trial') {
                    if($line =~ /^Set ([0-9]+)/) {
                        my $next_set = $1;
                        
                        $set = $next_set;
                        $local_num=0;
                    }
                    
                    push @morm_trial, "$set,$local_num,$line";
                    $local_num++;
                }
                
            }
            
            $update = "UPDATE cantab SET\n";
            
            my $row;
            foreach $row (0..4) {
                my $rowname = $row+1;
                my @bits = split(/,/, $morm_summary[$row]);
                next if $#bits<5;
                $update .= "Morm${rowname}_between='${bits[0]}',\n";
                $update .= "Morm${rowname}_within='${bits[1]}',\n";
                $update .= "Morm${rowname}_double='${bits[2]}',\n";
                $update .= "Morm${rowname}_actual='${bits[3]}',\n";
                $update .= "Morm${rowname}_optimal='${bits[4]}',\n";
                $update .= "Morm${rowname}_total='${bits[5]}',\n";
                
            }
            $update .= "Morm_strategy='". ($morm_summary[5]+0) ."',\n";
            
            $update .= "Morm_outcome='$outcome' WHERE CommentID='$${real_ids{'CommentID'}}';\n";
            
            &queue_query("DELETE FROM cantab_morm WHERE CommentID='$${real_ids{'CommentID'}}';");

            my $line;
            my $insert;
            foreach $line (@morm_trial) {
                my @bits = split(/,/, $line);
                next if $#bits<6;
                $insert = "INSERT INTO cantab_morm SET CommentID='$${real_ids{'CommentID'}}', Morm_set='$bits[0]', Morm_search='$bits[1]', Morm_between='$bits[2]', Morm_within='$bits[3]', Morm_double='$bits[4]', Morm_actual='$bits[5]', Morm_optimal='$bits[6]', Morm_boxes='$bits[7]', Morm_total='$bits[8]';\n";
                # fix Total lines
                $insert =~ s/Morm_search='[0-9]+'/Morm_search='Total'/ unless $insert =~ /Morm_total=''/;
                
                #print $insert;
                &queue_query($insert);
            }
            
            #print $update;
            &queue_query($update);
            
            
        } elsif ($block_type eq 'span') {
            # Spatial Span
            print "handling span\n";
            
            my ($mode, @span_trial);
            foreach $i (2..$#lines) {
                my $line = $lines[$i];
                chomp($line);
                
                next if $line =~ /^$/;
                next if $line =~ /^WARN Test/;
                
                
                if($line =~ /^(Practice Trials|Test Trials)/) {
                    $mode = $1;
                    next;
                }
                
                push @span_trial, "$mode,$line";
            }
            
            my @summary_lines = grep(/^Test Trials,[0-9]+,[0-9]+$/, @span_trial);
            my @summary_bits = split(/,/, $summary_lines[0]);
            $update = "UPDATE cantab SET Span_placement_errors='${summary_bits[1]}',\nSpan_box_errors='${summary_bits[2]}',\nSpan_outcome='$outcome'\nWHERE CommentID='$${real_ids{'CommentID'}}';\n";
            
            &queue_query("DELETE FROM cantab_span WHERE CommentID='$${real_ids{'CommentID'}}';");

            my $line;
            my $insert;
            foreach $line (@span_trial) {
                my @bits = split(/,/, $line);
                next if $#bits<5;
                $insert = "INSERT INTO cantab_span SET CommentID='$${real_ids{'CommentID'}}', Span_type='$bits[0]', Span_time='$bits[1]', Span_length='$bits[2]', Span_placement='$bits[3]', Span_box='$bits[4]', Span_position='$bits[5]', Span_response='$bits[6]';\n";
                
                #print $insert;
                &queue_query($insert);
            }
            
            #print $update;
            &queue_query($update);
            
            
        } elsif ($block_type eq 'mosc') {
            # Motor Screening
            print "handling mosc\n";
            
            my (@mosc_summary, @mosc_trial);
            my $cross = 0;
            
            foreach $i (2..$#lines) {
                my $line = $lines[$i];
                chomp($line);
                
                next if $line =~ /^$/;
                next if $line =~ /^WARN Test/;
                
                $cross++;
                if($cross>10) {
                    push @mosc_summary, $line;
                } else {
                    push @mosc_trial, "$cross,$line";
                }
            }
            
            $update = "UPDATE cantab SET\n";
            
            my $i;
            my @i_map = ('amean', 'gmean', 'stdev');
            foreach $i (0..2) {
                my @bits = split(/,/, $mosc_summary[$i]);
                $update .= "Mosc_${i_map[$i]}_latency='$bits[0]',\nMosc_${i_map[$i]}_error='$bits[1]',\n";
            }
            $update .= "Mosc_outcome='$outcome' WHERE CommentID='$${real_ids{'CommentID'}}';\n";
            
            &queue_query("DELETE FROM cantab_mosc WHERE CommentID='$${real_ids{'CommentID'}}';");

            my $line;
            my $insert;
            foreach $line (@mosc_trial) {
                my @bits = split(/,/, $line);
                next if $#bits<2;
                $insert = "INSERT INTO cantab_mosc SET CommentID='$${real_ids{'CommentID'}}', Mosc_cross='$bits[0]', Mosc_latency='$bits[1]', Mosc_error='$bits[2]';\n";
                
                #print $insert;
                &queue_query($insert);
            }
            
            #print $update;
            &queue_query($update);
            
            
            
        } else {
            print "unknown subtest!\n";
        }
        
        $first_block = 0;
    }
    #&run_queue(\$dbh);
}

# ------------------------------ MNI Header ----------------------------------
#@NAME       : carey_verify
#@INPUT      : $file (carey file), \%real_ids, $DATA_DIR, $dbhr (database handle reference), $psc
#@OUTPUT     : 
#@RETURNS    : 1 or 0
#@DESCRIPTION: Verifies that the carey $file can be imported
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 2003/03/25, Jonathan Harlap
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub carey_verify {
    my ($file, $real_ids, $DATA_DIR, $dbhr, $psc, $no_mail) = @_;
    return 0 unless $file=~/\.txt$/i;

    my $max_lines = 10;
    my %local_ids;
    my $i;
    my @lines;

    open FILE, $file;

    foreach $i (0..9) {
        my $line = <FILE>;
        $line =~ s/[\r\n]//g;
        push @lines, $line;
    }
    close FILE;

    $local_ids{'CandID'} = $lines[1] + 0;
    $local_ids{'PSCID'} = lc($lines[8]);

    if($local_ids{'CandID'} == $$real_ids{'CandID'} && 
       $local_ids{'PSCID'} eq $$real_ids{'PSCID'})
    {
        # insert some logic here to indicate what $which_carey_test should be
        # each of the carey tests is different in # of questions, so we have to 
        # first define $which_carey_test the kid took, and then use the appropriate
        # script
        
        $which_carey_test = &carey_determine_test($file, $real_ids);
        $db_which_carey_test = &db_determine_test($$real_ids{'CommentID'}, $dbhr);
        print "CAREY: $which_carey_test | $db_which_carey_test identified\n";
        
        if($which_carey_test ne $db_which_carey_test)
        { &error_mail($psc, "Carey file $file is the wrong carey ($which_carey_test instead of $db_which_carey_test)", 'carey', file_basename($file), $dbhr) unless $no_mail; return -1; }
        if($which_carey_test eq 'unknown')
        { &error_mail($psc, "Carey file $file is a corrupted carey, or some unknown carey type.", 'carey', file_basename($file), $dbhr) unless $no_mail; return -1;}
        
        # if we got here, then the test type is all good
        return 1;
    }

    # we're missing valid ids...
    &error_mail($psc, "Carey file ".file_basename($file)." has an ID problem inside the file, please correct the IDs on this dataset, reexport and resend this data.", 'carey', file_basename($file), $dbhr) unless $no_mail;

    return -1;
}


# ------------------------------ MNI Header ----------------------------------
#@NAME       : carey_determine_test
#@INPUT      : $file (carey file), \%real_ids, $DATA_DIR
#@OUTPUT     : 
#@RETURNS    : 
#@DESCRIPTION: Determines which of the carey tests the given file is
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 2003/03/25, Jonathan Harlap
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub carey_determine_test {
    my ($file, $real_ids, $DATA_DIR) = @_;
#bsq = 110
#ritq = 105
#eitq = 86
#tts = 107
# (add 9 lines for header to all test)

    $lines = `cat $file | wc -l` + 0;
    return 'carey_bsq' if $lines==119;
    return 'carey_ritq' if $lines==114;
    return 'carey_eitq' if $lines==95;
    return 'carey_tts' if $lines==116;
    return 'unknown';
}

# ------------------------------ MNI Header ----------------------------------
#@NAME       : carey_imp
#@INPUT      : $file (carey file), \%real_ids, $DATA_DIR, $dbhr (database handle ref), $psc (site name)
#@OUTPUT     : 
#@RETURNS    : 
#@DESCRIPTION: Imports the data from the carey file into the database
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 2003/03/25, Jonathan Harlap
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub carey_imp {
    my ($file, $real_ids, $DATA_DIR, $dbhr, $psc, $no_mail) = @_;

    # insert some logic here to indicate what $which_carey_test should be
    # each of the carey tests is different in # of questions, so we have to 
    # first define $which_carey_test the kid took, and then use the appropriate
    # script

    $which_carey_test = &carey_determine_test($file, $real_ids);
    
    my $core_path = &core_path($real_ids);
    my $file_base = &file_basename($file);

    if($which_carey_test eq 'carey_bsq'){

        &queue_query(q(CREATE TEMPORARY TABLE IF NOT EXISTS import_test_carey_bsq(

ID        tinyint(3) unsigned not null, 
DCCID	  int(6) not null,
Unknown1  varchar(7) not null, 
DoB	  date not null,
Empty1	  varchar(15) not null,
Unknown2  varchar(7) not null,
Empty2    varchar(15) not null,
DoT       date not null,
PSCID     char(7) not null,

Q1 char(1) not null, 
Q2 char(1) not null, 
Q3 char(1) not null, 
Q4 char(1) not null, 
Q5 char(1) not null, 
Q6 char(1) not null, 
Q7 char(1) not null, 
Q8 char(1) not null, 
Q9 char(1) not null, 
Q10 char(1) not null, 

Q11 char(1) not null, 
Q12 char(1) not null, 
Q13 char(1) not null, 
Q14 char(1) not null, 
Q15 char(1) not null, 
Q16 char(1) not null, 
Q17 char(1) not null, 
Q18 char(1) not null, 
Q19 char(1) not null, 
Q20 char(1) not null, 

Q21 char(1) not null, 
Q22 char(1) not null, 
Q23 char(1) not null, 
Q24 char(1) not null, 
Q25 char(1) not null, 
Q26 char(1) not null, 
Q27 char(1) not null, 
Q28 char(1) not null, 
Q29 char(1) not null, 
Q30 char(1) not null, 

Q31 char(1) not null, 
Q32 char(1) not null, 
Q33 char(1) not null, 
Q34 char(1) not null, 
Q35 char(1) not null, 
Q36 char(1) not null, 
Q37 char(1) not null, 
Q38 char(1) not null, 
Q39 char(1) not null, 
Q40 char(1) not null, 

Q41 char(1) not null, 
Q42 char(1) not null, 
Q43 char(1) not null, 
Q44 char(1) not null, 
Q45 char(1) not null, 
Q46 char(1) not null, 
Q47 char(1) not null, 
Q48 char(1) not null, 
Q49 char(1) not null, 
Q50 char(1) not null, 

Q51 char(1) not null, 
Q52 char(1) not null, 
Q53 char(1) not null, 
Q54 char(1) not null, 
Q55 char(1) not null, 
Q56 char(1) not null, 
Q57 char(1) not null, 
Q58 char(1) not null, 
Q59 char(1) not null, 
Q60 char(1) not null, 

Q61 char(1) not null, 
Q62 char(1) not null, 
Q63 char(1) not null, 
Q64 char(1) not null, 
Q65 char(1) not null, 
Q66 char(1) not null, 
Q67 char(1) not null, 
Q68 char(1) not null, 
Q69 char(1) not null, 
Q70 char(1) not null, 

Q71 char(1) not null, 
Q72 char(1) not null, 
Q73 char(1) not null, 
Q74 char(1) not null, 
Q75 char(1) not null, 
Q76 char(1) not null, 
Q77 char(1) not null, 
Q78 char(1) not null, 
Q79 char(1) not null, 
Q80 char(1) not null, 

Q81 char(1) not null, 
Q82 char(1) not null, 
Q83 char(1) not null, 
Q84 char(1) not null, 
Q85 char(1) not null, 
Q86 char(1) not null, 
Q87 char(1) not null, 
Q88 char(1) not null, 
Q89 char(1) not null, 
Q90 char(1) not null, 

Q91 char(1) not null, 
Q92 char(1) not null, 
Q93 char(1) not null, 
Q94 char(1) not null, 
Q95 char(1) not null, 
Q96 char(1) not null, 
Q97 char(1) not null, 
Q98 char(1) not null, 
Q99 char(1) not null, 
Q100 char(1) not null, 

Q101 char(1) not null, 
Q102 char(1) not null, 
Q103 char(1) not null, 
Q104 char(1) not null, 
Q105 char(1) not null, 
Q106 char(1) not null, 
Q107 char(1) not null, 
Q108 char(1) not null, 
Q109 char(1) not null, 
Q110 char(1) not null 

)
;

DELETE FROM import_test_carey_bsq;

LOAD DATA INFILE ").$file.q(" 
    INTO TABLE import_test_carey_bsq
    FIELDS
        TERMINATED BY '\n'
;

SELECT @dccid:=DCCID, @pscid:=PSCID, @dot:= DoT, 
       @q1:=Q1, @q2:=Q2, @q3:=Q3, @q4:=Q4, @q5:=Q5, @q6:=Q6, @q7:=Q7, @q8:=Q8, @q9:=Q9, @q10:=Q10, 
       @q11:=Q11, @q12:=Q12, @q13:=Q13, @q14:=Q14, @q15:=Q15, @q16:=Q16, @q17:=Q17, @q18:=Q18, @q19:=Q19, @q20:=Q20, 
       @q21:=Q21, @q22:=Q22, @q23:=Q23, @q24:=Q24, @q25:=Q25, @q26:=Q26, @q27:=Q27, @q28:=Q28, @q29:=Q29, @q30:=Q30, 
       @q31:=Q31, @q32:=Q32, @q33:=Q33, @q34:=Q34, @q35:=Q35, @q36:=Q36, @q37:=Q37, @q38:=Q38, @q39:=Q39, @q40:=Q40, 
       @q41:=Q41, @q42:=Q42, @q43:=Q43, @q44:=Q44, @q45:=Q45, @q46:=Q46, @q47:=Q47, @q48:=Q48, @q49:=Q49, @q50:=Q50, 
       @q51:=Q51, @q52:=Q52, @q53:=Q53, @q54:=Q54, @q55:=Q55, @q56:=Q56, @q57:=Q57, @q58:=Q58, @q59:=Q59, @q60:=Q60, 
       @q61:=Q61, @q62:=Q62, @q63:=Q63, @q64:=Q64, @q65:=Q65, @q66:=Q66, @q67:=Q67, @q68:=Q68, @q69:=Q69, @q70:=Q70, 
       @q71:=Q71, @q72:=Q72, @q73:=Q73, @q74:=Q74, @q75:=Q75, @q76:=Q76, @q77:=Q77, @q78:=Q78, @q79:=Q79, @q80:=Q80, 
       @q81:=Q81, @q82:=Q82, @q83:=Q83, @q84:=Q84, @q85:=Q85, @q86:=Q86, @q87:=Q87, @q88:=Q88, @q89:=Q89, @q90:=Q90, 
       @q91:=Q91, @q92:=Q92, @q93:=Q93, @q94:=Q94, @q95:=Q95, @q96:=Q96, @q97:=Q97, @q98:=Q98, @q99:=Q99, @q100:=Q100, 
       @q101:=Q101, @q102:=Q102, @q103:=Q103, @q104:=Q104, @q105:=Q105, @q106:=Q106, @q107:=Q107, @q108:=Q108, @q109:=Q109, @q110:=Q110 
FROM import_test_carey_bsq
;

UPDATE carey_bsq SET 
       Q1=@q1, Q2=@q2, Q3=@q3, Q4=@q4, Q5=@q5, Q6=@q6, Q7=@q7, Q8=@q8, Q9=@q9, Q10=@q10, 
       Q11=@q11, Q12=@q12, Q13=@q13, Q14=@q14, Q15=@q15, Q16=@q16, Q17=@q17, Q18=@q18, Q19=@q19, Q20=@q20, 
       Q21=@q21, Q22=@q22, Q23=@q23, Q24=@q24, Q25=@q25, Q26=@q26, Q27=@q27, Q28=@q28, Q29=@q29, Q30=@q30, 
       Q31=@q31, Q32=@q32, Q33=@q33, Q34=@q34, Q35=@q35, Q36=@q36, Q37=@q37, Q38=@q38, Q39=@q39, Q40=@q40, 
       Q41=@q41, Q42=@q42, Q43=@q43, Q44=@q44, Q45=@q45, Q46=@q46, Q47=@q47, Q48=@q48, Q49=@q49, Q50=@q50, 
       Q51=@q51, Q52=@q52, Q53=@q53, Q54=@q54, Q55=@q55, Q56=@q56, Q57=@q57, Q58=@q58, Q59=@q59, Q60=@q60, 
       Q61=@q61, Q62=@q62, Q63=@q63, Q64=@q64, Q65=@q65, Q66=@q66, Q67=@q67, Q68=@q68, Q69=@q69, Q70=@q70, 
       Q71=@q71, Q72=@q72, Q73=@q73, Q74=@q74, Q75=@q75, Q76=@q76, Q77=@q77, Q78=@q78, Q79=@q79, Q80=@q80, 
       Q81=@q81, Q82=@q82, Q83=@q83, Q84=@q84, Q85=@q85, Q86=@q86, Q87=@q87, Q88=@q88, Q89=@q89, Q90=@q90, 
       Q91=@q91, Q92=@q92, Q93=@q93, Q94=@q94, Q95=@q95, Q96=@q96, Q97=@q97, Q98=@q98, Q99=@q99, Q100=@q100, 
       Q101=@q101, Q102=@q102, Q103=@q103, Q104=@q104, Q105=@q105, Q106=@q106, Q107=@q107, Q108=@q108, Q109=@q109, Q110=@q110, Date_taken=@dot    
WHERE CommentID=)."'$${real_ids{'CommentID'}}'
;
UPDATE carey_bsq Set
      Data_dir = '".$DATA_DIR."',
      Status = 'assembly',
      Core_path = '$core_path',
      File_type = 'carey',
      File_name = '$file_base'
WHERE CommentID='$${real_ids{'CommentID'}}';");

        #&run_queue(\$dbh);

    } elsif($which_carey_test eq 'carey_ritq'){

        &queue_query(q(CREATE TEMPORARY TABLE IF NOT EXISTS import_test_carey_ritq(

ID        tinyint(3) unsigned not null, 
DCCID	  int(6) not null,
Unknown1  varchar(7) not null, 
DoB	  date not null,
Empty1	  varchar(15) not null,
Unknown2  varchar(7) not null,
Empty2    varchar(15) not null,
DoT       date not null,
PSCID     char(7) not null,

Q1 char(1) not null, 
Q2 char(1) not null, 
Q3 char(1) not null, 
Q4 char(1) not null, 
Q5 char(1) not null, 
Q6 char(1) not null, 
Q7 char(1) not null, 
Q8 char(1) not null, 
Q9 char(1) not null, 
Q10 char(1) not null, 

Q11 char(1) not null, 
Q12 char(1) not null, 
Q13 char(1) not null, 
Q14 char(1) not null, 
Q15 char(1) not null, 
Q16 char(1) not null, 
Q17 char(1) not null, 
Q18 char(1) not null, 
Q19 char(1) not null, 
Q20 char(1) not null, 

Q21 char(1) not null, 
Q22 char(1) not null, 
Q23 char(1) not null, 
Q24 char(1) not null, 
Q25 char(1) not null, 
Q26 char(1) not null, 
Q27 char(1) not null, 
Q28 char(1) not null, 
Q29 char(1) not null, 
Q30 char(1) not null, 

Q31 char(1) not null, 
Q32 char(1) not null, 
Q33 char(1) not null, 
Q34 char(1) not null, 
Q35 char(1) not null, 
Q36 char(1) not null, 
Q37 char(1) not null, 
Q38 char(1) not null, 
Q39 char(1) not null, 
Q40 char(1) not null, 

Q41 char(1) not null, 
Q42 char(1) not null, 
Q43 char(1) not null, 
Q44 char(1) not null, 
Q45 char(1) not null, 
Q46 char(1) not null, 
Q47 char(1) not null, 
Q48 char(1) not null, 
Q49 char(1) not null, 
Q50 char(1) not null, 

Q51 char(1) not null, 
Q52 char(1) not null, 
Q53 char(1) not null, 
Q54 char(1) not null, 
Q55 char(1) not null, 
Q56 char(1) not null, 
Q57 char(1) not null, 
Q58 char(1) not null, 
Q59 char(1) not null, 
Q60 char(1) not null, 

Q61 char(1) not null, 
Q62 char(1) not null, 
Q63 char(1) not null, 
Q64 char(1) not null, 
Q65 char(1) not null, 
Q66 char(1) not null, 
Q67 char(1) not null, 
Q68 char(1) not null, 
Q69 char(1) not null, 
Q70 char(1) not null, 

Q71 char(1) not null, 
Q72 char(1) not null, 
Q73 char(1) not null, 
Q74 char(1) not null, 
Q75 char(1) not null, 
Q76 char(1) not null, 
Q77 char(1) not null, 
Q78 char(1) not null, 
Q79 char(1) not null, 
Q80 char(1) not null, 

Q81 char(1) not null, 
Q82 char(1) not null, 
Q83 char(1) not null, 
Q84 char(1) not null, 
Q85 char(1) not null, 
Q86 char(1) not null, 
Q87 char(1) not null, 
Q88 char(1) not null, 
Q89 char(1) not null, 
Q90 char(1) not null, 

Q91 char(1) not null, 
Q92 char(1) not null, 
Q93 char(1) not null, 
Q94 char(1) not null, 
Q95 char(1) not null, 
Q96 char(1) not null, 
Q97 char(1) not null, 
Q98 char(1) not null, 
Q99 char(1) not null, 
Q100 char(1) not null, 

Q101 char(1) not null, 
Q102 char(1) not null, 
Q103 char(1) not null, 
Q104 char(1) not null, 
Q105 char(1) not null

)
;

DELETE FROM import_test_carey_ritq;

LOAD DATA INFILE ")."$file".q(" 
    INTO TABLE import_test_carey_ritq
    FIELDS
        TERMINATED BY '\n'
;

SELECT @dccid:=DCCID, @pscid:=PSCID, @dot:= DoT, 
       @q1:=Q1, @q2:=Q2, @q3:=Q3, @q4:=Q4, @q5:=Q5, @q6:=Q6, @q7:=Q7, @q8:=Q8, @q9:=Q9, @q10:=Q10, 
       @q11:=Q11, @q12:=Q12, @q13:=Q13, @q14:=Q14, @q15:=Q15, @q16:=Q16, @q17:=Q17, @q18:=Q18, @q19:=Q19, @q20:=Q20, 
       @q21:=Q21, @q22:=Q22, @q23:=Q23, @q24:=Q24, @q25:=Q25, @q26:=Q26, @q27:=Q27, @q28:=Q28, @q29:=Q29, @q30:=Q30, 
       @q31:=Q31, @q32:=Q32, @q33:=Q33, @q34:=Q34, @q35:=Q35, @q36:=Q36, @q37:=Q37, @q38:=Q38, @q39:=Q39, @q40:=Q40, 
       @q41:=Q41, @q42:=Q42, @q43:=Q43, @q44:=Q44, @q45:=Q45, @q46:=Q46, @q47:=Q47, @q48:=Q48, @q49:=Q49, @q50:=Q50, 
       @q51:=Q51, @q52:=Q52, @q53:=Q53, @q54:=Q54, @q55:=Q55, @q56:=Q56, @q57:=Q57, @q58:=Q58, @q59:=Q59, @q60:=Q60, 
       @q61:=Q61, @q62:=Q62, @q63:=Q63, @q64:=Q64, @q65:=Q65, @q66:=Q66, @q67:=Q67, @q68:=Q68, @q69:=Q69, @q70:=Q70, 
       @q71:=Q71, @q72:=Q72, @q73:=Q73, @q74:=Q74, @q75:=Q75, @q76:=Q76, @q77:=Q77, @q78:=Q78, @q79:=Q79, @q80:=Q80, 
       @q81:=Q81, @q82:=Q82, @q83:=Q83, @q84:=Q84, @q85:=Q85, @q86:=Q86, @q87:=Q87, @q88:=Q88, @q89:=Q89, @q90:=Q90, 
       @q91:=Q91, @q92:=Q92, @q93:=Q93, @q94:=Q94, @q95:=Q95, @q96:=Q96, @q97:=Q97, @q98:=Q98, @q99:=Q99, @q100:=Q100, 
       @q101:=Q101, @q102:=Q102, @q103:=Q103, @q104:=Q104, @q105:=Q105
FROM import_test_carey_ritq
;

UPDATE carey_ritq SET Q1=@q1, Q2=@q2, Q3=@q3, Q4=@q4, Q5=@q5, Q6=@q6, Q7=@q7, Q8=@q8, Q9=@q9, Q10=@q10, 
       Q11=@q11, Q12=@q12, Q13=@q13, Q14=@q14, Q15=@q15, Q16=@q16, Q17=@q17, Q18=@q18, Q19=@q19, Q20=@q20, 
       Q21=@q21, Q22=@q22, Q23=@q23, Q24=@q24, Q25=@q25, Q26=@q26, Q27=@q27, Q28=@q28, Q29=@q29, Q30=@q30, 
       Q31=@q31, Q32=@q32, Q33=@q33, Q34=@q34, Q35=@q35, Q36=@q36, Q37=@q37, Q38=@q38, Q39=@q39, Q40=@q40, 
       Q41=@q41, Q42=@q42, Q43=@q43, Q44=@q44, Q45=@q45, Q46=@q46, Q47=@q47, Q48=@q48, Q49=@q49, Q50=@q50, 
       Q51=@q51, Q52=@q52, Q53=@q53, Q54=@q54, Q55=@q55, Q56=@q56, Q57=@q57, Q58=@q58, Q59=@q59, Q60=@q60, 
       Q61=@q61, Q62=@q62, Q63=@q63, Q64=@q64, Q65=@q65, Q66=@q66, Q67=@q67, Q68=@q68, Q69=@q69, Q70=@q70, 
       Q71=@q71, Q72=@q72, Q73=@q73, Q74=@q74, Q75=@q75, Q76=@q76, Q77=@q77, Q78=@q78, Q79=@q79, Q80=@q80, 
       Q81=@q81, Q82=@q82, Q83=@q83, Q84=@q84, Q85=@q85, Q86=@q86, Q87=@q87, Q88=@q88, Q89=@q89, Q90=@q90, 
       Q91=@q91, Q92=@q92, Q93=@q93, Q94=@q94, Q95=@q95, Q96=@q96, Q97=@q97, Q98=@q98, Q99=@q99, Q100=@q100, 
       Q101=@q101, Q102=@q102, Q103=@q103, Q104=@q104, Q105=@q105, Date_taken=@dot
WHERE CommentID=)."'$${real_ids{'CommentID'}}'
;
UPDATE carey_ritq SET
      Data_dir = '".$DATA_DIR."',
      Status = 'assembly',
      Core_path = '$core_path',
      File_type = 'carey',
      File_name = '$file_base'
WHERE CommentID='$${real_ids{'CommentID'}}';");
        #&run_queue(\$dbh);

    } elsif($which_carey_test eq 'carey_eitq'){

        &queue_query(q(CREATE TEMPORARY TABLE IF NOT EXISTS import_test_carey_eitq(

ID        tinyint(3) unsigned not null, 
DCCID	  int(6) not null,
Unknown1  varchar(7) not null, 
DoB	  date not null,
Empty1	  varchar(15) not null,
Unknown2  varchar(7) not null,
Empty2    varchar(15) not null,
DoT       date not null,
PSCID     char(7) not null,

Q1 char(1) not null, 
Q2 char(1) not null, 
Q3 char(1) not null, 
Q4 char(1) not null, 
Q5 char(1) not null, 
Q6 char(1) not null, 
Q7 char(1) not null, 
Q8 char(1) not null, 
Q9 char(1) not null, 
Q10 char(1) not null, 

Q11 char(1) not null, 
Q12 char(1) not null, 
Q13 char(1) not null, 
Q14 char(1) not null, 
Q15 char(1) not null, 
Q16 char(1) not null, 
Q17 char(1) not null, 
Q18 char(1) not null, 
Q19 char(1) not null, 
Q20 char(1) not null, 

Q21 char(1) not null, 
Q22 char(1) not null, 
Q23 char(1) not null, 
Q24 char(1) not null, 
Q25 char(1) not null, 
Q26 char(1) not null, 
Q27 char(1) not null, 
Q28 char(1) not null, 
Q29 char(1) not null, 
Q30 char(1) not null, 

Q31 char(1) not null, 
Q32 char(1) not null, 
Q33 char(1) not null, 
Q34 char(1) not null, 
Q35 char(1) not null, 
Q36 char(1) not null, 
Q37 char(1) not null, 
Q38 char(1) not null, 
Q39 char(1) not null, 
Q40 char(1) not null, 

Q41 char(1) not null, 
Q42 char(1) not null, 
Q43 char(1) not null, 
Q44 char(1) not null, 
Q45 char(1) not null, 
Q46 char(1) not null, 
Q47 char(1) not null, 
Q48 char(1) not null, 
Q49 char(1) not null, 
Q50 char(1) not null, 

Q51 char(1) not null, 
Q52 char(1) not null, 
Q53 char(1) not null, 
Q54 char(1) not null, 
Q55 char(1) not null, 
Q56 char(1) not null, 
Q57 char(1) not null, 
Q58 char(1) not null, 
Q59 char(1) not null, 
Q60 char(1) not null, 

Q61 char(1) not null, 
Q62 char(1) not null, 
Q63 char(1) not null, 
Q64 char(1) not null, 
Q65 char(1) not null, 
Q66 char(1) not null, 
Q67 char(1) not null, 
Q68 char(1) not null, 
Q69 char(1) not null, 
Q70 char(1) not null, 

Q71 char(1) not null, 
Q72 char(1) not null, 
Q73 char(1) not null, 
Q74 char(1) not null, 
Q75 char(1) not null, 
Q76 char(1) not null, 
Q77 char(1) not null, 
Q78 char(1) not null, 
Q79 char(1) not null, 
Q80 char(1) not null, 

Q81 char(1) not null, 
Q82 char(1) not null, 
Q83 char(1) not null, 
Q84 char(1) not null, 
Q85 char(1) not null, 
Q86 char(1) not null

)
;

DELETE FROM import_test_carey_eitq;

LOAD DATA INFILE ")."$file".q(" 
    INTO TABLE import_test_carey_eitq
    FIELDS
        TERMINATED BY '\n'
;

SELECT @dccid:=DCCID, @pscid:=PSCID, @dot:= DoT, 
       @q1:=Q1, @q2:=Q2, @q3:=Q3, @q4:=Q4, @q5:=Q5, @q6:=Q6, @q7:=Q7, @q8:=Q8, @q9:=Q9, @q10:=Q10, 
       @q11:=Q11, @q12:=Q12, @q13:=Q13, @q14:=Q14, @q15:=Q15, @q16:=Q16, @q17:=Q17, @q18:=Q18, @q19:=Q19, @q20:=Q20, 
       @q21:=Q21, @q22:=Q22, @q23:=Q23, @q24:=Q24, @q25:=Q25, @q26:=Q26, @q27:=Q27, @q28:=Q28, @q29:=Q29, @q30:=Q30, 
       @q31:=Q31, @q32:=Q32, @q33:=Q33, @q34:=Q34, @q35:=Q35, @q36:=Q36, @q37:=Q37, @q38:=Q38, @q39:=Q39, @q40:=Q40, 
       @q41:=Q41, @q42:=Q42, @q43:=Q43, @q44:=Q44, @q45:=Q45, @q46:=Q46, @q47:=Q47, @q48:=Q48, @q49:=Q49, @q50:=Q50, 
       @q51:=Q51, @q52:=Q52, @q53:=Q53, @q54:=Q54, @q55:=Q55, @q56:=Q56, @q57:=Q57, @q58:=Q58, @q59:=Q59, @q60:=Q60, 
       @q61:=Q61, @q62:=Q62, @q63:=Q63, @q64:=Q64, @q65:=Q65, @q66:=Q66, @q67:=Q67, @q68:=Q68, @q69:=Q69, @q70:=Q70, 
       @q71:=Q71, @q72:=Q72, @q73:=Q73, @q74:=Q74, @q75:=Q75, @q76:=Q76, @q77:=Q77, @q78:=Q78, @q79:=Q79, @q80:=Q80, 
       @q81:=Q81, @q82:=Q82, @q83:=Q83, @q84:=Q84, @q85:=Q85, @q86:=Q86
FROM import_test_carey_eitq
;

UPDATE carey_eitq SET 
     Q1=@q1, Q2=@q2, Q3=@q3, Q4=@q4, Q5=@q5, Q6=@q6, Q7=@q7, Q8=@q8, Q9=@q9, Q10=@q10, 
       Q11=@q11, Q12=@q12, Q13=@q13, Q14=@q14, Q15=@q15, Q16=@q16, Q17=@q17, Q18=@q18, Q19=@q19, Q20=@q20, 
       Q21=@q21, Q22=@q22, Q23=@q23, Q24=@q24, Q25=@q25, Q26=@q26, Q27=@q27, Q28=@q28, Q29=@q29, Q30=@q30, 
       Q31=@q31, Q32=@q32, Q33=@q33, Q34=@q34, Q35=@q35, Q36=@q36, Q37=@q37, Q38=@q38, Q39=@q39, Q40=@q40, 
       Q41=@q41, Q42=@q42, Q43=@q43, Q44=@q44, Q45=@q45, Q46=@q46, Q47=@q47, Q48=@q48, Q49=@q49, Q50=@q50, 
       Q51=@q51, Q52=@q52, Q53=@q53, Q54=@q54, Q55=@q55, Q56=@q56, Q57=@q57, Q58=@q58, Q59=@q59, Q60=@q60, 
       Q61=@q61, Q62=@q62, Q63=@q63, Q64=@q64, Q65=@q65, Q66=@q66, Q67=@q67, Q68=@q68, Q69=@q69, Q70=@q70, 
       Q71=@q71, Q72=@q72, Q73=@q73, Q74=@q74, Q75=@q75, Q76=@q76, Q77=@q77, Q78=@q78, Q79=@q79, Q80=@q80, 
       Q81=@q81, Q82=@q82, Q83=@q83, Q84=@q84, Q85=@q85, Q86=@q86, Date_taken=@dot 
       
WHERE CommentID=)."'$${real_ids{'CommentID'}}'
;
UPDATE carey_eitq SET
      Data_dir = '".$DATA_DIR."',
      Status = 'assembly',
      Core_path = '$core_path',
      File_type = 'carey',
      File_name = '$file_base'
WHERE CommentID='$${real_ids{'CommentID'}}';");

        #&run_queue(\$dbh);

    } elsif($which_carey_test eq 'carey_tts'){

        &queue_query(q(CREATE TEMPORARY TABLE IF NOT EXISTS import_test_carey_tts(

ID        tinyint(3) unsigned not null, 
DCCID	  int(6) not null,  
Unknown1  varchar(7) not null, 
DoB	  date not null,
Empty1	  varchar(15) not null,
Unknown2  varchar(7) not null,
Empty2    varchar(15) not null,
DoT       date not null,
PSCID     char(7) not null,

Q1 char(1) not null, 
Q2 char(1) not null, 
Q3 char(1) not null, 
Q4 char(1) not null, 
Q5 char(1) not null, 
Q6 char(1) not null, 
Q7 char(1) not null, 
Q8 char(1) not null, 
Q9 char(1) not null, 
Q10 char(1) not null, 

Q11 char(1) not null, 
Q12 char(1) not null, 
Q13 char(1) not null, 
Q14 char(1) not null, 
Q15 char(1) not null, 
Q16 char(1) not null, 
Q17 char(1) not null, 
Q18 char(1) not null, 
Q19 char(1) not null, 
Q20 char(1) not null, 

Q21 char(1) not null, 
Q22 char(1) not null, 
Q23 char(1) not null, 
Q24 char(1) not null, 
Q25 char(1) not null, 
Q26 char(1) not null, 
Q27 char(1) not null, 
Q28 char(1) not null, 
Q29 char(1) not null, 
Q30 char(1) not null, 

Q31 char(1) not null, 
Q32 char(1) not null, 
Q33 char(1) not null, 
Q34 char(1) not null, 
Q35 char(1) not null, 
Q36 char(1) not null, 
Q37 char(1) not null, 
Q38 char(1) not null, 
Q39 char(1) not null, 
Q40 char(1) not null, 

Q41 char(1) not null, 
Q42 char(1) not null, 
Q43 char(1) not null, 
Q44 char(1) not null, 
Q45 char(1) not null, 
Q46 char(1) not null, 
Q47 char(1) not null, 
Q48 char(1) not null, 
Q49 char(1) not null, 
Q50 char(1) not null, 

Q51 char(1) not null, 
Q52 char(1) not null, 
Q53 char(1) not null, 
Q54 char(1) not null, 
Q55 char(1) not null, 
Q56 char(1) not null, 
Q57 char(1) not null, 
Q58 char(1) not null, 
Q59 char(1) not null, 
Q60 char(1) not null, 

Q61 char(1) not null, 
Q62 char(1) not null, 
Q63 char(1) not null, 
Q64 char(1) not null, 
Q65 char(1) not null, 
Q66 char(1) not null, 
Q67 char(1) not null, 
Q68 char(1) not null, 
Q69 char(1) not null, 
Q70 char(1) not null, 

Q71 char(1) not null, 
Q72 char(1) not null, 
Q73 char(1) not null, 
Q74 char(1) not null, 
Q75 char(1) not null, 
Q76 char(1) not null, 
Q77 char(1) not null, 
Q78 char(1) not null, 
Q79 char(1) not null, 
Q80 char(1) not null, 

Q81 char(1) not null, 
Q82 char(1) not null, 
Q83 char(1) not null, 
Q84 char(1) not null, 
Q85 char(1) not null, 
Q86 char(1) not null, 
Q87 char(1) not null, 
Q88 char(1) not null, 
Q89 char(1) not null, 
Q90 char(1) not null, 

Q91 char(1) not null, 
Q92 char(1) not null, 
Q93 char(1) not null, 
Q94 char(1) not null, 
Q95 char(1) not null, 
Q96 char(1) not null, 
Q97 char(1) not null, 
Q98 char(1) not null, 
Q99 char(1) not null, 
Q100 char(1) not null, 

Q101 char(1) not null, 
Q102 char(1) not null, 
Q103 char(1) not null, 
Q104 char(1) not null, 
Q105 char(1) not null, 
Q106 char(1) not null, 
Q107 char(1) not null

)
;

DELETE FROM import_test_carey_tts;

LOAD DATA INFILE ")."$file".q(" 
    INTO TABLE import_test_carey_tts
    FIELDS
        TERMINATED BY '\n'
;

SELECT @dccid:=DCCID, @pscid:=PSCID, @dot:= DoT,
       @q1:=Q1, @q2:=Q2, @q3:=Q3, @q4:=Q4, @q5:=Q5, @q6:=Q6, @q7:=Q7, @q8:=Q8, @q9:=Q9, @q10:=Q10, 
       @q11:=Q11, @q12:=Q12, @q13:=Q13, @q14:=Q14, @q15:=Q15, @q16:=Q16, @q17:=Q17, @q18:=Q18, @q19:=Q19, @q20:=Q20, 
       @q21:=Q21, @q22:=Q22, @q23:=Q23, @q24:=Q24, @q25:=Q25, @q26:=Q26, @q27:=Q27, @q28:=Q28, @q29:=Q29, @q30:=Q30, 
       @q31:=Q31, @q32:=Q32, @q33:=Q33, @q34:=Q34, @q35:=Q35, @q36:=Q36, @q37:=Q37, @q38:=Q38, @q39:=Q39, @q40:=Q40, 
       @q41:=Q41, @q42:=Q42, @q43:=Q43, @q44:=Q44, @q45:=Q45, @q46:=Q46, @q47:=Q47, @q48:=Q48, @q49:=Q49, @q50:=Q50, 
       @q51:=Q51, @q52:=Q52, @q53:=Q53, @q54:=Q54, @q55:=Q55, @q56:=Q56, @q57:=Q57, @q58:=Q58, @q59:=Q59, @q60:=Q60, 
       @q61:=Q61, @q62:=Q62, @q63:=Q63, @q64:=Q64, @q65:=Q65, @q66:=Q66, @q67:=Q67, @q68:=Q68, @q69:=Q69, @q70:=Q70, 
       @q71:=Q71, @q72:=Q72, @q73:=Q73, @q74:=Q74, @q75:=Q75, @q76:=Q76, @q77:=Q77, @q78:=Q78, @q79:=Q79, @q80:=Q80, 
       @q81:=Q81, @q82:=Q82, @q83:=Q83, @q84:=Q84, @q85:=Q85, @q86:=Q86, @q87:=Q87, @q88:=Q88, @q89:=Q89, @q90:=Q90, 
       @q91:=Q91, @q92:=Q92, @q93:=Q93, @q94:=Q94, @q95:=Q95, @q96:=Q96, @q97:=Q97, @q98:=Q98, @q99:=Q99, @q100:=Q100, 
       @q101:=Q101, @q102:=Q102, @q103:=Q103, @q104:=Q104, @q105:=Q105, @q106:=Q106, @q107:=Q107
FROM import_test_carey_tts
;

UPDATE carey_tts SET 
       Q1=@q1, Q2=@q2, Q3=@q3, Q4=@q4, Q5=@q5, Q6=@q6, Q7=@q7, Q8=@q8, Q9=@q9, Q10=@q10, 
       Q11=@q11, Q12=@q12, Q13=@q13, Q14=@q14, Q15=@q15, Q16=@q16, Q17=@q17, Q18=@q18, Q19=@q19, Q20=@q20, 
       Q21=@q21, Q22=@q22, Q23=@q23, Q24=@q24, Q25=@q25, Q26=@q26, Q27=@q27, Q28=@q28, Q29=@q29, Q30=@q30, 
       Q31=@q31, Q32=@q32, Q33=@q33, Q34=@q34, Q35=@q35, Q36=@q36, Q37=@q37, Q38=@q38, Q39=@q39, Q40=@q40, 
       Q41=@q41, Q42=@q42, Q43=@q43, Q44=@q44, Q45=@q45, Q46=@q46, Q47=@q47, Q48=@q48, Q49=@q49, Q50=@q50, 
       Q51=@q51, Q52=@q52, Q53=@q53, Q54=@q54, Q55=@q55, Q56=@q56, Q57=@q57, Q58=@q58, Q59=@q59, Q60=@q60, 
       Q61=@q61, Q62=@q62, Q63=@q63, Q64=@q64, Q65=@q65, Q66=@q66, Q67=@q67, Q68=@q68, Q69=@q69, Q70=@q70, 
       Q71=@q71, Q72=@q72, Q73=@q73, Q74=@q74, Q75=@q75, Q76=@q76, Q77=@q77, Q78=@q78, Q79=@q79, Q80=@q80, 
       Q81=@q81, Q82=@q82, Q83=@q83, Q84=@q84, Q85=@q85, Q86=@q86, Q87=@q87, Q88=@q88, Q89=@q89, Q90=@q90, 
       Q91=@q91, Q92=@q92, Q93=@q93, Q94=@q94, Q95=@q95, Q96=@q96, Q97=@q97, Q98=@q98, Q99=@q99, Q100=@q100, 
       Q101=@q101, Q102=@q102, Q103=@q103, Q104=@q104, Q105=@q105, Q106=@q106, Q107=@q107, Date_taken=@dot     
WHERE CommentID=)."'$${real_ids{'CommentID'}}'
;
UPDATE carey_tts SET
      Data_dir = '".$DATA_DIR."',
      Status = 'assembly',
      Core_path = '$core_path',
      file_type = 'carey',
      file_name = '$file_base'
WHERE CommentID='$${real_ids{'CommentID'}}';");

        #&run_queue(\$dbh);
           
    }
    
}


# ------------------------------ MNI Header ----------------------------------
#@NAME       : cbcl_verify
#@INPUT      : $file (cbcl file), \%real_ids, $DATA_DIR, $dbhr (database handle reference), $psc
#@OUTPUT     : 
#@RETURNS    : 1 or 0
#@DESCRIPTION: Verifies that the cbcl $file can be imported
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 2003/03/25, Jonathan Harlap
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub cbcl_verify {
    my ($file, $real_ids, $DATA_DIR, $dbhr, $psc, $no_mail) = @_;
    return 0 unless $file =~ /profexport\.txt$/i;

    my %local_ids;
    my @fields;

    my @lines = `cat $file | grep -e '"$${real_ids{'CandID'}}"' | grep -i -e '"$${real_ids{'PSCID'}}"' | grep -e '"$${real_ids{'VisitNo'}}"' -e '"v$${real_ids{'VisitNo'}}"' -e '"0$${real_ids{'VisitNo'}}"' `;

    foreach my $line (@lines) {
        @fields = split(',', $line);

        $local_ids{'CandID'} = $fields[4];
        $local_ids{'PSCID'} = lc($fields[2]);
        $local_ids{'VisitNo'} = $fields[12];
        # Fields can be 1, v1, or V1 so we get rid of the V to get a number 
        $local_ids{'VisitNo'} =~ s/v//i;
        $local_ids{'VisitNo'} =~ s/0([0-9])/$1/;
        
        if($local_ids{'CandID'} eq "\"$${real_ids{'CandID'}}\"" && 
           $local_ids{'PSCID'} eq "\"$${real_ids{'PSCID'}}\"" &&
           $local_ids{'VisitNo'} eq "\"$${real_ids{'VisitNo'}}\"")
        {

            # make sure the test type is correct
            $which_cbcl_test = &db_determine_test($$real_ids{'CommentID'}, $dbhr);
            $cbcl_test_check = &cbcl_determine_test($file, $real_ids);
            
            if($which_cbcl_test ne $cbcl_test_check)
            { &error_mail($psc, "CBCL file $file is the wrong cbcl type (".&cbcl_type_descriptor($cbcl_test_check)." instead of ".&cbcl_type_descriptor($which_cbcl_test).")", 'cbcl', &file_basename($file), $dbhr) unless $no_mail; return -1; }
            if((&cbcl_type_descriptor($which_cbcl_test) eq 'unknown') || (&cbcl_type_descriptor($cbcl_test_check) eq 'unknown'))
            { &error_mail($psc, "CBCL file $file is corrupt or an unknown type of cbcl.", 'cbcl', &file_basename($file), $dbhr) unless $no_mail; return -1; }
            
            # if we got here, we're happy
            return 1;
        }
    }

    # we're missing valid ids...
    &error_mail($psc, "CBCL file ".file_basename($file)." has an ID problem inside the file, please correct the IDs on this dataset, reexport and resend this data.", 'cbcl', file_basename($file), $dbhr) unless $no_mail;

    return -1;
}

# ------------------------------ MNI Header ----------------------------------
#@NAME       : cbcl_determine_test
#@INPUT      : $file (cbcl file), \%real_ids, $DATA_DIR
#@OUTPUT     : 
#@RETURNS    : 
#@DESCRIPTION: Determines which of the cbcl tests the given file is
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 2003/03/25, Jonathan Harlap
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub cbcl_determine_test {
    my ($file, $real_ids, $DATA_DIR) = @_;
 
    my %local_ids;
    my @fields;

    my @lines = `cat $file | grep -e '"$${real_ids{'CandID'}}"' | grep -i -e '"$${real_ids{'PSCID'}}"' | grep -e '"$${real_ids{'VisitNo'}}"' -e '"v$${real_ids{'VisitNo'}}"' -e '"0$${real_ids{'VisitNo'}}"'`;

    foreach my $line (@lines) {
        @fields = split(',', $line);

        $local_ids{'CandID'} = $fields[4];
        $local_ids{'PSCID'} = lc($fields[2]);
        $local_ids{'VisitNo'} = $fields[12];
        # Fields can be 1, v1, or V1 so we get rid of the V to get a number 
        $local_ids{'VisitNo'} =~ s/v//i;
        $local_ids{'VisitNo'} =~ s/0([0-9])/$1/;
        
        if($local_ids{'CandID'} eq "\"$${real_ids{'CandID'}}\"" && 
           $local_ids{'PSCID'} eq "\"$${real_ids{'PSCID'}}\"" &&
           $local_ids{'VisitNo'} eq "\"$${real_ids{'VisitNo'}}\"")
        {
            if($fields[13] eq '"CBC"') { return 'cbcl_418'; }
            elsif($fields[13] eq '"C15"') { return 'cbcl_15'; }
            elsif($fields[13] eq '"YAS"') { return 'cbcl_1821'; }
            else { return $fields[13]; }
        }
    }
    return 'unknown';
}
    
sub cbcl_type_descriptor {
    my $type = shift;
    
    return 'Caregiver Teacher Report (1:6-5:0)' if($type eq 'T15');
    return 'Child Behaviour Checklist (1:6-5:0)' if($type eq 'cbcl_15'); #C15
    return 'Child Behaviour Checklist (6y-18y)' if($type eq 'cbcl_418'); #CBC
    return 'Semistructured Clinical Interview (6y-18y)' if($type eq 'SIA');
    return 'Teacher\'s Report (6:0-18:0)' if($type eq 'TRF');
    return 'Young Adult Behaviour Checklist' if ($type eq 'YAB');
    return 'Young Adult Self-Report' if($type eq 'cbcl_1821'); #YAS
    return 'Youth Self-Report' if($type eq 'YSR');
    return 'Caregiver Teacher Report (2:0-5:0)' if($type eq 'T25');
    return 'Child behaviour Checklist (2:0-3:0)' if($type eq 'C23');

    return 'unknown';
}



# ------------------------------ MNI Header ----------------------------------
#@NAME       : cbcl_imp
#@INPUT      : $file (cbcl file), \%real_ids, $DATA_DIR, $dbhr (database handle ref), $psc (site name)
#@OUTPUT     : 
#@RETURNS    : 
#@DESCRIPTION: Imports the data from the cbcl file into the database
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 2003/03/25, Jonathan Harlap
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub cbcl_imp {
    my ($file, $real_ids, $DATA_DIR, $dbhr, $psc, $no_mail) = @_;

    $which_cbcl_test = &db_determine_test($$real_ids{'CommentID'}, $dbhr);

    my $core_path = &core_path($real_ids);
    my $file_base = &file_basename($file);

    &queue_query(q(CREATE TEMPORARY TABLE IF NOT EXISTS import_test_cbcl(

ID              char(12) not null,
Subject_num     int(11) unsigned not null,

FirstName       char(15) not null,
MiddleName      char(15) not null,
LastName        char(20) not null,
OtherName       char(20) not null,
Gender          char(1) not null,
DOB             text not null,
EthnicCode      char(2) not null,

Formver         char(4) not null,
Dataver         char(4) not null,
Formnumber      int(11) unsigned not null,
Formid          char(3) not null,

Type            char(3) not null,
Enterdate       date not null,
DFO             date not null,

Age             char(3) not null,
Agemonths       char(2) not null, 
Educode         char(3) not null,
FOBcode         char(2) not null,
FOBgender       char(1) not null,

ParentSES       char(2) not null,
SubjectSES      char(2) not null,
SpouseSES       char(2) not null,

AgencyCode      char(3) not null,
ClinCode        char(3) not null,

Sc1Name         char(30) not null,
Sc1Raw          int(11) not null,
Sc1t            int(11) not null, 
Sc1Clint        decimal(3,4) not null, 
Sc1Pct          int(11) not null,

Sc2Name         char(30) not null,
Sc2Raw          int(11) not null,
Sc2t            int(11) not null, 
Sc2Clint        decimal(3,4) not null, 
Sc2Pct          int(11) not null,

Sc3Name         char(30) not null,
Sc3Raw          int(11) not null,
Sc3t            int(11) not null, 
Sc3Clint        decimal(3,4) not null, 
Sc3Pct          int(11) not null,

Sc4Name         char(30) not null,
Sc4Raw          int(11) not null,
Sc4t            int(11) not null, 
Sc4Clint        decimal(3,4) not null, 
Sc4Pct          int(11) not null,
 
Sc5Name         char(30) not null,
Sc5Raw          int(11) not null,
Sc5t            int(11) not null, 
Sc5Clint        decimal(3,4) not null, 
Sc5Pct          int(11) not null,

Sc6Name         char(30) not null,
Sc6Raw          int(11) not null,
Sc6t            int(11) not null, 
Sc6Clint        decimal(3,4) not null, 
Sc6Pct          int(11) not null,

Sc7Name         char(30) not null,
Sc7Raw          int(11) not null,
Sc7t            int(11) not null, 
Sc7Clint        decimal(3,4) not null, 
Sc7Pct          int(11) not null,

Sc8Name         char(30) not null,
Sc8Raw          int(11) not null,
Sc8t            int(11) not null, 
Sc8Clint        decimal(3,4) not null, 
Sc8Pct          int(11) not null,

Sc9Name         char(30) not null,
Sc9Raw          int(11) not null,
Sc9t            int(11) not null, 
Sc9Clint        decimal(3,4) not null, 
Sc9Pct          int(11) not null,

Sc10Name         char(30) not null,
Sc10Raw          int(11) not null,
Sc10t            int(11) not null, 
Sc10Clint        decimal(3,4) not null, 
Sc10Pct          int(11) not null,

Sc11Name         char(30) not null,
Sc11Raw          int(11) not null,
Sc11t            int(11) not null, 
Sc11Clint        decimal(3,4) not null, 
Sc11Pct          int(11) not null,

Sc12Name         char(30) not null,
Sc12Raw          int(11) not null,
Sc12t            int(11) not null, 
Sc12Clint        decimal(3,4) not null, 
Sc12Pct          int(11) not null,

Sc13Name         char(30) not null,
Sc13Raw          int(11) not null,
Sc13t            int(11) not null, 
Sc13Clint        decimal(3,4) not null, 
Sc13Pct          int(11) not null,

Sc14Name         char(30) not null,
Sc14Raw          int(11) not null,
Sc14t            int(11) not null, 
Sc14Clint        decimal(3,4) not null, 
Sc14Pct          int(11) not null,

Sc15Name         char(30) not null,
Sc15Raw          int(11) not null,
Sc15t            int(11) not null, 
Sc15Clint        decimal(3,4) not null, 
Sc15Pct          int(11) not null,

Icc1             decimal(3,3) not null,
Icc1Sig          char(3) not null,
Icc2             decimal(3,3) not null,
Icc2Sig          char(3) not null,
Icc3             decimal(3,3) not null,
Icc3Sig          char(3) not null,
Icc4             decimal(3,3) not null,
Icc4Sig          char(3) not null,
Icc5             decimal(3,3) not null,
Icc5Sig          char(3) not null,
Icc6             decimal(3,3) not null,
Icc6Sig          char(3) not null,
Icc7             decimal(3,3) not null,
Icc7Sig          char(3) not null,
Icc8             decimal(3,3) not null,
Icc8Sig          char(3) not null,

Comp1Name        char(30) not null, 
Comp1Raw         char(4) not null,
Comp1t           char(4) not null, 
Comp1Pct         char(4) not null, 

Comp2Name        char(30) not null, 
Comp2Raw         char(4) not null,
Comp2t           char(4) not null, 
Comp2Pct         char(4) not null, 

Comp3Name        char(30) not null, 
Comp3Raw         char(4) not null,
Comp3t           char(4) not null, 
Comp3Pct         char(4) not null, 

Comp4Name        char(30) not null, 
Comp4Raw         char(4) not null,
Comp4t           char(4) not null, 
Comp4Pct         char(4) not null, 

Adap1Name        char(30) not null, 
Adap1Raw         char(4) not null,
Adap1t           char(4) not null,
Adap1Pct         char(4) not null, 

Adap2Name        char(30) not null, 
Adap2Raw         char(4) not null,
Adap2t           char(4) not null,
Adap2Pct         char(4) not null, 

Adap3Name        char(30) not null, 
Adap3Raw         char(4) not null,
Adap3t           char(4) not null,
Adap3Pct         char(4) not null, 

Adap4Name        char(30) not null, 
Adap4Raw         char(4) not null,
Adap4t           char(4) not null,
Adap4Pct         char(4) not null, 

Adap5Name        char(30) not null, 
Adap5Raw         char(4) not null,
Adap5t           char(4) not null,
Adap5Pct         char(4) not null, 

Adap6Name        char(30) not null, 
Adap6Raw         char(4) not null,
Adap6t           char(4) not null,
Adap6Pct         char(4) not null, 

SubUse1Raw       char(4) not null,
SubUse1t         char(4) not null,
SubRaw1Pct       char(4) not null,

SubUse2Raw       char(4) not null,
SubUse2t         char(4) not null,
SubRaw2Pct       char(4) not null,

SubUse3Raw       char(4) not null,
SubUse3t         char(4) not null,
SubRaw3Pct       char(4) not null,

SubUse4Raw       char(4) not null,
SubUse4t         char(4) not null,
SubRaw4Pct       char(4) not null,

CompAct1         char(4) not null,
CompAct2         char(4) not null,
CompAct3         char(4) not null,
CompAct4         char(4) not null,
CompAct5         char(4) not null,
CompAct6         char(4) not null,

CompSoc1         char(4) not null,
CompSoc2         char(4) not null,
CompSoc3         char(4) not null,
CompSoc4         char(4) not null,
CompSoc5         char(4) not null,
CompSoc6         char(4) not null,

CompSch1         char(4) not null,
CompSch2         char(4) not null,
CompSch3         char(4) not null,
CompSch4         char(4) not null,

DSM1Name         char(30) not null,
DSM1Raw          char(4) not null,
DSM1T            char(4) not null,
DSM1Pct          char(4) not null,

DSM2Name         char(30) not null,
DSM2Raw          char(4) not null,
DSM2T            char(4) not null,
DSM2Pct          char(4) not null,

DSM3Name         char(30) not null,
DSM3Raw          char(4) not null,
DSM3T            char(4) not null,
DSM3Pct          char(4) not null,

DSM4Name         char(30) not null,
DSM4Raw          char(4) not null,
DSM4T            char(4) not null,
DSM4Pct          char(4) not null,

DSM5Name         char(30) not null,
DSM5Raw          char(4) not null,
DSM5T            char(4) not null,
DSM5Pct          char(4) not null,

DSM6Name         char(30) not null,
DSM6Raw          char(4) not null,
DSM6T            char(4) not null,
DSM6Pct          char(4) not null,

DSM7Name         char(30) not null,
DSM7Raw          char(4) not null,
DSM7T            char(4) not null,
DSM7Pct          char(4) not null,

DSM8Name         char(30) not null,
DSM8Raw          char(4) not null,
DSM8T            char(4) not null,
DSM8Pct          char(4) not null,

LDSal            char(5) not null,
LDSalpct         char(4) not null,
LDSvc            char(4) not null,
LDSvcpct         char(4) not null

)
;

DELETE FROM import_test_cbcl;

LOAD DATA INFILE ")."$file".q(" 
    INTO TABLE import_test_cbcl
    FIELDS
        TERMINATED BY ','
        ENCLOSED BY '"'        
    LINES TERMINATED BY '\n'
;

SELECT @dccid:=LastName, @pscid:=FirstName, @visit:=Formid, @dot:=Enterdate,
	@sc1name:=Sc1Name, @sc1raw:=Sc1Raw, @sc1t:=Sc1t, @sc1clint:=Sc1Clint, @sc1pct:=Sc1Pct, 
	@sc2name:=Sc2Name, @sc2raw:=Sc2Raw, @sc2t:=Sc2t, @sc2clint:=Sc2Clint, @sc2pct:=Sc2Pct, 
	@sc3name:=Sc3Name, @sc3raw:=Sc3Raw, @sc3t:=Sc3t, @sc3clint:=Sc3Clint, @sc3pct:=Sc3Pct, 
	@sc4name:=Sc4Name, @sc4raw:=Sc4Raw, @sc4t:=Sc4t, @sc4clint:=Sc4Clint, @sc4pct:=Sc4Pct, 
	@sc5name:=Sc5Name, @sc5raw:=Sc5Raw, @sc5t:=Sc5t, @sc5clint:=Sc5Clint, @sc5pct:=Sc5Pct, 
	@sc6name:=Sc6Name, @sc6raw:=Sc6Raw, @sc6t:=Sc6t, @sc6clint:=Sc6Clint, @sc6pct:=Sc6Pct, 
	@sc7name:=Sc7Name, @sc7raw:=Sc7Raw, @sc7t:=Sc7t, @sc7clint:=Sc7Clint, @sc7pct:=Sc7Pct, 
	@sc8name:=Sc8Name, @sc8raw:=Sc8Raw, @sc8t:=Sc8t, @sc8clint:=Sc8Clint, @sc8pct:=Sc8Pct, 
	@sc9name:=Sc9Name, @sc9raw:=Sc9Raw, @sc9t:=Sc9t, @sc9clint:=Sc9Clint, @sc9pct:=Sc9Pct, 
	@sc10name:=Sc10Name, @sc10raw:=Sc10Raw, @sc10t:=Sc10t, @sc10clint:=Sc10Clint, @sc10pct:=Sc10Pct, 
	@sc11name:=Sc11Name, @sc11raw:=Sc11Raw, @sc11t:=Sc11t, @sc11clint:=Sc11Clint, @sc11pct:=Sc11Pct, 
	@sc12name:=Sc12Name, @sc12raw:=Sc12Raw, @sc12t:=Sc12t, @sc12clint:=Sc12Clint, @sc12pct:=Sc12Pct, 
	@sc13name:=Sc13Name, @sc13raw:=Sc13Raw, @sc13t:=Sc13t, @sc13clint:=Sc13Clint, @sc13pct:=Sc13Pct, 
	@sc14name:=Sc14Name, @sc14raw:=Sc14Raw, @sc14t:=Sc14t, @sc14clint:=Sc14Clint, @sc14pct:=Sc14Pct, 
	@sc15name:=Sc15Name, @sc15raw:=Sc15Raw, @sc15t:=Sc15t, @sc15clint:=Sc15Clint, @sc15pct:=Sc15Pct, 
	@icc1:=Icc1, @icc1sig:=Icc1Sig, @icc2:=Icc2, @icc2sig:=Icc2Sig, 
	@icc3:=Icc3, @icc3sig:=Icc3Sig, @icc4:=Icc4, @icc4sig:=Icc4Sig,
	@icc5:=Icc5, @icc5sig:=Icc5Sig, @icc6:=Icc6, @icc6sig:=Icc6Sig, 
	@icc7:=Icc7, @icc7sig:=Icc7Sig, @icc8:=Icc8, @icc8sig:=Icc8Sig, 
	@comp1name:=Comp1Name, @comp1raw:=Comp1Raw, @comp1t:=Comp1t, @comp1pct:=Comp1Pct, 
	@comp2name:=Comp2Name, @comp2raw:=Comp2Raw, @comp2t:=Comp2t, @comp2pct:=Comp2Pct, 
	@comp3name:=Comp3Name, @comp3raw:=Comp3Raw, @comp3t:=Comp3t, @comp3pct:=Comp3Pct, 
	@comp4name:=Comp4Name, @comp4raw:=Comp4Raw, @comp4t:=Comp4t, @comp4pct:=Comp4Pct,  
	@adap1name:=Adap1Name, @adap1raw:=Adap1Raw, @adap1t:=Adap1t, @adap1pct:=Adap1Pct,  
	@adap2name:=Adap2Name, @adap2raw:=Adap2Raw, @adap2t:=Adap2t, @adap2pct:=Adap2Pct,  
	@adap3name:=Adap3Name, @adap3raw:=Adap3Raw, @adap3t:=Adap3t, @adap3pct:=Adap3Pct,  
	@adap4name:=Adap4Name, @adap4raw:=Adap4Raw, @adap4t:=Adap4t, @adap4pct:=Adap4Pct,  
	@adap5name:=Adap5Name, @adap5raw:=Adap5Raw, @adap5t:=Adap5t, @adap5pct:=Adap5Pct,  
	@adap6name:=Adap6Name, @adap6raw:=Adap6Raw, @adap6t:=Adap6t, @adap6pct:=Adap6Pct,  
	@subuse1raw:=SubUse1Raw, @subuse1t:=SubUse1t, @subraw1pct:=SubRaw1Pct, 
	@subuse2raw:=SubUse2Raw, @subuse2t:=SubUse2t, @subuse2pct:=SubRaw2Pct, 
	@subuse3raw:=SubUse3Raw, @subuse3t:=SubUse3t, @subuse3pct:=SubRaw3Pct, 
	@subuse4raw:=SubUse4Raw, @subuse4t:=SubUse4t, @subuse4pct:=SubRaw4Pct, 
	@compact1:=CompAct1, @compact2:=CompAct2, @compact3:=CompAct3, 
	@compact4:=CompAct4, @compact5:=CompAct5, @compact6:=CompAct6, 
	@compsoc1:=CompSoc1, @compsoc2:=CompSoc2, @compsoc3:=CompSoc3, 
	@compsoc4:=CompSoc4, @compsoc5:=CompSoc5, @compsoc6:=CompSoc6, 
	@compsch1:=CompSch1, @compsch2:=CompSch2, @compsch3:=CompSch3, @compsch4:=CompSch4  
FROM import_test_cbcl
WHERE LastName=').$$real_ids{'CandID'}.q('
AND FirstName=').$$real_ids{'PSCID'}.q('
AND RIGHT(Formid,1)=').$$real_ids{'VisitNo'}.q('
ORDER BY DFO DESC LIMIT 1
;

UPDATE ).$which_cbcl_test.q( SET 
	Sc1Name=@sc1name, Sc1Raw=@sc1raw, Sc1t=@sc1t, Sc1Clint=@sc1clint, Sc1Pct=@sc1pct, 
	Sc2Name=@sc2name, Sc2Raw=@sc2raw, Sc2t=@sc2t, Sc2Clint=@sc2clint, Sc2Pct=@sc2pct, 
	Sc3Name=@sc3name, Sc3Raw=@sc3raw, Sc3t=@sc3t, Sc3Clint=@sc3clint, Sc3Pct=@sc3pct, 
	Sc4Name=@sc4name, Sc4Raw=@sc4raw, Sc4t=@sc4t, Sc4Clint=@sc4clint, Sc4Pct=@sc4pct, 
	Sc5Name=@sc5name, Sc5Raw=@sc5raw, Sc5t=@sc5t, Sc5Clint=@sc5clint, Sc5Pct=@sc5pct, 
	Sc6Name=@sc6name, Sc6Raw=@sc6raw, Sc6t=@sc6t, Sc6Clint=@sc6clint, Sc6Pct=@sc6pct, 
	Sc7Name=@sc7name, Sc7Raw=@sc7raw, Sc7t=@sc7t, Sc7Clint=@sc7clint, Sc7Pct=@sc7pct, 
	Sc8Name=@sc8name, Sc8Raw=@sc8raw, Sc8t=@sc8t, Sc8Clint=@sc8clint, Sc8Pct=@sc8pct, 
	Sc9Name=@sc9name, Sc9Raw=@sc9raw, Sc9t=@sc9t, Sc9Clint=@sc9clint, Sc9Pct=@sc9pct, 
	Sc10Name=@sc10name, Sc10Raw=@sc10raw, Sc10t=@sc10t, Sc10Clint=@sc10clint, Sc10Pct=@sc10pct, 
	Sc11Name=@sc11name, Sc11Raw=@sc11raw, Sc11t=@sc11t, Sc11Clint=@sc11clint, Sc11Pct=@sc11pct, 
	Sc12Name=@sc12name, Sc12Raw=@sc12raw, Sc12t=@sc12t, Sc12Clint=@sc12clint, Sc12Pct=@sc12pct, 
	Sc13Name=@sc13name, Sc13Raw=@sc13raw, Sc13t=@sc13t, Sc13Clint=@sc13clint, Sc13Pct=@sc13pct, 
	Sc14Name=@sc14name, Sc14Raw=@sc14raw, Sc14t=@sc14t, Sc14Clint=@sc14clint, Sc14Pct=@sc14pct, 
	Sc15Name=@sc15name, Sc15Raw=@sc15raw, Sc15t=@sc15t, Sc15Clint=@sc15clint, Sc15Pct=@sc15pct, 
	Icc1=@icc1, Icc1Sig=@icc1sig, Icc2=@icc2, Icc2Sig=@icc2sig, 
	Icc3=@icc3, Icc3Sig=@icc3sig, Icc4=@icc4, Icc4Sig=@icc4sig,
	Icc5=@icc5, Icc5Sig=@icc5sig, Icc6=@icc6, Icc6Sig=@icc6sig, 
	Icc7=@icc7, Icc7Sig=@icc7sig, Icc8=@icc8, Icc8Sig=@icc8sig, 
	Comp1Name=@comp1name, Comp1Raw=@comp1raw, Comp1t=@comp1t, Comp1Pct=@comp1pct, 
	Comp2Name=@comp2name, Comp2Raw=@comp2raw, Comp2t=@comp2t, Comp2Pct=@comp2pct, 
	Comp3Name=@comp3name, Comp3Raw=@comp3raw, Comp3t=@comp3t, Comp3Pct=@comp3pct, 
	Comp4Name=@comp4name, Comp4Raw=@comp4raw, Comp4t=@comp4t, Comp4Pct=@comp4pct,  
	Adap1Name=@adap1name, Adap1Raw=@adap1raw, Adap1t=@adap1t, Adap1Pct=@adap1pct,  
	Adap2Name=@adap2name, Adap2Raw=@adap2raw, Adap2t=@adap2t, Adap2Pct=@adap2pct,  
	Adap3Name=@adap3name, Adap3Raw=@adap3raw, Adap3t=@adap3t, Adap3Pct=@adap3pct,  
	Adap4Name=@adap4name, Adap4Raw=@adap4raw, Adap4t=@adap4t, Adap4Pct=@adap4pct,  
	Adap5Name=@adap5name, Adap5Raw=@adap5raw, Adap5t=@adap5t, Adap5Pct=@adap5pct,  
	Adap6Name=@adap6name, Adap6Raw=@adap6raw, Adap6t=@adap6t, Adap6Pct=@adap6pct,  
	SubUse1Raw=@subuse1raw, SubUse1t=@subuse1t, SubRaw1Pct=@subraw1pct, 
	SubUse2Raw=@subuse2raw, SubUse2t=@subuse2t, SubRaw2Pct=@subraw2pct, 
	SubUse3Raw=@subuse3raw, SubUse3t=@subuse3t, SubRaw3Pct=@subraw3pct, 
	SubUse4Raw=@subuse4raw, SubUse4t=@subuse4t, SubRaw4Pct=@subraw4pct, 
	CompAct1=@compact1, CompAct2=@compact2, CompAct3=@compact3, 
	CompAct4=@compact4, CompAct5=@compact5, CompAct6=@compact6, 
	CompSoc1=@compsoc1, CompSoc2=@compsoc2, CompSoc3=@compsoc3, 
	CompSoc4=@compsoc4, CompSoc5=@compsoc5, CompSoc6=@compsoc6, 
	CompSch1=@compsch1, CompSch2=@compsch2, CompSch3=@compsch3, 
        CompSch4=@compsch4, Date_taken=@dot
  WHERE CommentID=)."'$${real_ids{'CommentID'}}'
;

UPDATE $which_cbcl_test SET
      Data_dir = '".$DATA_DIR."',
      Status = 'assembly',
      Core_path = '$core_path',
      File_type = 'cbcl',
      File_name = '$file_base'
WHERE CommentID='$${real_ids{'CommentID'}}';");

    #&run_queue(\$dbh);
           

}

# ------------------------------ MNI Header ----------------------------------
#@NAME       : cvlt2_verify
#@INPUT      : $file (cvlt2 file), \%real_ids, $DATA_DIR, $dbhr (database handle reference), $psc
#@OUTPUT     : 
#@RETURNS    : 1 or 0
#@DESCRIPTION: Verifies that the cvlt2 $file can be imported
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 2003/03/25, Jonathan Harlap
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub cvlt2_verify {
    my ($file, $real_ids, $DATA_DIR, $dbhr, $psc, $no_mail) = @_;
    return 0 unless $file =~ /\.txt$/i;

    my %local_ids;
    my @fields;

    open FILE, "grep $${real_ids{'CandID'}} $file |";
    @fields = split(/,/, <FILE>);
    close FILE;

    if(scalar(grep(/'/, @fields)) > 0) { #'
        &error_mail($psc, "CVLT2 file ".file_basename($file)." was incorrectly exported such that it contains quotation marks.  Please reexport without quotation marks and resend this data.", 'cvlt2', file_basename($file), $dbhr) unless $no_mail;
        return -1;
    }

    @fields = split(/ /, $fields[1]);
    $local_ids{'CandID'} = $fields[2]+0;
    $local_ids{'PSCID'} = lc($fields[0]);
    $local_ids{'VisitNo'} = $fields[1]+0;
    
    if($local_ids{'CandID'} == $$real_ids{'CandID'} && 
       $local_ids{'PSCID'} eq $$real_ids{'PSCID'} &&      
       $local_ids{'VisitNo'} == $$real_ids{'VisitNo'})
    {
        return 1;
    }

    # we're missing valid ids...
    &error_mail($psc, "CVLT2 file ".file_basename($file)." has an ID problem inside the file, please correct the IDs on this dataset, reexport and resend this data.", 'cvlt2', file_basename($file), $dbhr) unless $no_mail;

    return -1;
}

# ------------------------------ MNI Header ----------------------------------
#@NAME       : cvlt2_imp
#@INPUT      : $file (cvlt2 file), \%real_ids, $DATA_DIR, $dbhr (database handle ref), $psc (site name)
#@OUTPUT     : 
#@RETURNS    : 
#@DESCRIPTION: Imports the data from the cvlt2 file into the database
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 2003/03/25, Jonathan Harlap
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub cvlt2_imp {
    my ($file, $real_ids, $DATA_DIR, $dbhr, $psc) = @_;
    open FILE, $file;
    while(<FILE>) {
        chomp;
        s/\r//;
        my @fields = split(/,|  /, $_);
        my $line;
        foreach my $field (@fields) { 
            $line .= ',' if length($line)>0;
            $line .= "'$field'"; 
        }
        $insert_string .= "INSERT INTO import_test_cvlt2 VALUES (\n$line\n);\n";
    }

    my $core_path = &core_path($real_ids);
    my $file_base = &file_basename($file);

    &queue_query(q(CREATE TEMPORARY TABLE IF NOT EXISTS import_test_cvlt2(

ID int(4) unsigned not null, 
IDS char(25) not null,

Temp_age1 tinytext not null,
Unknown1  tinytext not null, 
Temp_age2 tinytext not null,

DoB        date not null,     
Ethnic     tinytext not null, 
Sex        tinytext not null, 
Handedness tinytext not null, 
DoT        date not null,     
Form_type  tinytext not null, 

Scores_raw1   tinyint(2) unsigned not null, 
Scores_raw2   tinyint(2) unsigned not null, 
Scores_raw3   tinyint(2) unsigned not null, 
Scores_raw4   tinyint(2) unsigned not null, 
Scores_raw5   tinyint(2) unsigned not null, 
Scores_raw6   tinyint(2) unsigned not null, 
Scores_raw7   tinyint(2) unsigned not null, 
Scores_raw8   tinyint(2) unsigned not null, 
Scores_raw9   tinyint(2) unsigned not null, 
Scores_raw10   tinyint(2) unsigned not null, 
Scores_raw11   tinyint(2) unsigned not null, 

Cluster_raw1   decimal(3,1) not null, 
Cluster_raw2   decimal(3,1) not null, 
Cluster_raw3   decimal(3,1) not null, 
Cluster_raw4   decimal(3,1) not null, 
Cluster_raw5   decimal(3,1) not null, 
Cluster_raw6   decimal(2,1) not null, 
Cluster_raw7   decimal(2,1) not null, 
Cluster_raw8   decimal(2,1) not null, 
Cluster_raw9   decimal(2,1) not null, 

Discrim_raw1   decimal(3,1) not null, 
Discrim_raw2   decimal(3,1) not null, 
Discrim_raw3   decimal(3,1) not null, 
Discrim_raw4   decimal(3,1) not null, 
Discrim_raw5   decimal(3,1) not null, 
Discrim_raw6   decimal(3,1) not null, 

Discrim_raw7   decimal(3,1) not null, 
Discrim_raw8   decimal(3,1) not null, 
Discrim_raw9   decimal(3,1) not null, 
Discrim_raw10   decimal(3,1) not null, 
Discrim_raw11   decimal(3,1) not null, 

Learn_raw1   decimal(3,1) not null, 
Learn_raw2   decimal(3,1) not null, 
Learn_raw3   decimal(3,1) not null, 
Learn_raw4   decimal(3,1) not null, 
Learn_raw5   decimal(3,1) not null, 
Learn_raw6   decimal(3,1) not null, 
Learn_raw7   decimal(3,1) not null, 
Learn_raw8   decimal(3,1) not null, 
Learn_raw9   decimal(3,1) not null, 
Learn_raw10   decimal(3,1) not null, 

Error_raw1   decimal(3,1) not null, 
Error_raw2   decimal(3,1) not null, 
Error_raw3   decimal(3,1) not null, 
Error_raw4   decimal(3,1) not null, 
Error_raw5   decimal(3,1) not null, 
Error_raw6   decimal(3,1) not null, 
Error_raw7   decimal(3,1) not null, 
Error_raw8   decimal(3,1) not null, 
Error_raw9   decimal(3,1) not null, 
Error_raw10   decimal(3,1) not null, 
Error_raw11   decimal(3,1) not null, 
Error_raw12   decimal(3,1) not null, 
Error_raw13   decimal(3,1) not null, 

Delay_raw1   decimal(3,1) not null, 
Delay_raw2   decimal(3,1) not null, 
Delay_raw3   decimal(3,1) not null, 
Delay_raw4   decimal(3,1) not null, 
Delay_raw5   decimal(3,1) not null, 
Delay_raw6   decimal(3,1) not null, 
Delay_raw7   decimal(3,1) not null, 
Delay_raw8   decimal(3,1) not null, 
Delay_raw9   decimal(3,1) not null, 
Delay_raw10   decimal(3,1) not null, 
Delay_raw11   decimal(3,1) not null, 
Delay_raw12   decimal(3,1) not null, 

Scores_std1   decimal(3,1) not null, 
Scores_std2   decimal(3,1) not null, 
Scores_std3   decimal(3,1) not null, 
Scores_std4   decimal(3,1) not null, 
Scores_std5   decimal(3,1) not null, 
Scores_std6   decimal(3,1) not null, 
Scores_std7   decimal(3,1) not null, 
Scores_std8   decimal(3,1) not null, 
Scores_std9   decimal(3,1) not null, 
Scores_std10   decimal(3,1) not null, 
Scores_std11   decimal(3,1) not null, 

Cluster_std1   decimal(3,1) not null, 
Cluster_std2   decimal(3,1) not null, 
Cluster_std3   decimal(3,1) not null, 
Cluster_std4   decimal(3,1) not null, 

Cluster_std5   decimal(3,1) not null, 
Cluster_std6   decimal(3,1) not null, 

Discrim_std1   decimal(3,1) not null, 
Discrim_std2   decimal(3,1) not null, 
Discrim_std3   decimal(3,1) not null, 
Discrim_std4   decimal(3,1) not null, 
Discrim_std5   decimal(3,1) not null, 
Discrim_std6   decimal(3,1) not null, 

Learn_std1   decimal(3,1) not null, 
Learn_std2   decimal(3,1) not null, 
Learn_std3   decimal(3,1) not null, 
Learn_std4   decimal(3,1) not null, 
Learn_std5   decimal(3,1) not null, 
Learn_std6   decimal(3,1) not null, 
Learn_std7   decimal(3,1) not null, 
Learn_std8   decimal(3,1) not null, 
Learn_std9   decimal(3,1) not null, 
Learn_std10   decimal(3,1) not null, 

Error_std1   decimal(3,1) not null, 
Error_std2   decimal(3,1) not null, 
Error_std3   decimal(3,1) not null, 
Error_std4   decimal(3,1) not null, 
Error_std5   decimal(3,1) not null, 
Error_std6   decimal(3,1) not null, 
Error_std7   decimal(3,1) not null, 
Error_std8   decimal(3,1) not null, 
Error_std9   decimal(3,1) not null, 
Error_std10   decimal(3,1) not null, 

Delay_std1   decimal(3,1) not null, 
Delay_std2   decimal(3,1) not null, 
Delay_std3   decimal(3,1) not null, 
Delay_std4   decimal(3,1) not null, 
Delay_std5   decimal(3,1) not null, 
Delay_std6   decimal(3,1) not null, 
Delay_std7   decimal(3,1) not null, 

Recallage_std1   decimal(4,3) not null, 
Recallage_std2   decimal(4,3) not null, 
Recallage_std3   decimal(4,3) not null, 
Recallage_std4   decimal(4,3) not null, 
Recallage_std5   decimal(4,3) not null, 
Recallage_std6   decimal(4,3) not null, 

Recallage_std7   decimal(3,1) not null, 
Recallage_std8   decimal(3,1) not null, 
Recallage_std9   decimal(3,1) not null, 
Recallage_std10   decimal(3,1) not null, 
Recallage_std11   decimal(3,1) not null, 
Recallage_std12   decimal(3,1) not null, 

Recallper_std1   decimal(3,1) not null, 
Recallper_std2   decimal(3,1) not null, 
Recallper_std3   decimal(3,1) not null, 
Recallper_std4   decimal(3,1) not null, 
Recallper_std5   decimal(3,1) not null, 

Recall_z1   decimal(3,1) not null,
Recall_z2   decimal(3,1) not null,
Recall_z3   decimal(3,1) not null,
Recall_z4   decimal(3,1) not null,
Recall_z5   decimal(3,1) not null,
Recall_z6   decimal(3,1) not null


)
;

DELETE FROM import_test_cvlt2;

).$insert_string.q(

SELECT 
       @dot:=DoT,
       @scores_raw1:=Scores_raw1, @scores_raw2:=Scores_raw2, @scores_raw3:=Scores_raw3, @scores_raw4:=Scores_raw4,  
       @scores_raw5:=Scores_raw5, @scores_raw6:=Scores_raw6, @scores_raw7:=Scores_raw7, @scores_raw8:=Scores_raw8,  
       @scores_raw9:=Scores_raw9, @scores_raw10:=Scores_raw10, @scores_raw11:=Scores_raw11,  
       @cluster_raw1:=Cluster_raw1, @cluster_raw2:=Cluster_raw2, @cluster_raw3:=Cluster_raw3, @cluster_raw4:=Cluster_raw4, 
       @cluster_raw5:=Cluster_raw5, @cluster_raw6:=Cluster_raw6, @cluster_raw7:=Cluster_raw7, @cluster_raw8:=Cluster_raw8, 
       @cluster_raw9:=Cluster_raw9, 
       @discrim_raw1:=Discrim_raw1, @discrim_raw2:=Discrim_raw2, @discrim_raw3:=Discrim_raw3, @discrim_raw4:=Discrim_raw4, 
       @discrim_raw5:=Discrim_raw5, @discrim_raw6:=Discrim_raw6, @discrim_raw7:=Discrim_raw7, @discrim_raw8:=Discrim_raw8, 
       @discrim_raw9:=Discrim_raw9, @discrim_raw10:=Discrim_raw10, @discrim_raw11:=Discrim_raw11,        
       @learn_raw1:=Learn_raw1, @learn_raw2:=Learn_raw2, @learn_raw3:=Learn_raw3, @learn_raw4:=Learn_raw4, 
       @learn_raw5:=Learn_raw5, @learn_raw6:=Learn_raw6, @learn_raw7:=Learn_raw7, @learn_raw8:=Learn_raw8, 
       @learn_raw9:=Learn_raw9, @learn_raw10:=Learn_raw10, 
       @error_raw1:=Error_raw1, @error_raw2:=Error_raw2, @error_raw3:=Error_raw3, @error_raw4:=Error_raw4, 
       @error_raw5:=Error_raw5, @error_raw6:=Error_raw6, @error_raw7:=Error_raw7, @error_raw8:=Error_raw8, 
       @error_raw9:=Error_raw9, @error_raw10:=Error_raw10, @error_raw11:=Error_raw11, @error_raw12:=Error_raw12, 
       @error_raw13:=Error_raw13, 
       @delay_raw1:=Delay_raw1, @delay_raw2:=Delay_raw2, @delay_raw3:=Delay_raw3, @delay_raw4:=Delay_raw4, 
       @delay_raw5:=Delay_raw5, @delay_raw6:=Delay_raw6, @delay_raw7:=Delay_raw7, @delay_raw8:=Delay_raw8, 
       @delay_raw9:=Delay_raw9, @delay_raw10:=Delay_raw10, @delay_raw11:=Delay_raw11, @delay_raw12:=Delay_raw12, 
       @scores_std1:=Scores_std1, @scores_std2:=Scores_std2, @scores_std3:=Scores_std3, @scores_std4:=Scores_std4, 
       @scores_std5:=Scores_std5, @scores_std6:=Scores_std6, @scores_std7:=Scores_std7, @scores_std8:=Scores_std8, 
       @scores_std9:=Scores_std9, @scores_std10:=Scores_std10, @scores_std11:=Scores_std11,        
       @cluster_std1:=Cluster_std1, @cluster_std2:=Cluster_std2, @cluster_std3:=Cluster_std3, @cluster_std4:=Cluster_std4,
       @cluster_std5:=Cluster_std5, @cluster_std6:=Cluster_std6,  
       @discrim_std1:=Discrim_std1, @discrim_std2:=Discrim_std2, @discrim_std3:=Discrim_std3, @discrim_std4:=Discrim_std4, 
       @discrim_std5:=Discrim_std5, @discrim_std6:=Discrim_std6, 
       @learn_std1:=Learn_std1, @learn_std2:=Learn_std2, @learn_std3:=Learn_std3, @learn_std4:=Learn_std4, 
       @learn_std5:=Learn_std5, @learn_std6:=Learn_std6, @learn_std7:=Learn_std7, @learn_std8:=Learn_std8, 
       @learn_std9:=Learn_std9, @learn_std10:=Learn_std10, 
       @error_std1:=Error_std1, @error_std2:=Error_std2, @error_std3:=Error_std3, @error_std4:=Error_std4, 
       @error_std5:=Error_std5, @error_std6:=Error_std6, @error_std7:=Error_std7, @error_std8:=Error_std8, 
       @error_std9:=Error_std9, @error_std10:=Error_std10, 
       @delay_std1:=Delay_std1, @delay_std2:=Delay_std2, @delay_std3:=Delay_std3, @delay_std4:=Delay_std4, 
       @delay_std5:=Delay_std5, @delay_std6:=Delay_std6, @delay_std7:=Delay_std7, 
       @recallage_std1:=Recallage_std1, @recallage_std2:=Recallage_std2, @recallage_std3:=Recallage_std3, @recallage_std4:=Recallage_std4, 
       @recallage_std5:=Recallage_std5, @recallage_std6:=Recallage_std6, @recallage_std7:=Recallage_std7, @recallage_std8:=Recallage_std8,  
       @recallage_std9:=Recallage_std9, @recallage_std10:=Recallage_std10, @recallage_std11:=Recallage_std11, @recallage_std12:=Recallage_std12,
       @recallper_std1:=recallper_std1, @recallper_std2:=recallper_std2, @recallper_std3:=recallper_std3, @recallper_std4:=recallper_std4, 
       @recallper_std5:=recallper_std5, 
       @recall_z1:=Recall_z1, @recall_z2:=Recall_z2, @recall_z3:=Recall_z3, @recall_z4:=Recall_z4, 
       @recall_z5:=Recall_z5, @recall_z6:=Recall_z6 
FROM import_test_cvlt2
WHERE LCASE(IDS)=')."$${real_ids{'PSCID'}} $${real_ids{'VisitNo'}} $${real_ids{'CandID'}}".q('
;

UPDATE cvlt2 SET 
       Scores_raw1=@scores_raw1, Scores_raw2=@scores_raw2, Scores_raw3=@scores_raw3, Scores_raw4=@scores_raw4,  
       Scores_raw5=@scores_raw5, Scores_raw6=@scores_raw6, Scores_raw7=@scores_raw7, Scores_raw8=@scores_raw8,  
       Scores_raw9=@scores_raw9, Scores_raw10=@scores_raw10, Scores_raw11=@scores_raw11,
       Cluster_raw1=@cluster_raw1, Cluster_raw2=@cluster_raw2, Cluster_raw3=@cluster_raw3, Cluster_raw4=@cluster_raw4, 
       Cluster_raw5=@cluster_raw5, Cluster_raw6=@cluster_raw6, Cluster_raw7=@cluster_raw7, Cluster_raw8=@cluster_raw8, 
       Cluster_raw9=@cluster_raw9,
       Discrim_raw1=@discrim_raw, Discrim_raw2=@discrim_raw, Discrim_raw3=@discrim_raw, Discrim_raw4=@discrim_raw, 
       Discrim_raw5=@discrim_raw, Discrim_raw6=@discrim_raw, Discrim_raw7=@discrim_raw, Discrim_raw8=@discrim_raw, 
       Discrim_raw9=@discrim_raw, Discrim_raw10=@discrim_raw, Discrim_raw11=@discrim_raw,         
       Learn_raw1=@learn_raw1, Learn_raw2=@learn_raw2, Learn_raw3=@learn_raw3, Learn_raw4=@learn_raw4, 
       Learn_raw5=@learn_raw5, Learn_raw6=@learn_raw6, Learn_raw7=@learn_raw7, Learn_raw8=@learn_raw8, 
       Learn_raw9=@learn_raw9, Learn_raw10=@learn_raw10, 
       Error_raw1=@error_raw1, Error_raw2=@error_raw2, Error_raw3=@error_raw3, Error_raw4=@error_raw4, 
       Error_raw5=@error_raw5, Error_raw6=@error_raw6, Error_raw7=@error_raw7, Error_raw8=@error_raw8, 
       Error_raw9=@error_raw9, Error_raw10=@error_raw10, Error_raw11=@error_raw11, Error_raw12=@error_raw12, 
       Error_raw13=@error_raw13, 
       Delay_raw1=@delay_raw1, Delay_raw2=@delay_raw2, Delay_raw3=@delay_raw3, Delay_raw4=@delay_raw4, 
       Delay_raw5=@delay_raw5, Delay_raw6=@delay_raw6, Delay_raw7=@delay_raw7, Delay_raw8=@delay_raw8, 
       Delay_raw9=@delay_raw9, Delay_raw10=@delay_raw10, Delay_raw11=@delay_raw11, Delay_raw12=@delay_raw12, 
       Scores_std1=@scores_std1, Scores_std2=@scores_std2, Scores_std3=@scores_std3, Scores_std4=@scores_std4, 
       Scores_std5=@scores_std5, Scores_std6=@scores_std6, Scores_std7=@scores_std7, Scores_std8=@scores_std8, 
       Scores_std9=@scores_std9, Scores_std10=@scores_std10, Scores_std11=@scores_std11,        
       Cluster_std1=@cluster_std1, Cluster_std2=@cluster_std2, Cluster_std3=@cluster_std3, Cluster_std4=@cluster_std4,
       Cluster_std5=@cluster_std5, Cluster_std6=@cluster_std6, 
       Discrim_std1=@discrim_std1, Discrim_std2=@discrim_std2, Discrim_std3=@discrim_std3, Discrim_std4=@discrim_std4, 
       Discrim_std5=@discrim_std5, Discrim_std6=@discrim_std6,      
       Learn_std1=@learn_std1, Learn_std2=@learn_std2, Learn_std3=@learn_std3, Learn_std4=@learn_std4, 
       Learn_std5=@learn_std5, Learn_std6=@learn_std6, Learn_std7=@learn_std7, Learn_std8=@learn_std8, 
       Learn_std9=@learn_std9, Learn_std10=@learn_std10, 
       Error_std1=@error_std1, Error_std2=@error_std2, Error_std3=@error_std3, Error_std4=@error_std4, 
       Error_std5=@error_std5, Error_std6=@error_std6, Error_std7=@error_std7, Error_std8=@error_std8, 
       Error_std9=@error_std9, Error_std10=@error_std10,
       Delay_std1=@delay_std1, Delay_std2=@delay_std2, Delay_std3=@delay_std3, Delay_std4=@delay_std4, 
       Delay_std5=@delay_std5, Delay_std6=@delay_std6, Delay_std7=@delay_std7,
       Recallage_std1=@recallage_std1, Recallage_std2=@recallage_std2, Recallage_std3=@recallage_std3, Recallage_std4=@recallage_std4, 
       Recallage_std5=@recallage_std5, Recallage_std6=@recallage_std6, Recallage_std7=@recallage_std7, Recallage_std8=@recallage_std8,  
       Recallage_std9=@recallage_std9, Recallage_std10=@recallage_std10, Recallage_std11=@recallage_std11, Recallage_std12=@recallage_std12,
       Recallper_std1=@recallper_std1, Recallper_std2=@recallper_std2, Recallper_std3=@recallper_std3, Recallper_std4=@recallper_std4, 
       Recallper_std5=@recallper_std5,                        
       Recall_z1=@recall_z1, Recall_z2=@recall_z2, Recall_z3=@recall_z3, Recall_z4=@recall_z4, 
       Recall_z5=@recall_z5, Recall_z6=@recall_z6, Date_taken=@dot       
  WHERE CommentID=)."'$${real_ids{'CommentID'}}'
;
UPDATE cvlt2 SET
      Data_dir = '".$DATA_DIR."',
      Status = 'assembly',
      Core_path = '$core_path',
      File_type = 'cvlt2',
      File_name = '$file_base'
WHERE CommentID='$${real_ids{'CommentID'}}';");

    #&run_queue(\$dbh);

}

# ------------------------------ MNI Header ----------------------------------
#@NAME       : cvltc_verify
#@INPUT      : $file (cvltc file), \%real_ids, $DATA_DIR, $dbhr (database handle reference), $psc
#@OUTPUT     : 
#@RETURNS    : 1 or 0
#@DESCRIPTION: Verifies that the cvltc $file can be imported
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 2003/03/25, Jonathan Harlap
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub cvltc_verify {
    my ($file, $real_ids, $DATA_DIR, $dbhr, $psc, $no_mail) = @_;
    return 0 unless $file =~ /\.dat$/i;

    my %local_ids;
    my @fields;

    my @lines = `grep 'PART 1: CALCULATED DATA' $file`;
    unless(scalar(@lines) > 0) {
        &error_mail($psc, "CVLTC file ".file_basename($file)." has an ID problem inside the file, please correct the IDs on this dataset, reexport and resend this data.", 'cvltc', file_basename($file), $dbhr) unless $no_mail;
        return -1;
    }

    @lines = `grep "Child ID" $file`;
    
    @lines = grep /$${real_ids{'CandID'}}/, @lines;
    foreach my $line (reverse @lines) {

        $line =~ /^C v?([1-5])\s+([0-9]{6}),([a-z]{2}[a-z0-9][0-9]{4})/i;
        $local_ids{'VisitNo'} = $1;
        #$local_ids{'VisitNo'} =~ s/v//i;
        $local_ids{'VisitNo'} = $local_ids{'VisitNo'} + 0;
        $local_ids{'CandID'} = $2 + 0;
        $local_ids{'PSCID'} = lc($3);


        #print "${local_ids{'CandID'}},${local_ids{'VisitNo'}},${local_ids{'PSCID'}}\n";
        #print "$${real_ids{'CandID'}},$${real_ids{'VisitNo'}},$${real_ids{'PSCID'}}\n";

        if($local_ids{'CandID'} == $$real_ids{'CandID'} &&
           $local_ids{'VisitNo'} == $$real_ids{'VisitNo'} &&
           $local_ids{'PSCID'} eq $$real_ids{'PSCID'})
        {
            return 1;
        }
    }

    # we're missing valid ids...
    &error_mail($psc, "CVLTC file ".file_basename($file)." has an ID problem inside the file, please correct the IDs on this dataset, reexport and resend this data.", 'cvltc', file_basename($file), $dbhr) unless $no_mail;

    return -1;
}


# ------------------------------ MNI Header ----------------------------------
#@NAME       : cvltc_imp
#@INPUT      : $file (cvltc file), \%real_ids, $DATA_DIR, $dbhr (database handle ref), $psc (site name)
#@OUTPUT     : 
#@RETURNS    : 
#@DESCRIPTION: Imports the data from the cvltc file into the database
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 2003/03/25, Jonathan Harlap
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub cvltc_imp {

    my ($file, $real_ids, $DATA_DIR, $dbhr, $psc) = @_;
# ----------------------------------------------------
# creates a list of categories, useful for later
@cat_list = ("A1","A2","A3","A4","A5","A15","B","SDF"); 



# --------------------------------------------------------------------------
# opening the uploaded file for reading

open FILE, $file;
$which_line = 0;
while (<FILE>) {
    $which_line++;
    if (/$$real_ids{'CandID'}/ && /Child/ && /^C v?$$real_ids{'VisitNo'}/)
    {$real_start = $which_line;}
}

close FILE;
$which_line=0;

    my $core_path = &core_path($real_ids);
    my $file_base = &file_basename($file);

open UPLOAD_FILE, $file;

while ($line = <UPLOAD_FILE>){

    $which_line++;

    if ($line =~ /$$real_ids{'CandID'}/ 
        && $line =~ /^C v?$$real_ids{'VisitNo'}/ 
        && $line =~ /Child/ 
        && $which_line >= $real_start)
    {
        
        $start_line = $which_line;  

    } # end of if child id line

    next unless ($which_line >= $start_line);

    # pull out the 'correct' answers
    if ($which_line == $start_line + 6){
        $line =~ s/<.*/  /g;
        $line =~ s/C/ /g;
        @correct_array = split ' ', $line;        
    }

    # pull out the SemCL OE data
    if ($which_line == $start_line + 7){
        $line =~ s/<.*/  /g;
        $line =~ s/C/ /g;
        @semcloe_array = split ' ', $line;        
    }

    # pull out the SemCL Gl data
    if ($which_line == $start_line + 8){
        $line =~ s/<.*/  /g;
        $line =~ s/C/ /g;
        @semclgl_array = split ' ', $line;        
    }

    # pull out the SerCL OE data
    if ($which_line == $start_line + 9){
        $line =~ s/<.*/  /g;
        $line =~ s/C/ /g;
        @sercloe_array = split ' ', $line;        
    }

    # pull out the perseverations data
    if ($which_line == $start_line + 10){
        $line =~ s/<.*/  /g;
        $line =~ s/C/ /g;
        @pers_array = split ' ', $line;        
    }

    # pull out the intrusions data
    if ($which_line == $start_line + 11){
        $line =~ s/<.*/  /g;
        $line =~ s/C/ /g;
        @intr_array = split ' ', $line;        
    }

    # pull out the xlst intrusions data
    # there are only 5 data points in this array
    if ($which_line == $start_line + 12){
        $line =~ s/<.*/  /g;
        $line =~ s/C/ /g;
        @xlstintr_array = split ' ', $line;        
    }

    # pull out the immed. recall correct by cat. data
    # there are only 6 data points in this array
    if ($which_line == $start_line + 14){
        $line =~ s/<.*/  /g;
        $line =~ s/C/ /g;
        @immrecCC_array = split ' ', $line;        
    }

    # pull out the delayed recall correct by cat. data
    # there are only 6 data points in this array
    if ($which_line == $start_line + 16){
        $line =~ s/<.*/  /g;
        $line =~ s/C/ /g;
        @delrecCC_array = split ' ', $line;        
    }

    # pull out the regr/reg recall data
    # there are only 6 data points in this array
    if ($which_line == $start_line + 18){
        $line =~ s/<.*/  /g;
        $line =~ s/C/ /g;
        @RRrecall_array = split ' ', $line;        
    }

    # pull out the recog data
    # there are only 10 data points in this array
    if ($which_line == $start_line + 20){
        $line =~ s/<.*/  /g;
        $line =~ s/C/ /g;
        @recog_array = split ' ', $line;        
    }

    # pull out the reccmp data
    # there are only 7 data points in this array
    if ($which_line == $start_line + 22){
        $line =~ s/<.*/  /g;
        $line =~ s/C/ /g;
        @reccmp_array = split ' ', $line;        
    }

    # pull out the reccmp data
    # there are only 6 data points in this array
    if ($which_line == $start_line + 24){
        $line =~ s/<.*/  /g;
        $line =~ s/C/ /g;
        @perrccmp_array = split ' ', $line;        
    }

} # end of while reading UPLOAD_FILE


$query = "UPDATE cvltc SET\n";

# putting the correct data into the update query
foreach $i (0..(scalar(@cat_list)-1)){ 
    $query .= "$cat_list[$i]_corr=\'$correct_array[$i]\', "; 
} $query .= "SDC_corr=\'$correct_array[8]\', LDF_corr=\'$correct_array[9]\', LDC_corr=\'$correct_array[10]\', \n";

# putting the semcloe data into the update query
foreach $i (0..(scalar(@cat_list)-1)){ 
    $query .= "$cat_list[$i]_semOE=\'$semcloe_array[$i]\', "; 
} $query .= "LDF_semOE=\'$semcloe_array[8]\', \n";

# putting the semclgl data into the update query
foreach $i (0..(scalar(@cat_list)-1)){ 
    $query .= "$cat_list[$i]_semGL=\'$semclgl_array[$i]\', "; 
} $query .= "LDF_semGL=\'$semclgl_array[8]\', \n";

# putting the semclgl data into the update query
foreach $i (0..(scalar(@cat_list)-1)){ 
    $query .= "$cat_list[$i]_serOE=\'$sercloe_array[$i]\', "; 
} $query .= "LDF_serOE=\'$sercloe_array[8]\', \n";

# putting the perseverations data into the update query
foreach $i (0..(scalar(@cat_list)-1)){ 
    $query .= "$cat_list[$i]_pers=\'$pers_array[$i]\', "; 
} $query .= "SDC_pers=\'$pers_array[8]\', LDF_pers=\'$pers_array[9]\', LDC_pers=\'$pers_array[10]\', \n";

# putting the intrusions data into the update query
foreach $i (0..(scalar(@cat_list)-1)){ 
    $query .= "$cat_list[$i]_intr=\'$intr_array[$i]\', "; 
} $query .= "SDC_intr=\'$intr_array[8]\', LDF_intr=\'$intr_array[9]\', LDC_intr=\'$intr_array[10]\', \n";

# putting the xl intrusions data into the update query
$query .= "B_XL=\'$xlstintr_array[0]\', SDF_XL=\'$xlstintr_array[1]\', SDC_XL=\'$xlstintr_array[2]\', LDF_XL=\'$xlstintr_array[3]\', LDC_XL=\'$xlstintr_array[4]\', \n";

# putting the delayed and immed. recall data into the update query
$query .= "A_Pl=\'$immrecCC_array[0]\', A_Cl=\'$immrecCC_array[1]\', A_Fr=\'$immrecCC_array[2]\', B_Fr=\'$immrecCC_array[3]\', B_Sw=\'$immrecCC_array[4]\', B_Fu=\'$immrecCC_array[5]\', Sh_Pl=\'$delrecCC_array[0]\', Sh_Cl=\'$delrecCC_array[1]\', Sh_Fr=\'$delrecCC_array[2]\', Lg_Pl=\'$delrecCC_array[3]\', Lg_Cl=\'$delrecCC_array[4]\', Lg_Fr=\'$delrecCC_array[5]\', \n";

# putting the regr/reg recall data into the update query
$query .= "Slp=\'$RRrecall_array[0]\', ReCon=\'$RRrecall_array[1]\', PriR=\'$RRrecall_array[2]\', MidR=\'$RRrecall_array[3]\', RecR=\'$RRrecall_array[4]\', \n"; 

#putting the recog data into the update query
$query .= "Corr=\'$recog_array[0]\', FPos=\'$recog_array[1]\', DPri=\'$recog_array[2]\', Beta=\'$recog_array[3]\', BS=\'$recog_array[4]\', BSS=\'$recog_array[5]\', BN=\'$recog_array[6]\', NP=\'$recog_array[7]\', PS=\'$recog_array[8]\', UN=\'$recog_array[9]\', \n";

# putting the reccmp data into the update query
$query .= "BShr=\'$reccmp_array[0]\', BSSh=\'$reccmp_array[1]\', BNSh=\'$reccmp_array[2]\', SF_A5=\'$reccmp_array[3]\', LF_SF=\'$reccmp_array[4]\', LB_A1=\'$reccmp_array[5]\', RD_LF=\'$reccmp_array[6]\', \n";

# putting the reccmp data into the update query
$query .= "BShW=\'$perrccmp_array[0]\', BSSW=\'$perrccmp_array[1]\', BNSW=\'$perrccmp_array[2]\', SF_A5per=\'$perrccmp_array[3]\', LF_SFper=\'$perrccmp_array[4]\', LB_A1per=\'$perrccmp_array[5]\' \n";


# tie it all up together properly
$query .= "WHERE CommentID='$${real_ids{'CommentID'}}';\n";


# CHECK: Is this right? 
$query .= "UPDATE cvltc SET
      Data_dir = '".$DATA_DIR."',
      Status = 'assembly',
      Core_path = '$core_path',
      File_type = 'cvltc',
      File_name = '$file_base'
            WHERE CommentID='$${real_ids{'CommentID'}}';\n";

# execute the query
    &queue_query($query);
    #&run_queue(\$dbh);
}

# ------------------------------ MNI Header ----------------------------------
#@NAME       : das_verify
#@INPUT      : $file (das file), \%real_ids, $DATA_DIR, $dbhr (database handle reference), $psc
#@OUTPUT     : 
#@RETURNS    : 1 or 0
#@DESCRIPTION: Verifies that the das $file can be imported
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 2003/03/25, Jonathan Harlap
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub das_verify { 
    my ($file, $real_ids, $DATA_DIR, $dbhr, $psc, $no_mail) = @_;
    return 0 unless $file=~/\.txt$/i;
    open FILE, $file;
    while(<FILE>) {
        chomp;
        if(/$${real_ids{'CandID'}}/) {
            my @fields = split(/,/, $_);
            if($fields[1]+0 == $${real_ids{'CandID'}}
               && $fields[0]+0 == $${real_ids{'VisitNo'}}
               && lc($fields[2]) eq $${real_ids{'PSCID'}}
               && $#fields == 67)
            { return 1; }
        }
    }
    
    # we're missing valid ids...
    &error_mail($psc, "DAS file ".file_basename($file)." has an ID problem inside the file, please correct the IDs on this dataset, reexport and resend this data.", 'das', file_basename($file), $dbhr) unless $no_mail;

    return -1;
}

# ------------------------------ MNI Header ----------------------------------
#@NAME       : das_imp
#@INPUT      : $file (das file), \%real_ids, $DATA_DIR, $dbhr (database handle ref), $psc (site name)
#@OUTPUT     : 
#@RETURNS    : 
#@DESCRIPTION: Imports the data from the das file into the database
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 2003/03/25, Jonathan Harlap
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub das_imp {
    my ($file, $real_ids, $DATA_DIR, $dbhr, $psc, $no_mail) = @_;
    my $core_path = &core_path($real_ids);
    my $file_base = &file_basename($file);

    # make sure there's only one good DAS line for the current kid/visit in this file
    
    my @appropriate_lines = `grep -E '^$${real_ids{'VisitNo'}},$${real_ids{'CandID'}}' $file`;
    if(scalar(@appropriate_lines) != 1) {
        &error_mail($psc, "DAS file $file_base contains multiple datasets for $${real_ids{'CandID'}} visit $${real_ids{'VisitNo'}}", 'das', $file_base, $dbhr) unless $no_mail;
        next;
    }

    $query = "CREATE TEMPORARY TABLE IF NOT EXISTS das_temp ( F1 varchar(255) not null, F2 varchar(255) not null, F3 varchar(255) not null, F4 varchar(255) not null, F5 varchar(255) not null, F6 varchar(255) not null, F7 varchar(255) not null, F8 varchar(255) not null, F9 varchar(255) not null, F10 varchar(255) not null, F11 varchar(255) not null, F12 varchar(255) not null, F13 varchar(255) not null, F14 varchar(255) not null, F15 varchar(255) not null, F16 varchar(255) not null, F17 varchar(255) not null, F18 varchar(255) not null, F19 varchar(255) not null, F20 varchar(255) not null, F21 varchar(255) not null, F22 varchar(255) not null, F23 varchar(255) not null, F24 varchar(255) not null, F25 varchar(255) not null, F26 varchar(255) not null, F27 varchar(255) not null, F28 varchar(255) not null, F29 varchar(255) not null, F30 varchar(255) not null, F31 varchar(255) not null, F32 varchar(255) not null, F33 varchar(255) not null, F34 varchar(255) not null, F35 varchar(255) not null, F36 varchar(255) not null, F37 varchar(255) not null, F38 varchar(255) not null, F39 varchar(255) not null, F40 varchar(255) not null, F41 varchar(255) not null, F42 varchar(255) not null, F43 varchar(255) not null, F44 varchar(255) not null, F45 varchar(255) not null, F46 varchar(255) not null, F47 varchar(255) not null, F48 varchar(255) not null, F49 varchar(255) not null, F50 varchar(255) not null, F51 varchar(255) not null, F52 varchar(255) not null, F53 varchar(255) not null, F54 varchar(255) not null, F55 varchar(255) not null, F56 varchar(255) not null, F57 varchar(255) not null, F58 varchar(255) not null, F59 varchar(255) not null, F60 varchar(255) not null, F61 varchar(255) not null, F62 varchar(255) not null, F63 varchar(255) not null, F64 varchar(255) not null, F65 varchar(255) not null, F66 varchar(255) not null, F67 varchar(255) not null, F68 varchar(255) not null );

DELETE FROM das_temp;

LOAD DATA INFILE \"$file\" into table das_temp FIELDS terminated by ',' LINES terminated by '\\n';

DELETE FROM das_raw WHERE CommentID='".$${real_ids{'CommentID'}}."';


INSERT INTO das_raw SELECT '".$${real_ids{'CommentID'}}."' AS CommentID, tm.F1 AS F1, tm.F2 AS F2, tm.F3 AS F3, tm.F4 AS F4, tm.F5 AS F5, tm.F6 AS F6, tm.F7 AS F7, tm.F8 AS F8, tm.F9 AS F9, tm.F10 AS F10, tm.F11 AS F11, tm.F12 AS F12, tm.F13 AS F13, tm.F14 AS F14, tm.F15 AS F15, tm.F16 AS F16, tm.F17 AS F17, tm.F18 AS F18, tm.F19 AS F19, tm.F20 AS F20, tm.F21 AS F21, tm.F22 AS F22, tm.F23 AS F23, tm.F24 AS F24, tm.F25 AS F25, tm.F26 AS F26, tm.F27 AS F27, tm.F28 AS F28, tm.F29 AS F29, tm.F30 AS F30, tm.F31 AS F31, tm.F32 AS F32, tm.F33 AS F33, tm.F34 AS F34, tm.F35 AS F35, tm.F36 AS F36, tm.F37 AS F37, tm.F38 AS F38, tm.F39 AS F39, tm.F40 AS F40, tm.F41 AS F41, tm.F42 AS F42, tm.F43 AS F43, tm.F44 AS F44, tm.F45 AS F45, tm.F46 AS F46, tm.F47 AS F47, tm.F48 AS F48, tm.F49 AS F49, tm.F50 AS F50, tm.F51 AS F51, tm.F52 AS F52, tm.F53 AS F53, tm.F54 AS F54, tm.F55 AS F55, tm.F56 AS F56, tm.F57 AS F57, tm.F58 AS F58, tm.F59 AS F59, tm.F60 AS F60, tm.F61 AS F61, tm.F62 AS F62, tm.F63 AS F63, tm.F64 AS F64, tm.F65 AS F65, tm.F66 AS F66, tm.F67 AS F67, tm.F68 AS F68 FROM das_temp AS tm WHERE tm.F1 = $${real_ids{'VisitNo'}} AND tm.F2 = $${real_ids{'CandID'}} LIMIT 1;


UPDATE das
SET 
File_uploaded = 'Y'
WHERE
CommentID = '".$${real_ids{'CommentID'}}."';

UPDATE das SET
      Data_dir = '".$DATA_DIR."',
      Status = 'assembly',
      Core_path = '$core_path',
      File_type = 'das',
      File_name = '$file_base'
WHERE CommentID = '".$${real_ids{'CommentID'}}."';";

    &queue_query($query);
    #&run_queue(\$dbh);
}

# ------------------------------ MNI Header ----------------------------------
#@NAME       : dps4_verify
#@INPUT      : $file (dps4 file), \%real_ids, $DATA_DIR, $dbhr (database handle reference), $psc
#@OUTPUT     : 
#@RETURNS    : 1 or 0
#@DESCRIPTION: Verifies that the dps4 $file can be imported
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 2003/03/25, Jonathan Harlap
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub dps4_verify {
    my ($file, $real_ids, $DATA_DIR, $dbhr, $psc, $no_mail) = @_;
    open FILE, $file;
    my $line = <FILE>;
    chomp($line);
    close FILE;
    my @fields = split(/,,/, $line);

    if($file=~/y\.chr$/i) {
        if(
           $fields[0] eq '"DISC Predictive Scales (DPS) Report"'
           && $fields[17] =~ /"DPS-EYS(M|F)"/
           && $fields[5]+0 == $$real_ids{'CandID'}
           && lc($fields[9]) eq "\"$$real_ids{'PSCID'}\"")
        { return 1; }
    
        # we're missing valid ids...
        &error_mail($psc, "DPS4 file ".file_basename($file)." has an ID problem inside the file, please correct the IDs on this dataset, reexport and resend this data.", 'dps4', file_basename($file), $dbhr) unless $no_mail;
        return -1;
        
    } elsif($file=~/im\.chr$/i) {
        if(
           $fields[0] eq '"DPS-4 Impairment Module Report"'
           && $fields[14] =~ /"DPSIM-EY(M|F)"/
           && $fields[4]+0 == $$real_ids{'CandID'}
           && lc($fields[8]) eq "\"$$real_ids{'PSCID'}\"")
        { return 1; }
    
        # we're missing valid ids...
        &error_mail($psc, "DPS4 file ".file_basename($file)." has an ID problem inside the file, please correct the IDs on this dataset, reexport and resend this data.", 'dps4', file_basename($file), $dbhr) unless $no_mail;
        return -1;

    }
    return 0;
}

# ------------------------------ MNI Header ----------------------------------
#@NAME       : dps4_imp
#@INPUT      : $file (dps4 file), \%real_ids, $DATA_DIR, $dbhr (database handle ref), $psc (site name)
#@OUTPUT     : 
#@RETURNS    : 
#@DESCRIPTION: Imports the data from the dps4 file into the database
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 2003/03/25, Jonathan Harlap
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub dps4_imp {
    my ($file, $real_ids, $DATA_DIR, $dbhr, $psc) = @_;
    return 0 unless $file=~/(y|im)\.chr$/i;

    my $core_path = &core_path($real_ids);
    my $file_base = &file_basename($file);

    if($file=~/y\.chr$/i) {
        $query = "CREATE TEMPORARY TABLE IF NOT EXISTS dpsyTemp (
Im1  text,   /* test name title*/
Im2  text,   /* type*/
Im3  text,   /* print date title*/
Im4  text,   /* print date*/
Im5  text,   /* id title*/
Im6  text,   /* id number*/
Im7  text,   /* last name title*/
Im8  text,   /* l name */
Im9  text,   /* firstname title*/
Im10 text,   /* f name */
Im11 text,   /* age title*/
Im12 text,   /* age number*/
Im13 text,   /* sex title*/
Im14 text,   /* sex what*/
Im15 text,   /* sid title*/
Im16 text,   /* sid numebr*/
Im17 text,   /* interview title*/
Im18 text,   /* interview*/
Im19 text,   /* date title*/
Im20 text,   /* DATEinterview*/
Im21 text,   /* location title*/
Im22 text,   /* LOCATION */
Im23 text,   /* int type title*/
Im24 text,   /* interview TYPE*/
Im25 text,   /* iid title*/
Im26 text,   /* IID*/
Im27 text,   /* sougroup title*/
Im28 text,   /* SUBGROUP*/
Im29 text,   /* qid title*/
Im30 text,   /* gate title*/
Im31 text,   /* questions title*/
Im32 text,   /* answer  title*/
Im33 text,   /* score title*/
Im34 text,   /* QID*/
Im35 text,   /* GATE STAR*/
Im36 text,   /* QUESTIONS*/
Im37 text,   /* ANSWER*/
Im38 text,   /* SCORE*/
Im39 text,   /* Cut Off Gate*/
Im40 text,   /* subtotal score title*/
Im41 text,   /* SUBTOTAL SCORE*/
Im42 text,   /* page title*/
Im43 text   /* page number*/
);

DELETE FROM dpsyTemp;

LOAD DATA INFILE \"$file\"
into table dpsyTemp
FIELDS 
  terminated by ',,'
  optionally enclosed by '\"'
LINES
  terminated by '\\n';

DELETE FROM dpsy WHERE CommentID='$${real_ids{'CommentID'}}';


INSERT INTO dpsy 
SELECT 
'$${real_ids{'CommentID'}}' AS CommentID,
Im2 AS Im2, Im4 AS Im4, Im6 AS Im6, Im8 AS Im8, Im10 AS Im10, 
Im12 AS Im12, Im14 AS Im14, Im16 AS Im16, Im18 AS Im18, Im20 AS Im20, 
Im22 AS Im22, Im24 AS Im24, Im26 AS Im26, Im28 AS Im28, Im34 AS Im34, 
Im35 AS Im35, Im36 AS Im36, Im37 AS Im37, Im38 AS Im38, Im39 AS Im39, Im41 AS Im41 
FROM dpsyTemp;

SELECT \@date_taken := Im20
from dpsyTemp;



DELETE FROM dpsyTemp;


UPDATE dps4 SET
      Data_dir = '".$DATA_DIR."',
      Status = 'assembly',
      Core_path = '$core_path',
      File_type = 'dps4',
      File_name = '$file_base',
      File_y    = '$file_base'
                   WHERE CommentID='$${real_ids{'CommentID'}}';";

        &queue_query($query);
        #&run_queue(\$dbh);
    } elsif($file=~/im\.chr$/i) {
        $query = "CREATE TEMPORARY TABLE IF NOT EXISTS dpsimTemp (
Im1  text,   /* test name title*/
Im2  text,   /* print date title*/
Im3  text,   /* print date*/
Im4  text,   /* id title*/
Im5  text,   /* ID number*/
Im6  text,   /* last name title*/
Im7  text,   /* l name */
Im8  text,   /* firstname title*/
Im9  text,   /* f name */
Im10 text,   /* age title*/
Im11 text,   /* AGEnumber*/
Im12 text,   /* sex title*/
Im13 text,   /* SEX */
Im14 text,   /* interview title*/
Im15 text,   /* interview*/
Im16 text,   /* date title*/
Im17 text,   /* DATEinterview*/
Im18 text,   /* location title*/
Im19 text,   /* LOCATION */
Im20 text,   /* int type title*/
Im21 text,   /* interview WAY TYPE*/
Im22 text,   /* QID title*/
Im23 text,   /* questions title*/
Im24 text,   /* answer  title*/
Im25 text,   /* score title*/
Im26 text,   /* QID */
Im27 text,   /* QUESTION*/
Im28 text,   /* ANSWER*/
Im29 text,   /* SCORE*/
Im30 text,   /* total score title*/
Im31 text,   /* TOTAL SCORE*/
Im32 text,   /* page title*/
Im33 text   /* page number*/
);


LOAD DATA INFILE \"$data_root/$datadir/$file\"
  into table dpsimTemp
FIELDS 
  terminated by ',,'
  optionally enclosed by '\"'
LINES
  terminated by '\\n';

DELETE FROM dpsim WHERE CommentID='$${real_ids{'CommentID'}}';


INSERT INTO dpsim
SELECT 
'$${real_ids{'CommentID'}}' AS CommentID, 
Im3 AS Im3, Im5 AS Im5, Im7 AS Im7, Im9 AS Im9, Im11 AS Im11, 
Im13 AS Im13, Im15 AS Im15, Im17 AS Im17, Im19 AS Im19, Im21 AS Im21, 
Im26 AS Im26, Im27 AS Im27, Im28 AS Im28, Im29 AS Im29, Im31 AS Im31 
FROM dpsimTemp;

SELECT \@date_taken := im20
from dpsyTemp;



DELETE FROM dpsimTemp;


UPDATE dps4 SET
      Data_dir = '".$DATA_DIR."',
      Status = 'assembly',
      Core_path = '$core_path',
      File_type = 'dps4',
      File_im = '$file_base'
                   WHERE CommentID='$${real_ids{'CommentID'}}';";
      
        &queue_query($query);
        #&run_queue(\$dbh);
    }
}

# ------------------------------ MNI Header ----------------------------------
#@NAME       : disc_verify
#@INPUT      : $file (disc file), \%real_ids, $DATA_DIR, $dbhr (database handle reference), $psc
#@OUTPUT     : 
#@RETURNS    : 1 or 0
#@DESCRIPTION: Verifies that the disc $file can be imported
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 2003/03/25, Jonathan Harlap
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub disc_verify {

    my ($file, $real_ids, $DATA_DIR, $dbhr, $psc, $no_mail) = @_;
    my @lines = ();
    open DFILE, $file;
    while(<DFILE>) {
        chomp;
        s/\r//g;
        push @lines, $_;
    }
    close DFILE;
    
    if($file=~/\.ans$/i) {
        return 1;
    } elsif($file=~/\.rtf$/i) {
        if($lines[25]=~/\\par C-DISC Clinical Diagnostic Report/
           && $lines[28] =~ /$${real_ids{'PSCID'}}/i
           && $lines[29] =~ /00$${real_ids{'CandID'}}/
           )
        { return 1; }
        
        # we're missing valid ids...
        &error_mail($psc, "DISC file ".file_basename($file)." has an ID problem inside the file, please correct the IDs on this dataset, reexport and resend this data.", 'disc', file_basename($file), $dbhr) unless $no_mail;
        return -1;

    } elsif (index($file,'.') == -1) {
        if((($file =~ /y$/i && $lines[1]=~/C-DISC DIAGNOSTIC REPORT \(YOUTH\)/)
	    || (!($file =~ /y$/i) && $lines[1]=~/C-DISC DIAGNOSTIC REPORT \(PARENT\)/))
           && $lines[5]=~/00$${real_ids{'CandID'}}/
           && $lines[5]=~/$${real_ids{'PSCID'}}/i
           && $lines[9]=~/COMPUTER ASSISTED/
           && $lines[9]=~/ORIGINAL/
           )
        { return 1; }
    
        # we're missing valid ids...
        &error_mail($psc, "DISC file ".file_basename($file)." has an ID problem inside the file, please correct the IDs on this dataset, reexport and resend this data.", 'disc', file_basename($file), $dbhr) unless $no_mail;
        return -1;

    }
    return 0;
}


# ------------------------------ MNI Header ----------------------------------
#@NAME       : disc_imp
#@INPUT      : $file (disc file), \%real_ids, $DATA_DIR, $dbhr (database handle ref), $psc (site name)
#@OUTPUT     : 
#@RETURNS    : 
#@DESCRIPTION: Imports the data from the disc file into the database
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 2003/03/25, Jonathan Harlap
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub disc_imp {
    my ($file, $real_ids, $DATA_DIR, $dbhr, $psc) = @_;

    my $core_path = &core_path($real_ids);
    my $file_base = &file_basename($file);

        $query = "UPDATE disc
SET 
Data_dir      = '".$DATA_DIR."',
Status     = 'assembly',
Core_path      = '$core_path',
File_type      = 'disc',\n";

    if ($file =~ /\.rtf$/i) {
        $query .="File_cli";
    } elsif ($file =~ /\.ans$/i) {
        $query .="File_raw";
    } elsif (index($file, '.')==-1){
        $query .="File_diag";
    }

    if ($file =~ /y\./i) {
        $query .= "_y";
    }
    
    $query .= "='$file_base'\n";

    $query .= "WHERE CommentID = '$${real_ids{'CommentID'}}'";

    &queue_query($query);
    #&run_queue(\$dbh);
}

# ------------------------------ MNI Header ----------------------------------
#@NAME       : psi_verify
#@INPUT      : $file (psi file), \%real_ids, $DATA_DIR, $dbhr (database handle reference), $psc
#@OUTPUT     : 
#@RETURNS    : 1 or 0
#@DESCRIPTION: Verifies that the psi $file can be imported
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 2003/03/25, Jonathan Harlap
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub psi_verify {
    my ($file, $real_ids, $DATA_DIR, $dbhr, $psc, $no_mail) = @_;
    return 0 unless ($file=~/\.dat$/i || $file=~/\.rpt$/i);
    
    if($file=~/\.rpt$/i) {
        return 1;
    } elsif($file=~/\.dat$/i) {
        my %local_ids;
        my @fields;
        
        open FILE, $file;
        @fields = split(/,/, <FILE>);
        close FILE;
        
        $local_ids{'CandID'} = $fields[1];
        $local_ids{'PSCID'} = lc($fields[0]);
        
        if($local_ids{'CandID'} eq "\"$$real_ids{'CandID'}\"" && 
           $local_ids{'PSCID'} eq "\"$$real_ids{'PSCID'}\"" &&
           $#fields == 25 || $#fields == 26)
        {
            return 1;
        }
    
        # we're missing valid ids...
        &error_mail($psc, "PSI file ".file_basename($file)." has an ID problem inside the file, please correct the IDs on this dataset, reexport and resend this data.", 'psi', file_basename($file), $dbhr) unless $no_mail;
        return -1;

    }
    return 0;
}

# ------------------------------ MNI Header ----------------------------------
#@NAME       : psi_imp
#@INPUT      : $file (psi file), \%real_ids, $DATA_DIR, $dbhr (database handle ref), $psc (site name)
#@OUTPUT     : 
#@RETURNS    : 
#@DESCRIPTION: Imports the data from the psi file into the database
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 2003/03/25, Jonathan Harlap
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub psi_imp {
    my ($file, $real_ids, $DATA_DIR, $dbhr, $psc) = @_;

    my $core_path = &core_path($real_ids);
    my $file_base = &file_basename($file);

    if($file=~/\.dat$/i) {

        &queue_query(q(CREATE TEMPORARY TABLE IF NOT EXISTS import_test_psi(

PSCID char(7) not null, 
DCCID int(6) not null,  

Respondant text not null,                 
Ethnicity  text not null,		  
Resp_age   tinyint(2) unsigned not null,  
Name       text not null,		  
Child_age  tinyint(2) unsigned not null,  
DoT        date not null,		  

Unknown1   varchar(10) not null,	  

cAD  tinyint(2) unsigned not null, 
cAC  tinyint(2) unsigned not null, 
cDE  tinyint(2) unsigned not null, 
cMO  tinyint(2) unsigned not null, 
cDI  tinyint(2) unsigned not null, 
cRE  tinyint(2) unsigned not null, 
sCHD tinyint(3) unsigned not null, 
cDP  tinyint(2) unsigned not null, 
cAT  tinyint(2) unsigned not null, 
cRO  tinyint(2) unsigned not null, 
cCO  tinyint(2) unsigned not null, 
cIS  tinyint(2) unsigned not null, 
cSP  tinyint(2) unsigned not null, 
cHE  tinyint(2) unsigned not null, 
sPAD tinyint(3) unsigned not null, 
sTOT tinyint(3) unsigned not null, 
LS  tinyint(2) not null            

)
;

DELETE FROM import_test_psi;

LOAD DATA INFILE ")."$file".q(" 
    INTO TABLE import_test_psi
    FIELDS
	OPTIONALLY ENCLOSED BY '"'
        TERMINATED BY ','
    LINES TERMINATED BY '\n'
;

SELECT @dccid:=DCCID, @pscid:=PSCID, @dot:=DoT,
       @cad:=cAD, @cac:=cAC, @cde:=cDE, @cmo:=cMO, 
       @cdi:=cDI, @cre:=cRE,  @schd:=sCHD, 
       @cdp:=cDP, @cat:=cAT, @cro:=cRO, @cco:=cCO,  
       @cis:=cIS, @csp:=cSP, @che:=cHE, @spad:=sPAD,
       @stot:=sTOT, @ls:=LS         
FROM import_test_psi
;

UPDATE psi SET 
       cAD=@cad, cAC=@cac, cDE=@cde, cMO=@cmo, 
       cDI=@cdi, cRE=@cre, sCHD=@schd, 
       cDP=@cdp, cAT=@cat, cRO=@cro, cCO=@cco,  
       cIS=@cis, cSP=@csp, cHE=@che, sPAD=@spad,
       sTOT=@stot, LS=@ls, Date_taken=@dot
WHERE CommentID=)."'$${real_ids{'CommentID'}}'
;

UPDATE psi SET
      Data_dir = '".$DATA_DIR."',
      Status = 'assembly',
      Core_path = '$core_path',
      File_type = 'psi',
      File_name = '$file_base',
      File_export = '$file_base'
WHERE CommentID='$${real_ids{'CommentID'}}';");
    } elsif($file=~/\.rpt$/i) {

        &queue_query("UPDATE psi SET
      Data_dir = '".$DATA_DIR."',
      Status = 'assembly',
      Core_path = '$core_path',
      File_type = 'psi',
      File_report = '$file_base'
WHERE CommentID='$${real_ids{'CommentID'}}';");

    }
}

# ------------------------------ MNI Header ----------------------------------
#@NAME       : wj3_verify
#@INPUT      : $file (wj3 file), \%real_ids, $DATA_DIR, $dbhr (database handle reference), $psc
#@OUTPUT     : 
#@RETURNS    : 1 or 0
#@DESCRIPTION: Verifies that the wj3 $file can be imported
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 2003/03/25, Jonathan Harlap
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub wj3_verify {
    my ($file, $real_ids, $DATA_DIR, $dbhr, $psc, $no_mail) = @_;
    return 0 unless $file =~ /\.txt$/i;

    my @lines = `grep "Name:" $file`;
    my $line = $lines[0];
    
    chomp($line);
    $line =~ s/\s//g;
    my @fields = split(/[:,]/, $line);
    my %local_ids;

    $local_ids{'CandID'} = $fields[1] + 0;
    $local_ids{'PSCID'} = lc($fields[2]);

    if($local_ids{'CandID'} == $$real_ids{'CandID'} && 
       $local_ids{'PSCID'} eq $$real_ids{'PSCID'})
    {
        return 1;
    }
    
    # we're missing valid ids...
    &error_mail($psc, "WJ3 file ".file_basename($file)." has an ID problem inside the file, please correct the IDs on this dataset, reexport and resend this data.", 'wj3', file_basename($file), $dbhr) unless $no_mail;

    return -1;
}

# ------------------------------ MNI Header ----------------------------------
#@NAME       : wj3_imp
#@INPUT      : $file (wj3 file), \%real_ids, $DATA_DIR, $dbhr (database handle ref), $psc (site name)
#@OUTPUT     : 
#@RETURNS    : 
#@DESCRIPTION: Imports the data from the wj3 file into the database
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : 
#@CREATED    : 2003/03/25, Jonathan Harlap
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub wj3_imp {
    my ($file, $real_ids, $DATA_DIR, $dbhr, $psc) = @_;

    my $core_path = &core_path($real_ids);
    my $file_base = &file_basename($file);

# open the data file
open UPLOAD_FILE, $file;

while ($line = <UPLOAD_FILE>){

    # pulls out all the headers
    if ($line =~ /CLUSTER\/Test/g){
        $line =~ s/to/ /;
        $line =~ s/SS\(68\% BAND\)/ss68bandmax ss68bandmin/;

        @headerbits = split ' ', $line;
        shift @headerdatabits;
    }

    # pulls out the data values for the calculation scores
    if ($line =~ /Calculation/g){
        $line = reverse $line;
        $line =~ s/\(/ /;
        $line =~ s/\)/ /;
        $line =~ s/-/ /;
        $line = reverse $line;

        @cal_databits = split ' ', $line;
        shift @cal_databits;
    }
    
    # pulls out the data values for the letter-word scores
    if ($line =~ /Letter-Word Identification/g){
        $line =~ s/Letter-Word Identification/LetWordID/;
        $line = reverse $line;
        $line =~ s/\(/ /;
        $line =~ s/\)/ /;
        $line =~ s/-/ /;
        $line = reverse $line;

        @let_databits = split ' ', $line;
        shift @let_databits;
    }    

    # pulls out the data for the passage comprehension scores
    if ($line =~ /Passage Comprehension/g){
        $line =~ s/Passage Comprehension/PassageComp/;
        $line = reverse $line;
        $line =~ s/\(/ /;
        $line =~ s/\)/ /;
        $line =~ s/-/ /;
        $line = reverse $line;

        @pass_databits = split ' ', $line;
        shift @pass_databits;
    }

    #Finds and stores date
    if ($line =~ /Date of Testing/g) {
        # read M/D/Y into Y-M-D
        $line =~ /([0-9]{1,2})\/([0-9]{1,2})\/([0-9]{2,4})/;
        $date_taken = "$3-$1-$2";

    # Finish...
    }
}

# build the query to be used
$query = "UPDATE wj3 SET\n"; 

# assoc. letter-word data with db fields
foreach $i (0..(scalar(@headerbits)-1)){
    $j = $i +1; 
    $query .= "L$j=\'$let_databits[$i]\', ";
}

# assoc. calculation data with db fields
foreach $i (0..(scalar(@headerbits)-1)){
    $j = $i +1; 
    $query .= "C$j=\'$cal_databits[$i]\', ";
}

# assoc. passage comprehension data with db fields
foreach $i (0..(scalar(@headerbits)-1)){
    $j = $i +1; 
    $query .= "P$j=\'$pass_databits[$i]\'";
    $query .= ", ";    
}

# who|what|where should this data go?
$query .= "Data_dir = '".$DATA_DIR."',
      Status = 'assembly',
      Core_path = '$core_path',
      File_type = 'wj3',
      File_name = '$file_base',\n";

$query .= "\nDate_taken='$date_taken'\nWHERE CommentID='$${real_ids{'CommentID'}}';\n"; 


# execute the query
    &queue_query($query);
    #&run_queue(\$dbh);
}

1;
