#!/usr/bin/perl
#
# NeuroCam management script - Manager daemon.
# Written by Christopher Thomas.
#
# This project is Copyright (c) 2021 by Vanderbilt University, and is released
# under the Creative Commons Attribution-ShareAlike 4.0 International License.

#
# Includes
#

use strict;
use warnings;
use Time::HiRes;
use POSIX;
use Socket;
use Image::Magick;
use Cwd;
use Proc::Daemon;

require "neurocam-libmt.pl";
require "neurocam-libcam.pl";
require "neurocam-libnetwork.pl";
require "neurocam-libsession.pl";
require "neurocam-libmanage.pl";
require "neurocam-libweb.pl";
require "neurocam-libstitch.pl";
require "neurocam-libpost.pl";



#
# Notes
#

# Status query command:
#
# "what is your status reply to port NNNN"
#
# Status responses:
#
# "busy (transcoding/archiving/detecting/autoexposing/etc) (progress string)"
# (the optional progress string is always in parentheses if present)
# "running cameras"
# "idle"
#
# Diagnostics commands:
#
# "debug version to port NNNN"
#
# "debug report to port NNNN"
#
# NOTE - Where directories and files are specified, any fully-qualified
# path (relative or absolute) is valid! This introduces security holes,
# but is needed for USB drive processing.
#
# Session commands:
#
# "start cameras repository=(dir) config=(file)"
# "stop cameras"
# "shut down"
#
# "repository=auto" and "config=auto" tell the manager to choose its own
# values for those parameters.
#
# Monitoring commands (must be running cameras when issued):
#
# "feed (subdir name)"
#
# The default feed is "Monitor", which does stitching. Other feeds just copy
# video directly. NOTE - Stitched frame size differs from raw frame size!
#
# Configuration commands (cannot be running cameras when issued):
#
# "snapshot config=(file) outdir=(dir)"
# "autocamadjust config=(file) size=(resolution wanted) rate=(fps wanted)"
#
# Repository commands (cannot be running cameras when issued):
#
# "timeshift repository=(dir)"
# "composite repository=(dir)"
# "transcode repository=(dir) stream=(subdir name) output=(file w/o suffix)"
# "archive rootdir=(dir) output=(file without suffix)"
# "unpack input=(file without suffix) rootdir=(dir)"
# "metadata rootdir=(dir)"
#
# "cancel processing"
# "unprocess repository=(dir)"
# "copy source=(dir) dest=(dir)"
# "delete repository=(dir)"
# "disksynch"
#



#
# Imported Constants
#

# FIXME - Doing this the messy way. Any imported variables need appropriate
# "our" declarations.

our ($NCAM_port_mgrdaemon_base, $NCAM_port_mgrdaemon_query);
our ($NCAM_port_camdaemon_command);
our ($NCAM_port_gpio_base);

# Parent directory under which repository folders are created.
our ($NCAM_cgi_repository_base);

# Software version.
# FIXME - This should be somewhere more central than CGI.
our ($NCAM_cgi_version);



#
# Global Variables
#

# Debugging records.
my ($laststartcmd);
$laststartcmd = '(none)';

# Network information.
my ($netinfo_p);



#
# Functions
#



# Launches the GPIO monitoring daemon if it isn't already running.
# NOTE - This creates and then destroys a couple of sockets, changing
# the next available port number.
# Returns the pid of the GPIO monitor, or undef if it was already running.

sub DoLaunchGPIO
{
  my ($gpiopid);
  my ($network_p);
  my ($result);

  $gpiopid = undef;

  # This should only return instances of the GPIO daemon.
  $network_p = NCAM_ProbeNetworkDevices( [ $NCAM_port_gpio_base ], 1000);

  if ( 1 > scalar(@$network_p) )
  {
    # Clean out lockfiles, if we can.
    $result = `rm -f /var/lock/LCK*tty*`;

    # This has no arguments to parse, so the PID should be correct.
    # Give it list context just to make sure of that.
    $gpiopid = NCAM_LaunchDaemon( [ './neurocam-gpio.pl' ] );
    # FIXME - Debugging by redirecting stderr to /tmp/gpio.log.
#    $gpiopid = NCAM_LaunchDaemon( './neurocam-gpio.pl 2>/tmp/gpio.log' );
  }

  return $gpiopid;
}



# Starts the camera capture daemon.
# Arg 0 is the repository directory (base plus folder).
# Arg 1 is the configuration file to load.
# No return value.

sub DoStartCameras
{
  my ($repodir, $configfile);
  my ($cmd);

  $repodir = $_[0];
  $configfile = $_[1];

  if ( (defined $repodir) && (defined $configfile) )
  {
    # Handle the special "auto" repository case.
    if ('auto' eq $repodir)
    {
      $repodir = $NCAM_cgi_repository_base . '/'
        . NCAM_GetDefaultRepoFolder();
    }

    # We don't need to handle the "auto" config case; just don't pass
    # a config file in that instance.


    # Prepare the command.
    $cmd = './neurocam-daemon.pl'
      . ' --repository=' . $repodir;
    # The daemon will auto-config if we don't supply a config file.
    if ('auto' ne $configfile)
    { $cmd .= ' --sessionconfig=' . $configfile; }

    # FIXME - Diagnostics.
    $laststartcmd = $cmd;


    # Launch the camera daemon using Proc::Daemon.
    NCAM_LaunchDaemon($cmd);

    # The daemon is now running.
    # FIXME - Discarding the pid. It's a shell invocation anyways, to parse
    # it into command-and-arguments.

    # FIXME - Not recording the command port!
    # The config file _can_ override that, so this may matter.
  }
}



# Shuts down the camera capture daemon.
# Arg 0 is the transmit socket handle to use.
# No return value.

sub DoStopCameras
{
  my ($sockethandle);

  $sockethandle = $_[0];

  if (defined $sockethandle)
  {
    # FIXME - Blithely assume that the camera daemon is running.
    # FIXME - Using the default command port! This may have been overridden!

    NCAM_SendSocket($sockethandle, $$netinfo_p{hostip},
      $NCAM_port_camdaemon_command, 'CMD stop');

    # FIXME - Not waiting for the shutdown to finish. It takes a few seconds.
  }
}



# Selects a new monitor feed.
# Arg 0 is the transmit socket handle to use.
# Arg 1 is the name of the feed to use (a folder name or "Monitor").
# No return value.

sub DoSelectFeed
{
  my ($sockethandle, $newfeed);

  $sockethandle = $_[0];
  $newfeed = $_[1];

  if ( (defined $sockethandle) && (defined $newfeed) )
  {
    # FIXME - Blithely assume that the camera daemon is running.
    # FIXME - Using the default command port! This may have been overridden!

    NCAM_SendSocket($sockethandle, $$netinfo_p{hostip},
      $NCAM_port_camdaemon_command, "CMD monitor $newfeed");
  }
}



# Aligns timestamps to strobe flashes.
# This is non-blocking (forking a child process).
# Arg 0 is the repository directory path.
# Arg 1 is a socket handle to send the "finished" message with.
# Returns the child thread PID.

sub DoSynchTimestamps
{
  my ($repodir, $donehandle, $childpid);

  $repodir = $_[0];
  $donehandle = $_[1];

  $childpid = undef;

  if ( (defined $repodir) && (defined $donehandle) )
  {
    $childpid = fork();

    if (0 == $childpid)
    {
      # We're the child.
      NCAM_SetProcessName('mgr-synchronizing');

      # Wrap the post-processing function for this.
      NCAM_AdjustTimestampsAllStreams($repodir, $NCAM_port_mgrdaemon_query);

      # Report completion.
      NCAM_SendSocket($donehandle, $$netinfo_p{hostip},
        $NCAM_port_mgrdaemon_query, 'finished adjusting timestamps');

      # End the thread.
      exit(0);
    }
  }

  return $childpid;
}



# Assembles composite stream frames from slot streams.
# This is non-blocking (forking a child process).
# Arg 0 is the repository directory path.
# Arg 1 is a socket handle to send the "finished" message with.
# Returns the child thread PID.

sub DoMakeComposite
{
  my ($repodir, $donehandle, $childpid);

  $repodir = $_[0];
  $donehandle = $_[1];

  $childpid = undef;

  if ( (defined $repodir) && (defined $donehandle) )
  {
    $childpid = fork();

    if (0 == $childpid)
    {
      # We're the child.
      NCAM_SetProcessName('mgr-compositing');

      # Wrap the post-processing function for this.
      NCAM_BuildCompositeFrames($repodir, $NCAM_port_mgrdaemon_query);

      # Report completion.
      NCAM_SendSocket($donehandle, $$netinfo_p{hostip},
        $NCAM_port_mgrdaemon_query, 'finished compositing');

      # End the thread.
      exit(0);
    }
  }

  return $childpid;
}



# Transcodes a series of frames into a movie.
# This is non-blocking (forking a child process).
# Arg 0 is the repository directory path.
# Arg 1 is the name of the subdirectory containing images.
# Arg 2 is the base name of the output file to create.
# Arg 3 is a socket handle to send the "finished" message with.
# Returns the child thread PID.

sub DoTranscodeFrameset
{
  my ($repodir, $slotname, $obase, $donehandle, $childpid);
  my ($outfname, $vcodec, $bitrate);
  my ($cmd, $result);
  my ($symlinks_p);
  my ($framerate);

  $repodir = $_[0];
  $slotname = $_[1];
  $obase = $_[2];
  $donehandle = $_[3];

  $childpid = undef;

  if ( (defined $repodir) && (defined $slotname) && (defined $obase)
    && (defined $donehandle) )
  {
    $childpid = fork();

    if (0 == $childpid)
    {
      # We're the child.
      NCAM_SetProcessName('mgr-transcoding');

      # Wrap the post-processing function for this.
      NCAM_TranscodeFrameset($repodir, $slotname, $obase,
        $NCAM_port_mgrdaemon_query);

      # Report completion.
      NCAM_SendSocket($donehandle, $$netinfo_p{hostip},
        $NCAM_port_mgrdaemon_query, 'finished transcoding');

      # End the thread.
      exit(0);
    }
  }

  return $childpid;
}



# Archives a directory tree into a single downloadable file.
# This is non-blocking (forking a child process).
# This is intended to provide a convenient way to move repositories over
# http.
# NOTE - We change to the directory that _contains_ the named directory
# prior to archiving. Archived paths _start_ with the named directory,
# not the full specified path of that directory.
# Arg 0 is the root directory of the tree to archive.
# Arg 1 is the base name of the output file to create.
# Arg 2 is a socket handle to send the "finished" message with.
# Returns the child thread PID.

sub DoArchiveTree
{
  my ($archdir, $obase, $donehandle, $childpid);
  my ($origdir, $newdir);
  my ($cmd, $result);

  $archdir = $_[0];
  $obase = $_[1];
  $donehandle = $_[2];

  $childpid = undef;

  if ( (defined $archdir) && (defined $obase) && (defined $donehandle) )
  {
    $childpid = fork();

    if (0 == $childpid)
    {
      # We're the child.
      NCAM_SetProcessName('mgr-archiving');


      # Get our starting path.
      $origdir = cwd();

      # Turn our target path into an absolute path if it isn't already.
      if (!($obase =~ m/^\//))
      { $obase = $origdir . '/' . $obase; }

      # If our source path is anything other than one relative step from
      # us, split it into directory and target.
      # This regex discards trailing slashes, which is fine.
      # Starting with or without a slash is also fine.

      $newdir = '.';

      if ($archdir =~ m/^(.*\/)([^\/]+)/)
      {
        $newdir = $1;
        $archdir = $2;
      }

      # Move to the appropriate prefix directory.
      chdir $newdir;


      # We're creating an uncompressed .tar archive.
      # Most of the files will be compressed frames or videos, so there's
      # no point in trying to gzip it.

      # Remove the target file if present.
      $cmd = "rm -f $obase.tar";
      $result = `$cmd`;

      $cmd = "tar -cf $obase.tar $archdir";

      $result = `$cmd`;


      # Return to the starting directory.
      # Not needed, but do it anyways.
      chdir $origdir;

      # Report completion.
      NCAM_SendSocket($donehandle, $$netinfo_p{hostip},
        $NCAM_port_mgrdaemon_query, 'finished archiving');

      # End the thread.
      exit(0);
    }
  }

  return $childpid;
}



# Unpacks an archived directory tree back into a directory.
# This is non-blocking (forking a child process).
# This is intended for moving archives from USB drives back to the local disk.
# NOTE - We change to the directory that _contains_ the named directory
# prior to unpacking. Archived paths _start_ with the named directory,
# not the full specified path of that directory.
# Arg 0 is the base name of the archive file to unpack.
# Arg 1 is the root directory of the tree to create.
# Arg 2 is a socket handle to send the "finished" message with.
# Returns the child thread PID.

sub DoUnpackTree
{
  my ($archbase, $destdir, $donehandle, $childpid);
  my ($origdir, $newdir);
  my ($cmd, $result);

  $archbase = $_[0];
  $destdir = $_[1];
  $donehandle = $_[2];

  $childpid = undef;

  if ( (defined $archbase) && (defined $destdir) && (defined $donehandle) )
  {
    $childpid = fork();

    if (0 == $childpid)
    {
      # We're the child.
      NCAM_SetProcessName('mgr-unpacking');


      # Get our starting path.
      $origdir = cwd();

      # Turn our source path into an absolute path if it isn't already.
      if (!($archbase =~ m/^\//))
      { $archbase = $origdir . '/' . $archbase; }

      # If our destination path is anything other than one relative step from
      # us, split it into directory and target.
      # This regex discards trailing slashes, which is fine.
      # Starting with or without a slash is also fine.

      $newdir = '.';

      if ($destdir =~ m/^(.*\/)([^\/]+)/)
      {
        $newdir = $1;
        $destdir = $2;
      }

      # Move to the appropriate prefix directory.
      chdir $newdir;


      # We're unpacking an uncompressed .tar archive.
      # Most of the files were compressed frames or videos, so there was
      # no point in trying to gzip it.

      # Remove the target directory if present.
      $cmd = "rm -rf $destdir";
      $result = `$cmd`;

      $cmd = "tar -xf $archbase.tar $destdir";

      $result = `$cmd`;


      # Return to the starting directory.
      # Not needed, but do it anyways.
      chdir $origdir;

      # Report completion.
      NCAM_SendSocket($donehandle, $$netinfo_p{hostip},
        $NCAM_port_mgrdaemon_query, 'finished unpacking');

      # End the thread.
      exit(0);
    }
  }

  return $childpid;
}



# Recalculates metadata for all folders within a repository root directory.
# This is non-blocking (forking a child process).
# Arg 0 is the root directory containing repository folders.
# Arg 1 is 1 if the update is to be forced and 0 if only stale entries update.
# Arg 2 is a socket handle to send the "finished" message with.
# Returns the child thread PID.

sub DoCalculateMetadata
{
  my ($rootdir, $doforce, $donehandle, $childpid);

  $rootdir = $_[0];
  $doforce = $_[1];
  $donehandle = $_[2];

  $childpid = undef;

  if ( (defined $rootdir) && (defined $doforce) && (defined $donehandle) )
  {
    $childpid = fork();

    if (0 == $childpid)
    {
      # We're the child.
      NCAM_SetProcessName('mgr-metadata');

      # Wrap the post-processing function for this.
      NCAM_UpdateRepositoryMetadata($rootdir, $doforce);

      # Report completion.
      NCAM_SendSocket($donehandle, $$netinfo_p{hostip},
        $NCAM_port_mgrdaemon_query, 'finished updating metadata');

      # End the thread.
      exit(0);
    }
  }

  return $childpid;
}



# Removes post-processing files from a repository.
# This should be done before re-processing or after cancelling.
# This is non-blocking; it could take a while, due to file count/size.
# Arg 0 is the repository directory path.
# Arg 1 is a socket handle to send the "finished" message with.
# Returns the child thread PID.

sub DoDeletePostfiles
{
  my ($repodir, $donehandle, $childpid);
  my ($cmd, $result);

  $repodir = $_[0];
  $donehandle = $_[1];

  $childpid = undef;

  if ( (defined $repodir) && (defined $donehandle) && (-d $repodir) )
  {
    $childpid = fork();

    if (0 == $childpid)
    {
      # We're the child.
      NCAM_SetProcessName('mgr-delpost');

      # Remove trailing /, if any, from the directory path.
      if ($repodir =~ m/(.*)\/\s*$/)
      { $repodir = $1; }

      # Remove files produced by post-processing.

      $cmd = "rm -f $repodir.tar";
      $result = `$cmd`;

      # FIXME - Assuming .mp4 extension. This may change!
      $cmd = "rm -f $repodir/*.mp4";
      $result = `$cmd`;

      $cmd = "rm -rf $repodir/Composite";
      $result = `$cmd`;
      $cmd = "rm -f $repodir/logfile-composited.txt";
      $result = `$cmd`;

      $cmd = "rm -f $repodir/logfile-timed.txt";
      $result = `$cmd`;

      # Report completion.
      NCAM_SendSocket($donehandle, $$netinfo_p{hostip},
        $NCAM_port_mgrdaemon_query, 'finished deleting post-files');

      # End the thread.
      exit(0);
    }
  }

  return $childpid;
}



# Deletes a session's repository folder (along with any archive tarball).
# This is non-blocking; it could take a while, due to file count/size.
# Arg 0 is the repository directory path.
# Arg 1 is a socket handle to send the "finished" message with.
# Returns the child thread PID.

sub DoRemoveRepository
{
  my ($repodir, $donehandle, $childpid);
  my ($cmd, $result);

  $repodir = $_[0];
  $donehandle = $_[1];

  $childpid = undef;

  # NOTE - We may have a .tar file and no folder.
  if ( (defined $repodir) && (defined $donehandle)
    && ((-d $repodir) || (-e "$repodir.tar")) )
  {
    $childpid = fork();

    if (0 == $childpid)
    {
      # We're the child.
      NCAM_SetProcessName('mgr-delpost');

      # Remove trailing /, if any, from the directory path.
      if ($repodir =~ m/(.*)\/\s*$/)
      { $repodir = $1; }

      # Remove the .tar archive (if any), and the entire directory.

      $cmd = "rm -f $repodir.tar";
      $result = `$cmd`;

      $cmd = "rm -rf $repodir";
      $result = `$cmd`;

      # Report completion.
      NCAM_SendSocket($donehandle, $$netinfo_p{hostip},
        $NCAM_port_mgrdaemon_query, 'finished deleting session folder');

      # End the thread.
      exit(0);
    }
  }

  return $childpid;
}



# Copyies a session's repository folder from one location to another.
# This is intended to allow transfer of a repository to a USB drive.
# This is non-blocking; it could take a while, due to file count/size.
# Arg 0 is the source tree's root directory.
# Arg 1 is the new root directory to create.
# Arg 2 is a socket handle to send the "finished" message with.
# Returns the child thread PID.

sub DoCopyRepository
{
  my ($sourcedir, $destdir, $donehandle, $childpid);
  my ($cmd, $result);

  $sourcedir = $_[0];
  $destdir = $_[1];
  $donehandle = $_[2];

  $childpid = undef;

  if ( (defined $sourcedir) && (defined $destdir) && (defined $donehandle) )
  {
    $childpid = fork();

    if (0 == $childpid)
    {
      # We're the child.
      NCAM_SetProcessName('mgr-copying');

      # Remove trailing /, if any, from the directory paths.
      if ($sourcedir =~ m/(.*)\/\s*$/)
      { $sourcedir = $1; }
      if ($destdir =~ m/(.*)\/\s*$/)
      { $destdir = $1; }

      # Nuke and pave any existing directory of this name.
      # Ditto tarball.
      $cmd = "rm -rf $destdir";
      $result = `$cmd`;
      $cmd = "rm -f $destdir.tar";
      $result = `$cmd`;

      # Copy the tree, _and_ the archive tarball if any.
      # This preserves the postprocessed/non-postprocessed state.

      if (-d $sourcedir)
      {
        $cmd = "cp -r $sourcedir $destdir";
        $result = `$cmd`;
      }

      if (-e "$sourcedir.tar")
      {
        $cmd = "cp $sourcedir.tar $destdir.tar";
        $result = `$cmd`;
      }

      # Report completion.
      NCAM_SendSocket($donehandle, $$netinfo_p{hostip},
        $NCAM_port_mgrdaemon_query, 'finished copying');

      # End the thread.
      exit(0);
    }
  }

  return $childpid;
}



# Forces a disk synch.
# This is non-blocking; it could take a while for slow USB drives.
# Arg 0 is a socket handle to send the "finished" message with.
# Returns the child thread PID.

sub DoDiskSynch
{
  my ($donehandle, $childpid);
  my ($cmd, $result);

  $donehandle = $_[0];

  $childpid = undef;

  if (defined $donehandle)
  {
    $childpid = fork();

    if (0 == $childpid)
    {
      # We're the child.
      NCAM_SetProcessName('mgr-disksynch');

      NCAM_ForceDiskSync();

      # Report completion.
      NCAM_SendSocket($donehandle, $$netinfo_p{hostip},
        $NCAM_port_mgrdaemon_query, 'finished synchronizing disks');

      # End the thread.
      exit(0);
    }
  }

  return $childpid;
}



# Polls cameras and streams, getting snapshot images for thumbnails and for
# the preview of the monitor pane.
# Arg 0 is the config filename to read.
# Arg 1 is a directory to store the resulting images in.
# Arg 2 is a socket handle to send the "finished" message with.
# Returns the child thread pid.

sub DoGenerateSnapshots
{
  my ($configfile, $outdir, $donehandle, $childpid);
  my ($session_p, $errstr);

  $configfile = $_[0];
  $outdir = $_[1];
  $donehandle = $_[2];

  $childpid = undef;

  if ( (defined $configfile) && (defined $outdir) && (defined $donehandle) )
  {
    $childpid = fork();

    if (0 == $childpid)
    {
      # We're the child.
      NCAM_SetProcessName('mgr-previewing');

      ($session_p, $errstr) = NCAM_ReadSessionConfigFile($configfile);

      if (defined $session_p)
      {
        # FIXME - This doesn't emit progress reports.
        NCAM_GenerateConfigThumbnails($session_p, $outdir);
      }

      # Report completion.
      # FIXME - Ignore errors.
      NCAM_SendSocket($donehandle, $$netinfo_p{hostip},
        $NCAM_port_mgrdaemon_query, 'finished generating preview');

      # End the thread.
      exit(0);
    }
  }

  return $childpid;
}



# Adjusts resolution, frame rate, and exposure time of all cameras.
# Exposure is adjusted until the desired frame rate is met; if that can't
# be done, the frame rate is dropped until it can be.
# Arg 0 is the config filename to read.
# Arg 1 is the desired resolution.
# Arg 2 is the desired frame rate.
# Arg 3 is a socket handle to send the "finished" message with.
# Returns the child thread pid.

sub DoAutoAdjustCameras
{
  my ($configfile, $desiredsize, $desiredrate, $donehandle, $childpid);
  my ($session_p, $errstr);
  my ($camlist_p, $thisdev, $thiscam_p, $thismeta_p);
  my ($sizes_p, $rates_p, $chosensize, $chosenrate);
  my (@ratelist, $thisrate);
  my ($explist_p, $thisexplabel, $thisexpreal, $chosenexplabel);
  my ($test_ok, $test_total, $test_dropped);

  $configfile = $_[0];
  $desiredsize = $_[1];
  $desiredrate = $_[2];
  $donehandle = $_[3];

  $childpid = undef;

  if ( (defined $configfile) && (defined $desiredsize)
    && (defined $desiredrate) && (defined $donehandle) )
  {
    $childpid = fork();

    if (0 == $childpid)
    {
      # We're the child.
      NCAM_SetProcessName('mgr-calibrating');

      # FIXME - All of this should be moved to a library function.

      ($session_p, $errstr) = NCAM_ReadSessionConfigFile($configfile);

      if (defined $session_p)
      {
        $camlist_p = $$session_p{cameras};
        foreach $thisdev (keys %$camlist_p)
        {
          $thiscam_p = $$camlist_p{$thisdev};
          $thismeta_p = $$thiscam_p{meta};

          # FIXME - Only test one size.
          $sizes_p = $$thismeta_p{sizes};
          $chosensize =
            NCAM_FindClosestResolution($desiredsize, keys %$sizes_p);

          # Walk through frame rates for this size from highest to lowest.
          # Discard ones that are higher (allow a bit of wiggle room).
          # Keep walking until we've chosen a rate (or run out).

          $chosenrate = undef;
          $chosenexplabel = undef;

          $rates_p = $$sizes_p{$chosensize};
          # The list is already sorted in descending order, but resort anyways.
          @ratelist = sort {$b <=> $a} @$rates_p;

          foreach $thisrate (@ratelist)
          {
            if ( (!(defined $chosenrate))
              && ($thisrate <= ($desiredrate + 3)) )
            {
              # Walk through exposure settings from longest to shortest.
              $explist_p = $$thiscam_p{explist};
              foreach $thisexplabel (sort {$b <=> $a} keys %$explist_p)
              {
                $thisexpreal = $$explist_p{$thisexplabel};

                if (!(defined $chosenexplabel))
                {
                  # Send a progress report.
                  NCAM_SendSocket($donehandle, $$netinfo_p{hostip},
                    $NCAM_port_mgrdaemon_query,
# FIXME - This is a bit verbose. Use it for diagnostics.
#"progress $thisdev $chosensize $thisrate fps exp $thisexplabel");
# FIXME - This is middle-of-the-road; a full sweep is about 35 seconds.
"progress $thisdev $chosensize $thisrate fps");

                  # Test this exposure setting at this resolution and fps.
                  NCAM_SetExposure($thismeta_p, $thisexpreal);
                  # FIXME - If we walk sizes, change this from "chosensize".
                  ($test_ok, $test_total, $test_dropped) =
                    NCAM_TestCapture($thismeta_p, $chosensize, $thisrate);

                  # FIXME - Blindly trusting the "ok" flag.
                  # With mplayer, the actual results are dodgy.
                  if ($test_ok)
                  {
                    $chosenrate = $thisrate;
                    $chosenexplabel = $thisexplabel;
                  }
                }
              }
            }
          }

          # We always have a chosen rate.
          # FIXME - That won't be true if we actually do a rate scan.

          # If we didn't find anything, pick the slowest allowed rate.
          if (!(defined $chosenrate))
          {
            $chosenrate = pop @ratelist;
          }

          # If we don't have an exposure, pick "+0" for sanity.
          if (!(defined $chosenexplabel))
          {
            $chosenexplabel = '+0';
          }

          # Update this camera's settings.
          $$thiscam_p{size} = $chosensize;
          $$thiscam_p{rate} = $chosenrate;
          $$thiscam_p{exp} = $chosenexplabel;
        }

        # Write the altered session configuration.
        NCAM_WriteSessionConfigFile($configfile, $session_p);
      }

      # Report completion.
      # FIXME - Ignore errors.
      NCAM_SendSocket($donehandle, $$netinfo_p{hostip},
        $NCAM_port_mgrdaemon_query, 'finished adjusting cameras');

      # End the thread.
      exit(0);
    }
  }

  return $childpid;
}



#
# Main Program
#

my ($state);
my ($recvhandle, $replyhandle, $taskhandle);
my ($has_message, $sender_ip, $message);
my ($replyport);
my ($childpid, $gpiopid);
my ($progress, $replymsg);
my (@commandqueue, $thiscommand);
my ($runningchild, $processdir);
# FIXME - State tracking for debugging.
my ($lastcommand);


# Check for an existing manager daemon. If there is one, exit immediately.
# NOTE - Doing this _before_ altering our base port number, so as to not
# conflict with ports the manager is using.
$message = NCAM_GetManagerStatus();

if (defined $message)
{
  # Abort; there's a manager daemon already running.
  print STDERR "### NeuroCam manager is already running; bailing out.\n";
}
else
{
  # We're the new management daemon.

  # FIXME - Diagnostics banner.
  print STDERR "### Starting NeuroCam manager.\n";


  # Tweak our starting port number to avoid collisions.
  NCAM_SetNextListenPort($NCAM_port_mgrdaemon_base);

  # Fetch network settings.
  $netinfo_p = NCAM_GetNetworkInfo();


  # Initialize state.
  $state = 'idle';
  $progress = '';
  $lastcommand = '(none)';
  @commandqueue = ();
  $runningchild = undef;
  $processdir = undef;

  # Get network handles.
  # FIXME - Sharing the task handle between processes is asking for trouble.
  # It only works if we enforce there being only one task at a time.

  $recvhandle = NCAM_GetListenSocket($NCAM_port_mgrdaemon_query);
  $replyhandle = NCAM_GetTransmitSocket();
  $taskhandle = NCAM_GetTransmitSocket();

  # Launch the GPIO daemon if it isn't already running.
  # If we didn't need to launch it, the pid is undefined.
  $gpiopid = DoLaunchGPIO();

  # Spin, receiving messages and initiating tasks until told to stop.

  while ('shutting down' ne $state)
  {
    NCAM_Yield();

    # Handle new messages.

    ($has_message, $sender_ip, $message) =
      NCAM_CheckReceiveSocket($recvhandle);

    if ( ($has_message) && ($message =~ m/^\s*(.*\S)/) )
    {
      # We've received something. Process it.
      # NOTE - This should never be time consuming; anything that would be
      # is handed off to a child thread.

      # Trim surrounding whitespace.
      # We're guaranteed at least _some_ non-whitespace from the regex.
      $message = $1;


      # Handle immediate messages here.
      # Anything that's not immediate gets queued and handled afterwards.

      if ($message =~ m/^what is your status reply to port (\d+)$/i)
      {
        $replyport = $1;

        # The "state" variable contains a human-readable status description.
        $replymsg = $state;

        if ( ($state =~ m/^busy/) && ('' ne $progress) )
        { $replymsg .= ' (' . $progress . ')'; }

        NCAM_SendSocket($replyhandle, $sender_ip, $replyport, $replymsg);
      }
      elsif ($message =~ m/^debug version to port (\d+)$/i)
      {
        $replyport = $1;

        NCAM_SendSocket($replyhandle, $sender_ip, $replyport,
          "NeuroCam mananger version: $NCAM_cgi_version");
      }
      elsif ($message =~ m/^debug report to port (\d+)$/i)
      {
        $replyport = $1;

        # FIXME - Diagnostics dump of everything we can't just query.
        NCAM_SendSocket($replyhandle, $sender_ip, $replyport,
          "Last command was:  $lastcommand");
        NCAM_SendSocket($replyhandle, $sender_ip, $replyport,
          "Last camera start was:  $laststartcmd");

        NCAM_SendSocket($replyhandle, $sender_ip, $replyport,
          "Command queue:");
        foreach $thiscommand (@commandqueue)
        {
          NCAM_SendSocket($replyhandle, $sender_ip, $replyport,
            $thiscommand);
        }
        NCAM_SendSocket($replyhandle, $sender_ip, $replyport,
          "End of queue.");
      }
      elsif ($message =~ m/^shut\s*down$/i)
      {
        # If the camera daemon is running, shut it down.
        if ('running cameras' eq $state)
        {
          DoStopCameras($replyhandle);
        }

        # Otherwise, exit no matter what.
        # We can wait for transcoding threads outside of this loop.
        # FIXME - The "taskhandle" port may be unusable while child threads
        # are still running!
        $state = 'shutting down';

        # FIXME - Diagnostics.
        # We should never be able to query this.
        $lastcommand = "shutdown";
      }
      elsif ($message =~ m/^start cameras repository=(\S+) config=(\S+)$/i)
      {
        if ('idle' eq $state)
        {
          DoStartCameras($1, $2);
          $state = 'running cameras';
          # FIXME - Diagnostics.
          $lastcommand = "start \"$1\" \"$2\"";
        }
      }
      elsif ($message =~ m/^stop cameras$/i)
      {
        if ('running cameras' eq $state)
        {
          DoStopCameras($replyhandle);
          $state = 'idle';
          # FIXME - Diagnostics.
          $lastcommand = "stop cameras";
        }
      }
      elsif ($message =~ m/^feed\s+(\w+)/i)
      {
        if ('running cameras' eq $state)
        {
          # FIXME - We don't have the session config here, so pass this on
          # without filtering and let the daemon deal with it.
          DoSelectFeed($replyhandle, $1);
          $lastcommand = "feed \"$1\"";
        }
      }
      elsif ($message =~ m/^progress\s+(.*\S)/i)
      {
        # FIXME - Assume we're only doing one thing at a time.
        # Update the progress status for this task.
        $progress = $1;
      }
      elsif ($message =~ m/^finished/i)
      {
        # FIXME - Assume we're only doing one thing at a time.
        # Don't worry about _what_ finished, just mark it done.
        if ($state =~ m/^busy/)
        {
          $state = 'idle';
          $progress = '';
          $runningchild = undef;
          $processdir = undef;
        }
      }
      elsif ($message =~ m/^cancel processing/i)
      {
        # FIXME - Assume we're only doing one thing at a time.
        # Further assume it's cancellable if and only if we have a pid.
        # Don't worry about _what_ finished, just kill it.
        if (($state =~ m/^busy/) && (defined $runningchild))
        {
          # Kill the running task.
          # FIXME - Sleeping for nonzero time! We'll be unresponsive.
          # FIXME - This might leave stale socket handles?
          kill 'TERM', $runningchild;
          NCAM_SleepMillis(700);
          kill 'KILL', $runningchild;
          NCAM_SleepMillis(700);

          # Reset state.
          $state = 'idle';
          $progress = '';
          $runningchild = undef;

          # Nuke the remaining command queue.
          # FIXME - There might be unrelated commands wiped, here?
          @commandqueue = ();

          # Push an "unprocess" command for the processing we interrupted.
          push @commandqueue, "unprocess repository=$processdir";
        }
      }
      else
      {
        # This is a processing command. Enqueue it.
        push @commandqueue, $message;
      }
    }


    # If we're idle, process any pending queued commands.

    if ( ('idle' eq $state) && (defined $commandqueue[0]) )
    {
      $message = shift @commandqueue;

      if ($message =~ m/^timeshift repository=(\S+)$/i)
      {
        $progress = '';
        $state = 'busy synchronizing timestamps';
        # We can cancel this, so record the child pid.
        $runningchild = DoSynchTimestamps($1, $taskhandle);
        $processdir = $1;
        # FIXME - Diagnostics.
        $lastcommand = "timeshift \"$1\"";
      }
      elsif ($message =~ m/^composite repository=(\S+)$/i)
      {
        $progress = '';
        $state = 'busy compositing';
        # We can cancel this, so record the child pid.
        $runningchild = DoMakeComposite($1, $taskhandle);
        $processdir = $1;
        # FIXME - Diagnostics.
        $lastcommand = "composite \"$1\"";
      }
      elsif ($message =~
         m/^transcode repository=(\S+) stream=(\w+) output=(\S+)$/i)
      {
        $progress = '';
        $state = 'busy transcoding';
        # We can cancel this, so record the child pid.
        $runningchild = DoTranscodeFrameset($1, $2, $3, $taskhandle);
        $processdir = $1;
        # FIXME - Diagnostics.
        $lastcommand = "transcode \"$1/$2\" to \"$3\"";
      }
      elsif ($message =~ m/^archive rootdir=(\S+) output=(\S+)$/i)
      {
        $progress = '';
        $state = 'busy archiving';
        # We can cancel this, so record the child pid.
        $runningchild = DoArchiveTree($1, $2, $taskhandle);
        $processdir = $1;
        # FIXME - Diagnostics.
        $lastcommand = "archive \"$1\" to \"$2\"";
      }
      elsif ($message =~ m/^unpack input=(\S+) rootdir=(\S+)$/i)
      {
        $progress = '';
        $state = 'busy unpacking';
        # We can cancel this, so record the child pid.
        $runningchild = DoUnpackTree($1, $2, $taskhandle);
        $processdir = $1;
        # FIXME - Diagnostics.
        $lastcommand = "unpack \"$1\" to \"$2\"";
      }
      elsif ($message =~ m/^metadata rootdir=(\S+)(.*)$/i)
      {
        my ($folder, $forceflag);

        $folder = $1;
        $forceflag = $2;

        # FIXME - Kludge progress label.
        $progress = $folder;
        # Size calculation is the only operation that takes time.
        $state = 'busy calculating sizes';
        # This cannot be cancelled; discard pid.
        DoCalculateMetadata($folder,
          ($forceflag =~ m/force/ ? 1 : 0),
          $taskhandle);
        $lastcommand = "metadata \"$1\"";
      }
      elsif ($message =~ m/^unprocess repository=(\S+)$/i)
      {
        $progress = '';
        $state = 'busy removing post-processed files';
        # FIXME - Discarding child pid. This isn't an interruptible task.
        DoDeletePostfiles($1, $taskhandle);
        # FIXME - Diagnostics.
        $lastcommand = "unprocess \"$1\"";
      }
      elsif ($message =~ m/^delete repository=(\S+)$/i)
      {
        $progress = '';
        $state = 'busy removing session folder';
        # FIXME - Discarding child pid. This isn't an interruptible task.
        DoRemoveRepository($1, $taskhandle);
        # FIXME - Diagnostics.
        $lastcommand = "delete \"$1\"";
      }
      elsif ($message =~ m/^copy source=(\S+) dest=(\S+)$/i)
      {
        $progress = '';
        $state = 'busy copying session folder';
        # FIXME - Discarding child pid. This isn't an interruptible task.
        DoCopyRepository($1, $2, $taskhandle);
        # FIXME - Diagnostics.
        $lastcommand = "copy \"$1\" to \"$2\"";
      }
      elsif ($message =~ m/^disksync/i)
      {
        # Tolerating both "sync" and "synch" in the command name.
        $progress = '';
        $state = 'busy synchronizing disks';
        # FIXME - Discarding child pid. This isn't an interruptible task.
        DoDiskSynch($taskhandle);
        # FIXME - Diagnostics.
        $lastcommand = "disksynch";
      }
      elsif ($message =~ m/^snapshot config=(\S+) outdir=(\S+)/i)
      {
        $progress = '';
        $state = 'busy generating preview';
        # FIXME - Discarding child pid. This isn't an interruptible task.
        DoGenerateSnapshots($1, $2, $taskhandle);
        # FIXME - Diagnostics.
        $lastcommand = "snapshot config \"$1\" to dir \"$2\"";
      }
      elsif ($message =~ m/^autocamadjust config=(\S+) size=(\S+) rate=(\S+)/i)
      {
        $progress = '';
        $state = 'busy auto-adjusting cameras';
        # FIXME - Discarding child pid. This isn't an interruptible task.
        DoAutoAdjustCameras($1, $2, $3, $taskhandle);
        # FIXME - Diagnostics.
        $lastcommand =
          "adjust cameras (config \"$1\", want \"$2\" at \"$3\" fps)";
      }
      else
      {
        # Bogus message. Complain.
        print STDERR "### Manager cannot parse message:\n\"$message\"\n";
      }
    }


    # Finished handling the current message and/or pending command.
  }


  # If we get here, we've been told to shut down.

  print STDERR "### Manager shutting down.\n";

  # Tell the GPIO handler to shut down.
  NCAM_SendSocket($replyhandle, $$netinfo_p{hostip},
    $NCAM_port_gpio_base, 'shutdown');

  if (defined $gpiopid)
  {
    NCAM_SleepMillis(500);
    kill 'TERM', $gpiopid;
    NCAM_SleepMillis(500);
    kill 'KILL', $gpiopid;
  }
  else
  {
    # We don't own the GPIO handler; kill it the hard way.
    my ($result);
    NCAM_SleepMillis(500);
    $result = `killall neurocam-gpio.pl`;
    NCAM_SleepMillis(500);
    $result = `killall -9 neurocam-gpio.pl`;
  }

  # FIXME - We _should_ spin here answering status queries while doing
  # non-blocking tests for child threads to terminate. Instead, just wait().

  # Close sockets.
  NCAM_CloseSocket($recvhandle);
  NCAM_CloseSocket($replyhandle);
  NCAM_CloseSocket($taskhandle);

  # Wait for child threads to wrap up.
  # This only happens if we shut down in the middle of transcoding/etc.

  # FIXME - While this is happening, the taskhandle socket might still be
  # in use! It depends on whether "shutdown" on a socket invalidates the
  # child process's instance of it or not.
  # FIXME - Worst-case scenario, writing to a shut-down socket hangs and
  # creates a zombie process. We need a better system here.

  do
  {
    $childpid = wait();
  }
  while (0 <= $childpid);
}



#
# This is the end of the file.
#
