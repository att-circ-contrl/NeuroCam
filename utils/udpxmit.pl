#!/usr/bin/perl
#
# Quick and dirty UDP transmitter to test various clients/servers.
# Written by Christopher Thomas.
#
# Usage:  udpxmit.pl <address> <port> <message>
#

#
# Includes

use strict;
use warnings;
use Socket;



#
# Main Program

my ($destport, $destaddr, $msg);
my ($destpacked);

$destaddr = $ARGV[0];
$destport = $ARGV[1];
$msg = $ARGV[2];

if (!( (defined $destport) && (defined $destaddr) && (defined $msg) ))
{
  print << "Endofblock";

 Quick and dirty UDP transmitter to test various clients/servers.
 Written by Christopher Thomas.

 Usage:  udpxmit.pl <address> <port> <message>

Endofblock
}
else
{
  # FIXME - No error checking!

  # Create the socket.
  socket(SOCKFILE, PF_INET, SOCK_DGRAM, getprotobyname("udp"));
  # 0 means we don't care what port we're assigned.
  bind(SOCKFILE, pack_sockaddr_in(0, INADDR_ANY));

  # Build the target address.
  $destpacked = pack_sockaddr_in($destport, inet_aton($destaddr));

  # Send the message.
  send(SOCKFILE, $msg, 0, $destpacked);


  # Done.

  shutdown(SOCKFILE, SHUT_RDWR);
  close(SOCKFILE);
}


#
# This is the end of the file.
