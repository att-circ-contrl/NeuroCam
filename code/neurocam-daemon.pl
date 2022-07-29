#!/usr/bin/perl
#
# NeuroCam management script - Data acquisition daemon.
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

# Path fix needed for more recent Perl versions.
use lib ".";

require "neurocam-libmt.pl";
require "neurocam-libcam.pl";
require "neurocam-libnetwork.pl";
require "neurocam-libsession.pl";
require "neurocam-libstitch.pl";
require "neurocam-libmjpeg.pl";
# FIXME - Diagnostics.
require "neurocam-libdebug.pl";



#
# Public Constants
#

# FIXME - Doing this the messy way. Any imported variables need appropriate
# "our" declarations.

our ($NCAM_port_camdaemon_base, $NCAM_port_camdaemon_monitorframe);

our (@NCAM_session_slots);
our (%NCAM_default_settings);

our ($stitchinfo_monitor_p, $stitchslots_monitor_p);


#
# Private Constants
#

my ($monitordir);
$monitordir = 'Monitor';

my ($tattlecomm, $tattleframes);
$tattlecomm = 0;
$tattleframes = 0;

my ($stitchernicelevel);
# Downgrade the stitcher's priority so that we're less likely to drop
# captured frames.
$stitchernicelevel = +5;


# Monitor frame reporting port.
# FIXME - Hardcode a port number. Order of events makes it hard to
# automatically assign one!
my ($monitor_report_port);
$monitor_report_port = $NCAM_port_camdaemon_monitorframe;


# Lookahead for scouting for new frames.
# Each file tests generates a fstat() call, so they're not free.
# That said, there _should_ only be one or two of these, unless a glitch
# has occurred. Expensive glitch recovery is acceptable.
my ($video_frame_scout_lookahead);
$video_frame_scout_lookahead = 50;



#
# Functions
#


# Creates a repository structure in the specified directory.
# The directory is created if necessary.
# Arg 0 is the repository directory.
# Arg 1 points to the session configuration.
# Returns a hash of paths or undef on error.
# (This contains slot+monitor dirs, logfile, metafile, sessionfile.)

sub CreateRepository
{
  my ($repodir, $session_p, $paths_p);
  my ($is_ok);
  my ($reposubdir);
  my ($cmd, $result);
  my ($hash_p, $thiskey, $thisval);
  my ($dirname, $filepath);

  $repodir = $_[0];
  $session_p = $_[1];
  $paths_p = {};

  $is_ok = 0;

  if (!( (defined $repodir) && (defined $session_p) ))
  {
    print "### [CreateRepository]  Bad arguments.\n";
  }
  else
  {
    $is_ok = 1;


    # Create repository folder and (if specified) subfolder.

    # If we don't have this directory, create it.
    if (!(-d $repodir))
    {
      if (!mkdir($repodir))
      {
        print "### [CreateRepository]  Unable to create \"$repodir\".\n";
        $is_ok = 0;
      }
    }

    if ( $is_ok && (!(-d $repodir)) )
    {
      # This shouldn't happen.
      print "### [CreateRepository]  Repository still doesn't exist.\n";
      $is_ok = 0;
    }

    # If we don't have the desired _subdirectory_, create it.
    $reposubdir = $$session_p{repodir};
    if ( $is_ok && (defined $reposubdir)
      && ('/' ne $reposubdir) && ('.' ne $reposubdir) )
    {
      # We have what seems to be a subdirectory name. Try to create it.
      # FIXME - Not squashing or sanity-checking this name! That should
      # have happened when the config file was first generated.
      # FIXME - Assuming that this is a single level deep!
      $repodir .= '/'.$reposubdir;

      if (!(-d $repodir))
      {
        if (!mkdir($repodir))
        {
          print "### [CreateRepository]  Unable to create \"$repodir\".\n";
          $is_ok = 0;
        }
      }

      if ( $is_ok && (!(-d $repodir)) )
      {
        # This shouldn't happen.
        print "### [CreateRepository]  Repository still doesn't exist.\n";
        $is_ok = 0;
      }
    }


    # Initialize the repository (sub)folder.

    if ($is_ok)
    {
      # FIXME - Nuke everything currently in the repository.
      # This lends itself to painful mistakes, but that's better than
      # having two runs' results mixed.

      $cmd = 'rm -rf ' . $repodir . '/*';
      $result = `$cmd`;

      # Make note of the base repository path.
      $$paths_p{repodir} = $repodir;

      # Write the session config file.
      $filepath = $repodir . '/session.config';
      $$paths_p{sessionfile} = $filepath;
      if (!open(SESSION, ">$filepath"))
      {
        print "### [CreateRepository]  Unable to write to \"$filepath\".\n";
        $is_ok = 0;
      }
      else
      {
        my ($text_p);

        $text_p = NCAM_SessionConfigToText($session_p);
        print SESSION @$text_p;
        close(SESSION);
      }

      # Make a note of where the logfile and session metadata file go.
      $$paths_p{logfile} = $repodir . '/logfile.txt';
      $$paths_p{metafile} = $repodir . '/metadata.txt';

      # Create directories.
      # NOTE - Creating config file's slots, not the canonical slots.
      # These should be the same, but we may add/remove slots later.
      # FIXME - Not splitting up image-dump directories yet!
      # This will have to be done to avoid hundreds of thousands of frames
      # per directory.
      if ($is_ok)
      {
        $hash_p = $$session_p{slots};
        foreach $dirname (keys %$hash_p)
        {
          $filepath = $repodir . '/' . $dirname;
          $$paths_p{$dirname} = $filepath;
          if (!mkdir($filepath))
          {
            $is_ok = 0;
          }
        }

        $filepath = $repodir . '/' . $monitordir;
        $$paths_p{$monitordir} = $filepath;
        if (!mkdir($filepath))
        {
          $is_ok = 0;
        }

        if (!$is_ok)
        {
          print "### [CreateRepository]  Unable to create subdirectories.\n";
        }
      }
    }
  }

  if (!$is_ok)
  {
    $paths_p = undef;
  }

  return $paths_p;
}



# Creates a new video frame tracker widget.
# FIXME - This would be cleaner if object-oriented.
# No arguments.
# Returns a pointer to the tracker's handle.

sub MakeNewVideoTracker
{
  my ($handle_p);

  $handle_p = {};

  return $handle_p;
}



# Probes for the existence of new frames for a given stream.
# Arg 0 points to the video frame tracker handle.
# Arg 1 is the name of the directory to check for frames.
# Returns (frame number, filename) if successful, and (undef, undef) if not.
# The filename returned does _not_ include the path.

sub TrackVideoUpdate
{
  my ($handle_p, $dirname, $framenumber, $filename);
  my ($testname, $testnumber, $scoutoset, $found);

  $handle_p = $_[0];
  $dirname = $_[1];

  $framenumber = undef;
  $filename = undef;

  if ( (defined $handle_p) && (defined $dirname) )
  {
    # Extract the expected frame number.
    # If we don't already have a count, pick a reasonable starting point.

    # This is the last frame we did find, if any.
    $framenumber = $$handle_p{$dirname};

    if (!(defined $framenumber))
    {
      # Mplayer frames start at 1, not 0. Other things might start at 0.
      # We scout ahead several frames, so we'll find it either way.
      $framenumber = 0;
    }
    else
    {
      # Start looking at 1 after the last frame.
      $framenumber++;
    }

    # Search across the scouting window to see if any frames exist.
    # Take the first one, if so.
    $found = 0;
    $testnumber = undef;
    $testname = undef;
    for ($scoutoset = 0;
      (!$found) && ($scoutoset <= $video_frame_scout_lookahead);
      $scoutoset++)
    {
      # FIXME - This format is mplayer-specific.
      # FIXME - Local path construction by magic here!
      $testnumber = $framenumber + $scoutoset;
      $filename = sprintf('%08d.jpg', $testnumber);
      $testname = $dirname . '/' . $filename;

      if ( ( -e $testname ) && ( -s $testname ) )
      {
        $found = 1;
      }
    }

    if ($found)
    {
      $framenumber = $testnumber;
      $$handle_p{$dirname} = $testnumber;
    }
    else
    {
      $framenumber = undef;
      $filename = undef;
    }
  }

  return ($framenumber, $filename);
}



# This sets up the log file and writes data to it.
# This idles when it sees a "stop" command, but never terminates.
# Arg 0 points to the session hash.
# Arg 1 points to the path lookup hash.
# Arg 2 is the filehandle to listen to for events.
# No return value.

sub DoLogger
{
  my ($session_p, $paths_p, $eventhandle);
  my ($logname);
  my ($thisline);
  my ($done);
  my ($thistime);

  $session_p = $_[0];
  $paths_p = $_[1];
  $eventhandle = $_[2];

  if ( (defined $session_p) && (defined $paths_p) && (defined $eventhandle) )
  {
    $logname = $$paths_p{logfile};
    if (open(LOGFILE, ">$logname"))
    {
      # Make the logfile auto-flush.
      # Do this the slightly longer but less cryptic way.
      {
        # This saves the old default handle, selects the log file as default,
        # sets that to autoflush, and then sets the old handle as default.
        my $oldhandle;
        $oldhandle = select(LOGFILE);
        $| = 1;
        select $oldhandle;
      }
      # The short and more cryptic way:
#      select((select(LOGFILE), $| = 1)[0]);

# FIXME - Diagnostics.
if ($tattlecomm) { print STDERR "-- Logging started.\n"; }

      # Write down events that are forwarded to us.
      # Spinning with blocking is okay.

      # NOTE - This blocks, so we don't need to yield.

      $done = 0;
      while ( (!$done) && (defined ($thisline = <$eventhandle>)) )
      {
        # Check for the "stop" command.
        # This may have sender information prepended.
        if ($thisline =~ m/CMD\s+stop/i)
        { $done = 1; }

        # Whatever this is, it gets written.
        # Prepend a timestamp.
        # FIXME - Fetching a timestamp may slow things down!
        $thistime = NCAM_GetRelTimeMillis();
        chomp($thisline);

# FIXME - Diagnostics.
if ($tattlecomm)
{
if ( $tattleframes || (!($thisline =~ m/^\s*\[\S+\]\s+\d+\s+\S+/)) )
{ print STDERR "-- Log message: $thisline\n"; }
}

        $thisline = '(' . $thistime . ') ' . $thisline . "\n";
        print LOGFILE $thisline;
      }

# FIXME - Diagnostics.
if ($tattlecomm) { print STDERR "-- Logging stopped.\n"; }

      # Done.
      close(LOGFILE);
      close($eventhandle);
    }
  }

  # FIXME - Spin instead of returning.
  while (1) {}
}



# This assembles monitor frames, saves them, and hands them off to be
# streamed.
# Arg 0 points to the session hash.
# Arg 1 points to the path lookup hash.
# Arg 2 is the filehandle to listen to for stitch commands.
# Arg 3 is the filehandle to send frame filenames to imagecast.
# Arg 4 is the UDP port to report frame events to.
# No return value.

sub DoStitcher
{
  my ($session_p, $paths_p, $cmdhandle, $casthandle, $monitorframeport);
  my ($thisline);
  my (@imglist, $oname, $thisimg);
  my ($slotname, %imglut, $placement_p);
  my ($baseimage, $slotimage);
  my ($osetx, $osety);
  my ($transmitter);
  my ($cmd, $result);

  $session_p = $_[0];
  $paths_p = $_[1];
  $cmdhandle = $_[2];
  $casthandle = $_[3];
  $monitorframeport = $_[4];

  if ( (defined $session_p) && (defined $paths_p) && (defined $cmdhandle)
    && (defined $casthandle) && (defined $monitorframeport) )
  {
# FIXME - Diagnostics.
if ($tattlecomm) { print STDERR "-- Stitching started.\n"; }

    # Get a UDP transmit socket.
    # FIXME - Not checking for failure!
    $transmitter = NCAM_GetTransmitSocket();

    # Handle image-stitching requests.
    # Spinning with blocking is okay.

    # NOTE - This blocks, so we don't need to yield.

    while (defined ($thisline = <$cmdhandle>))
    {
      # FIXME - Handle overload conditions, if present.
      while (NCAM_HandleCanRead($cmdhandle))
      { $thisline = <$cmdhandle>; }

      # We now have the most recent pending stitch request.


      # These should all be well-formatted command strings:

      # Version 1 - composite image:
      # stitch (output filename) (6 input filenames in slot order)
      # An input filename of "empty" indicates an unused slot.

      # Version 2 - single image:
      # solo (output filename) (1 slot name) (1 input filename)
      # The input file must exist.


      if ($thisline =~ m/^\s*stitch\s+(.*\S)/)
      {
        # Sort this into a list of images indexed by slot name.

        $thisline = $1;
        @imglist = split(/\s+/, $thisline);

        $oname = shift @imglist;
        $oname = $$paths_p{repodir} . '/' . $oname;

        %imglut = ();

        foreach $slotname (@NCAM_session_slots)
        {
          $thisimg = shift @imglist;
          if ( (defined $thisimg) && ('empty' ne $thisimg) )
          {
            $imglut{$slotname} = $$paths_p{repodir} . '/' . $thisimg;
          }
        }


        # Build this image.

# FIXME - Diagnostics.
#print STDERR "Building \"$oname\".\n";

        NCAM_CreateStitchedImage($oname, \%imglut,
          $stitchinfo_monitor_p, $stitchslots_monitor_p);


        # Send this filename to the imagecaster.
        # FIXME - This _shouldn't_ block, but it'd be nice to guarantee that.
        print $casthandle $oname . "\n";

        # Tell the listener that we've produced a frame.
        # Message content doesn't matter, but send the filename anyways.
        NCAM_SendSocket($transmitter, 'localhost', $monitorframeport,
          $oname);


        # Finished stitching this frame.
      }
      elsif ($thisline =~ m/^\s*solo\s+(\S+)\s+(\S+)\s+(\S+)/)
      {
        # Get fully-qualified filenames.
        $oname = $$paths_p{repodir} . '/' . $1;
        $slotname = $2;
        $thisimg = $$paths_p{repodir} . '/' . $3;


        # FIXME - Copying is fast, and is preferred.
        # Compositing with one image gives consistent-sized output, with a
        # label.
        if (1)
        {
          # Copy the image.
          # FIXME - This causes a shell invocation, which may take time.
          $cmd = "cp $thisimg $oname";
          $result = `$cmd`;
        }
        else
        {
          # Build this image.
          NCAM_CreateSoloImage($oname, { $slotname => $thisimg },
            $stitchinfo_monitor_p, $stitchslots_monitor_p);
        }

        # Send this filename to the imagecaster.
        # FIXME - This _shouldn't_ block, but it'd be nice to guarantee that.
        print $casthandle $oname . "\n";

        # Tell the listener that we've produced a frame.
        # Message content doesn't matter, but send the filename anyways.
        NCAM_SendSocket($transmitter, 'localhost', $monitorframeport,
          $oname);


        # Finished stitching this frame.
      }

    }

    # We've shut down. Close the transmitter socket.
    NCAM_CloseSocket($transmitter);
  }

  # FIXME - Spin instead of returning.
  while (1) {}
}



# This sets up UDP listener sockets and listens for events.
# This idles when it sees a "stop" command, but never terminates.
# Arg 0 points to the session hash.
# Arg 1 points to the path lookup hash.
# Arg 2 is the filehandle to send logger events to.
# Arg 3 is the filehandle to send master events to.
# Arg 4 is the filehandle to send stitcher events to.
# Arg 5 is the port to listen for monitor frame transmissions on.
# No return value.

sub DoListener
{
  my ($session_p, $paths_p,
    $loggerhandle, $masterhandle, $stitcherhandle,
    $monitorframeport);
  my (%vidhandles, %talkhandles);
  my ($sources_p, $srclabel, $srcdata_p, $thisport);
  my (@loggerqueue, @masterqueue, @stitcherqueue);
  my ($thistime);
  my ($vidtracker_p, $thisframe, $thisfilename);
  my ($lastmonitortime, %mostrecentframes, $monitorcount, $monitorok);
  my ($thisname, $thishandle, $hasmessage, $senderip);
  my ($thisline, $done);
  my ($monitorsource, $solofile);

  $session_p = $_[0];
  $paths_p = $_[1];
  $loggerhandle = $_[2];
  $masterhandle = $_[3];
  $stitcherhandle = $_[4];
  $monitorframeport = $_[5];

  if ( (defined $session_p) && (defined $paths_p)
    && (defined $loggerhandle) && (defined $masterhandle)
    && (defined $stitcherhandle) && (defined $monitorframeport) )
  {
# FIXME - Diagnostics.
if ($tattlecomm)
{
print $loggerhandle "Listener ping to logger.\n";
print $masterhandle "Listener ping to master.\n";
}

    # Create UDP listening ports.

    %talkhandles = ();
    %vidhandles = ();

    # Command port.

    if (defined ($thisport = $$session_p{cmdport}))
    {
      $talkhandles{'local'} = NCAM_GetListenSocket($thisport);
    }

    # Message ports.
    # These are keyed by the source's full URL.
    # This includes the talkback port, which we don't use here.

    $sources_p = $$session_p{talkers};
    foreach $srclabel (keys %$sources_p)
    {
      $srcdata_p = $$sources_p{$srclabel};
      if ($$srcdata_p{enabled})
      {
        $thisport = $$srcdata_p{myport};
        $talkhandles{$$srcdata_p{key}} = NCAM_GetListenSocket($thisport);
      }
    }

    # Video ports.
    # Only use the ones that have been assigned to slots.
    # These are keyed by slot name, which is also the image directory name.
    # NOTE - We're manually adding the monitor port here too.

    %mostrecentframes = ();
    foreach $thisname (@NCAM_session_slots)
    {
      $mostrecentframes{$thisname} = 'empty';
    }
    $lastmonitortime = undef;
    $monitorcount = 0;

    $sources_p = $$session_p{slots};
    foreach $srclabel (keys %$sources_p)
    {
      $srcdata_p = $$sources_p{$srclabel};

      if ('camera' eq $$srcdata_p{type})
      {
        $srcdata_p = $$srcdata_p{config};
        $thisport = $$srcdata_p{updateport};
        $vidhandles{$srclabel} = NCAM_GetListenSocket($thisport);

# FIXME - Tolerate missing streams. Leave this as 'empty'.
#        $mostrecentframes{$srclabel} = undef;
      }
      elsif ('stream' eq $$srcdata_p{type})
      {
        $srcdata_p = $$srcdata_p{config};
        $thisport = $$srcdata_p{updateport};
        $vidhandles{$srclabel} = NCAM_GetListenSocket($thisport);

# FIXME - Tolerate missing streams. Leave this as 'empty'.
#        $mostrecentframes{$srclabel} = undef;
      }
    }

    $vidhandles{$monitordir} = NCAM_GetListenSocket($monitorframeport);


    # Spin, processing messages.
    # NOTE - We have to poll quickly, so use non-blocking operations
    # where possible.

    $done = 0;
    @loggerqueue = ();
    @masterqueue = ();
    @stitcherqueue = ();

# FIXME - Diagnostics.
if ($tattlecomm)
{
    @loggerqueue = ( 'First queue entry.' );
    @masterqueue = ( 'First queue entry.' );
}

# FIXME - Diagnostics.
if ($tattlecomm)
{
print $loggerhandle "Listener initialized.\n";
print $masterhandle "Listener initialized.\n";
}

    # Create a new video frame tracker widget.
    # FIXME - This would be cleaner if object-oriented.
    $vidtracker_p = MakeNewVideoTracker();

    # Default to "composite of all video feeds" for the monitor.
    $monitorsource = 'Monitor';

    while (!$done)
    {
      # FIXME - Yield. This might introduce unacceptable delays!
      NCAM_Yield();

      # Get a timestamp.
      # FIXME - Fetching a timestamp may slow things down!
      $thistime = NCAM_GetRelTimeMillis();


      # Check for "new frame" events.
      # NOTE - This catches monitor frames too, by design.

      foreach $thisname (keys %vidhandles)
      {
        $thishandle = $vidhandles{$thisname};

        ($hasmessage, $senderip, $thisline) =
          NCAM_CheckReceiveSocket($thishandle);

        if ($hasmessage && (defined $thisline))
        {
# FIXME - Diagnostics.
if ($tattlecomm && $tattleframes)
{
chomp($thisline);
print STDERR "-- Video update: $thisline\n";
}

          # Mplayer is telling us that it has a new frame.
          # Mplayer's timestamps aren't useful; just record the event.

          # See if we actually do have a new frame.
          ($thisframe, $thisfilename) =
            TrackVideoUpdate($vidtracker_p,
            $$paths_p{repodir} . '/' . $thisname);

          # If so, make note of the frame.
          if ( (defined $thisfilename) && (defined $thisframe) )
          {
            # Turn the filename into an in-repository path.
            $thisfilename = $thisname . '/' . $thisfilename;

            $thisline = sprintf('[%s]  frame %d  %s',
              $thisname, $thisframe, $thisfilename);

            push @loggerqueue, $thisline;


            # Update the monitor's record of the most recent frames.
            $mostrecentframes{$thisname} = $thisfilename;
          }
        }
      }


      # Check to see if it's time to send a new frame.
      # FIXME - Using 33 ms period rather than exactly 1/30 seconds.
      if ( (!(defined $lastmonitortime))
        || ( 33 <= ($thistime - $lastmonitortime) ) )
      {
        $monitorok = 1;

        foreach $thisname (@NCAM_session_slots)
        {
          $thisfilename = $mostrecentframes{$thisname};

          if (!(defined $thisfilename))
          { $monitorok = 0; }
        }

        if ($monitorok)
        {
          $lastmonitortime = $thistime;
          $monitorcount++;

          $thisfilename = sprintf('%s/%08d.jpg', $monitordir, $monitorcount);

          # This will be undef if the source is "Monitor", and "empty" if
          # the source hasn't sent frames yet.
          $solofile = $mostrecentframes{$monitorsource};

          if ( ('Monitor' eq $monitorsource)
            || (!(defined $solofile)) || ('empty' eq $solofile) )
          {
            $thisline = 'stitch ' . $thisfilename;

            foreach $thisname (@NCAM_session_slots)
            {
              $thisline .= ' ' . $mostrecentframes{$thisname};
            }
          }
          else
          {
            $thisline = 'solo ' . $thisfilename . ' '
              . $monitorsource . ' ' . $solofile;
          }

          push @stitcherqueue, $thisline;

          # We don't log stitched frames here; we're notified of completed
          # frames via UDP, above.
        }
      }


      # Check for "new message" events.

      foreach $thisname (keys %talkhandles)
      {
        $thishandle = $talkhandles{$thisname};

        ($hasmessage, $senderip, $thisline) =
          NCAM_CheckReceiveSocket($thishandle);

        if ($hasmessage && (defined $thisline))
        {
          # This contains message text.
          # Forward it to the logger.
          # If it's a command, forward it to the master too.

          chomp($thisline);

# FIXME - Diagnostics.
if ($tattlecomm) { print STDERR "-- Talker said: $thisline\n"; }

          if ($thisline =~ m/^\s*CMD\s+/i)
          {
            push @masterqueue, $thisline;
          }

          $thisline = '[' . $thisname . ']  ' . $thisline;
          push @loggerqueue, $thisline;
        }
      }

      # Emit queued events.
      # Emit one message per channel per pass, to avoid pausing if there's
      # a bottleneck. UDP reads have to happen without delay.
      # NCAM_HandleCanWrite() should always return true under normal conditons,
      # but check it anyways.

      if (NCAM_HandleCanWrite($loggerhandle))
      {
        $thisline = shift @loggerqueue;
        if (defined $thisline)
        {
# FIXME - Diagnostics.
if ($tattlecomm) { print STDERR "-- Log write: $thisline\n"; }

          # We need a newline to force a flush.
          print $loggerhandle $thisline . "\n";
        }
      }

      if (NCAM_HandleCanWrite($stitcherhandle))
      {
        $thisline = shift @stitcherqueue;
        if (defined $thisline)
        {
# FIXME - Diagnostics.
if ($tattlecomm) { print STDERR "-- Stitcher write: $thisline\n"; }

          # We need a newline to force a flush.
          print $stitcherhandle $thisline . "\n";
        }
      }

      if (NCAM_HandleCanWrite($masterhandle))
      {
        $thisline = shift @masterqueue;
        if (defined $thisline)
        {
# FIXME - Diagnostics.
if ($tattlecomm) { print STDERR "-- Master write: $thisline\n"; }

          # Check for the shutdown command.
          # Also check for "CMD monitor (new feed)" commands.
          if ($thisline =~ m/CMD\s+stop/i)
          {
            $done = 1;
          }
          elsif ($thisline =~ m/CMD\s+monitor\s+(\w+)/i)
          {
            # If this feed _exists_, switch to it.
            # We have video handles for all valid feeds, including "Monitor".
            if (defined $vidhandles{$1})
            {
              $monitorsource = $1;
            }
          }

          # We need a newline to force a flush.
          print $masterhandle $thisline . "\n";
        }
      }
    }
# FIXME - Diagnostics.
if ($tattlecomm) { print STDERR "-- Listener stopped.\n"; }


    # Done.

    # Close pipes.
    close($loggerhandle);
    close($stitcherhandle);
    close($masterhandle);

    # Close sockets.

    foreach $thisname (keys %talkhandles)
    {
      $thishandle = $talkhandles{$thisname};
      close($thishandle);
    }

    foreach $thisname (keys %vidhandles)
    {
      $thishandle = $vidhandles{$thisname};
      close($thishandle);
    }
  }

  # FIXME - Spin instead of returning.
  while (1) {}
}



# Starts a camera capture thread.
# Arg 0 points to the configuration information for the camera.
# Arg 1 is the path to store image frames in.
# Returns the child PID, or undef on error.

sub StartCameraThread
{
  my ($config_p, $path, $pid);
  my ($devdata_p);
  my ($exposure);
  my ($width, $height);

  $pid = undef;

  $config_p = $_[0];
  $path = $_[1];

  if ( (defined $config_p) && (defined $path) )
  {
    # Try to fetch camera metadata. We need this to set exposure.
    # This should now nominally be guaranteed on read-in.
    $devdata_p = $$config_p{meta};

    if (defined $devdata_p)
    {
      # Set up the child process, and return immediately.
      $pid = fork();

      if (0 == $pid)
      {
        # We're the child. Set exposure, then transfer control to mplayer.
        NCAM_SetProcessName('ncam-dae-camera');

        NCAM_InitCameraConfig($config_p);
        NCAM_SetExposureByStop($config_p, $$config_p{exp});

        # Parse the requested geometry.
        $width = 640;
        $height = 480;
        if ($$config_p{size} =~ m/(\d+)x(\d+)/)
        {
          $width = $1;
          $height = $2;
        }

        # FIXME - We need to set this in-flight as well.
        # Fork a child process to do it after one second.
        if (0 == fork())
        {
          # We're the child.

          # Wait until the camera is running.
          sleep(1);

          # Initialize configuration.
          NCAM_InitCameraConfig($config_p);
          NCAM_SetExposureByStop($config_p, $$config_p{exp});

          # End the child thread.
          exit(0);
        }

        # We're the parent thread. Start the camera.
        # Give arguments as a list.
        # This avoids a shell invocation, and gives us the right PID.
        exec('mplayer', 'tv://', '-tv',
          'device=' . $$config_p{device}
          . ':width=' . $width . ':height=' . $height
          . ':outfmt=mjpg:fps=' . $$config_p{rate},
          # FIXME - Leave JPEG output at the default quality.
          '-vo', 'jpeg:outdir=' . $path,
          '-udp-master', '-udp-ip', '127.0.0.1',
          '-udp-port', $$config_p{updateport},
          '-really-quiet', '-nosound');

        # We shouldn't reach here!
        die "### Returned from camera exec(). Shouldn't happen.";
      }

      # Done.
    }
  }

  return $pid;
}



# Starts a stream capture thread.
# Arg 0 points to the configuration information for the stream.
# Arg 1 is the path to store image frames in.
# Returns the child PID, or undef on error.

sub StartStreamThread
{
  my ($config_p, $path, $pid);
  my ($devdata_p);
  my ($exposure);
  my ($width, $height);

  $pid = undef;

  $config_p = $_[0];
  $path = $_[1];

  if ( (defined $config_p) && (defined $path) )
  {
    # Set up the child process, and return immediately.
    $pid = fork();

    if (0 == $pid)
    {
      # We're the child. Transfer control to mplayer.
      NCAM_SetProcessName('ncam-dae-stream');

      # FIXME - We need to specify a frame rate!
      # If this is too low, the buffer fills up.
      # If this is too high, it can stutter, but that's tolerable.
      # FakeUnity gives 30 fps nominally. Real vlc gives whatever's asked.

      # Give arguments as a list.
      # This avoids a shell invocation, and gives us the right PID.
      exec('mplayer', '-demuxer', 'lavf', $$config_p{url},
        '-fps', '30',
        # FIXME - Leave JPEG output at the default quality.
        '-vo', 'jpeg:outdir=' . $path,
        '-udp-master', '-udp-ip', '127.0.0.1',
        '-udp-port', $$config_p{updateport},
        '-really-quiet', '-nosound');

      # We shouldn't reach here!
      die "### Returned from stream exec(). Shouldn't happen.";
    }

    # Done.
  }

  return $pid;
}



# This sets up files and pipes and starts daemon processes to handle
# listening, logging, and serving the monitor stream.
# When a shutdown command occurs, this also cleans up threads and closes
# files and sockets.
# Arg 0 points to the session hash.
# Arg 1 points to the path lookup hash.
# No return value.

sub DoDaemon
{
  my ($session_p, $paths_p);
  my ($listenlogread, $listenlogwrite);
  my ($listenstitchread, $listenstitchwrite);
  my ($listenmasterread, $listenmasterwrite);
  my ($logger_pid, $listener_pid, $stitcher_pid);
  my ($imagecast_handle);
  my (@vidpids, $thispid);
  my ($slots_p, $slotname, $thisslot_p);
  my ($talkers_p, $talkname, $thistalk_p, $talksocket);
  my ($thisline, $done);

  $session_p = $_[0];
  $paths_p = $_[1];

  if ( (defined $session_p) && (defined $paths_p) )
  {
    # Set up communications pipes for the processes.
    # These are named (sender)(receiver)(which end).
    # The listener forwards events to the logger.
    # The listener also forwards commands to the master.
    # The listener tells the stitcher to build new monitor frames.

    ($listenlogread, $listenlogwrite) = NCAM_GetNewPipe();
    ($listenstitchread, $listenstitchwrite) = NCAM_GetNewPipe();
    ($listenmasterread, $listenmasterwrite) = NCAM_GetNewPipe();


    # Fetch a timestamp before spawning child threads, so that the
    # relative times reported all have a common reference point.
    NCAM_GetRelTimeMillis();


    # Set up child threads.


    # First child: spin off the logger.
    $logger_pid = fork();
    if (0 == $logger_pid)
    {
      # We're the child (logger).
      NCAM_SetProcessName('ncam-dae-logger');

      # Close all filehandles except the one we listen to.
      close($listenlogwrite);
      close($listenstitchread);
      close($listenstitchwrite);
      close($listenmasterread);
      close($listenmasterwrite);

      # Run the logger process.
      DoLogger($session_p, $paths_p, $listenlogread);
      die "###  Logger function returned (it isn't supposed to do that!).";
    }
    # Give this time to set up.
    NCAM_SleepMillis(100);
# FIXME - Diagnostics.
if ($tattlecomm) { print $listenlogwrite "Writing test.\n"; }


    # Second child: spin off the imagecasting server.
    # FIXME - This doesn't give us a PID; instead we get a pipe handle.
    # FIXME - Use the single-client version. Multi- can leave zombies.
    $imagecast_handle =
      NCAM_StartLiveImagecastSingle($$session_p{monitorport});


    # Second child: spin off the stitcher.
    $stitcher_pid = fork();
    if (0 == $stitcher_pid)
    {
      # We're the child (stitcher).
      NCAM_SetProcessName('ncam-dae-stitcher');

      # Close all filehandles except the one we listen to.
      close($listenlogread);
      close($listenlogwrite);
      close($listenstitchwrite);
      close($listenmasterread);
      close($listenmasterwrite);

      # Alter our priority level.
      # We want to downgrade our priority so that capture takes precedence.
      POSIX::nice($stitchernicelevel);

      # Run the stitcher process.
      DoStitcher($session_p, $paths_p, $listenstitchread,
        $imagecast_handle, $monitor_report_port);
      die "###  Stitcher function returned (it isn't supposed to do that!).";
    }
    # Give this time to set up.
    NCAM_SleepMillis(100);


    # Third child: spin off the listener.
    $listener_pid = fork();
    if (0 == $listener_pid)
    {
      # We're the child (listener).
      NCAM_SetProcessName('ncam-dae-listener');

      # Close all filehandles except the ones we write to.
      close($listenlogread);
      close($listenstitchread);
      close($listenmasterread);

      # Run the listener process.
      DoListener($session_p, $paths_p,
        $listenlogwrite, $listenmasterwrite, $listenstitchwrite,
        $monitor_report_port);
      die "###  Listener function returned (it isn't supposed to do that!).";
    }
    # Give this time to set up.
    NCAM_SleepMillis(100);


    # We're the parent. Close all of the inter-child filehandles.
    # The only one left open is listener-to-master reading.
    close($listenlogread);
    close($listenlogwrite);
    close($listenstitchread);
    close($listenstitchwrite);
    close($listenmasterwrite);


    # Now that infrastructure is set up, spin off video grabbers.

    # Video ports.
    # Only use the ones that have been assigned to slots.
    # These are keyed by slot name, which is also the image directory name.

    $slots_p = $$session_p{slots};
    foreach $slotname (keys %$slots_p)
    {
      $thisslot_p = $$slots_p{$slotname};

      if ('camera' eq $$thisslot_p{type})
      {
        $thispid = StartCameraThread($$thisslot_p{config},
          $$paths_p{$slotname});

        if (defined $thispid)
        { push @vidpids, $thispid; }
      }
      elsif ('stream' eq $$thisslot_p{type})
      {
        $thispid = StartStreamThread($$thisslot_p{config},
          $$paths_p{$slotname});

        if (defined $thispid)
        { push @vidpids, $thispid; }
      }
    }


    # Tell any enabled talkers that we want to hear from them.

    $talksocket = NCAM_GetTransmitSocket();

    $talkers_p = $$session_p{talkers};
    foreach $talkname (keys %$talkers_p)
    {
      $thistalk_p = $$talkers_p{$talkname};

      if ($$thistalk_p{enabled})
      {
        NCAM_SendSocket($talksocket, $$thistalk_p{host}, $$thistalk_p{port},
          "talk to me on port " . $$thistalk_p{myport});
      }
    }

    NCAM_CloseSocket($talksocket);
    $talksocket = undef;


    # Spin, monitoring the command channel until we get a shutdown command.
    # Blocking is ok; we only have one stream to monitor.

    # NOTE - This does block, so a yield isn't needed.

    $done = 0;
    while ( (!$done) && (defined ($thisline = <$listenmasterread>)) )
    {
      if ($thisline =~ m/^\s*CMD\s+stop/i)
      {
        # We're done.
        $done = 1;
      }
# FIXME - Diagnostics.
if ($tattlecomm)
{
chomp($thisline);
print "-- Master received: $thisline\n";
}
    }

# FIXME - Diagnostics.
if(!$done)
{
print "###  Listener-to-master read failed.\n";
}


    # Assume that no matter how we got here, we should shut down.


    # Tell any enabled talkers to stop talking.

    $talksocket = NCAM_GetTransmitSocket();

    $talkers_p = $$session_p{talkers};
    foreach $talkname (keys %$talkers_p)
    {
      $thistalk_p = $$talkers_p{$talkname};

      if ($$thistalk_p{enabled})
      {
        NCAM_SendSocket($talksocket, $$thistalk_p{host}, $$thistalk_p{port},
          "stop talking");
      }
    }

    NCAM_CloseSocket($talksocket);
    $talksocket = undef;


    # Kill the video grabber threads. Forcibly if necessary.

    foreach $thispid (@vidpids)
    { kill 'TERM', $thispid; }

    NCAM_SleepMillis(2000);

    foreach $thispid (@vidpids)
    { kill 'KILL', $thispid; }

    # Now kill the daemon threads.

    kill 'TERM', $listener_pid;
    kill 'TERM', $stitcher_pid;
    kill 'TERM', $logger_pid;

    NCAM_SleepMillis(1000);

    kill 'KILL', $listener_pid;
    kill 'KILL', $stitcher_pid;
    kill 'KILL', $logger_pid;


    # Tell the monitor streamer to stop streaming.
    # Prepend a newline in case we interrupted other communication above.
    # FIXME - This should be done via UDP instead, to guarantee non-blocking.
    # FIXME - This may take a while to die!
    print $imagecast_handle "\nshutdown\n";


    # Done.
    # Return to the caller.
  }
}



# Parses command-line arguments.
# No arguments.
# Returns an options hash.

sub ProcessArgs
{
  my ($options_p);
  my ($thisarg);
  my ($is_ok);

  $options_p = {};
  $is_ok = 1;

  foreach $thisarg (@ARGV)
  {
    if ($thisarg =~ m/^--(\S+?)=(.*\S)/)
    {
      $$options_p{$1} = $2;
    }
    elsif ($thisarg =~ m/^--(\S+)/)
    {
      $$options_p{$1} = 1;
    }
    else
    {
      $is_ok = 0;
    }
  }

  if (!$is_ok)
  {
    $options_p = undef;
    print "Use \"--help\" for help.\n";
  }

  return $options_p;
}



# Displays a help screen.
# No arguments.
# No return value.

sub PrintHelp
{
  print << "Endofblock";

NeuroCam management script - Data acquisition daemon.
Written by Christopher Thomas.

Usage:  neurocam-daemon.pl (options)

Valid options:

--help     - Displays this help screen.

--repository=<dir>       - Specifies where this capture session's data goes.
--sessionconfig=<file>   - Specifies a session configuration file to read.

Endofblock
}



#
# Main Program
#

my ($options_p);
my ($repodir, $sessionfile);
my ($session_p, $errstr);
my ($paths_p);


# Tweak our starting port number to avoid collisions.
NCAM_SetNextListenPort($NCAM_port_camdaemon_base);

# Get appropriate command-line arguments, or defaults if we don't have those.
$options_p = ProcessArgs();

# Failure to parse options has already been reported.
if (defined $options_p)
{
  $repodir = $$options_p{repository};
  $sessionfile = $$options_p{sessionconfig};

  if (defined $$options_p{help})
  {
    PrintHelp();
  }
  elsif (!(defined $repodir))
  {
    PrintHelp();
  }
  else
  {
    if (defined $sessionfile)
    {
      # This returns undef on error.
      ($session_p, $errstr) = NCAM_ReadSessionConfigFile($sessionfile);

      if (!(defined $session_p))
      { print '### ' . $errstr; }
    }
    else
    {
      # Build a new session config using defaults.
      # Warn the user that this is a bad idea.
      print "** Autodetecting camera configuration. This is a bad idea!\n";

      my ($cameras_p, $network_p);
      my ($monitorfile, $monitorport, $cmdport);

      $monitorfile = $NCAM_default_settings{monitorfile};
      $monitorport = $NCAM_default_settings{monitorport};
      $cmdport = $NCAM_default_settings{cmdport};

      $cameras_p = NCAM_GetCameraList();
      print "-- Assuming game and GPIO are on default ports.\n";
      $network_p =
        NCAM_ProbeNetworkDevices($NCAM_default_settings{talkquerylist}, 1000);

      print "-- Putting monitor on :$monitorport/$monitorfile and"
        . " control on $cmdport.\n";
      $session_p = NCAM_CreateNewSessionConfig($cameras_p, $network_p,
        $monitorfile, $monitorport, $cmdport);
      NCAM_PopulateSlotsByDefault($session_p);

# FIXME - Diagnostics. Dump all structures to STDERR.
if(0)
{
print STDERR "\nCamera data begins:\n";
print STDERR NCAM_StructureToText($cameras_p) . "\n";
print STDERR "Camera data ends.\n\n";
print STDERR "Network data begins:\n";
print STDERR NCAM_StructureToText($network_p) . "\n";
print STDERR "Network data ends.\n\n";
print STDERR "Session data begins:\n";
print STDERR NCAM_StructureToText($session_p) . "\n";
print STDERR "Session data ends.\n\n";
}
    }

    # If we have a session hash at all, it's ostensibly valid. Proceed.
    if (defined $session_p)
    {
      $paths_p = CreateRepository($repodir, $session_p);

      if (!(defined $paths_p))
      {
        print "-- Couldn't create repository. Bailing out.\n";
      }
      else
      {
        # This runs until we get a shutdown command, then cleans itself up.
        DoDaemon($session_p, $paths_p);
      }
    }
  }
}


#
# This is the end of the file.
#
