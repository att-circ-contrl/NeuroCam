#!/usr/bin/perl
#
# Quick and dirty UDP snooper to look at mplayer synch packets.
# Written by Christopher Thomas.
#
# Usage:  udpsnoop.pl  <port number>
#

#
# Includes

use strict;
use warnings;
use Socket;


#
# Functions


# Converts a packed byte string into a human-readable hex dump.
# Arg 0 is the string to convert.
# Returns a human-readable string.

sub MakeHexString
{
  my ($string, $result);
  my ($thisbyte);

  $string = $_[0];
  $result = "";

  if (!(defined $string))
  {
    print "### [MakeHexString]  Bad arguments.\n";
  }
  else
  {
    while ($string =~ m/(.)(.*)/)
    {
      $thisbyte = ord($1);
      $string = $2;

      $result .= sprintf(' %02x', $thisbyte);
    }
  }

  return $result;
}


# Converts a packed IP address/port combination into a human-readable string.
# Arg 0 is the packed address to convert.
# Returns a human-readable string.

sub UnpackAddressPort
{
  my ($packed, $result);
  my ($addr, $port);

  $packed = $_[0];
  $result = "";

  if (!(defined $packed))
  {
    print "### [UnpackAddressPort]  Bad arguments.\n";
  }
  else
  {
    ($port, $addr) = unpack_sockaddr_in($packed);
    # The address is four packed bytes. Unpack it.
    $addr = inet_ntoa($addr);
    # The port is an integer.

    $result = $addr . ':' . $port;
  }

  return $result;
}



#
# Main Program

my ($listenport);
my ($frompacked);
my ($thismsg);

$listenport = $ARGV[0];

if (!(defined $listenport))
{
  print << "Endofblock";

 Quick and dirty UDP snooper to look at mplayer synch packets.
 Written by Christopher Thomas.

 Usage:  udpsnoop.pl  <port number>

Endofblock
}
else
{
  # FIXME - No error checking.
  socket(SOCKFILE, PF_INET, SOCK_DGRAM, getprotobyname("udp"));
  # Don't bother with REUSEADDR and setsockopts().
  bind(SOCKFILE, sockaddr_in($listenport, INADDR_ANY));
  # NOTE - listen() is only needed for TCP.


  # Spin, accepting packets.
  # "recv" returns a packed address, or "" for addresses not supported,
  # or undef on fail.
  # recv(socketfile, scalar, max message bytes, flags).
  while (defined ($frompacked = recv(SOCKFILE, $thismsg, 65536, 0)))
  {
    # See what we got.


    print '-- ' . UnpackAddressPort($frompacked) . " :\n";

    # FIXME - mplayer's UDP packets are human-readable text.
#    print MakeHexString($thismsg) . "\n";
    print $thismsg . "\n";
  }


  # Done.
  # This should only hapen if an error occurs.
  print "###  Recv() loop terminated. Error reported: $!\n";
}


#
# This is the end of the file.
