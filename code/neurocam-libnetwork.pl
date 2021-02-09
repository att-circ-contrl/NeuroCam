#!/usr/bin/perl
#
# NeuroCam management script - Networking library.
# Written by Christopher Thomas.
#
# This project is Copyright (c) 2021 by Vanderbilt University, and is released
# under the Creative Commons Attribution-ShareAlike 4.0 International License.

#
# Includes
#

use strict;
use warnings;



#
# Public Constants
#

# FIXME - Doing this the messy way. Anywhere that uses this needs to have
# a corresponding "our" declaration.

# Base port numbers and special/default port numbers used for various
# purposes. These should have enough padding to not overlap.

our ($NCAM_port_default_base);
our ($NCAM_port_camdaemon_base, $NCAM_port_camdaemon_command);
our ($NCAM_port_camdaemon_monitorframe, $NCAM_port_camdaemon_monitorstream);
our ($NCAM_port_mgrdaemon_base, $NCAM_port_mgrdaemon_query);
our ($NCAM_port_game_base, $NCAM_port_game_query, $NCAM_port_game_stream);
our ($NCAM_port_cgi_base);
our ($NCAM_port_mjpeglib_base);
our ($NCAM_port_gpio_base);

# Default base.
$NCAM_port_default_base = 7000;

# Camera daemon ranges.
$NCAM_port_camdaemon_base = 9000;
$NCAM_port_camdaemon_command = 9999;
$NCAM_port_camdaemon_monitorframe = 9998;
$NCAM_port_camdaemon_monitorstream = 8090;

# Management daemon ranges.
$NCAM_port_mgrdaemon_base = 10000;
$NCAM_port_mgrdaemon_query = 10999;

# Game ranges.
# The query port is important for all external streams/talkers.
# The other ranges are only used by FakeUnity.
$NCAM_port_game_base = 11000;
$NCAM_port_game_query = 8888;
$NCAM_port_game_stream = 8080;

# CGI ranges.
# These are mostly used for reply-to ports when performing queries.
$NCAM_port_cgi_base = 12000;

# MJPEG library ranges.
# Ports are allocated for internal communication with the multi-client
# server.
# FIXME - Multiple instances of this library will overlap ranges!
$NCAM_port_mjpeglib_base = 13000;

# GPIO daemon ranges.
$NCAM_port_gpio_base = 14000;


#
# Private Variables
#

# Next available port to assign to people.
my ($next_listen_port);
# Initialize this to a reasonable default.
$next_listen_port = $NCAM_port_default_base;

# Ports that we or another part of the system are using. Not to be allocated.
my (%reserved_ports);

# Various local network information. Initialized on the first query.
my ($local_network_info_p);



#
# Public Functions
#


# Returns absolute wall-clock time in milliseconds.
# This is relative to midnight on 1 January 1970.
# No arguments.
# Returns an integer timestamp.

sub NCAM_GetAbsTimeMillis
{
  my ($seconds, $micros, $millis);

  ($seconds, $micros) = Time::HiRes::gettimeofday();

  # These are probably already integers, but bulletproof anyways.
  $millis = int($micros / 1000) + int($seconds) * 1000;

  return $millis;
}


# Returns relative wall-clock time in milliseconds.
# This is wall-clock time since the first call to GetRelTimeMillis().
# No arguments.
# Returns an integer timestamp.

# FIXME - Static variables the hard way.
{
my ($firstmillis);

sub NCAM_GetRelTimeMillis
{
  my ($millis);

  $millis = NCAM_GetAbsTimeMillis();

  if (!(defined $firstmillis))
  {
    $firstmillis = $millis;
  }

  return $millis - $firstmillis;
}

# End of static variable block.
}



# Sleeps for the specified number of milliseconds.
# Sleeping for 0 milliseconds causes a thread yield.
# Arg 0 is the number of milliseconds to sleep for.
# No return value.

sub NCAM_SleepMillis
{
  my ($millis);

  $millis = $_[0];
  Time::HiRes::usleep(1000 * int($millis));
}



# Resets the next listen-port value to the specific port number.
# This is useful for avoiding port-range collisions between different programs
# or processes within a program.
# Arg 0 is the port number to set it to.
# No return value.

sub NCAM_SetNextListenPort
{
  my ($port);

  $port = $_[0];

  if (defined $port)
  {
    $next_listen_port = $port;
  }
}



# Returns the next available listening port.
# No arguments.
# Returns a port ID.

sub NCAM_GetNextListenPort
{
  my ($port);

  while (defined $reserved_ports{$next_listen_port})
  {
    $next_listen_port++;
  }

  # This port isn't in the reserved list, so return it.
  $port = $next_listen_port;
  $next_listen_port++;

  # Flag the returned port as in-use.
  $reserved_ports{$port} = 1;

  return $port;
}



# Flags a port as being in use.
# This lets our auto-allocation avoid manually-allocated port numbers.
# Arg 0 is the port number to reserve.
# No return value.

sub NCAM_FlagPortAsUsed
{
  my ($port);

  $port = $_[0];

  if (defined $port)
  {
    $reserved_ports{$port} = 1;
  }
}



# This returns both ends of an anonymous pipe for inter-process
# communication. auto-flush is enabled for both ends.
# FIXME - This still seems to use line-based buffering.
# No arguments.
# Returns (reader, writer).

sub NCAM_GetNewPipe
{
  my ($reader, $writer);
  local (*TEMPREAD, *TEMPWRITE);

  # FIXME - No error checking.
  pipe(TEMPREAD, TEMPWRITE);

  # Make both of these auto-flush.
  # Do this the longer but slightly less cryptic way.
  {
    # This saves the old default handle, selects the desired pipe as default,
    # sets that to autoflush, and then sets the old handle as default again.
    my ($oldhandle);

    $oldhandle = select(TEMPWRITE);
    $| = 1;
    select(TEMPREAD);
    $| = 1;
    select($oldhandle);
  }

  # Put these into scalars so that they're easier to deal with.
  $reader = *TEMPREAD;
  $writer = *TEMPWRITE;

  return($reader, $writer);
}



# Attempts to create a listening UDP socket handle. This starts listening
# immediately.
# Arg 0 is the port to listen to.
# Returns a filehandle, or undef on error.

sub NCAM_GetListenSocket
{
  my ($port, $result);
  local (*TEMPHANDLE);

  $port = $_[0];
  $result = undef;

  if (defined $port)
  {
    # FIXME - No error checking!
    socket(TEMPHANDLE, PF_INET, SOCK_DGRAM, getprotobyname('udp'));
    bind(TEMPHANDLE, sockaddr_in($port, INADDR_ANY));
    # NOTE - listen() is only needed for TCP.

    # FIXME - Blithely assume this succeeded.
    $result = *TEMPHANDLE;
  }

  return $result;
}



# Attempts to create a transmitting UDP socket handle.
# No arguments.
# Returns a filehandle, or undef on error.

sub NCAM_GetTransmitSocket
{
  my ($result);
  local (*TEMPHANDLE);

  $result = undef;

  # FIXME - No error checking!
  socket(TEMPHANDLE, PF_INET, SOCK_DGRAM, getprotobyname('udp'));
  bind(TEMPHANDLE, sockaddr_in(0, INADDR_ANY));

  # FIXME - Blithely assume this succeeded.
  $result = *TEMPHANDLE;

  return $result;
}



# Attempts to create a listening TCP socket handle. This starts listening
# immediately.
# Arg 0 is the port to listen to.
# Returns a filehandle, or undef on error.

sub NCAM_GetListenStreamSocket
{
  my ($port, $result);
  local (*TEMPHANDLE);

  $port = $_[0];
  $result = undef;

  if (defined $port)
  {
    # FIXME - No error checking!
    socket(TEMPHANDLE, PF_INET, SOCK_STREAM, getprotobyname('tcp'));
    bind(TEMPHANDLE, sockaddr_in($port, INADDR_ANY));
    listen(TEMPHANDLE, SOMAXCONN);

    # FIXME - Blithely assume this succeeded.
    $result = *TEMPHANDLE;
  }

  return $result;
}



# Shuts down and closes a socket handle.
# Arg 0 is the handle.
# No return value.

sub NCAM_CloseSocket
{
  my ($handle);
  local (*TEMPHANDLE);

  $handle = $_[0];

  if (defined $handle)
  {
    *TEMPHANDLE = $handle;
    shutdown(TEMPHANDLE, SHUT_RDWR);
    close(TEMPHANDLE);
  }
}



# This performs a non-blocking query of read capability for a filehandle.
# Arg 0 is the handle to test.
# Returns 1 if the handle can be read from now and 0 otherwise.

sub NCAM_HandleCanRead
{
  my ($handle, $can_read);
  my ($filevec, $filecount);

  $handle = $_[0];
  $can_read = 0;

  if (defined $handle)
  {
    # Build a vector containing only this filehandle.
    $filevec = '';
    vec($filevec, fileno($handle), 1) = 1;

    # Use a timeout of zero, to poll.
    # This overwrites the vector, but we don't care about that.
    $filecount = select($filevec, undef, undef, 0);

    if (0 < $filecount)
    { $can_read = 1; }
  }

  return $can_read;
}



# This performs a non-blocking query of write capability for a filehandle.
# Arg 0 is the handle to test.
# Returns 1 if the handle can be written to now and 0 otherwise.

sub NCAM_HandleCanWrite
{
  my ($handle, $can_write);
  my ($filevec, $filecount);

  $handle = $_[0];
  $can_write = 0;

  if (defined $handle)
  {
    # Build a vector containing only this filehandle.
    $filevec = '';
    vec($filevec, fileno($handle), 1) = 1;

    # Use a timeout of zero, to poll.
    # This overwrites the vector, but we don't care about that.
    $filecount = select(undef, $filevec, undef, 0);

    if (0 < $filecount)
    { $can_write = 1; }
  }

  return $can_write;
}



# Queries local networking information.
# This returns a copy of the network info hash. If this is the first
# invocation, probing for network information will be performed first.
# This contains "hostname", "hostpacked", and "hostip".
# No arguments.
# Returns a pointer to a copy of the network info hash.

sub NCAM_GetNetworkInfo
{
  my ($infocopy_p);
  my ($hostname, $hostpacked, $hostip);
  my ($scratch);
  my (@addrlist);
  my ($debug_p);

  if (!(defined $local_network_info_p))
  {
    $debug_p = {};
    $$debug_p{method} = 'none';


    # Get host information.

    # FIXME - Doing this the really kludgy way.
    $hostname = `hostname`;
    chomp($hostname);


    # FIXME - There are three ways to get the IP address.
    # Using inet_aton on the hostname sometimes gives localhost on the
    # target machine.
    # Using "nslookup" uses DNS, which is sometimes dodgy on the target.
    # Using "ifconfig" on the wired interface _should_ always work.
    # FIXME - Wired interfaces vary! We get "eno1" on the new machine.
    # On my desktop, we get "enp2s0".
    # May want to make wireless interfaces work too ("wlan0").

    $hostip = undef;

    # First pass: scan all network interfaces.

    # Save ifconfig output to the debug hash.
    $scratch = `/sbin/ifconfig`;
    $$debug_p{ifconfig} = $scratch;

    @addrlist = ();
    while ($scratch =~ m/inet addr\s*:\s*(\d+\.\d+\.\d+\.\d+)(.*)/s)
    {
      push @addrlist, $1;
      $scratch = $2;
    }

    # Save the address list to the debug hash.
    $scratch = [];
    @$scratch = @addrlist;
    $$debug_p{addrlist} = $scratch;

    # Pick an arbitrary address that isn't the loopback address.
    # FIXME - We should prioritize wired over wireless if possible.
    # That would require saving the device names from ifconfig, though.
    foreach $scratch (@addrlist)
    {
      if (!($scratch =~ m/^127/))
      {
        $hostip = $scratch;
        $$debug_p{method} = 'ifconfig';
      }
    }


    # Second pass (fallback): Use "nslookup".

    if (!(defined $hostip))
    {
      $scratch = `nslookup $hostname`;
      $$debug_p{nslookup} = $scratch;

      if ($scratch =~ m/Name:\s+\S+\s+Address:\s+(\S+)/ms)
      {
        $hostip = $1;
        $$debug_p{method} = 'nslookup';
      }
    }


    # Third pass (fallback): Use inet_ functions.

    if (!(defined $hostip))
    {
      $hostpacked = inet_aton($hostname);
      $hostip = inet_ntoa($hostpacked);
      $$debug_p{method} = 'inet lib';
    }


    # FIXME - Derive packed address from IP, not name.
    $hostpacked = inet_aton($hostip);


# FIXME - Diagnostics.
if (0)
{
print << "Endofblock";
** Detected network settings:
  Host: $hostname
    IP: $hostip
Endofblock
}

    # Set up the information hash.
    # This includes receive and transmit socket handles.
    $local_network_info_p =
    {
      'hostname' => $hostname,
      'hostpacked' => $hostpacked,
      'hostip' => $hostip,
      # FIXME - Add a hash with debugging information.
      'debug' => $debug_p
    };


    # We now have detailed networking information.
  }

  # Make a copy by value.
  $infocopy_p = {};
  %$infocopy_p = %$local_network_info_p;

  return $infocopy_p;
}



# This checks a UDP socket for messages, returns the message
# information if present.
# NOTE - Using select() directly to poll multiple sockets is more
# efficient, but this still works and abstracts that away.
# Arg 0 is the socket handle to check.
# Returns (has_message, sender_ip, message). The last two may be undef.

sub NCAM_CheckReceiveSocket
{
  my ($handle, $has_message, $sender_ip, $message);
  my ($sender_raw, $sender_ip_packed, $sender_port);

  $handle = $_[0];
  $has_message = 0;

  if (defined $handle)
  {
    if (NCAM_HandleCanRead($handle))
    {
      # FIXME - Blithely assume this succeeds. It _should_.
      $sender_raw = recv($handle, $message, 65536, 0);

      ($sender_port, $sender_ip_packed) = unpack_sockaddr_in($sender_raw);
      $sender_ip = inet_ntoa($sender_ip_packed);

      $has_message = 1;
    }
  }

  return ($has_message, $sender_ip, $message);
}



# This sends a message via UDP socket.
# Arg 0 is the socket handle to use.
# Arg 1 is the target IP address.
# Arg 2 is the target port.
# Arg 3 is the message to send.
# No return value.

sub NCAM_SendSocket
{
  my ($handle, $target_ip, $target_port, $message);
  my ($target_packed);

  $handle = $_[0];
  $target_ip = $_[1];
  $target_port = $_[2];
  $message = $_[3];

  if ( (defined $handle)
    && (defined $target_ip) && (defined $target_port)
    && (defined $message ) )
  {
    $target_packed = pack_sockaddr_in($target_port, inet_aton($target_ip));
    send($handle, $message, 0, $target_packed);
  }
}



# This sends a message via a freshly created UDP socket.
# NOTE - Don't do this if you can avoid it! It has overhead.
# Arg 0 is the target IP address.
# Arg 1 is the target port.
# Arg 2 is the message to send.
# No return value.

sub NCAM_SendAnonSocket
{
  my ($target_ip, $target_port, $message);
  my ($socket);

  $target_ip = $_[0];
  $target_port = $_[1];
  $message = $_[2];

  if ( (defined $target_ip) && (defined $target_port) && (defined $message ) )
  {
    $socket = NCAM_GetTransmitSocket();
    NCAM_SendSocket($socket, $target_ip, $target_port, $message);
    NCAM_CloseSocket($socket);
  }
}



# This closes private network sockets and performs other cleanup prior to
# shutdown.
# FIXME - Not needed any more?
# No arguments.
# No return value.

sub NCAM_ShutdownNetwork
{
  if (defined $local_network_info_p)
  {
#    NCAM_CloseSocket($$local_network_info_p{socktrans});
#    NCAM_CloseSocket($$local_network_info_p{sockrecv});
  }

  # Return to uninitialized state. Reinitialization should work.
  undef $local_network_info_p;
}



# This probes for network stream and message sources and assembles
# metadata for them.
# Arg 0 points to a list of ports to probe.
# Arg 1 is the number of milliseconds to wait for responses.
# Returns a pointer to a list of metadata hash pointers.

sub NCAM_ProbeNetworkDevices
{
  my ($probelist_p, $waitmillis, $network_p);
  my ($sendport, $listenport, $sendsocket, $recvsocket);
  my ($thistime, $endtime);
  my ($has_msg, $sender, $msg);
  my ($entry_p);

  $probelist_p = $_[0];
  $waitmillis = $_[1];

  $network_p = [];

  if ( (defined $probelist_p) && (defined $waitmillis) )
  {
    # Get sockets for probing.
    $listenport = NCAM_GetNextListenPort();
    $sendsocket = NCAM_GetTransmitSocket();
    $recvsocket = NCAM_GetListenSocket($listenport);

    # Shotgun broadcast queries to all ports before listening for replies.
    # We need to set the broadcast permission flag for this.
    setsockopt($sendsocket, SOL_SOCKET, SO_BROADCAST, 1);
    foreach $sendport (@$probelist_p)
    {
      NCAM_SendSocket($sendsocket, inet_ntoa(INADDR_BROADCAST), $sendport,
        "looking for sources reply to port " . $listenport);
      # FIXME - Ping localhost explicitly too.
      # This might generate multiple replies from the same (local) machine.
      # Call that a "feature" (user gets to choose which interface is used).
      # We do need to do this, as local doesn't always respond to broadcasts.
      NCAM_SendSocket($sendsocket, inet_ntoa(INADDR_LOOPBACK), $sendport,
        "looking for sources reply to port " . $listenport);
    }
    # Revoke broadcast permission.
    setsockopt($sendsocket, SOL_SOCKET, SO_BROADCAST, 0);

    # Spin, waiting for replies until we time out.

    $thistime = NCAM_GetAbsTimeMillis();
    $endtime = $thistime + $waitmillis;

    while ($thistime < $endtime)
    {
      # Check for pending messages.
      ($has_msg, $sender, $msg) = NCAM_CheckReceiveSocket($recvsocket);
      if ($has_msg)
      {
        # We got a response. See if it's one we understand.
        if ($msg =~ m/^\s*message source at \s*(\S+):(\d+) label \s*(.*\S)/i)
        {
          $entry_p =
          {
            'type' => 'talker',
            'host' => $1,
            'port' => $2,
            'label' => $3
          };
          push @$network_p, $entry_p;
        }
        elsif ($msg =~ m/^\s*stream source at \s*(\S+) label \s*(.*\S)/i)
        {
          # NOTE - We reject URLs with spaces in them now!
          # This might cause problems in the future.
          $entry_p =
          {
            'type' => 'stream',
            'url' => $1,
            'label' => $2
          };
          push @$network_p, $entry_p;
        }
        # Ignore anything we don't know how to deal with.
      }

      # Force a yield. Querying time should do that, but force it anyways.
      NCAM_SleepMillis(0);
      $thistime = NCAM_GetAbsTimeMillis();
    }

    # Get rid of the sockets we'd allocated.
    NCAM_CloseSocket($sendsocket);
    NCAM_CloseSocket($recvsocket);
  }

  return $network_p;
}



#
# Main Program
#


# Report success.
1;



#
# This is the end of the file.
#
