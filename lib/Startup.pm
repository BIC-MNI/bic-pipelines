# ------------------------------ MNI Header ----------------------------------
#@NAME       : Startup.pm
#@INPUT      : 
#@OUTPUT     : 
#@RETURNS    : 
#@DESCRIPTION: Code that should be executed in all "serious" (long-running, 
#              usually) Perl scripts.
#
#              Please read all comments here before using!
#@METHOD     : 
#@GLOBALS    : The following subroutines are exported into the namespace
#              of your main program:
#                 &Startup
#                 &SelfAnnounce
#                 &Shutdown
#                 &Cleanup
#                 &Fatal
#              Also, the following variables are exported by tha package,
#              but only set when you call &Startup:
#                 $ProgramPath, $ProgramName - the two components of $0
#                 $TmpDir   - a (hopefully) uniquely named temporary directory
#                 $StartDir - the working directory at startup
#                 $StartDirName - the final component of the directory from 
#                    which we were run (eg. if pwd = "/usr/local/poobah" on
#                    startup, then $StartDirName will be "poobah")
#
#                 @DefaultArgs - a basic argument table (for use with my
#                    ParseArgs package) for setting common globals
#                    ($Verbose, $Execute, $Debug, $Clobber, $Debug, $TmpDir,
#                    and $KeepTmp) via common options (-verbose, -execute,
#                    -debug, etc)
#                 $KeepTmp - set to 0; change this to 1 to prevent deleting
#                    the temporary directory and everything in it.
#
#              These flags aren't actually used by anything in startup.pl,
#              but are frequently useful and can be changed by the 
#              arguments in @DefaultArgs:
#
#                 $Verbose - a commonly-used flag that controls whether
#                     your program should be noisy or quiet; set to 1
#                 $Execute - a commonly-used flag that controls whether
#                     subprograms are actually run (and various other
#                     outside-world-interaction stuff, depending on the
#                     application; set to 1
#                 $Clobber - flag denoting whether your program should
#                     overwrite existing files (and tell subprograms to
#                     do the same)
#                 $Debug   - turns on even more verbosity (and tell 
#                     subprograms to do the same)
#
#              Also, &Startup modifies the %SIG builtin hash to install
#              a handler for various signals.  (The handler just prints
#              out what signal was received, calls &Cleanup [to
#              nuke the contents of $TmpDir], and exits with non-zero
#              return status.)
#
#@CALLS      : 
#@CREATED    : 95/05/16, Greg Ward: from code in mritotal, do_mritopet, and
#                        autocrop
#@MODIFIED   : 95/07/07, GW: renamed from gpw_common.pl to startup.pl,
#                        moved the actual startup code into &Startup,
#                        added tons of comments
#              95/08/22, GW: removed $PrintTimes from list of needed globals
#                        (now it's just a parameter to &Cleanup); cosmetic
#                        and doc changes
#              96/03/21, GW: rearranged shutdown sequence, added/edited
#                        tons of comments
#@COMMENTS   : 
#@VERSION    : $Id: Startup.pm,v 1.1.1.1 2004/12/02 21:27:32 lbaer Exp $
#----------------------------------------------------------------------------

# --------------------------------------------------------------------
# Copyright (c) 1995 Greg Ward, McConnell Brain Imaging Centre,
# Montreal Neurological Institute, McGill University.  Permission to
# use, copy, modify, and distribute this software and its
# documentation for any purpose and without fee is hereby granted,
# provided that the above copyright notice appear in all copies.  The
# author and McGill University make no representations about the
# suitability of this software for any purpose.  It is provided "as
# is" without express or implied warranty.
# --------------------------------------------------------------------

# To use startup.pl, you should (obviously) have `require "startup.pl"'
# in your code.  Then, before any serious work (eg. creating
# directories, processing files, etc.) is done, call &Startup.  See
# &Startup for a complete list of everything it does.
# 
# Then, once serious processing has begun (ie. if there might be files
# in $TmpDir), you should call &Fatal instead of die for any errors;
# this will properly clean up and leave a non-zero exit status for the
# caller.)  (Note: calling die will also result in $TmpDir being cleanup
# up, but you have to worry about putting a newline at the end of the
# error string in order to prevent the "in xxx line yyy" message.
# However, you don't have to worry about any modules calling die (or
# croak) -- your program will still clean up correctly, thanks to the
# "die handler" set by &Startup.)
# 
# When everything finishes normally, call &Shutdown as one of the last
# things you do.  (It doesn't have to be the last, as it doesn't exit --
# it just prints out some timing stats and nukes the temporary
# directory.)

# ------------------------------------------------------------------ #

package Startup;

require 5.001;
require Exporter;

@ISA = qw/Exporter/;
@EXPORT = qw/&Startup &SelfAnnounce &Cleanup &Shutdown &Fatal &cleanup_and_die
             $ProgramPath $ProgramName $StartDir $StartDirName $TmpDir
             @DefaultArgs $KeepTmp $Verbose $Execute $Clobber $Debug $KeepTmp/;
            


# ------------------------------------------------------------------ #
#   public subroutines                                               #
# ------------------------------------------------------------------ #

$KeepTmp = 1;			# so we don't nuke current dir if
				# caller forgets to call &Startup


# ------------------------------ MNI Header ----------------------------------
#@NAME       : &Startup
#@INPUT      : none
#@OUTPUT     : none (well, a bunch of globals shoved into your namespace)
#@RETURNS    : 
#@DESCRIPTION: Call this when your program starts -- this performs a number
#              of tasks that are almost always useful in long-running Perl
#              scripts:
#                 * sets a bunch of globals (see above)
#                 * sets a signal handler for the more common signals
#                 * sets a handler for die (this and the signal handler
#                   both result in &Cleanup being called, so that 
#                   $TmpDir is blasted away unless $KeepTmp is true)
#                 * unbuffers STDOUT and STDERR (handy for "tail -f"'ing 
#                   log files
#@METHOD     : 
#@GLOBALS    : $ProgramPath, $ProgramName,
#              $TmpDir
#              $StartDir, $StartDirName
#              @DefaultArgs
#              $Verbose, $Execute, $Clobber, $Debug, $KeepTmp
#@CALLS      : 
#@CREATED    : 
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub Startup
{
   ($ProgramPath,$ProgramName) = $0 =~ /(.*\/)?([^\/]*)/;
   $ProgramPath = "" unless defined $ProgramPath;
   $ProgramPath =~ s|/$||;	# strip trailing slash

   my ($basetmp) = (defined ($ENV{"TMPDIR"}) ? $ENV{"TMPDIR"} : "/tmp");
   $TmpDir = ($basetmp . "/${ProgramName}_$$");
   
   chop ($StartDir = `pwd`);
   ($StartDirName) = $StartDir =~ /.*\/([^\/]+)/;

   $SIG{'INT'} = 
   $SIG{'TERM'} = 
   $SIG{'QUIT'} =
   $SIG{'HUP'} =
   $SIG{'PIPE'} = \&catch_signal;

   $SIG{'__DIE__'} = \&Cleanup;
   
   select (STDERR); $| = 1;
   select (STDOUT); $| = 1;
   
   @start_times = times;

   $Verbose = 1;
   $Execute = 1;
   $Clobber = 0;
   $Debug = 0;
   $KeepTmp = 0;

   @DefaultArgs =
      (["Basic behaviour options", "section"],
       ["-verbose|-quiet", "boolean", 0, \$Verbose, 
	"print status information and command lines of subprograms " .
	"[default; opposite is -quiet]" ],
       ["-execute|-noexecute", "boolean", 0, \$Execute, 
	"actually execute planned commands [default]"],
       ["-clobber|-noclobber", "boolean", 0, \$Clobber,
	"blithely overwrite files (and make subprograms do as well) " .
	"[default: -noclobber]"],
       ["-debug|-nodebug", "boolean", 0, \$Debug,
	"spew lots of debugging info (and make subprograms do so as well) " .
	"[default: -nodebug]"],
       ["-tmpdir", "string", 1, \$TmpDir,
	"set the temporary working directory"],
       ["-keeptmp|-nokeeptmp", "boolean", 0, \$KeepTmp,
	"don't delete temporary files when finished [default: -nokeeptmp]"]);
}


# ------------------------------ MNI Header ----------------------------------
#@NAME       : &SelfAnnounce
#@INPUT      : $filehandle - [optional] name of filehandle to print
#                         announcement to; assumed to be in package "main";
#                         defaults to "STDOUT"
#              $program - [optional] program name to print instead of $0
#              @args    - [optional] program arguments to print instead
#                         @ARGV
#@OUTPUT     : 
#@RETURNS    : 
#@DESCRIPTION: Prints the user, host, time, and full command line (as
#              supplied in @args).  Useful for later figuring out
#              what happened from a log file.
#
#              Assumes you have require'd "misc_utilities.pl" from main
#              package to get &userstamp, &timestamp, and &shellquote, and
#              that &Startup has been called to set $StartDir.
#@METHOD     : 
#@GLOBALS    : $0, @ARGV
#@CALLS      : 
#@CREATED    : 
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub SelfAnnounce
{
   my ($filehandle, $program, @args) = @_;
   package main;

   $filehandle = \*STDOUT unless defined $filehandle;
   $program = $0 unless defined $program;
   @args = @ARGV unless @args;

   printf $filehandle ("%s %s running:\n", 
                       &userstamp(undef,undef,$StartDir),
                       &timestamp());
   print $filehandle "  $program " . &shellquote (@args) . "\n\n";
}


# ------------------------------ MNI Header ----------------------------------
#@NAME       : &Cleanup
#@INPUT      : 
#@OUTPUT     : 
#@RETURNS    : 
#@DESCRIPTION: If $TmpDir exists and is a writeable directory, and $KeepTmp
#              is false, blasts $TmpDir into oblivion by running "/bin/rm -rf"
#              on it.
#@METHOD     : 
#@GLOBALS    : $TmpDir, $KeepTmp
#@CALLS      : 
#@CREATED    : 
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub Cleanup
{
   chdir $StartDir;
   if (-e $TmpDir && -d $TmpDir && -w $TmpDir)
   {
      system ("/bin/rm", "-rf", $TmpDir) unless ($KeepTmp || $TmpDir eq "");
   }
}


# ------------------------------ MNI Header ----------------------------------
#@NAME       : &Shutdown
#@INPUT      : $print_times - if true, will print out the running time
#                             of your program
#@OUTPUT     : 
#@RETURNS    : 
#@DESCRIPTION: Call this when your program exits normally.  (For abnormal
#              exits, you should call &Fatal -- this will result in $TmpDir
#              being wiped out of existence, and your program returns a
#              non-zero exit status.)  Doesn't actually exit the program --
#              just (optionally) prints the running time, and calls
#              &Cleanup to (optionally) nuke everything in $TmpDir.
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : &Cleanup (so $TmpDir and $KeepTmp matter)
#@CREATED    : 
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub Shutdown
{
   my ($print_times) = @_;
   if ($print_times)
   {
      my (@stop_times, $i, $user, $system);

      @stop_times = times;
      foreach $i (0 .. 3)
      { 
	 $elapsed[$i] = $stop_times[$i] - $Startup::start_times[$i];
      }
      $user = $elapsed[0] + $elapsed[2];
      $system = $elapsed[1] + $elapsed[3];
      print "Elapsed time in ${ProgramName}:\n";
      printf "%g sec (user) + %g sec (system) = %g sec (total)\n", 
	      $user, $system, $user+$system;
   }

   &Cleanup ();
}


# ------------------------------ MNI Header ----------------------------------
#@NAME       : &Fatal
#@INPUT      : $message - (optional) message to print before exiting.
#                         Don't bother putting a newline on the end of
#                         $message -- &Fatal takes care of it for you.
#              $status  - (optional) exit status.  If not given, 1 is used.
#@OUTPUT     : 
#@RETURNS    : 
#@DESCRIPTION: Call in case of emergency, ie. in place of die after your
#              program starts doing "serious processing" and needs to be
#              cleaned up after.  Prints $message (if given), cleans up
#              $TmpDir (see &Cleanup), and exits with status given by
#              $status (or 1, if $status was not given).
#
#              Unlike die, no indication of where &Fatal was called from is
#              printed.  Thus, for conditions that are really internal
#              errors, you should probably call die yourself.  (Note that,
#              since &Startup sets a handler for die, your temporary
#              directory will still get cleaned up when you call die.)
#@METHOD     : 
#@GLOBALS    : 
#@CALLS      : &Cleanup
#@CREATED    : 
#@MODIFIED   : 
#-----------------------------------------------------------------------------
sub Fatal
{
   my ($message, $status) = @_;
   print STDERR "$ProgramName: $message\n" if defined $message;
   &Cleanup ();
   exit (defined $status ? $status : 1);
}


# ------------------------------------------------------------------ #
#   private subroutines and global variables                         #
# ------------------------------------------------------------------ #


# Most of the important signals (taken from <sys/signal.h> under IRIX 5.2) 

%signals = ("HUP", "hung-up", 
	    "INT", "interrupted", 
	    "QUIT", "quit",
	    "ILL", "illegal instruction",
	    "TRAP", "trace trap",
	    "ABRT", "aborted",
	    "EMT", "EMT instruction",
	    "FPE", "floating-point exception",
	    "KILL", "killed",
	    "BUS", "bus error",
	    "SEGV", "segmentation violation",
	    "SYS", "bad argument to system call",
	    "PIPE", "broken pipe (write with no one to read it)",
	    "ALRM", "alarm clock",
	    "TERM", "terminated");



sub cleanup_and_die             # you probably shouldn't call this 
{				# (because it dies silently)
   &Cleanup ();
   exit 1;
}

sub catch_signal		# %SIG points to this - you shouldn't call it
{
   my ($sig) = @_;
   &Fatal ("$signals{$sig}");
}
