#!/usr/local/bin/perl5 -w
#
# Andrew Janke - rotor@bic.mni.mcgill.ca
# generate html files for checking
#
# Sun Feb  3 20:31:21 EST 2002 - intital version
# Sun Feb 10 20:33:16 EST 2002 - moved html code from *_check to here
# May 1 - changed for NIHPD - Louis.

use Getopt::Tabular;
use pipeline_functions;
use MNI::Spawn;
use File::Basename;

MNI::Spawn::SetOptions (verbose => 0,execute => 1,strict  => 0);

$| = 1;

sub id_scan
{
    my ($minc, $psc) = @_;
    my $dbh = &connect_to_db();
    
    my @headers;
    my $acq_date;
    my %minc_ids;
    my $type;
    
    &get_headers($minc, \@headers);
    $acq_date = get_info('dicom_0x0008:el_0x0020', '-', \@headers); #acq_date
    $acq_date =~ s/-//g;
    
    &get_ids(\@headers, \%minc_ids, $psc);
    &get_objective(\%minc_ids, $acq_date, \$dbh);
#$minc_ids{'objective'} = 1;
    $type = &identify_scan_db($psc, $minc_ids{'objective'}, \@headers, \$dbh);
    my $series_description = get_info('dicom_0x0008:el_0x103e', '-', \@headers);
    print "$type ($minc) ($series_description)\n";
    
    my $new_type = identify_scan_db($rowhr->{'Center_name'}, $rowhr->{'Objective'}, 
\@headers, \$dbh);
    print($new_type);
}




chomp($me = `basename $0`);
$verbose         = 0;
$clobber         = 0;
$main            = 0;
$debug           = 0;
$checks_todo[0]  = '';
@opt_table = (
              ["-debug",   "boolean",  0,         \$debug,   "turn on debug"              ],
              ["-verbose", "boolean",  0,         \$verbose, "be verbose"                 ],
              ["-clobber", "boolean",  0,         \$clobber, "clobber existing files"     ],
              ["-main",    "boolean",  0,         \$main,    "generate main index file"   ],
              );

if ($debug) {
  $verbose = 1;

}


foreach $c (@checks){
    push(@opt_table, ["-$c", "const", $c, \$checks_todo[0], "do $c html check files" ]);
   }

# Check arguments
&GetOptions (\@opt_table, \@ARGV) || exit 1;
if($#ARGV < -1){ die "Usage: $me [options] [subject [subject] [...]]\n" }

@all_checks = split("\n", `./pipeline_constants -checks`);
@checks = split("\n", `./pipeline_constants -checks`);

@pats_todo = @ARGV[0..$#ARGV];

# global pipeline_constants

chomp ($main_html = `./pipeline_constants -htmlfile`);

#chomp($prim_modal = `pipeline_constants -prim_modal`);
#chomp($mod_ext = `pipeline_constants -mod_ext`);



# make the main index if asked
if($main){
    print("hmm");
    @subjects_unordered = pipeline_functions::get_list_passed_subjects_with_check();
    @subjects = sort { $a cmp $b } @subjects_unordered ;
    print("now\n\n\n\n");
    print("$main_html");
    $outfile = $main_html;

    
   if(-e $outfile && !$clobber){
      die "$me: $outfile exists! use -clobber to overwrite\n";
      }
   
   if($verbose){
      print STDOUT "$me: generating $outfile\n";
      }

   open(HTML, ">$outfile");
   print HTML "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 3.2//EN\">\n".
              "<HTML>\n".
              "<HEAD>\n".
              "<TITLE>main index for NIHPD data</TITLE>\n".
              "</HEAD>\n".
              "<BODY>\n".
              "<H1>main index for NIHPD data $#subjects subjects</H1>\n";

   print HTML "<PRE>\n";
   foreach $line (@subjects){
       ($subject, $data_path) = split (" ",$line);
       #print("processing $subject\n");

       
       $htmldir  = "${data_path}\/work\/html\/";
       print HTML "$subject ";

       foreach $c (@all_checks){
	   print HTML "<A HREF=\"$htmldir/$subject\_$c.html\">$c</A>|";
       }
       print HTML "\n";

}
   print HTML "</PRE>\n";

   print HTML "</BODY>\n".
              "</HTML>\n";
   close(HTML);

   exit;

}

# subjeck check files
# set up the pats array
if(!defined @pats_todo){
   warn "*** $me: No input subjects, doing the lot\n";
   @pats_todo = @subjects;
   }

# set up checks array
if($checks_todo[0] eq ''){
   warn "*** $me: No input checks, doing the lot\n";
   @checks_todo = @checks;
   }





foreach $subject_visit (@pats_todo){

   # set up the required arrays

   ($subject, $visit) = split(":", $subject_visit);

   $search_criteria = "select concat_ws(' ', scan_type, objective, concat_ws('/', Data_path, Core_path, File_type, File_name), mriid, selected) from  mri where CandID = '$subject' and VisitNo = $visit and File_type = 'native'";
   @types_all = pipeline_functions::make_query($search_criteria);

   @types_selected = pipeline_functions::get_selected_files($subject_visit, "scan_type, objective, complete_path, mriid, selected");
   @mriid_list = pipeline_functions::get_selected_files($subject_visit, "mriid");
  

   if(length(@types_selected) == 3)
   {
       $three_processable = 1;
   }
 
  # check and make the output directory if needed
   ($type) = split(' ',$types_all[0]);


   chomp ($checkdir = pipeline_functions::get_checkdir_from_subject_visit($subject_visit));

   $htmldir  = $checkdir; $htmldir  =~ s/check/html/;
   $reportdir = $checkdir; $reportdir =~ s/check/report/;

   if(!-e $htmldir){
       warn "$me: Making directory $htmldir\n";
       system('mkdir', $htmldir) == 0 or die;
   } 

   if($verbose){
      print STDOUT "HTML $subject_visit: ";
      }

   @complete_list = pipeline_functions::get_list_passed_subjects();
# set up subject_visits reverse hash
   for($c = 0; $c <= $#complete_list; $c++){   
       $pat_r{$complete_list[$c]} = $c;
   }

   # get the prev and next subject_visit in the list
   $index = $pat_r{$subject_visit};
   $prev = ($index != 0)          ? $complete_list[$index - 1] : "";
   $next = ($index != $#complete_list) ? $complete_list[$index + 1] : "";
   
  
   if ($prev) 
   { 
       chomp($prevcheckdir = pipeline_functions::get_checkdir_from_subject_visit($prev));
       $prevdir  = $prevcheckdir; $prevdir  =~ s/check/html/;
   }
   else {$prevdir=""};

   if ($next) 
   { 
       chomp($nextcheckdir = pipeline_functions::get_checkdir_from_subject_visit($next));
       $nextdir  = $nextcheckdir; $nextdir  =~ s/check/html/;
   }
   else {$nextdir=""}; 

   # foreach todo
   foreach $todo (@checks_todo){

       if ($todo eq "mnc") {
	   @table_types = @types_all;
       }
       elsif($todo eq "selected") {
	   @table_types = @types_selected;
       }	  
       elsif($todo eq "tal") {
	   @table_types  =pipeline_functions::get_processed_files_from_mriid("scan_type, objective,complete_path, mriid, source_list", "final/$todo", @mriid_list);
	   ($d, $d, $tal_path, $d, $source_list)= split(" ", $table_types[0]);
	   $fallbackdir = dirname($tal_path);
	   $fallbackdir =~ s/final\/tal/work\/tmp/;
	   $fallbackfile ="$tmpdir\/T1.${source_list}.tal_fallback.mnc";
	   $out_line = "5 1 $outfile NA $source_list";
	   @table_types = (@table_types, $out_line);
	   
	   print("OUTPUT @table_types\n\n\n");
       }	  
             
       else  {
	   @table_types  =pipeline_functions::get_processed_files_from_mriid("scan_type, objective,complete_path, mriid, source_list", "final/$todo", @mriid_list);
       } 
      if($verbose){
         print STDOUT "Matthew:$todo\n";
         }
       print("\n\n$todo\n@table_types\n\n");
     
      $outfile = "$htmldir/$subject_visit\_$todo.html";
      if(-e $outfile && !$clobber){
         warn "$me: $outfile exists! use -clobber to overwrite\n";
         next;
         }

      # make helper files
      # animate
      # $filen = "$datadir/html/$subject_visit\_$todo.animate";
      # open(FH, ">$filen");
      # foreach(@types){
      #    print FH "../check/$subject_visit/$subject_visit.$_.$todo.jpg ";
      #    }
      # print FH "-delay 10 ";
      # close(FH);

       #$num = scalar @table_types;
       #$extra_info .= " $num";
       print("############Creating HTML page:$outfile\n");
       
       
       open(HTML, ">$outfile") ;
       print HTML "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 3.2//EN\">\n".
                 "<HTML>\n".
                 "<HEAD>\n".
		     ##TODO ADD extra info
                 "<TITLE>$subject_visit - $todo</TITLE>\n".
                 "</HEAD>\n".
                 "<BODY>\n";


      print HTML "<TABLE BORDER=\"0\">\n".
                 "   <TR>\n".
                 "      <TD>prev</TD>\n".
                 "      <TD>current</TD>\n".
                 "      <TD>next</TD>\n".
                 "      <TD><a href=\"$main_html\">home</a></TD>\n".
                 "   </TR>\n".
                 "   <TR>\n".
                 "      <TD><H4><A HREF=\"$prevdir/$prev\_$todo.html\">$prev</A></H4></TD>\n".
                 "      <TD><H1>$subject_visit</H1></TD>\n".
                 "      <TD><H4><A HREF=\"$nextdir/$next\_$todo.html\">$next</A></H4></TD>\n".
                 "   </TR>\n".
                 "</TABLE>\n";

      print HTML "<PRE>";
                 foreach $c (@all_checks){
                    if($c eq $todo){
                       print HTML "<B>$c</B>|";
                       }
                    else{
                       print HTML "<A HREF=\"$htmldir/$subject_visit\_$c.html\">$c</A>|";
                       }
                    }
      print HTML "</PRE>\n";


				# if raw data, then show everything, else
				# show only a table of the anatomical scans.
 

      if ($todo eq "selected") {
	  $todo = "mnc";
      }
      
      if(!$three_processable && $todo =~ 'cls' && $todo eq 'seg' && $todo eq 'lob')
      {
	  print HTML "Three Anatomical scans have not been selected<br>";
	  next;
      }
      
      if($todo eq 'cls' || $todo eq 'cls_msk' || $todo eq 'tal' || $todo eq 'tal_msk' || $todo eq 'nl1' || $todo eq 'pve' || $todo eq 'seg' || $todo eq 'lob')
      {  
	  
	 ($type, $objective) = split(" ", $types_all[0] );
	 if($objective eq '2')
	 {
	  print HTML "Objective two cannot process tal or classified<br>";
	  next;
	 }
     }
     if ($todo eq  'final' || $todo eq  'msk_final' || $todo eq  'clp_msk')
     {
	 print HTML "final and msk_final pages are not implemented yet<br>";
	 next;
     }

      # now the table
      print HTML "<TABLE BORDER=\"0\">\n";

      print HTML "   <TR>\n";
         foreach(@table_types){ 
	     chomp;
	     ($type, $objective, $thefile) = split (" ",$_ );
	     $type =~ s/ //g;
	     
	 }
      print HTML "   </TR>\n";
      print HTML "</form>\n";


      # now the table
      print HTML "<TABLE BORDER=\"0\">\n";

      if(!($todo eq 'cls') && !($todo eq 'smt'))
      {
      print HTML "   <TR>\n";
         foreach(@table_types){ 

	     chomp;
	     ($type, $objective, $thefile) = split (" ",$_ );

	     $type =~ s/ //g;
	     $thefile =~ s/ //g;
	     chomp($file = `basename $thefile`);
	     $file =~ s/\.gz//;
	     $file =~ s/\.mnc//;
	
	     </td>
	 }
      print HTML "   </TR>\n";
      print HTML "</form>\n";
  }



      print HTML "   <TR>\n";
         foreach(@table_types){ 
	     chomp;
	     ($type, $objective,$thefile, $mriid, $selected) = split (" ",$_ );
	     
#	     $type =~ s/ //g;

	     chomp($file = `basename $thefile`);
	     $file =~ s/\.gz//;
	     $file =~ s/\.mnc//;
 	     print HTML "      <TD>$file</TD>\n";
	 }
      print HTML "   </TR>\n";

      print HTML "   <TR>\n";
         foreach $line(@table_types){
	     
	     chomp($line);
	     
	     ($type, $objective,$thefile, $mriid, $selected) = split (" ",$line );

	     if(!$selected){$selected = "unknown"};
	     print("Including file $thefile\n");

	     chomp($file = `basename $thefile`);
	     $file =~ s/\.gz//;
	     $file =~ s/\.mnc//;

	     
	     if($selected =~ /T1/)
	     {
		 print HTML "<TD>Current T1</TD>";
	     }
	     elsif($selected =~ /T2/)
	     {
		 print HTML "<TD>Current T2</TD>";
	     }

	     elsif($selected =~ /PD/)
	     {
		 print HTML "<TD>Current PD</TD>";
	     }
	     else{print HTML "<TD></TD>";}

	 }
      print HTML "   </TR>\n";

      print HTML "   <TR>\n";
      foreach(@table_types){
	  chomp;
	  ($type, $objective, $thefile, $MRIID) = split (" ",$_ );
	  
	  $r1 = $thefile;
	  
	  $r2 = "";
	  $img_src = "$checkdir/$MRIID.jpg";

	  if($todo eq 'tal_msk' || $todo eq 'cls' || $todo eq 'cls_msk' || $todo eq 'pve' || $todo eq 'seg' || $todo eq 'lob'){
	      @tal_file  =pipeline_functions::get_processed_files_from_mriid_scan_type("complete_path", "final/tal", 'obj1_t1w', @mriid_list);
	      $r2 = $tal_file[0];
	  }
	  if($todo eq 'nl1')
	  {
	      chomp($model    = `./pipeline_constants -model_nl`);
	      #chomp($model_mask    = `./pipeline_constants -model_nl_mask`);
	      chomp($modeldir = `./pipeline_constants -modeldir_nl`);
	      $r2  = "$modeldir/$model.mnc";
	      
	  }
	  # register helper
	  $regfile = "$htmldir/$file.$MRIID.$todo.register";
	  open(FH, ">$regfile");
	  print FH "$r1 $r2\n";
	  close(FH);
   
	  print HTML "      <TD><A HREF=\"$regfile\">";
	
	  print HTML " <IMG SRC=\"$img_src\"></A></TD>\n";
      }
      print HTML "   </TR>\n";

      print HTML "   </TABLE>\n";

  }
   print HTML "</BODY>\n".
       "</HTML>\n";

   close(HTML);
  
}
   


