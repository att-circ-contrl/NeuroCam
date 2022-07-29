#!/usr/bin/perl
#
# NeuroCam suite - Fake Unity machine.
# Written by Christopher Thomas.
#

#
# Includes
#

use strict;
use warnings;
use Time::HiRes;
use POSIX;
use Socket;

# Path fix needed for more recent Perl versions.
use lib ".";

require "neurocam-libmt.pl";
require "neurocam-libnetwork.pl";
require "neurocam-libmjpeg.pl";
require "neurocam-libdebug.pl";



#
# Public Constants
#

# FIXME - Doing this the messy way. Any imported variables need appropriate
# "our" declarations.

our ($NCAM_mjpeg_global_header);
our ($NCAM_port_game_base, $NCAM_port_game_query, $NCAM_port_game_stream);



#
# Private Constants
#

my ($screenfps, $imagefps);

# Screencast FPS is written as a floating-point value.
$screenfps = '30.0';

# Imagecast FPS is used as divisor; integer and floating point both work.
$imagefps = 30;



#
# Functions
#


# Displays a help screen.
# No arguments.
# No return value.

sub PrintHelp
{
  print << "Endofblock";

NeuroCam suite - Fake Unity machine.
Written by Christopher Thomas.

Usage:  fakeunity.pl (options)


Valid options:

--help   - Displays this help screen.

--screencast         - Broadcasts a stream with root window's contents.
--imagecast=<dir>    - Broadcasts a stream that loops all jpegs in <dir>.
--heartbeat          - Provide a heartbeat without a video stream.

--timeout=[##m][##s]  - Sends a "stop" command after the specified delay.
                        Delay is relative to program start, not connection.

--listenport=<value>   - Port that NeuroCam tries to contact to talk to us.

--streamname=<name>    - URL filename for the MJPEG output stream.
--streamport=<value>   - Port on which the MJPEG stream is offered.

--heartbeat-interval=<value>   - Milliseconds between successive heartbeats.

--debug              - Prints out network debugging information.


Valid UDP commands:

"looking for sources reply to port NNNN"
"talk to me on port NNNN"
"stop talking"
"shutdown"


UDP messages sent by this program:

"message source at HOST:PORT label XXXX"
"stream source at http://URL label XXXX"
"MSG Unity timestamp NNNNNN ms"
"CMD stop"

Endofblock
}



# Reads command-line arguments, returning an options/config hash.
# No arguments.
# Returns a pointer to the options hash, or undef on error.

sub ProcessArgs
{
  my ($options_p);
  my ($thisarg, $thiskey, $thisval);
  my ($is_ok);

  $is_ok = 1;

  # Build default values for options.
  $options_p =
  {
    'listenport' => $NCAM_port_game_query,
    'streamname' => 'stream.mjpg',
    # This should not be 8080; if the daemon is running on the same machine,
    # that's its monitor feed port.
    'streamport' => $NCAM_port_game_stream,
    'heartbeat-interval' => 1000
  };


  foreach $thisarg (@ARGV)
  {
    # First pass: parse the argument string.

    $thiskey = undef;
    $thisval = undef;

    if ($thisarg =~ m/--(\S+?)=(.*?)\s*$/)
    {
      $thiskey = $1;
      $thisval = $2;
    }
    elsif ($thisarg =~ m/--(\S+)/)
    {
      $thiskey = $1;
    }
    else
    {
      # NOTE - This may eventually be used for something.
      print "###  Unrecognized argument: \"$thisarg\".\n";
      $is_ok = 0;
    }


    # Second pass: Make sure the option specified is valid.

    if (defined $thiskey)
    {
      # Make sure we have appropriate key/value pairs.

      if ( ('help' eq $thiskey) || ('screencast' eq $thiskey)
        || ('heartbeat' eq $thiskey) || ('debug' eq $thiskey) )
      {
        # Catch-all for switch-type options.
        $thisval = '1';
      }
      elsif ( ('imagecast' eq $thiskey) || ('timeout' eq $thiskey)
        || ('listenport' eq $thiskey)
        || ('streamname' eq $thiskey) || ('streamport' eq $thiskey)
        || ('heartbeat-interval' eq $thiskey) )
      {
        # Catch-all for key/value options. Further validation later.
        if (!(defined $thisval))
        {
          $is_ok = 0;
          print "###  \"--$thiskey\" without value specified.\n";
        }
      }

      # Validation or further parsing of specific options.

      if (defined $thisval)
      {
        if ('timeout' eq $thiskey)
        {
          if ($thisval =~ m/(\d+)m(\d+)s/)
          {
            $thisval = (60 * $1) + $2;
          }
          elsif ($thisval =~ m/(\d+)m/)
          {
            $thisval = 60 * $1;
          }
          elsif ($thisval =~ m/(\d+)s/)
          {
            $thisval = $1;
          }
          else
          {
            print "###  Can't parse timeout \"$thisval\".\n";
            $is_ok = 0;
          }
        }
      }

      # We should now have a valid key and value.
      if ($is_ok)
      {
        $$options_p{$thiskey} = $thisval;
      }
    }
  }


  if (!$is_ok)
  {
    $options_p = undef;
    print "###  Use \"--help\" for help.\n";
  }

  return $options_p;
}



# Produces a human-readable dump of network debugging information.
# Arg 0 points to the network information hash.
# Returns a multi-line string.

sub FormatNetworkDebugInfo
{
  my ($netinfo_p, $result);
  my ($debug_p, $addrlist, $scratch);

  $netinfo_p = $_[0];
  $result = '';

  if (!(defined $netinfo_p))
  {
    print "### [FormatNetworkDebugInfo]  Bad arguments.\n";
  }
  else
  {
    $debug_p = $$netinfo_p{debug};

    # FIXME - Doing this the lazy way.
    $result = "== Networking information begins.\n\n"
      . NCAM_StructureToText($netinfo_p, '  ')
      . "\n== Networking information ends.\n";
  }

  return $result;
}



# Transmits a list of source streams offered.
# Arg 0 is the target IP address.
# Arg 1 is the target port.
# Arg 2 is 1 if a video stream exists, 0 otherwise.
# Arg 3 points to the options hash.
# No return value.

sub TransmitSourceList
{
  my ($target_addr, $target_port, $have_video, $options_p);
  my ($netinfo_p, $my_addr);
  my ($dest_packed);
  my ($msg);

  $target_addr = $_[0];
  $target_port = $_[1];
  $have_video = $_[2];
  $options_p = $_[3];

  if (!( (defined $target_addr) && (defined $target_port)
    && (defined $have_video) && (defined $options_p) ))
  {
    print "### [TransmitSourceList]  Bad arguments.\n";
  }
  else
  {
    # Get this machine's address.
    $netinfo_p = NCAM_GetNetworkInfo();
    $my_addr = $$netinfo_p{hostip};

    # Create a one-time socket for this.
    socket(LISTSOCK, PF_INET, SOCK_DGRAM, getprotobyname('udp'));
    # 0 means we don't care what port we're assigned (to transmit).
    bind(LISTSOCK, pack_sockaddr_in(0, INADDR_ANY));


    # Tell the client that we offer messages and maybe video.

    $dest_packed = pack_sockaddr_in($target_port, inet_aton($target_addr));

    if ($have_video)
    {
      $msg = 'stream source at http://' . $my_addr . ':'
        . $$options_p{streamport} . '/' . $$options_p{streamname}
      . ' label Unity';
      send(LISTSOCK, $msg, 0, $dest_packed);
# FIXME - Diagnostics.
print "-- Replied with:  $msg\n";
    }

    $msg = 'message source at ' . $my_addr . ':' . $$options_p{listenport}
      . ' label Unity';
    send(LISTSOCK, $msg, 0, $dest_packed);
# FIXME - Diagnostics.
print "-- Replied with:  $msg\n";


    # Close the socket.
    shutdown(LISTSOCK, SHUT_RDWR);
    close(LISTSOCK);
  }
}



# Forks a process that starts a screencast.
# Arg 0 points to the options hash.
# Returns a list of child PIDs.

sub ForkScreencast
{
  my ($options_p, $pid);

  $options_p = $_[0];
  $pid = undef;

  # Diagnostics - tell the user what we're doing.
  print '-- Streaming screencast: ' . $$options_p{streamport} . '/'
    . $$options_p{streamname} . "\n";

  # Spawn a new process. If we're the parent, return. If we're the child,
  # wait until killed.

print "Parent process: " . $$ . "\n";
  $pid = fork();
  # FIXME - Not checking for undef (error).

  if (0 == $pid)
  {
    NCAM_SetProcessName('fake-screencast');
print "Child process: " . $$ . "\n";
    # We're the child process. Call "cvlc" with appropriate arguments.

    # Force the list-type invocation so that we get the correct child ID.
    # NOTE - Do not quote arguments in list context. They aren't
    # shell-evaluated, and VLC does not like seeing the quotes.
    exec('cvlc', 'screen://', '--screen-fps=' . $screenfps,
      ':sout=#transcode{vcodec=MJPG,vb=1000,scale=0.5,acodec=none}'
        . ':http{mux=mpjpeg,dst=:' . $$options_p{streamport}
        . '/' . $$options_p{streamname} . '}',
      ':sout-keep'
    );

    # FIXME - We should never reach here, both because cvlc doesn't exit
    # and because exec() doesn't return.
    # We get warnings if the next statement isn't "die" or the like.
    die "### [ForkScreencast]  Returned from exec(). How did you do that?";
  }

  return ( $pid );
}



# Forks a process that starts an imagecast.
# Arg 0 is the directory to look for jpeg images in.
# Arg 1 points to the options hash.
# Returns a list of child PIDs.

sub ForkImagecast
{
  my ($imagedir, $options_p, @pidlist);
  my ($streamport, $streamname);
  my (@flist);
  my ($serverpid);
  my ($framehandle);
  my ($starttime, $nexttime, $thistime, $framecount);
  my ($jidx);

  my ($isok);
  my ($readok, $bytes_read, $stringdata, $thisdata);

  $imagedir = $_[0];
  $options_p = $_[1];
  @pidlist = ();

  $streamport = $$options_p{streamport};
  $streamname = $$options_p{streamname};

  @flist = `ls $imagedir/*.jpg $imagedir/*.jpeg 2>/dev/null`;

  for ($jidx = 0; defined $flist[$jidx]; $jidx++)
  { chomp($flist[$jidx]); }


  if (1 > scalar(@flist))
  {
    print "### [ForkImagecast]  No jpeg images found in \"$imagedir\".\n";
  }
  else
  {
    # Diagnostics - tell the user what we're doing.
    print "-- Streaming animation: $streamport/$streamname"
      . "   (from: $imagedir)\n";

print "Parent process: " . $$ . "\n";

    # Fork a server process to feed images to the real server process.

    $serverpid = fork();
    # FIXME - Not checking for undef (error).
    push @pidlist, $serverpid;

    if (0 == $serverpid)
    {
      NCAM_SetProcessName('fake-imagecast');
print "Child process: " . $$ . "\n";

      # Start a live imagecasting server.
      # Single-client and multi-client both work, but multi- sometimes
      # leaves zombie processes.
      $framehandle = NCAM_StartLiveImagecastSingle($streamport);
#      $framehandle = NCAM_StartLiveImagecastMulti($streamport);

      # FIXME - Trap TERM, so that we have time to do a graceful shutdown
      # of the client.
      # Do this _after_ forking the imagecast server, so that we don't end
      # up with a million child threads trying to do this too.
      $SIG{TERM} = sub { print $framehandle "shutdown\n"; };

      # Spin, sending frame updates when appropriate.
      # NOTE - The server threads read the frame files directly!
      # We're counting on the disk cache subsystem catching this.

      # Initialize housekeeping.
      $starttime = NCAM_GetRelTimeMillis();
      $framecount = 0;
      $jidx = 0;

      # Spin, transmitting frames with or without clients listening.
      while (1)
      {
        # Tell the manager we have a new frame.
        print $framehandle $flist[$jidx] . "\n";

        # Move on to the next file.
        $jidx++;
        if (!(defined $flist[$jidx]))
        { $jidx = 0; }


        # Spin until the next frame is due.
        # NOTE - Handle the overload case gracefully too.
        # First increment frame count until the next frame is in the future,
        # _then_ wait for the next frame.
        $thistime = NCAM_GetRelTimeMillis();
        do
        {
          $framecount++;
          $nexttime = $starttime + int(1000 * $framecount / $imagefps);
        }
        while ($nexttime <= $thistime);

        while (NCAM_GetRelTimeMillis() < $nexttime)
        {
          NCAM_Yield();
        }
      }

      # FIXME - We should never reach here.
      die "### [ForkImagecast]  Broke out of while (1). How?";
    }
  }


  # Done.
  return @pidlist;
}



#
# Main Program
#

my ($options_p);
my ($had_command);
my (@child_pids, @these_pids, $this_pid);
my ($have_stream);
my ($thistime, $endtime, $beattime);
my ($have_client, $client_src, $client_dest);
my ($filevec, $filecount);
my ($client_addr, $client_port, $msg);
my ($done);


$options_p = ProcessArgs();

# Tweak our starting port number to avoid collisions.
NCAM_SetNextListenPort($NCAM_port_game_base);

# Errors in parsing will have been reported by ProcessArgs().
if (defined $options_p)
{
  $had_command = 0;

  # Perform command setup actions.
  # Mostly this is launching video streaming child processes.

  @child_pids = ();
  $have_stream = 0;

  # Debug happens before, and does not preclude, other commands.
  if (defined $$options_p{debug})
  {
    $had_command = 1;

    print FormatNetworkDebugInfo(NCAM_GetNetworkInfo());
  }

  if (defined $$options_p{screencast})
  {
    $had_command = 1;

    @these_pids = ForkScreencast($options_p);
    push @child_pids, @these_pids;

    $have_stream = 1;
  }
  elsif (defined $$options_p{imagecast})
  {
    $had_command = 1;

    @these_pids = ForkImagecast($$options_p{imagecast}, $options_p);
    push @child_pids, @these_pids;

    $have_stream = 1;
  }
  elsif (defined $$options_p{heartbeat})
  {
    # No streaming, just heartbeat services.
    $had_command = 1;
  }


  # If we didn't have any other command, display a help screen.
  # Otherwise wait for a NeuroCam to ask for information and supply it.

  if (!$had_command)
  {
    PrintHelp();
  }
  else
  {
    # Initialize timestamps.

    $endtime = undef;
    $thistime = NCAM_GetRelTimeMillis();

    if (defined $$options_p{timeout})
    {
      $endtime = $thistime + 1000 * $$options_p{timeout};
    }

    $beattime = $thistime + $$options_p{'heartbeat-interval'};


    # Set up sockets.
    # We're listening for "looking for source" broadcasts, and we're
    # transmitting heartbeat and command packets.

    # FIXME - No error checking!

    # Listener socket.
    socket(LISTENER, PF_INET, SOCK_DGRAM, getprotobyname('udp'));
    bind(LISTENER, sockaddr_in($$options_p{listenport}, INADDR_ANY));
    # NOTE - listen() is only needed for TCP.

    # FIXME - Diagnostics.
    print "-- Listening on port " . $$options_p{listenport} . ".\n";

    # Broadcasting socket gets set up when we have a client.


    # Loop forever or until we have a timeout.

    # FIXME - Diagnostics.
    print "-- FakeUnity started at $thistime milliseconds.\n";

    $done = 0;
    $have_client = 0;

    while (!$done)
    {
      # Update timestamp.

      $thistime = NCAM_GetRelTimeMillis();

      if (defined $endtime)
      {
        if ($thistime >= $endtime)
        { $done = 1; }
      }


      # If we're talking to someone, send chatter.
      if ($have_client)
      {
        if ($thistime >= $beattime)
        {
          $msg = "MSG Unity timestamp $thistime ms";
          send(CLIENT, $msg, 0, $client_dest);

          # We shouldn't have to skip beats, but handle that case anyways.
          while ($thistime >= $beattime)
          { $beattime += $$options_p{'heartbeat-interval'}; }
        }
      }


      # If we've received traffic on the listener port, deal with it.

      # We need bit vectors for select(). At least the single-file case is
      # less ugly than the multi-file case.
      # It wants (readables), (writables), (exceptions), timeout.
      # We only care about reading, and timeout 0 lets us poll.

      $filevec = '';
      vec($filevec, fileno(LISTENER), 1) = 1;

      # This overwrites filevec to flag the handles that were active.
      # We don't care about that here.
      $filecount = select($filevec, undef, undef, 0);

      if (0 < $filecount)
      {
        # Args are handle, message scalar, max message bytes, flags.
        $client_src = recv(LISTENER, $msg, 65536, 0);

        # Unpack source information.
        ($client_port, $client_addr) = unpack_sockaddr_in($client_src);
        $client_addr = inet_ntoa($client_addr);

        # FIXME - Diagnostics.
        if (1)
        {
          print "-- Message from $client_addr:$client_port:\n";
          chomp($msg);
          print $msg . "\n";
        }


        # Parse commands.

        if ($msg =~ m/^looking for sources reply to port (\d+)/i)
        {
          TransmitSourceList($client_addr, $1, $have_stream, $options_p);
        }
        elsif ($msg =~ m/^talk to me on port (\d+)/i)
        {
          # If we have a client already, shut them down.
          if ($have_client)
          {
            shutdown(CLIENT, SHUT_RDWR);
            close(CLIENT);

            $have_client = 0;
          }

          # Create a new client handle.

          $have_client = 1;

          $client_dest = pack_sockaddr_in($1, inet_aton($client_addr));

          socket(CLIENT, PF_INET, SOCK_DGRAM, getprotobyname('udp'));
          # 0 means we don't care what port we're assigned (to transmit).
          bind(CLIENT, pack_sockaddr_in(0, INADDR_ANY));


          # Reset "last heartbeat" to the current time.
          $beattime = $thistime;
        }
        elsif ($msg =~ m/^stop talking/i)
        {
          # If we have a client, shut them down.
          if ($have_client)
          {
            shutdown(CLIENT, SHUT_RDWR);
            close(CLIENT);

            $have_client = 0;
          }
        }
        elsif ($msg =~ m/^shutdown/i)
        {
          # We've been told to shut everything down.
          $done = 1;
        }
        else
        {
          # No idea what this is. Complain about it.
          ($client_port, $client_addr) = unpack_sockaddr_in($client_src);
          $client_addr = inet_ntoa($client_addr);
          print "-- Bogus message from $client_addr.\n";
        }
      }

      NCAM_Yield();
    }

    # FIXME - Diagnostics.
    print "-- FakeUnity ended at $thistime milliseconds.\n";


    # If we have a client, tell them to end this session.
    if ($have_client)
    {
      $msg = "CMD stop";
      send(CLIENT, $msg, 0, $client_dest);
    }


    # Try to clean up sockets.
    # FIXME - No error checking!

    shutdown(LISTENER, SHUT_RDWR);
    close(LISTENER);

    if ($have_client)
    {
      shutdown(CLIENT, SHUT_RDWR);
      close(CLIENT);
    }
  }


  # Kill child processes if we have them.

  # Wait for a few seconds first!

  if (0 < scalar(@child_pids))
  {
    # FIXME - Diagnostics.
    print "-- Killing child PIDs: ";
    foreach $this_pid (@child_pids)
    { print ' ' . $this_pid; }
    print "\n";

    sleep(3);

    foreach $this_pid (@child_pids)
    { kill 'TERM', $this_pid; }

    sleep(3);

    foreach $this_pid (@child_pids)
    { kill 'KILL', $this_pid; }

    # FIXME - Diagnostics.
    print "--- Done.\n";
  }


  # Done.
}


#
# This is the end of the file.
#
