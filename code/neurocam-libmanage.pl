#!/usr/bin/perl
#
# NeuroCam management script - Manager daemon library.
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
# Private Constants
#

# Timeout for manager queries, in milliseconds.
# This should only actually be reached if the manager isn't running.
my ($NCAM_mgr_query_timeout);
$NCAM_mgr_query_timeout = 1000;



#
# Imported Constants
#

# FIXME - Doing this the messy way. Any imported variables need appropriate
# "our" declarations.

our ($NCAM_port_mgrdaemon_query);



#
# Public Functions
#

# Transmits a UDP message to the management daemon.
# Arg 0 is the socket to use.
# Arg 1 is the message to transmit.
# No return value.

sub NCAM_SendManagerCommand
{
  my ($sockhandle, $message);
  my ($netinfo_p);

  $sockhandle = $_[0];
  $message = $_[1];

  if ( (defined $sockhandle) && (defined $message) && ($message =~ m/\S/) )
  {
    # This should always be true, per test above.
    if ($message =~ m/^\s*(.*\S)/)
    {
      # Trim surrounding whitespace.
      $message = $1;
    }

    $netinfo_p = NCAM_GetNetworkInfo();
    NCAM_SendSocket($sockhandle, $$netinfo_p{hostip},
      $NCAM_port_mgrdaemon_query, $message);
  }
}



# Queries the status of the management daemon (and by extension the camera
# daemon). This is blocking but will time out if the manager doesn't respond.
# No arguments.
# Returns a status string, or undef if the daemon is not active.

sub NCAM_GetManagerStatus
{
  my ($listenport, $socksend, $sockrecv);
  my ($response);
  my ($endtime);
  my ($has_message, $sender_ip);

  $response = undef;

  $listenport = NCAM_GetNextListenPort();
  $socksend = NCAM_GetTransmitSocket();
  $sockrecv = NCAM_GetListenSocket($listenport);

  $endtime = NCAM_GetAbsTimeMillis() + $NCAM_mgr_query_timeout;

  NCAM_SendManagerCommand($socksend,
    "what is your status reply to port " . $listenport);

  while ( (!(defined $response)) && (NCAM_GetAbsTimeMillis() < $endtime) )
  {
    ($has_message, $sender_ip, $response) =
      NCAM_CheckReceiveSocket($sockrecv);

    if (!$has_message)
    { $response = undef; }
  }

  NCAM_CloseSocket($socksend);
  NCAM_CloseSocket($sockrecv);

  return $response;
}



# Launches a daemon process.
# NOTE - The PID is only accurate for list-type invocations!
# Otherwise it returns the PID for the shell invocation that parsed the
# command string.
# Examples:
#   NCAM_LaunchDaemon('ping localhost');
#   NCAM_LaunchDaemon( [ 'ping', 'localhost]' ] );
# Arg 0 is a scalar or an array reference specifying the command.
# Returns the process ID of the child process.

sub NCAM_LaunchDaemon
{
  my ($cmd, $pid);
  my ($daemon);
  my ($pwd);

  $cmd = $_[0];
  $pid = undef;

  if (defined $cmd)
  {
    $pwd = cwd();

    # FIXME - This doesn't seem to respect file_umask.
    # Result seems to always be rwx--x--x.
    $daemon = Proc::Daemon->new(
      'work_dir' => $pwd,
      'exec_command' => $cmd,
      'file_umask' => '022'
    );

    $pid = $daemon->Init();
  }

  return $pid;
}



#
# Main Program
#


# Report success.
1;



#
# This is the end of the file.
#
