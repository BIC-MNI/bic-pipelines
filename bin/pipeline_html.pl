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
$debug          = 0;
$do_only_obj_1   = 0;


$checks_todo[0]  = '';
@opt_table = (
              ["-debug",   "boolean",  0,         \$debug,   "turn on debug"              ],
              ["-verbose", "boolean",  0,         \$verbose, "be verbose"                 ],
              ["-clobber", "boolean",  0,         \$clobber, "clobber existing files"     ],
              ["-main",    "boolean",  0,         \$main,    "generate main index file"   ],
	      ["-only_obj_1",    "boolean",  0,         \$do_only_obj_1,    "do only objective 1 files "   ],
              );

if ($debug) {
  $verbose = 1;

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
if($do_only_obj_1) 
{ 
    $main_html =~ s/\.html/_only_obj_1\.html/;
}



# make the main index if asked
if($main){
    
   
    if(!$do_only_obj_1)
    {
	@subjects_unordered = pipeline_functions::get_list_passed_subjects_with_check();
    }
    else
    { 
	@subjects_unordered = pipeline_functions::get_list_passed_subjects_with_check(1);
	
    }
    
    
       
    @subjects = sort { $a cmp $b } @subjects_unordered ;
    
    if(!$do_only_obj_1)
    {

	$search_criteria = "select distinct concat_ws(' ',concat_ws(':', mri_visit_status.CandID, mri_visit_status.visitno)) from mri_visit_status,mri where mri_visit_status.CandID>0 and mri_visit_status.QCStatus='Pass' and mri_visit_status.Pending='N' and mri.CandID = mri_visit_status.CandID and mri.visitno = mri_visit_status.visitno and mri.objective = 1 order by mri.CandID";
	@complete_list = pipeline_functions::make_query($search_criteria);
    }
    elsif($do_only_obj_1)
    {

	$search_criteria = "select distinct mri.candid from mri_visit_status,mri where mri_visit_status.CandID>0 and mri_visit_status.QCStatus='Pass' and mri_visit_status.Pending='N' and mri.CandID = mri_visit_status.CandID and mri.visitno = mri_visit_status.visitno and mri.objective = 1 order by mri.CandID";
	@number_candidates = pipeline_functions::make_query($search_criteria);
	
	$numbers_text = "$#subjects  visits from  subjects $#number_candidates";
    }   

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
              "<H1>main index for NIHPD data $numbers_text</H1>\n";

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

   #$search_criteria = "select concat_ws(' ', scan_type, objective, concat_ws('/', Data_path, Core_path, File_type, File_name), mriid, selected) from  mri where CandID = '$subject' and VisitNo = $visit and File_type = 'native'";
   #@types_all = pipeline_functions::make_query($search_criteria);

   @types_selected = pipeline_functions::get_selected_files($subject_visit, "scan_type, objective, complete_path, mriid, selected, file_type");
   @mriid_list = pipeline_functions::get_selected_files($subject_visit, "mriid");
  

   if(length(@types_selected) == 3)
   {
       $three_processable = 1;
   }
 
  # check and make the output directory if needed
  # ($type) = split(' ',$types_all[0]);


   chomp ($checkdir = pipeline_functions::get_checkdir_from_subject_visit($subject_visit));

   $htmldir  = $checkdir; $htmldir  =~ s/check/html/;
   $reportdir = $checkdir; $reportdir =~ s/check/report/;

   #`rm $htmldir/*`;
   #print("hmmm rming\n\n\n\n\n");
   if(!-e $htmldir){
       warn "$me: Making directory $htmldir\n";
       system('mkdir', $htmldir) == 0 or die;
   } 

   if($verbose){
      print STDOUT "HTML $subject_visit: ";
  }
   if(!$do_only_obj_1)
   {
       @complete_list = pipeline_functions::get_list_passed_subjects();
   }
   else
   {
       @complete_list = pipeline_functions::get_list_passed_subjects(1);
   }

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

       $outfile = "$htmldir/$subject_visit\_$todo.html";
       
       if(-e $outfile && !$clobber){
	   warn "$me: $outfile exists! use -clobber to overwrite\n";
	   next;
       }


       @table_types = ();
       if($todo eq "selected") {
	   @table_types = @types_selected;
	   @list = ();
       }	  
       elsif($todo eq "anatomicals")
       {
	   @anat_list = ('clp', 'crp', 'nuc');
	   foreach $temp_type(@anat_list)
	   {

	       $search_criteria = "select concat_ws(' ', scan_type, objective, concat_ws('/', Data_path, Core_path, File_type, File_name), mriid, source_list, file_type) from  mri where CandID = '$subject' and VisitNo = $visit and File_type = 'final/$temp_type'";
	       @temp = pipeline_functions::make_query($search_criteria);
	       @table_types = (@table_types, @temp);
	       
	   }
       
       }
       elsif($todo eq "normalized_registrations")
       {
	   @anat_list = ("tal_msk_normalized", "nl1_msk_normalized");
	   foreach $temp_type(@anat_list)
	   {

	       $search_criteria = "select concat_ws(' ', scan_type, objective, concat_ws('/', Data_path, Core_path, File_type, File_name), mriid, source_list, file_type) from  mri where CandID = '$subject' and VisitNo = $visit and File_type = 'final/$temp_type'";
	       @temp = pipeline_functions::make_query($search_criteria);

	       @table_types = (@table_types, @temp);
	       
	   }
       }
       elsif($todo eq "registrations")
       {
	   @anat_list = ('tal', 'nl1');
	   foreach $temp_type(@anat_list)
	   {

	       $search_criteria = "select concat_ws(' ', scan_type, objective, concat_ws('/', Data_path, Core_path, File_type, File_name), mriid, source_list, file_type) from  mri where CandID = '$subject' and VisitNo = $visit and File_type = 'final/$temp_type'";
	       @temp = pipeline_functions::make_query($search_criteria);

	       @table_types = (@table_types, @temp);
	       
	   }	   
       }
       elsif($todo eq "classifications")
       {
	   @list = ("cls_tal_msk", "cls_nl1_msk");
       }
       elsif($todo eq "pve")
       {
	   @list = ("pve_tal_wm", "pve_tal_gm", "pve_tal_csf", "pve_nl1_wm", "pve_nl1_gm", "pve_nl1_csf");
       }
       elsif($todo eq "segmentations")
       {
	   @list = ("lob_tal", "lob_nl1", "seg_tal", "seg_nl1");
       }
       elsif($todo eq "smooth")
       {
	   @list = ("smooth_tal_wm", "smooth_tal_gm", "smooth_tal_csf", "smooth_nl1_wm", "smooth_nl1_gm", "smooth_nl1_csf");
       }

      
       foreach $temp_type(@list)
       {
	   $search_criteria = "select concat_ws(' ', scan_type, objective, concat_ws('/', Data_path, Core_path, File_type, File_name), mriid, source_list, file_type) from  mri where CandID = '$subject' and VisitNo = $visit and File_type = 'final/$temp_type'";
	   @temp = pipeline_functions::make_query($search_criteria);
	   @table_types = (@table_types, @temp);
       }
        
      if($verbose){
         print STDOUT "Matthew:$todo\n";
         }
       print("\n\n$todo\n@table_types\n\n");
     


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
	     ($type, $objective,$thefile, $mriid, $selected, $file_type) = split (" ",$_ );
	     
	     $search_criteria = "select scan_type from mri_scan_type  where id = $type";
	     @real_type = pipeline_functions::make_query($search_criteria);

#	     $type =~ s/ //g;

	     chomp($file = `basename $thefile`);
	     $file =~ s/\.gz//;
	     $file =~ s/\.mnc//;
 	     print HTML "<TD>$real_type[0]</TD>\n";
	 }
      print HTML "   </TR>\n";

      print HTML "   <TR>\n";
         foreach(@table_types){ 
	     chomp;
	     ($type, $objective,$thefile, $mriid, $selected, $file_type) = split (" ",$_ );
	     $file_type =~ s/final\///;
 	     print HTML "<TD>$file_type</TD>\n";
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

	  if($thefile =~ /tal/){
	      @tal_file  =pipeline_functions::get_processed_files_from_mriid_scan_type("complete_path", "final/tal", 'obj1_t1w', @mriid_list);
	      $r2 = $tal_file[0];
	      
	  }
	  elsif($thefile =~ /nl1/)
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
	  print("img source: $img_src\n");
	  print HTML " <IMG SRC=\"$img_src\"></A></TD>\n";
      }
      print HTML "   </TR>\n";

      print HTML "   </TABLE>\n";

  
       print HTML "</BODY>\n".
	   "</HTML>\n";
       
       close(HTML);
   }
}
   

