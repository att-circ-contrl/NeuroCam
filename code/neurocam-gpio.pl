#!/usr/bin/perl
#
# NeuroCam management script - GPIO monitoring script.
# Written by Christopher Thomas.
#
# This looks for USB serial ports (continually checking for new ones),
# probes to see if they contain GPIO devices, and listens to any GPIO
# devices, relaying messages to the camera daemon and start/stop signals
# to the manager as appropriate.
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
use IPC::Open2;

require "neurocam-libmt.pl";
require "neurocam-libnetwork.pl";



#
# Imported Constants
#

# FIXME - Doing this the messy way. Any imported variables need appropriate
# "our" declarations.

our ($NCAM_port_gpio_base);
our ($NCAM_port_camdaemon_command);
our ($NCAM_port_mgrdaemon_query);



#
# Constants
#

# Baud rates to probe, in order.
my (@probebauds);
@probebauds = ( 230400, 115200, 9600 );

# Bitmasks for "start recording" and "stop recording" control lines.
my ($cmdmask_start, $cmdmask_stop);
$cmdmask_start = 0x80;
$cmdmask_stop = 0x40;

# Dead time between successive commands, in milliseconds.
my ($cmddeadtime);
$cmddeadtime = 10000;


# Debugging flags.

# FIXME - Allow use of "picocom" instead of "cu".
# "cu" tries to use CTS/RTS, which the Nano's FTDI doesn't offer, I think.
# Whatever the reason, transmitting _to_ the Nano fails.
my ($use_alt_serial);
$use_alt_serial = 0;

# Show device detection handshaking.
my ($debug_device_detect);
$debug_device_detect = 0;

# Progress and data tattling flags.
my ($debug_tattle_banners);
my ($debug_tattle_data);
$debug_tattle_banners = 1;
$debug_tattle_data = 0;

# Main loop tattling.
my ($debug_tattle_messages);
$debug_tattle_messages = 0;



#
# Global Variables
#

# Networking information.
my ($netinfo_p, $hostip);
# Port the parent thread is listening on.
my ($parentport);



#
# Functions
#

# Attempts to connect to a tty device using the specified baud rate.
# Arg 0 is the device to connect to.
# Arg 1 is the baud rate to use.
# Returns (pid, readhandle, writehandle).

sub OpenSerialPort
{
  my ($device, $baud);
  my ($pid, $readhandle, $writehandle);
  local (*TEMPREAD, *TEMPWRITE);
  my ($lockname, $cmd, $response);

  $device = $_[0];
  $baud = $_[1];

  $pid = undef;
  $readhandle = undef;
  $writehandle = undef;

  if (!( (defined $device) && (defined $baud) ))
  {
    print STDERR "### [OpenSerialPort]  Bad arguments.\n";
  }
  else
  {
    # Remove stale lockfiles, if any.
    # FIXME - This is likely specific to this _version_ of Linux!
    # FIXME - This regex _should_ always match, and _should_ be safe if
    # it doesn't, but the failure case is still ugly.
    $lockname = $device;
    if ($lockname =~ m/(tty\S+)/)
    { $lockname = $1; }
    $cmd = 'rm -f /var/lock/*' . $lockname;
    $response = `$cmd`;


    # FIXME - Horrid kludge using open2() and "cu".
    # This may have latency and buffering issues!

    # Using the list-argument method to get the true PID (rather than
    # the PID of the shell instance parsing the arguments).

    # FIXME - "cu" does not play nicely with the FTDI driver for some reason.
    if ($use_alt_serial)
    {
      # The only workable alternative I've found on Mint is "picocom".
      # "screen (device) (baud)" works from a shell but not from here.
      if (1)
      {
        $pid = open2(*TEMPREAD, *TEMPWRITE,
          'picocom', '--baud', $baud, $device);
      }
      else
      {
        $pid = open2(*TEMPREAD, *TEMPWRITE, 'screen', $device, $baud);
      }
    }
    else
    {
      # Baseline: Use "cu".
      $pid = open2(*TEMPREAD, *TEMPWRITE, 'cu', '-l', $device, '-s', $baud);
    }

    # FIXME - I think open2() fails in worse ways than this.
    # Docs say it raises an exception instead of returning undef.
    if (!(defined $pid))
    {
      print STDERR "### [OpenSerialPort]  Unable to open serial port.\n";
    }
    else
    {
      $readhandle = *TEMPREAD;
      $writehandle = *TEMPWRITE;
    }
  }

  return ($pid, $readhandle, $writehandle);
}



# Waits for the specified length of time and then kills the specified process.
# This is intended as a failsafe for processes whose I/O hangs.
# Arg 0 is the pid to kill.
# Arg 1 is the absolute time at which to perform the kill.

sub ScheduleKillAbs
{
  my ($targetpid, $endtime);
  my ($childpid);

  $targetpid = $_[0];
  $endtime = $_[1];

  if ((defined $targetpid) && (defined $endtime))
  {
    $childpid = fork();

    if (0 == $childpid)
    {
      # We're the child.
      NCAM_SetProcessName('ncam-gpio-killer');

      while (NCAM_GetAbsTimeMillis() < $endtime)
      {
        # Yield.
        NCAM_Yield();
      }

      kill 'TERM', $targetpid;

      NCAM_SleepMillis(200);

      kill 'KILL', $targetpid;

      # End the thread gracefully.
      exit(0);
    }

    # The parent returns immediately.
  }
}



# Returns a version of a string that translates nonprintable characters
# into "<xx>" strings.
# Arg 0 is the string to convert.
# Returns the converted string.

sub MakePrintableString
{
  my ($orig, $result);
  my (@charlist, $thischar);

  $orig = $_[0];
  $result = '';

  if (defined $orig)
  {
    @charlist = split(//, $orig);

    foreach $thischar (@charlist)
    {
      if ((' ' le $thischar) && ('~' ge $thischar))
      { $result .= $thischar; }
      else
      { $result .= sprintf('<%02x>', ord($thischar)); }
    }
  }

  return $result;
}



# Monitors a GPIO device, sending messages to the camera and management
# daemons.
# Arg 0 is the read handle.
# Arg 1 is the write handle.
# Arg 2 is the label to give this device when reporting.
# Arg 3 is the full device identity string.
# No return value.

sub MonitorGPIODevice
{
  my ($readhandle, $writehandle, $labelstring, $idstring);
  my ($devtype, $subtype, $devtask);
  my ($initstring, $startmask, $stopmask);
  my ($sockhandle);
  my ($thisline, $regid, $dataval);
  my ($want_start, $want_stop, $prev_start, $prev_stop);
  my ($thistime, $nextcmdtime);

  $readhandle = $_[0];
  $writehandle = $_[1];
  $labelstring = $_[2];
  $idstring = $_[3];

  if (!( (defined $readhandle) && (defined $writehandle)
    && (defined $labelstring) && (defined $idstring) ))
  {
    print STDERR "### [MonitorGPIODevice]  Bad arguments.\n";
  }
  else
  {
    # Try to get a bit more information out of the ID string.

    $devtype = undef;
    $subtype = undef;
    $devtask = undef;

    if ($idstring =~
      m/devicetype\s*:\s*(\S+)\s+subtype\s*:\s*(\S+)\s+task\s*:\s*(.*\S)/)
    {
      $devtype = $1;
      $subtype = $2;
      $devtask = $3;
    }
    elsif ($idstring =~ m/devicetype\s*:\s*(\S+)\s+subtype\s*:\s*(\S+)/)
    {
      $devtype = $1;
      $subtype = $2;
    }
    elsif ($idstring =~ m/devicetype\s*:\s*(\S+)/)
    {
      # We _should_ always have this, if this function was called at all.
      $devtype = $1;
    }


    # Figure out how to initialize and talk to this device, based on what
    # we know about it.

    $initstring = '';
    $startmask = 0x00;
    $stopmask = 0x00;

    if ( (defined $devtype) && ('GPIOv1' eq $devtype) )
    {
      # This is a v1 GPIO device. Initialize it.
      $initstring .= "INI\nECH 0\n";

      # Check for known subtypes.
      if ( (defined $subtype) && ('neurocam' eq $subtype) )
      {
        # This device is configured for use with the NeuroCam system.

        # Note that we'll accept start/stop commands from this device.
        $startmask = $cmdmask_start;
        $stopmask = $cmdmask_stop;

        # Enable pull-ups.
        $initstring .= "PPU 1\n";


        # Check for known tasks.
        if ( (defined $devtask) && ('light strobe' eq $devtask) )
        {
          # Add task initialization.
          $initstring .= "TPP 10000\nTPD 20\nTSK 1\n";
        }
      }

      # Reporting comes last.
      $initstring .= "REP 1\n";
    }
    else
    {
      # This isn't a known type of GPIO device.
    }

    # FIXME - Diagnostics.
    if ($debug_tattle_banners)
    {
      print STDERR '-- Montioring device with type "'
        . (defined $devtype ? $devtype : '(undef)')
        . '", subtype "'
        . (defined $subtype ? $subtype : '(undef)')
        . '", task "'
        . (defined $devtask ? $devtask : '(undef)')
        . "\".\n";
    }


    # Create a reporting socket.
    $sockhandle = NCAM_GetTransmitSocket();


    # Initialize command processing.
    # Doing this early so that sample timestamps are after the dead time.
    $prev_start = undef;
    $prev_stop = undef;
    $nextcmdtime = NCAM_GetAbsTimeMillis();


    # Wait a moment for the device to stabilize.
    NCAM_SleepMillis(200);


    # Send the initialization string.
    print $writehandle $initstring;


    # Spin, listening to the device.
    # NOTE - Sometimes this terminates non-gracefully. Check for undef.
    while (1)
    {
      $thisline = 1;

      while ( (defined $thisline) && NCAM_HandleCanRead($readhandle) )
      {
        # NOTE - Disconnect can sometimes make this undefined.
        $thisline = <$readhandle>;

        if (defined $thisline)
        {
          # FIXME - Diagnostics.
          if ($debug_tattle_data)
          {
            print STDERR $thisline;
          }

          # FIXME - Assume that everything talks like a GPIOv1.
          if ($thisline =~ m/^\s*([A-Z])\s*:\s*([0-9a-fA-F]+)\s*$/)
          {
            # This is a register update.
            $regid = $1;
            $dataval = $2;

            # No matter what, report this as a message packet.
            # This may contain changed non-command pins.
            # Bounce this through the parent thread.
            NCAM_SendSocket($sockhandle, $hostip, $parentport,
              "MSG gpio $labelstring $regid: $dataval");


            # Check to see if this is a start or stop command.

            if ('I' eq $regid)
            {
              $want_start = 0;
              $want_stop = 0;

              if (hex($dataval) & $startmask)
              { $want_start = 1; }
              if (hex($dataval) & $stopmask)
              { $want_stop = 1; }

              # Make sure that our first sample does not count as an edge.
              if (!(defined $prev_start))
              { $prev_start = $want_start; }
              if (!(defined $prev_stop))
              { $prev_stop = $want_stop; }


              # We trigger on rising edges, with dead time after any command.

              $thistime = NCAM_GetAbsTimeMillis();

              if ( (!$prev_start) && $want_start
                && ($thistime >= $nextcmdtime) )
              {
                $nextcmdtime = $thistime + $cmddeadtime;

                # Tell the manager to start a capture session.
                # FIXME - Sending this directly, not through the parent!
                NCAM_SendSocket($sockhandle, $hostip,
                  $NCAM_port_mgrdaemon_query,
                  "start cameras repository=auto config=auto");
              }

              if ( (!$prev_stop) && $want_stop
                && ($thistime >= $nextcmdtime) )
              {
                $nextcmdtime = $thistime + $cmddeadtime;

                # Tell the manager to stop capturing.
                # FIXME - Sending this directly, not through the parent!
                NCAM_SendSocket($sockhandle, $hostip,
                  $NCAM_port_mgrdaemon_query,
                  "stop cameras");
              }

              # Update our edge detection.
              $prev_start = $want_start;
              $prev_stop = $want_stop;
            }

            # Finished processing this register update.
          }
        }
      }

      # Yield.
      NCAM_Yield();
    }


    # Finished monitoring this device.
  }
}



# Probes a USB serial port, checking to see if it has a device we want to
# talk to. If so, a handler thread is spun off.
# Arg 0 is the device filename.
# Returns (childpid, ttypid, baud, id string) on success, or undef on error.

sub ProbePort
{
  my ($devname, $childpid, $ttypid, $foundbaud, $idstring);
  my ($readhandle, $writehandle);
  my ($bidx, $thisbaud, $found);
  my ($endtime, $response, $bytesread, $thesebytes);
  my ($devtype);
  my ($label);

  $devname = $_[0];

  $childpid = undef;
  $ttypid = undef;
  $foundbaud = undef;
  $idstring = undef;

  $devtype = undef;

  if (!(defined $devname))
  {
    print STDERR "### [ProbePort]  Bad arguments.\n";
  }
  else
  {
    # FIXME - Diagnostics.
    if ($debug_device_detect)
    {
      print "-- Probing \"$devname\".\n";
    }

    # Try probing at various baud rates.
    $found = 0;
    for ($bidx = 0;
      (!$found) && (defined ($thisbaud = $probebauds[$bidx]));
      $bidx++)
    {
      ($ttypid, $readhandle, $writehandle) =
        OpenSerialPort($devname, $thisbaud);

      if (defined $ttypid)
      {
        # Give the connection a moment to stabilize.
        NCAM_SleepMillis(200);

        # Set up a time-delayed kill, in case I/O hangs.
        # That's normal when connecting at the wrong speed.
        # NOTE - The kill should be _earlier_ than our loop exit, so that
        # we don't initiate a second trial while the first is still running.
        ScheduleKillAbs($ttypid, NCAM_GetAbsTimeMillis() + 1000);

        # Try to query the device type.
        # Give it a second to respond before giving up.

        print $writehandle "IDQ\n";

        # If we connect at the wrong speed, we'll get gibberish, not
        # cleanly terminated lines of text.
        # Just glom all bytes read for one second and analyze it afterwards.

        # NOTE - Our loop exit should be _later_ than the kill, so that
        # we don't initiate a second trial while the first is still running.
        $response = '';
        $endtime = NCAM_GetAbsTimeMillis() + 1500;

        while (NCAM_GetAbsTimeMillis() < $endtime)
        {
          if (NCAM_HandleCanRead($readhandle))
          {
            $thesebytes = '';
            $bytesread = sysread($readhandle, $thesebytes, 1);

            if ((defined $bytesread) && (0 < $bytesread))
            { $response .= $thesebytes; }
          }
        }

        if ($response =~ m/.*^\s*(.*?devicetype\s*:.*?\S)\s*$/ms)
        {
          # We found something that responds to inquiries.
          # Extract that response string for downstream processing.
          $found = 1;
          $response = $1;

          # Extract the device type. This _should_ always match.
          if ($response =~ m/devicetype\s*:\s*(\S+)/)
          { $devtype = $1; }
          else
          { $devtype = 'unknown'; }
        }
        elsif ($debug_device_detect)
        {
          # FIXME - Diagnostics.
          print "-- Failed to connect at $thisbaud baud. Response:\n";
          print MakePrintableString($response) . "\n";
        }

        # No matter what, the probe thread should be dead by now.

        # Close both filehandles, ignoring errors.
        close($readhandle);
        close($writehandle);

        undef $ttypid;
        undef $readhandle;
        undef $writehandle;
      }
    }


    # If we found a device that we can talk to, spin off a handler
    # thread.

    if (!$found)
    {
      # FIXME - Diagnostics.
      if ($debug_device_detect)
      {
        print "-- No device found.\n";
      }
    }
    else
    {
      # Make a label for this device based on the tty name.

      $label = $devname;

      if ($devname =~ m/ttyACM(\d+)/)
      { $label = 'A' . $1; }
      elsif ($devname =~ m/ttyUSB(\d+)/)
      { $label = 'U' . $1; }
      elsif ($devname =~ m/tty\.?(.*)usbmodem(.*)/)
      { $label = 'M' . $1 . $2; }


      # FIXME - Diagnostics.
      if ($debug_device_detect)
      {
        print "-- Found \"$devtype\" on $devname at $thisbaud baud.\n";
        print "-- Response:  \"$response\"\n";
        print "-- Using label \"$label\".\n";
      }

      # Only spin off a child if this is a device type we understand.
      if ('GPIOv1' eq $devtype)
      {
        $foundbaud = $thisbaud;
        $idstring = $response;

        # Give it a moment, then spin off a child with its own connection.
        NCAM_SleepMillis(500);

        ($ttypid, $readhandle, $writehandle) =
          OpenSerialPort($devname, $foundbaud);

        $childpid = fork();

        if (0 == $childpid)
        {
          # We're the child.
          NCAM_SetProcessName('ncam-gpio-monitor');
          MonitorGPIODevice($readhandle, $writehandle, $label, $idstring);

          # Exit gracefully. We shouldn't actually reach here.
          exit(0);
        }

        # We're the parent. Close our copies of the file handles.
        close($readhandle);
        close($writehandle);

        # Finished spinning off the child.
      }
      else
      {
        # FIXME - Diagnostics.
        # This is an unexpected error, so don't filter it.
        print STDERR "-- Not sure how to handle a \"$devtype\" device.\n";
      }
    }


    # Finished probing this port.
  }

  return ($childpid, $ttypid, $foundbaud, $idstring);
}



# Spins until killed, updating the list of serial ports and probing new ports.
# NOTE - This creates sockets (for itself and for child threads).
# This spawns child threads and reports them to the master.
# No arguments.
# No return value (does not return).

sub DoSerialProbeLoop
{
  my (@rawlist, $thisport);
  my (%oldlut, %newlut, $entry_p);
  my ($childpid, $ttypid, $foundbaud, $idstring);
  my ($reportsock);

  $reportsock = NCAM_GetTransmitSocket();

  %oldlut = ();

  # Wait a moment, so that the parent's monitoring loop can start.
  sleep(1);

  # Spin until killed.
  while (1)
  {
    # Get a list of currently-existing ports.
    %newlut = ();
    @rawlist = `ls /dev/ttyACM* /dev/ttyUSB* /dev/tty*usbmodem* 2>/dev/null`;

    foreach $thisport (@rawlist)
    {
      if ($thisport =~ m/^\s*(\/dev\/tty.*\S)/)
      {
        $thisport = $1;
        $newlut{$thisport} = 1;
      }
    }

    # If we have old ports that are no longer listed, remove them.
    foreach $thisport (keys %oldlut)
    {
      if (!(defined $newlut{$thisport}))
      {
        $entry_p = $oldlut{$thisport};

        # If we actually created a child for this, reap child threads.
        if ('HASH' eq ref($entry_p))
        {
          $childpid = $$entry_p{childpid};
          $ttypid = $$entry_p{ttypid};

          kill 'TERM', $childpid;
          kill 'TERM', $ttypid;

          NCAM_SleepMillis(500);

          kill 'KILL', $childpid;
          kill 'KILL', $ttypid;

          # Notify the parent that we've reaped child threads.
          NCAM_SendSocket($reportsock, $hostip, $parentport,
            "reaped child " . $childpid);
          NCAM_SendSocket($reportsock, $hostip, $parentport,
            "reaped child " . $ttypid);

          if ($debug_tattle_banners)
          {
            print STDERR "-- Lost contact with $thisport.\n";
          }
        }

        # Delete this record.
        delete $oldlut{$thisport};
      }
    }

    # If we have new ports that haven't been probed, probe them.
    # This will fork handlers for them if anything we can talk to is detected.
    foreach $thisport (keys %newlut)
    {
      if (!(defined $oldlut{$thisport}))
      {
        # FIXME - This will dup copies of our socket!
        ($childpid, $ttypid, $foundbaud, $idstring) = ProbePort($thisport);

        # One way or another, we've handled this port.
        if (defined $childpid)
        {
          $oldlut{$thisport} =
          {
            'childpid' => $childpid,
            'ttypid' => $ttypid,
            'baud' => $foundbaud,
            'idstring' => $idstring
          };

          # Notify the parent that we've created children.
          NCAM_SendSocket($reportsock, $hostip, $parentport,
            "created child " . $childpid);
          NCAM_SendSocket($reportsock, $hostip, $parentport,
            "created child " . $ttypid);

          if ($debug_tattle_banners)
          {
            print STDERR "-- Added device on $thisport.\n";
          }
        }
        else
        {
          # Mark this port as probed but not in use.
          $oldlut{$thisport} = 'not detected';
        }

        # Done.
      }
    }

    # Sleep, so that we don't hammer "ls".
    sleep(5);
  }

  # FIXME - We should never reach here.
  die "### [DoSerialProbeLoop]  while (1) exited. How?";
}



#
# Main Program
#

my ($listensock, $sendsock);
my (%childlist, $childpid);
my ($finished);
my (%clienthosts, $clientports_p, $thishost, $thisport);
my ($has_message, $sender, $message);


# Initialize networking.

NCAM_SetNextListenPort($NCAM_port_gpio_base);

$netinfo_p = NCAM_GetNetworkInfo();
$hostip = $$netinfo_p{hostip};
$parentport = NCAM_GetNextListenPort();

$listensock = NCAM_GetListenSocket($parentport);
$sendsock = NCAM_GetTransmitSocket();


# FIXME - Diagnostics.
if ($debug_tattle_banners)
{
  print STDERR "== Serial peripheral monitor listening on port $parentport.\n";
}


# Fork the serial probing process.

%childlist = ();

$childpid = fork();

if (0 == $childpid)
{
  # We're the child.
  NCAM_SetProcessName('ncam-gpio-prober');

  # Close duplicate filehandles.
  close($listensock);
  close($sendsock);

  # Probe forever.
  DoSerialProbeLoop();

  # We should never reach here!
  die "### Serial-probing function returned (it isn't supposed to do that!).";
}

$childlist{$childpid} = 1;


# Run the message loop.
# This responds to outside queries, serial device reports, and notifications
# of new serial device threads.

%clienthosts = ();

$finished = 0;

while (!$finished)
{
  # Check for new messages.
  ($has_message, $sender, $message) = NCAM_CheckReceiveSocket($listensock);

  if ($has_message)
  {
    if ($debug_tattle_messages)
    {
      print STDERR '-- Message "' . $message . "\".\n";
    }

    # This is either someone giving us orders, a broadcast query, a child
    # creation report, or a message to relay.
    if ($message =~ m/^looking for sources reply to port (\d+)/i)
    {
      $thishost = $sender;
      $thisport = $1;

      # Fixed response; we're treated as one source no matter how many
      # peripherals we've detected.
      # FIXME - We may want to change our label if we add more types of
      # peripheral.
      $message = 'message source at ' . $hostip . ':' . $parentport
        . ' label GPIO';

      NCAM_SendSocket($sendsock, $thishost, $thisport, $message);
    }
    elsif ($message =~ m/^talk to me on port (\d+)/i)
    {
      # Add this IP and port to the client list.

      $thishost = $sender;
      $thisport = $1;

      $clientports_p = $clienthosts{$thishost};
      if (!(defined $clientports_p))
      {
        $clientports_p = {};
        $clienthosts{$thishost} = $clientports_p;
      }

      $$clientports_p{$thisport} = 1;

      if ($debug_tattle_banners)
      {
        print "-- Added client at $thishost:$thisport.\n";
      }
    }
    elsif ($message =~ m/^stop talking/i)
    {
      # Remove this IP and port from the client list.
      # FIXME - We can't distinguish multiple ports from the same host!
      # Shut them all down.

      $thishost = $sender;

      if (defined $clienthosts{$thishost})
      {
        delete $clienthosts{$thishost};
      }

      if ($debug_tattle_banners)
      {
        print "-- Removed all clients at $thishost.\n";
      }
    }
    elsif ($message =~ m/^shutdown/i)
    {
      # We've been told to shut down.
      $finished = 1;
    }
    elsif ($message =~ m/^created child (\d+)/)
    {
      # Add this child to the list.
      $childlist{$1} = 1;
    }
    elsif ($message =~ m/^reaped child (\d+)/)
    {
      # Strike this child from the list.
      if (defined $childlist{$1})
      {
        delete $childlist{$1};
      }
    }
    else
    {
      # This is a message. Relay it to all clients.

      foreach $thishost (keys %clienthosts)
      {
        $clientports_p = $clienthosts{$thishost};

        foreach $thisport (keys %$clientports_p)
        {
          NCAM_SendSocket($sendsock, $thishost, $thisport, $message);
        }
      }
    }
  }

  # Yield, to avoid hogging CPU during busy-waiting.
  NCAM_Yield();
}


# FIXME - Diagnostics.
if ($debug_tattle_banners)
{
  print STDERR "== Shutting down.\n";
}


# We've been told to shut down.
# Walk through the child port list and kill threads.
# Do this oldest to newest, to kill the process that _creates_ threads first.

foreach $childpid (sort {$a <=> $b} keys %childlist)
{
  kill 'TERM', $childpid;
}

sleep (1);

foreach $childpid (sort {$a <=> $b} keys %childlist)
{
  kill 'KILL', $childpid;
}


# Get rid of our sockets.

NCAM_CloseSocket($listensock);
NCAM_CloseSocket($sendsock);


# Done.


#
# This is the end of the file.
#
