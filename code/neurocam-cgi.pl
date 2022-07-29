#!/usr/bin/perl
#
# NeuroCam management script - CGI invocation UI.
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
use CGI;
use Cwd;
use Proc::Daemon;
use Image::Magick;

# Path fix needed for more recent Perl versions.
use lib ".";

require "neurocam-libmt.pl";
require "neurocam-libcam.pl";
require "neurocam-libnetwork.pl";
require "neurocam-libsession.pl";
require "neurocam-libmanage.pl";
require "neurocam-libweb.pl";
require "neurocam-libstitch.pl";
require "neurocam-libpost.pl";



#
# Imported Constants
#

# Fixme - Doing this the messy way. Any imported variables need appropriate
# "our" declarations.

our ($NCAM_cgi_repository_base, $NCAM_cgi_usb_repository_base);
our ($NCAM_cgi_do_move_delete);

our ($NCAM_port_cgi_base);
our ($NCAM_port_mgrdaemon_query);
our ($NCAM_port_camdaemon_command);

our (%NCAM_default_settings);
our (@NCAM_session_slots);

our ($stitchinfo_monitor_p);



#
# Private Constants
#

# Scratch file for passing configuration information to the daemon.
my ($tempconfigfile);
$tempconfigfile = '/tmp/neurocam-session.config';

# Scratch file for storing the most recent configuration.
# On one hand, this should persist, and /tmp will wipe it on reboot.
# On the other hand, camera IDs will be scrambled on reboot, so that's fine.
my ($lastconfigfile);
$lastconfigfile = '/tmp/neurocam-recent.config';

# Filesystem and HTTP paths to the auxiliary files directory.
my ($auxpathunix, $auxpathweb);
$auxpathunix = 'auxfiles';
$auxpathweb = 'auxfiles/';

# Lookup table of button-name feed labels to folder names.
my (%feednamelut);
%feednamelut =
(
  'Scene A' => 'SceneA', 'Scene B' => 'SceneB', 'Scene C' => 'SceneC',
  'Face A' => 'FaceA', 'Face B' => 'FaceB', 'Game' => 'Game',
  'Combined Feed' => 'Monitor'
);


#
# Functions
#


# Probes cameras and network devices.
# NOTE - This takes nonzero time.
# No arguments.
# Returns ($cameras_p, $netdevs_p).

sub ProbeDevices
{
  my ($cameras_p, $netdevs_p);

  $cameras_p = NCAM_GetCameraList();
  $netdevs_p =
    NCAM_ProbeNetworkDevices($NCAM_default_settings{talkquerylist}, 1000);

  return ($cameras_p, $netdevs_p);
}


# Attempts to load the most recently used copy of the session config.
# Failing that, it probes devices and creates one, saving it to disk.
# Arg 0 is the filename expected to contain the session config.
# Returns a pointer to a valid configuration hash.

sub LoadOrCreateSessionConfig
{
  my ($fname, $session_p);
  my ($errstr);
  my ($cameras_p, $netdevs_p);

  $fname = $_[0];
  $session_p = undef;

  if (defined $fname)
  {
    ($session_p, $errstr) = NCAM_ReadSessionConfigFile($fname);
  }

  if (!(defined $session_p))
  {
    # Probe devices.
    ($cameras_p, $netdevs_p) = ProbeDevices();

    # Assemble and populate a session based on default settings.
    $session_p = NCAM_CreateNewSessionConfig($cameras_p, $netdevs_p,
      $NCAM_default_settings{monitorfile},
      $NCAM_default_settings{monitorport},
      $NCAM_default_settings{cmdport});
    NCAM_PopulateSlotsByDefault($session_p);

    # Write the config file back to disk.
    NCAM_WriteSessionConfigFile($fname, $session_p);
  }

  # Force use of the default communications settings.
  # This should already have been handled, but do it anyways.
  $$session_p{cmdport} = $NCAM_default_settings{cmdport};
  $$session_p{monitorport} = $NCAM_default_settings{monitorport};
  $$session_p{monitorfile} = $NCAM_default_settings{monitorfile};

  return $session_p;
}



# Sets all cameras to the specified resolution and frame rate.
# Modifies the provided session config hash.
# Arg 0 is the configuration file to alter.
# Arg 1 is the desired resolution.
# Arg 2 is the desired frame rate.
# Arg 3 is the desired exposure.
# No return value.

sub SetAllCameras
{
  my ($session_p, $targetsize, $targetrate, $targetexp);
  my ($camlist_p, $thisdev, $thiscam_p, $thismeta_p);
  my ($chosensize, $chosenrate);
  my ($sizelist_p, $rates_p, @ratelist, $thisrate);

  $session_p = $_[0];
  $targetsize = $_[1];
  $targetrate = $_[2];
  $targetexp = $_[3];

  if ( (defined $session_p) && (defined $targetsize) && (defined $targetrate)
    && (defined $targetexp) )
  {
    $camlist_p = $$session_p{cameras};
    foreach $thisdev (keys %$camlist_p)
    {
      $thiscam_p = $$camlist_p{$thisdev};
      $thismeta_p = $$thiscam_p{meta};

      $chosensize = undef;
      $chosenrate = undef;

      $sizelist_p = $$thismeta_p{sizes};
      $chosensize =
        NCAM_FindClosestResolution($targetsize, keys %$sizelist_p);

      $rates_p = $$sizelist_p{$chosensize};
      # Copy by value and guarantee sorting in descending order.
      @ratelist = sort {$b <=> $a} @$rates_p;

      foreach $thisrate (@ratelist)
      {
        # Pick the _lowest_ rate that's still at least the target rate.
        if ($thisrate >= $targetrate)
        {
          $chosenrate = $thisrate;
        }
      }

      # If no rates were acceptable, pick the highest.
      if (!(defined $chosenrate))
      {
        $chosenrate = pop @ratelist;
      }

      # The target exposure label is always acceptable.

      # Update this camera's settings.
      $$thiscam_p{size} = $chosensize;
      $$thiscam_p{rate} = $chosenrate;
      $$thiscam_p{exp} = $targetexp;
    }
  }
}



# This kills the NeuroCam manager and daemon, if active, and all sub-threads.
# FIXME - Killing the GPIO widget will leave filehandles in limbo. Devices
# may need to be re-plugged.
# There's no way around this, as the manager kills it itself if we don't.
# This just cleans up zombies.

sub KillAllNeurocamProcesses
{
  my ($username, @processes, $cmd, $result);
  my ($thisline, $thisname, $thispid, @pidlist);

  # This should be "www-data" under Mint, but check anyways.
  $username = `whoami`;

  $cmd = "ps -u $username";
  @processes = `$cmd`;

  # Walk through the process list.
  # We care about "neurocam-manager.pl", "neurocam-daemon.pl", and all names
  # set using NCAM_SetProcessName.
  # FIXME - Also killing "neurocam-gpio.pl", per above.

  @pidlist = ();

  foreach $thisline (@processes)
  {
    if ($thisline =~ m/^\s*(\d+)\s+.*\s+(\S+)\s*$/)
    {
      $thispid = $1;
      $thisname = $2;

      # The name may be truncated. I see 15 characters in my own list.
      # Also kill mplayer instances.
      if ( ($thisname =~ m/^neurocam-/) || ($thisname =~ m/^ncam-/)
        || ($thisname =~ m/^mjpeg-/) || ($thisname =~ m/^mgr-/)
        || ($thisname =~ m/^mplayer/) )
      {
        # Exclude things we want to protect.
        # Everything else gets added to the PID list.
        if (!( ($thisname =~ m/cgi/) ))
        {
          push @pidlist, $thispid;
        }
      }
    }
  }

  # If we have PIDs, kill them all.
  if (defined $pidlist[0])
  {
    $cmd = 'kill -9';

    foreach $thispid (@pidlist)
    { $cmd .= ' ' . $thispid; }

    $result = `$cmd`;
  }

  # Give it a moment.
  sleep(1);

  # Done.
}



# This asks NeuroCam processes nicely to stop, waits a moment, then
# kills everything.
# NOTE - This takes several seconds.
# No arguments.
# No return value.

sub StopNicelyThenKill
{
  # First, ask the manager nicely to shut down.
  # Ask the daemon to shut down too, just in case we're in a strange state.
  NCAM_SendAnonSocket('localhost', $NCAM_port_camdaemon_command, 'CMD stop');
  NCAM_SendAnonSocket('localhost', $NCAM_port_mgrdaemon_query, 'shutdown');

  # Give that time to do its thing.
  sleep(2);

  # Kill everything we can, with prejudice.
  # No need to wait afterwards; the function call does that for us.
  KillAllNeurocamProcesses();
}



#
# Main Program
#

my ($netinfo_p, $hostip);
my ($query, $params_p);
my ($caller, $destpage, $action);
my ($mgrstatus);
my ($session_p);
my ($commandhost, $commandport);
my ($monitorhost, $monitorport, $monitorfilename);
my ($sessiontext_p);
my ($cmd, $result);
my ($busytask, $busyprogress, $busyfallthrough, $busyargs_p, $busycancel);
my ($thisarg, $had_args);
my ($repotop, $repofolder);
my ($slotname);
my (@vidlist, @vidframes);
my ($errmsg);
my ($need_config_snapshots, $need_browser_update, $browser_update_force);
my ($cameras_p, $netdevs_p);
my ($autovidsize, $autovidrate, $autovidexp);
my ($use_ledsynch);


# Tweak our starting port number to avoid collisions.
NCAM_SetNextListenPort($NCAM_port_cgi_base);


# Get network info.
$netinfo_p = NCAM_GetNetworkInfo();
$hostip = $$netinfo_p{hostip};


# Fetch the CGI arguments.
$query = CGI->new();
$params_p = $query->Vars();

# Emit the "we're well-formatted CGI output" magic string.
print $query->header();

# Past this point, we have an argument hash and all of our output is manual,
# so we don't care about the CGI object.


# Extract information about what we're being asked to do.
# Some or all of these may be undefined.
$caller = $$params_p{callingpage};
$destpage = $$params_p{destpage};
$action = $$params_p{command};


# Figure out what the manager is doing.
# This will pause briefly if the manager isn't active.
$mgrstatus = NCAM_GetManagerStatus();

# If the manager is inactive, restart it.
# FIXME - This tries to detect _again_, so the pause is longer.
if (!(defined $mgrstatus))
{
  # FIXME - We might want to kill any zombie instances here.
  NCAM_LaunchDaemon('./neurocam-manager.pl');
  # FIXME - Discarding the pid.

  # Query the status again.
  # Give it time to launch first.
  NCAM_SleepMillis(500);
  $mgrstatus = NCAM_GetManagerStatus();
}

# Force sanity no matter what.
if (!(defined $mgrstatus))
{ $mgrstatus = 'ERROR: Unable to detect or restart manager.'; }


# Set reasonable defaults.

if (!(defined $caller))
{ $caller = 'none'; }

if (!(defined $action))
{ $action = 'none'; }

$busyfallthrough = 'browser';
$busyargs_p = {};

if (!(defined $destpage))
{
  if ($mgrstatus =~ m/^running/)
  { $destpage = 'monitor'; }
  elsif ($mgrstatus =~ m/^busy/)
  { $destpage = 'busy'; }
  else
  { $destpage = 'config'; }
#  { $destpage = 'browser'; }
}


# FIXME - Diagnostics.
print "<!-- (initial) caller: $caller   target: $destpage   action: $action -->\n";


# FIXME - Force default communication settings.

$commandhost = $hostip;
$commandport = $NCAM_default_settings{cmdport};

$monitorhost = $hostip;
$monitorport = $NCAM_default_settings{monitorport};
$monitorfilename = $NCAM_default_settings{monitorfile};


# Default to "no session config".
$session_p = undef;


# Default to "nothing wrong".
$errmsg = undef;


# Default to "we don't need anything".
$need_config_snapshots = 0;
$need_browser_update = 0;
$browser_update_force = 0;


# Zeroth pass: turn a completed "busy" page into a new target.
# We have to do this before the first pass because the busy page may now 
# include an action to be performed.
# Otherwise it's like the first pass: respond to command inputs from the busy
# page.

if ('busy' eq $caller)
{
  # See if we've been asked to cancel processing.
  if ('Cancel' eq $action)
  {
    # Send the "cancel" command, and give it a moment to take effect.
    NCAM_SendAnonSocket($hostip, $NCAM_port_mgrdaemon_query,
      "cancel processing");
    sleep(2);
  }

  # Doublecheck manager status; "cancel" may have changed this.
  $mgrstatus = NCAM_GetManagerStatus();

  # Generate either a "busy" page or the fall-through page.

  $busyfallthrough = $$params_p{fallthrough};

  # First argument pass: extract the arguments to forward.
  $busyargs_p = {};
  foreach $thisarg (keys %$params_p)
  {
    if ($thisarg =~ m/^arg(\S+)$/)
    { $$busyargs_p{$1} = $$params_p{$thisarg}; }
  }

  if ( ($mgrstatus =~ m/^busy/) )
  {
    $destpage = 'busy';
  }
  else
  {
    $destpage = $busyfallthrough;
    # Action defaults to 'none'.
    $action = 'none';


    # If we have arguments, copy them over.
    # This includes overwriting the commanded action.

    if (defined $$busyargs_p{command})
    { $action = $$busyargs_p{command}; }

    $had_args = 0;
    foreach $thisarg (keys %$busyargs_p)
    {
      $had_args = 1;
      # Stuff this back into the CGI params hash.
      # FIXME - This might break CGI object state?
      $$params_p{$thisarg} = $$busyargs_p{$thisarg};
    }

    # Squash the argument hash, now that we're done with it.
    $busyargs_p = {};


    # FIXME - Kludge the calling page to be the same as the target if we had
    # arguments.
    if ($had_args)
    { $caller = $destpage; }
  }
}



# First pass: take action based on where we came from and with what command.

if ('config' eq $caller)
{
  # Load the previously-saved session config.
  # This is in the CGI script's executing directory.
  # If we don't have one, force a detect/assign cycle.
  $session_p = LoadOrCreateSessionConfig($lastconfigfile);

  # The user might have altered controls on the config page.
  # Update our picture of what the session config is.
  NCAM_UpdateSessionFromCGI($session_p, $params_p);

  # Resave the session configuration state.
  NCAM_WriteSessionConfigFile($lastconfigfile, $session_p);


  # Process any commands the user issued.

  # By default, assume we want to stay on the configuration page.
  $destpage = 'config';

  if ('Start' eq $action)
  {
    # Prepare a repository and launch the daemon.

    # Force use of an auto-generated repository name.
    $$session_p{repodir} = NCAM_GetDefaultRepoFolder();

    # Dump a copy of the configuration hash to /tmp.
    # NOTE - We're _not_ saving this to our "last-used" file.
    NCAM_WriteSessionConfigFile($tempconfigfile, $session_p);

    # Invoke the daemon.

    # FIXME - The daemon just wants the _root_ repository directory.
    # The subfolder is read from the session configuration, which is why
    # we made sure it was actually recorded/valid, above.

    # NOTE - Invoke through the manager, not directly.
    # It'll pass the repository name as-given, so above still applies.

    NCAM_SendAnonSocket($hostip, $NCAM_port_mgrdaemon_query,
      'start cameras'
      . ' repository=' . $NCAM_cgi_repository_base
# FIXME - This is wrong (for now, we're passing subfolder via config).
#      . repository=' . $$session_p{repodir}
      . ' config=' . $tempconfigfile);

    # Daemon is running.

    # Give it a moment to start up.
    NCAM_SleepMillis(200);

    # FIXME - Not cleaning up the configuration file in /tmp!

    # We're switching to the monitoring page.
    $destpage = 'monitor';
  }
  elsif ('Switch to Repository Browser' eq $action)
  {
    # Switch to the repository management view.
    $destpage = 'browser';
  }
  elsif ('Refresh Preview' eq $action)
  {
    $need_config_snapshots = 1;
  }
  elsif ('Probe Devices' eq $action)
  {
    ($cameras_p, $netdevs_p) = ProbeDevices();

    # Prune any missing devices.
    $session_p =
      NCAM_ConfirmSessionDevices($session_p, $cameras_p, $netdevs_p);

    # Update slot assignments.
    NCAM_PopulateUnassignedSlots($session_p);

    # Resave the session configuration state.
    NCAM_WriteSessionConfigFile($lastconfigfile, $session_p);

    # Refresh preview.
    $need_config_snapshots = 1;
  }
  elsif ('Auto-Assign Slots' eq $action)
  {
    # This automatically clears any pre-existing assignments.
    NCAM_PopulateSlotsByDefault($session_p);
    # Resave the session configuration state.
    NCAM_WriteSessionConfigFile($lastconfigfile, $session_p);

    # Refresh preview.
    $need_config_snapshots = 1;
  }
  elsif ('Set Cameras' eq $action)
  {
    # Remember that "auto*" and "all*" are different.
    $autovidsize = $$params_p{allvidsize};
    $autovidrate = $$params_p{allvidrate};
    $autovidexp = $$params_p{allvidexp};

    if ( (defined $autovidsize) && (defined $autovidrate)
      && (defined $autovidexp) )
    {
      # Walk through the camera list, setting all cameras to the desired
      # resolution and frame rate (or reasonable approximation).

      SetAllCameras($session_p, $autovidsize, $autovidrate, $autovidexp);

      # Resave the session configuration state.
      NCAM_WriteSessionConfigFile($lastconfigfile, $session_p);
    }

    # Refresh preview.
    $need_config_snapshots = 1;
  }
  elsif ('Adjust Exposure' eq $action)
  {
    # Remember that "auto*" and "all*" are different.
    $autovidsize = $$params_p{autovidsize};
    $autovidrate = $$params_p{autovidrate};

    if ( (defined $autovidsize) && (defined $autovidrate) )
    {
      # Queue a camera adjustment session.
      NCAM_SendAnonSocket($hostip, $NCAM_port_mgrdaemon_query,
"autocamadjust config=$lastconfigfile size=$autovidsize rate=$autovidrate");
    }

    # Queue a preview after camera settings have been decided.
    $need_config_snapshots = 1;
  }
  elsif ('Restart Manager' eq $action)
  {
    # Try to shut everything down nicely, then shut it down not-nicely.
    StopNicelyThenKill();

    # Switch to the "busy" page, to force a reload of the config page.
    $destpage = 'busy';
    $busyfallthrough = 'config';
  }
  elsif ('Shut Down' eq $action)
  {
    $destpage = 'shutdown';
  }
  else
  {
    # No idea what this is.
    $errmsg = "Unknown command \"$action\".";
  }
}
elsif ('controlpane' eq $caller)
{
  # We're either rendering the control panel for the first time, generating
  # a marker, or shutting down the session.

  # By default, redraw.
  if ('none' eq $action)
  {
    $action = 'Refresh';
  }

  # Send any requested messages.

  if ('Annotate' eq $action)
  {
    NCAM_SendAnonSocket($commandhost, $commandport,
      'User annotation: "' . $$params_p{notetext} . "\"\n");
  }
  elsif ('End Session' eq $action)
  {
    # New way: Tell the manager to stop the camera daemon.
    NCAM_SendAnonSocket($hostip, $NCAM_port_mgrdaemon_query, 'stop cameras');

    # Give it a moment.
    NCAM_SleepMillis(200);
  }
  elsif ('Refresh' ne $action)
  {
    # Assume this is one of the marker buttons.
    NCAM_SendAnonSocket($commandhost, $commandport,
      'Marker: ' . $action . "\n");
  }


  # Set the target page.

  # By default, redraw the control pane.
  $destpage = 'controlpane';

  # If we've finished, use trickery to reload the entire page, not just the
  # frame.
  if ('End Session' eq $action)
  {
    $destpage = 'bouncebrowser';
  }
}
elsif ('controlfeed' eq $caller)
{
  # We're selecting a new video feed.

  # No matter what, we're going to redraw the control pane.
  $destpage = 'controlpane';

  # Translate the feed name to a folder name.
  $slotname = $feednamelut{$action};

  # Only change the feed if 1) the lookup succeeded and 2) the feed exists.
  # FIXME - We don't have the repository subfolder or session config here,
  # so we can't check for existence!
  # Let the manager and daemon deal with that.
  if (defined $slotname)
  {
    # Tell the manager to switch to the new feed.
    NCAM_SendAnonSocket($hostip, $NCAM_port_mgrdaemon_query, "feed $slotname");
  }
}
elsif ('videopane' eq $caller)
{
  # We're generating the video panel.
  # This is normally only called once, not refreshed.

  # FIXME - This is obsolete. First invocation should be with "destpage" set.
  $destpage = 'videopane';
}
elsif ('browser' eq $caller)
{
  # The user has clicked on a browser management button.

  # Extract parameters.
  # NOTE - Repository root might be on a USB drive.
  $repotop = $$params_p{repotop};
  if (!(defined $repotop))
  { $repotop = $NCAM_cgi_repository_base; }
  $repofolder = $$params_p{folder};


  # Set a default destination.
  # This includes a busy-wait fall-through.
  $destpage = 'browser';
  $busyfallthrough = 'browser';


  # Handle the requested action.

  if ($action =~ m/post/i)
  {
    # This is either a new post-process pass or a redo.

    # If it's a redo, delete the results of the previous attempt.
    # FIXME - This trashes any associated tarball as well.
    # With the new storage scheme (non-local tar only), that shouldn't matter.
    if ($action =~ m/redo/i)
    {
      NCAM_SendAnonSocket($hostip, $NCAM_port_mgrdaemon_query,
        "unprocess repository=$repotop/$repofolder");
    }


    # Check to see whether or not we should adjust timestamps.

    $use_ledsynch = 0;
    # The confirmation checkbox only shows up if checked.
    # It has the key "synchcheck" and the value "useledsynch".
    if (defined $$params_p{synchcheck})
    {
      $use_ledsynch = 1;
    }


    # Build any missing components.

    if ( $use_ledsynch
      && (!( -e "$repotop/$repofolder/logfile-timed.txt" )) )
    {
      # Align video timestamps.
      NCAM_SendAnonSocket($hostip, $NCAM_port_mgrdaemon_query,
        "timeshift repository=$repotop/$repofolder");
    }

    if (!( -e "$repotop/$repofolder/logfile-composited.txt" ))
    {
      # Build composite frames.
      NCAM_SendAnonSocket($hostip, $NCAM_port_mgrdaemon_query,
        "composite repository=$repotop/$repofolder");
    }


    # Check to see which slots have frames.
    @vidlist = ();
    foreach $slotname (@NCAM_session_slots)
    {
      # This fails gracefully if the directory isn't present.
      # NOTE - This may contain millions of files. Truncate.
      @vidframes = `ls $repotop/$repofolder/$slotname|head -5|grep jpg`;

      if ( (-d "$repotop/$repofolder/$slotname")
        && (0 < scalar(@vidframes)) )
      { push @vidlist, $slotname; }
    }

    # Monitor frames _should_ always exist.
    # Composited frames will exist after the previous command finishes.
    push @vidlist, 'Monitor';
    push @vidlist, 'Composite';

    # Assemble movies.
    foreach $slotname (@vidlist)
    {
      # Build this stream's video.
      NCAM_SendAnonSocket($hostip, $NCAM_port_mgrdaemon_query,
        "transcode repository=$repotop/$repofolder stream=$slotname"
        . " output=$repotop/$repofolder/$slotname");
    }


    # Synch disks.
    NCAM_SendAnonSocket($hostip, $NCAM_port_mgrdaemon_query,
      "disksynch");


    # Trigger an update.
    $need_browser_update = 1;
  }
  elsif ('Delete' eq $action)
  {
    # The confirmation checkbox only shows up if checked.
    # It has the key "deletecheck" and the value "reallydelete".
    if (defined $$params_p{deletecheck})
    {
      # FIXME - This deletes the specified .tar _and_ folder.
      # This means we can use it for any storage case.
      NCAM_SendAnonSocket($hostip, $NCAM_port_mgrdaemon_query,
        "delete repository=$repotop/$repofolder");
      # Synch disks.
      NCAM_SendAnonSocket($hostip, $NCAM_port_mgrdaemon_query,
        "disksynch");
    }
    else
    {
      $errmsg =
        "Please check confirmation box to really delete \"$repofolder\".";
    }
  }
  elsif ('Eject' eq $action)
  {
    # Synch disks and unmount this drive.
    NCAM_SendAnonSocket($hostip, $NCAM_port_mgrdaemon_query,
      "disksynch");
    $destpage = 'eject';
    $busyfallthrough = 'eject';
  }
  elsif ( $action =~ m/(Move|Copy) to (Local|USB)/ )
  {
    # FIXME - Hardwiring source and target repository root directories.
    my ($localbase, $usbbase);
    my ($localname, $usbname);
    my ($dest_local);

    $localbase = $NCAM_cgi_repository_base;

    $usbbase = NCAM_GetExternalMountpoint();
    if (!(defined $usbbase))
    {
      $errmsg = "USB drive is not mounted.";
    }
    else
    {
      $usbbase .= '/' . $NCAM_cgi_usb_repository_base;

      # Flag direction, to make life easier.
      $dest_local = 0;
      if ( $action =~ m/to Local/ )
      {
        $dest_local = 1;
      }

      # Set appropriate targets.
      # NOTE - Do _not_ add a .tar suffix or trailing / to any of these.
      $localname = "$localbase/$repofolder";
      $usbname = "$usbbase/$repofolder";

      # Sanity check and proceed.
      if (!(-d "$usbbase"))
      {
        # NOTE - This should be auto-created by NCAM_MountExternalDrive().
        $errmsg = "Can't find \"$usbbase\".";
      }
      elsif ( $dest_local && (!(-e "$usbname.tar")) )
      {
        $errmsg = "Can't find \"$usbname.tar\".";
      }
      elsif ( (!$dest_local) && (!(-d "$localname")) )
      {
        $errmsg = "Can't find \"$localname\".";
      }
      else
      {
        # Target is nuked and paved by the manager, if needed, so don't worry
        # about it.

        if ($dest_local)
        {
          # Unpack archive.
          # This unpacks _file_ "foo/bar.tar" to _directory_ "foo/bar/".
          # This nukes any previous target folder without our help.
          NCAM_SendAnonSocket($hostip, $NCAM_port_mgrdaemon_query,
            "unpack input=$usbname rootdir=$localname");
        }
        else
        {
          # Build archive.
          # This archives _directory_ "foo/bar/" to _file_ "foo/bar.tar".
          # This nukes any previous archive file without our help.
          NCAM_SendAnonSocket($hostip, $NCAM_port_mgrdaemon_query,
            "archive rootdir=$localname output=$usbname");
        }

        # Synch disks.
        NCAM_SendAnonSocket($hostip, $NCAM_port_mgrdaemon_query,
          "disksynch");


        # Force a metadata update.
        $need_browser_update = 1;


        # Queue the next part of this task.
        $busyfallthrough = 'browser';
# FIXME - Need to overhaul this.
#        $busyargs_p =
#          { 'command' => 'Copycheck', 'src' => $srcdir, 'dst' => $dstdir };
        $destpage = 'busy';
      }
    }
  }
  elsif ('Copycheck' eq $action)
  {
    my ($srcdir, $dstdir);

    # Retrieve source and destination arguments.
    $srcdir = $$params_p{src};
    $dstdir = $$params_p{dst};

    if (!( (defined $srcdir) && (defined $dstdir) ))
    {
      $errmsg = "Missing source and destination info for copy-check.";
    }
    else
    {
      # Check to make sure the copy was successful before nuking the
      # original!
      if (!(-d "$dstdir"))
      {
        $errmsg = "Copy failed; could not create \"$dstdir\".";
      }
      else
      {
        # Remove the original directory after copying.
        if ($NCAM_cgi_do_move_delete)
        {
          NCAM_SendAnonSocket($hostip, $NCAM_port_mgrdaemon_query,
            "delete repository=$srcdir");

          # Synch disks.
          NCAM_SendAnonSocket($hostip, $NCAM_port_mgrdaemon_query,
            "disksynch");

          $destpage = 'busy';
        }
      }
    }
  }
  elsif ('Recalc Sizes' eq $action)
  {
    # Force a metadata update.
    $need_browser_update = 1;
    $browser_update_force = 1;
  }
  elsif ('Restart Manager' eq $action)
  {
    # Try to shut everything down nicely, then shut it down not-nicely.
    StopNicelyThenKill();

    # Switch to the "busy" page, to force a reload of the browser page.
    $destpage = 'busy';
    $busyfallthrough = 'browser';
  }
  elsif ('Shut Down' eq $action)
  {
    # We should never reach here, as the relevant button specifies the
    # shutdown page as the target, but keep this for robustness.
    $destpage = 'shutdown';
  }
  else
  {
    # No idea what this is.
    $errmsg = "Unknown command \"$action\".";
  }


  # Doublecheck manager status, in case our operation involves waiting.
  # If we're busy, override the default destination.

  # Fallthrough should already be set (default or otherwise).

  $mgrstatus = NCAM_GetManagerStatus();

  if ($mgrstatus =~ m/^busy/)
  { $destpage = 'busy'; }
}
elsif ('bouncer' eq $caller)
{
  # We've gone through a frame exit or similar forwarding.
  # The destination specifier should tell us what to render.

  # FIXME - Nothing to do here. Destination is already set.
}
elsif ('none' ne $caller)
{
  # FIXME - This is ok!
  # Among other things it happens on startup.
}



# Post-processing: If we're switching to the config page, but aren't
# coming _from_ the config page or a wait page, we need new snapshots.
# FIXME - We do need new snapshots after auto-exposure!
# Kludge that by having the auto-exposure task queue a preview task.

if ( ('config' eq $destpage)
  && ('config' ne $caller) && ('busy' ne $caller) )
{
  $need_config_snapshots = 1;
}


# Post-processing: If we're displaying the browser page for any reason,
# check to see if metadata is stale.

if ('browser' eq $destpage)
{
  my ($mountpoint);

  # Check to see if the local drive metadata needs updating.
  if (NCAM_IsRepositoryMetadataStale($NCAM_cgi_repository_base))
  {
    $need_browser_update = 1;
  }

  # If we have a USB drive that wasn't mounted, mount it.
  if ( NCAM_IsExternalDrivePlugged() && (!NCAM_IsExternalDriveMounted()) )
  {
    NCAM_MountExternalDrive($NCAM_cgi_usb_repository_base);
  }

  # Check to see if the USB drive metadata needs updating, if we have one.
  $mountpoint = NCAM_GetExternalMountpoint();
  if (defined $mountpoint)
  {
    if ( NCAM_IsRepositoryMetadataStale($mountpoint . '/'
      . $NCAM_cgi_usb_repository_base) )
    {
      $need_browser_update = 1;
    }
  }
}


# Post-processing: If we need new snapshots, perform that task.
if ($need_config_snapshots)
{
  NCAM_SendAnonSocket($hostip, $NCAM_port_mgrdaemon_query,
    "snapshot config=$lastconfigfile outdir=$auxpathunix");

  # Give it a moment.
  NCAM_SleepMillis(200);

  # Alter destination to the busy-wait page.
  $destpage = 'busy';
  $busyfallthrough = 'config';

  # Refresh the manager status.
  $mgrstatus = NCAM_GetManagerStatus();
}


# Post-processing: If we need to refresh repository info, perform that task.
if ($need_browser_update)
{
  my ($mountpoint);

  NCAM_SendAnonSocket( $hostip, $NCAM_port_mgrdaemon_query,
    "metadata rootdir=$NCAM_cgi_repository_base"
    . ($browser_update_force ? ' force' : '') );

  $mountpoint = NCAM_GetExternalMountpoint();

  if (defined $mountpoint)
  {
    if (-d "$mountpoint/$NCAM_cgi_usb_repository_base")
    {
      NCAM_SendAnonSocket( $hostip, $NCAM_port_mgrdaemon_query,
        "metadata rootdir=$mountpoint/$NCAM_cgi_usb_repository_base"
        . ($browser_update_force ? ' force' : '') );
    }
  }

  # Give it a moment.
  NCAM_SleepMillis(200);

  # Alter destination to the busy-wait page.
  $destpage = 'busy';
  $busyfallthrough = 'browser';

  # Refresh the manager status.
  $mgrstatus = NCAM_GetManagerStatus();
}



# FIXME - Diagnostics.
print "<!-- (revised) caller: $caller   target: $destpage   action: $action -->\n";


# Second pass: Render our destination page.

if ('config' eq $destpage)
{
  # We're editing the configuration.

  # Load the previous version of the configuration, or create one from
  # whole cloth if we can't do that.
  $session_p = LoadOrCreateSessionConfig($lastconfigfile);

  # FIXME - Embed a copy of the session config as a comment.
  if (1)
  {
    print '<!--'."\n";
    $sessiontext_p = NCAM_SessionConfigToText($session_p);
    print @$sessiontext_p;
    print '-->'."\n";
  }

  # Generate the configuration page.
  # NOTE - "$errmsg" contains an error message, or undef.
  print NCAM_GenerateConfigPage($session_p, $auxpathunix, $auxpathweb, $errmsg);
}
elsif ('monitor' eq $destpage)
{
  # We're switching to the monitoring page.
  print NCAM_GenerateMonitorPage();
}
elsif ('controlpane' eq $destpage)
{
  # Redraw the control pane.
  print NCAM_GenerateControlPanePage();
}
elsif ('videopane' eq $destpage)
{
  # We're drawing the video pane.
  # This is normally only done once (not refreshed).

  # FIXME - Give the imagecast server time to start up!
  NCAM_SleepMillis(1000);

  # FIXME - Optionally force a geometry.
  if (1)
  {
    print NCAM_GenerateVideoPanePage($monitorhost,
      $monitorport, $monitorfilename,
      $$stitchinfo_monitor_p{fullsize});
  }
  else
  {
    print NCAM_GenerateVideoPanePage($monitorhost,
      $monitorport, $monitorfilename);
  }
}
elsif ('bouncebrowser' eq $destpage)
{
  # Bouncer pages are called from within a frame.
  # Our real target this time is the browser page.
  print NCAM_GenerateFrameExitPage(
    'callingpage=bouncer&destpage=browser');
}
elsif ('browser' eq $destpage)
{
  my ($mountpoint);

  # This returns undef if no drives are mounted.
  $mountpoint = NCAM_GetExternalMountpoint();

  if ( (defined $mountpoint) && ($mountpoint =~ m/^\s*\/(\S+)/) )
  {
    # NOTE - The web directory contains symlinks to the USB mountpoints.
    # Use these instead of the absolute paths, so that we can properly
    # serve files.

    # Strip the leading /. That might not be needed, since "/" in a URL
    # refers to the web root and the symlink is in the web root, but
    # strip it anyways.
    $mountpoint = $1;

    print NCAM_GenerateBrowser( [
      { 'name' => 'Local Drive', 'path' => $NCAM_cgi_repository_base },
      { 'name' => 'USB Drive',
        'path' => $mountpoint . '/' . $NCAM_cgi_usb_repository_base }
    ], $errmsg );
  }
  else
  {
    print NCAM_GenerateBrowser( [
      { 'name' => 'Local Drive', 'path' => $NCAM_cgi_repository_base },
    ], $errmsg );
  }
}
elsif ('busy' eq $destpage)
{
  # FIXME - Have the task default to something readable.
  $busytask = 'busy';
  $busyprogress = '';

  # The task name can have multiple words.
  # The progress string is always within parentheses if present.
  if ($mgrstatus =~ m/^busy\s+(.*\S)\s+(\(.*\))/)
  {
    $busytask = $1;
    # This includes parentheses.
    $busyprogress = $2;
  }
  elsif ($mgrstatus =~ m/^busy\s+(.*\S+)/)
  {
    $busytask = $1;
  }

  # Figure out if we want a cancel button.
  $busycancel = undef;
  if ( ($busytask eq 'synchronizing timestamps' )
    || ($busytask eq 'compositing' )
    || ($busytask eq 'transcoding' )
    || ($busytask eq 'archiving' ) )
  {
    # These are post-processing tasks, which are interruptible.
    $busycancel = 'cancel';
  }

  # Make task names more user-friendly.
  if ($busytask eq "synchronizing timestamps")
  { $busytask = "adjusting video timestamps"; }
  elsif ($busytask eq "compositing")
  { $busytask = "building composite frames"; }
  elsif ($busytask eq "transcoding")
  { $busytask = "assembling frames into movies"; }
  elsif ($busytask eq "archiving")
  { $busytask = "making downloadable package"; }
  elsif ($busytask eq "calculating sizes")
  {
    $busytask = "calculating disk space";

    # FIXME - Kludge progress string.
    if ($busyprogress =~ m/usb/)
    { $busyprogress = '(USB drive)'; }
    elsif ($busyprogress =~ m/\S/)
    { $busyprogress = '(local drive)'; }
  }
  elsif ($busytask eq "removing session folder")
  { $busytask = "deleting files"; }
  elsif ($busytask eq "copying session folder")
  { $busytask = "copying files"; }
  elsif ($busytask eq "synchronizing disks")
  { $busytask = "committing changes to disk"; }

  # The "busyargs_p" hash contains arguments to pass to the fallthrough page.
  # An empty argument hash is acceptable.
  # The "busycancel" flag is either 'cancel' or undef.
  print NCAM_GenerateBusyPage($busytask, $busyprogress, $busyfallthrough,
    $busyargs_p, $busycancel);
}
elsif ('eject' eq $destpage)
{
  # First, unmount the drive.
  # This _may_ cause a delay, but really shouldn't, as we've already
  # synchronized disks.
  NCAM_UnmountExternalDrive();

  # Wait for the user to unplug the drive.
  print NCAM_GenerateEjectPage();
}
elsif ('shutdown' eq $destpage)
{
  # First, tell the user what we're doing.
  print NCAM_GenerateShutdownPage();

  # Try to shut everything down nicely, then shut it down not-nicely.
  StopNicelyThenKill();

  # Queue the shutdown command.
  # We have to launch this as a daemon, because our shutdown page won't
  # render until the CGI script exits.
  NCAM_LaunchDaemon('./neurocam-shutdown.pl');
}
else
{
  print NCAM_GenerateMessagePage("Unknown destination page \"$destpage\".");
}


#
# This is the end of the file.
#
