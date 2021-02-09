#!/usr/bin/perl
#
# NeuroCam management script - Motion JPEG library.
# Writen by Christopher Thomas.
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

our ($NCAM_mjpeg_global_header);
our ($NCAM_mjpeg_frame_header, $NCAM_mjpeg_frame_footer);
our ($NCAM_mjpeg_boundary_marker);

$NCAM_mjpeg_boundary_marker = 'neurocam-boundary';

# This is a multipart HTTP response header plus the first separator.
$NCAM_mjpeg_global_header =
"HTTP/1.1 200 OK\r\n" .
"Pragma: no-cache\r\n" .
"Content-Type: multipart/x-mixed-replace;boundary="
  . $NCAM_mjpeg_boundary_marker . "\r\n" .
"\r\n";
# .
#"--" . $NCAM_mjpeg_boundary_marker . "\r\n";

$NCAM_mjpeg_frame_header =
"Content-Type: image/jpeg\r\n" .
"\r\n";

$NCAM_mjpeg_frame_footer =
"--" . $NCAM_mjpeg_boundary_marker . "\r\n";



#
# Imported Constants
#

# FIXME - Doing this the messy way. Any imported variables need appropriate
# "our" declarations.

our ($NCAM_port_mjpeglib_base);



#
# Public Functions
#


# Reads one or more binary files into memory.
# This was intended for use with JPEGs, but can be used for anything.
# These are stored as an array of references to data scalars, rather
# than as an array of scalars, so that they can be passed by reference.
# Arg 0 points to a list of filenames to read from.
# Returns a pointer to a list of file data references, or undef on error.

sub NCAM_ReadBinaryFiles
{
  my ($fnames_p, $fdata_p);
  my ($thisname, $thisdata_p, $isok);
  my ($oset, $count);

  $fnames_p = $_[0];
  $fdata_p = undef;

  if (defined $fnames_p)
  {
    $isok = 1;
    $fdata_p = [];

    foreach $thisname (@$fnames_p)
    {
      if ($isok)
      {
        if (!open(JPEGFILE, "<:raw", $thisname))
        {
          $isok = 0;
        }
        else
        {
          # This is freshly instantiated for every iteration.
          # Taking a reference to it gives a series of unique references.
          my ($realdata);

          # FIXME - BFI read using sysread().
          # The diamond operator is supposed to work but doesn't.
          $oset = 0;
          $realdata = '';
          do
          {
            $count = sysread(JPEGFILE, $realdata, 1024, $oset);
            $oset += $count;
          }
          while ($count > 0);

          $thisdata_p = \$realdata;
          push @$fdata_p, $thisdata_p;

          close(JPEGFILE);
        }
      }

      # Finished with this image.
    }

    if (!$isok)
    {
      undef $fdata_p;
    }
  }

  return $fdata_p;
}



# Writes one MJPEG frame to a stream.
# NOTE - This will generate SIGPIPE on failure! A custom handler should be
# running when this function is called.
# Arg 0 is the handle to write to.
# Arg 1 points to the JPEG data to write.
# Returns 1 if successful and 0 if not.

sub NCAM_SendMJPEGFrame
{
  my ($handle, $jpeg_p, $isok);
  my ($bytes_written);

  $handle = $_[0];
  $jpeg_p = $_[1];
  $isok = 0;

  if ( (defined $handle) && (defined $jpeg_p) )
  {
    # NOTE - This uses syswrite(), bypassing most buffering.
    # NOTE - This will generate SIGPIPE on failure! Trap that before calling.

    $isok = 1;

    # Header.
    $bytes_written = syswrite($handle, $NCAM_mjpeg_frame_header);
    if (!(defined $bytes_written))
    { $isok = 0; }

    # Image data.
    if ($isok)
    {
      $bytes_written = syswrite($handle, $$jpeg_p);
      if (!(defined $bytes_written))
      { $isok = 0; }
    }

    # Footer.
    if ($isok)
    {
      $bytes_written = syswrite($handle, $NCAM_mjpeg_frame_footer);
      if (!(defined $bytes_written))
      { $isok = 0; }
    }

    # Done.
  }

  return $isok;
}



# Starts a live imagecasting server - multiple client version.
# Send JPEG filenames to this to transmit those frames to all clients.
# Send "shutdown" to this to shut down the server and all clients.
# Arg 0 is the port to serve streams from. Filename requested is ignored.
# Returns a filehandle to send filenames and commands to.
# FIXME - Not returning any PIDs!

sub NCAM_StartLiveImagecastMulti
{
  my ($stream_port);
  my ($command_xmit, $command_recv);
  my ($managerpid, $serverpid, $clientpid);
  my ($stream_listener, $stream_client);
  my ($broadcast_handle, %client_ports, $this_port);
  my ($clientreg_xmit, $clientreg_recv);
  my ($thisline);
  my ($done);
  my ($has_message, $sender_ip, $message);
  my ($fname, $fdata_p, $isok);
  my ($readok, $bytes_read, $stringdata, $thisdata);

  $stream_port = $_[0];
  $command_xmit = undef;

  # FIXME - No error checking on any of the "new socket" or "new process"
  # operations.

  if (defined $stream_port)
  {
    # Get a pipe for the caller to communicate with the manager with.
    ($command_recv, $command_xmit) = NCAM_GetNewPipe();

    # Set up the manager thread.
    $managerpid = fork();

    if (0 == $managerpid)
    {
      NCAM_SetProcessName('mjpeg-manager');

      # We're the manager. Close the command transmit handle.
      close($command_xmit);

      # Get a pipe for the server to tell the manager about clients with.
      ($clientreg_recv, $clientreg_xmit) = NCAM_GetNewPipe();

      # Set up the server thread.
      $serverpid = fork();

      if (0 == $serverpid)
      {
        NCAM_SetProcessName('mjpeg-server');

        # We're the server.

        # Close the command receive handle. That's for the manager.
        close($command_recv);
        # Likewise close the client registration receive handle.
        close($clientreg_recv);

        # Redirect SIGPIPE, because we'll see it when clients disconnect.
        $SIG{PIPE} = sub {};

        # Adjust the port assignment namespace, so that we don't collide
        # with anything the main thread will allocate (or fakeunity.pl).
        # FIXME - Multiple _invocations_ of this function will still
        # collide! Manually adjust this magic constant if that situation
        # occurs.
        NCAM_SetNextListenPort($NCAM_port_mjpeglib_base);

        # Set up a listening TCP socket, and spin on accept() until killed.
        $stream_listener = NCAM_GetListenStreamSocket($stream_port);

        while(accept($stream_client, $stream_listener))
        {
          # We have a new client connection.

          # Get a new handshaking port, and record the port number.
          # FIXME - This still might eventually collide with the parent.
          $this_port = NCAM_GetNextListenPort();
# FIXME - Diagnostics.
#print STDERR "-- Streamer listening on port $this_port.\n";

          # Fork a child process for this client connection.
          $clientpid = fork();

          if (0 == $clientpid)
          {
            NCAM_SetProcessName('mjpeg-client');

            # Set binary mode, and send the header.
            binmode $stream_client, ':raw';
            syswrite($stream_client, $NCAM_mjpeg_global_header);

# FIXME - Diagnostics.
#print STDERR "-- ($this_port) Sent header.\n";
            # Set up a UDP listening socket so that we can learn about frames.
            $broadcast_handle = NCAM_GetListenSocket($this_port);


            # Spin, sending the client frames as they become available.

            $done = 0;
            $isok = 1;

            while (!$done)
            {
              # Wait for a new frame to become available.
              $has_message = 0;
              while (!$has_message)
              {
                NCAM_Yield();

                ($has_message, $sender_ip, $message) =
                  NCAM_CheckReceiveSocket($broadcast_handle);
              }

              # We have a message from the manager.

# FIXME - Diagnostics.
#chomp($message);
#print STDERR "-- ($this_port) Command: $message.\n";


              # Read anything pending from the client.
              # This should just be the GET command, so reading it one byte
              # at a time is okay.
              # FIXME - The javascript movie-player firehoses GET packets!

              $readok = 1;
              $stringdata = '';
              while ($readok && NCAM_HandleCanRead($stream_client))
              {
                $thisdata = '';
                $bytes_read = sysread($stream_client, $thisdata, 1);
                if ( (!(defined $bytes_read)) || (1 > $bytes_read) )
                { $readok = 0; }
                else
                { $stringdata .= $thisdata; }
              }
              # Just discard whatever it was we've read.


              # Process the message from the manager.
              # If this is a shutdown message, shut down. Otherwise
              # transmit the frame.
              if ($message =~ m/shutdown/i)
              {
                $done = 1;
              }
              elsif ($message =~ m/^\s*(.*\S)/)
              {
                # Try to read this image. This returns undef on failure.
                $fname = $1;
                $fdata_p = NCAM_ReadBinaryFiles([ $fname ]);
                if (defined $fdata_p)
                {
                  # This should be a list of one element (a reference to the
                  # image we loaded).
                  $fdata_p = $$fdata_p[0];

                  # Try to transmit this frame, with appropriate wrapping.
                  # This will fail if the client has disconnected.
                  $isok = NCAM_SendMJPEGFrame($stream_client, $fdata_p);
                  if (!$isok)
                  {
                    $done = 1;
# FIXME - Diagnostics.
#print STDERR "-- ($this_port) Client disconnected.\n";
                  }
                }
              }

              # Keep spinning, transmitting frames.
            }


            # The client has disconnected, or we've been told to shut down.
            # If it's the latter, shut down the client socket.
            if ($isok)
            {
              # Close and shut down the client socket.
              NCAM_CloseSocket($stream_client);
            }

            # Close our listening socket.
            NCAM_CloseSocket($broadcast_handle);

            # FIXME - Not notifying the manager of the disconnection!
            # We'd need to have the manager listening via UDP rather than
            # pipe for that.

            # End this process (the client thread) here.
            exit(0);
          }
          else
          {
            # We're the server.

            # Close (but don't shut down) the client handle.
            close($stream_client);

            # Report the new client to the manager.
            print $clientreg_xmit "add $this_port\n";
          }

          # We're the server. Keep spinning.
        }

        # We should never get here. accept() must have encountered an error.
        while (1) {}
      }
      else
      {
        # We're the manager.

        # Close the client registration transmit handle. We just receive.
        close($clientreg_xmit);

        # Set up our UDP broadcast socket.
        $broadcast_handle = NCAM_GetTransmitSocket();
        # Name notwithstanding, it does not need the broadcast bit.

        # Initialize the list of client UDP ports.
        %client_ports = ();

        # Read the command stream, relaying filenames, until shutdown.
        # We're also listening for client registrations (and deletions).
        $done = 0;
        while (!$done)
        {
          NCAM_Yield();

          # Poll the client registration channel.
          # FIXME - This had better be non-blocking!
          if (NCAM_HandleCanRead($clientreg_recv))
          {
            $thisline = <$clientreg_recv>;

            if ($thisline =~ m/add\s+(\d+)/)
            {
              $client_ports{$1} = 1;
            }
            elsif ($thisline =~ m/delete\s+(\d+)/)
            {
              if (defined $client_ports{$1})
              { delete $client_ports{$1}; }
            }
# FIXME - Diagnostics.
#chomp($thisline);
#print STDERR "-- Client registration: $thisline\n";
          }

          # Poll the command channel.
          # FIXME - This had better be non-blocking!
          if (NCAM_HandleCanRead($command_recv))
          {
            $thisline = <$command_recv>;

            if ($thisline =~ m/shutdown/i)
            {
              $done = 1;
# FIXME - Diagnostics.
#chomp($thisline);
#print STDERR "-- Filename/Command: $thisline\n";
            }
            elsif ($thisline =~ m/^\s*(.*\S)/)
            {
              $thisline = $1;
              foreach $this_port (keys %client_ports)
              {
                NCAM_SendSocket($broadcast_handle,
                  inet_ntoa(INADDR_LOOPBACK),
                  $this_port, $thisline);
              }
            }
          }
# FIXME - Diagnostics.
#chomp($thisline);
#print STDERR "-- Filename/Command: $thisline\n";
        }


        # We've been told to terminate.

        # Before doing anything else, shut down the server.
        # Otherwise it spawns new clients that we don't know about.
        kill 'TERM', $serverpid;
        NCAM_SleepMillis(1000);
        kill 'KILL', $serverpid;

        # Next, tell the clients to shut down.
        foreach $this_port (keys %client_ports)
        {
          NCAM_SendSocket($broadcast_handle, inet_ntoa(INADDR_LOOPBACK),
            $this_port, "shutdown");
# FIXME - Diagnostics
#print STDERR "-- Shutting down $this_port.\n";
        }

        # Close our broadcast socket.
        NCAM_CloseSocket($broadcast_handle);
      }

      # End this process (the manager thread) here.
      exit(0);
    }
  }

  return $command_xmit;
}



# Starts a live imagecasting server - single-client version.
# Send JPEG filenames to this to transmit those frames to all clients.
# Send "shutdown" to this to shut down the server and all clients.
# Arg 0 is the port to serve streams from. Filename requested is ignored.
# Returns a filehandle to send filenames and commands to.
# FIXME - Not returning any PIDs!

sub NCAM_StartLiveImagecastSingle
{
  my ($stream_port);
  my ($command_xmit, $command_recv);
  my ($managerpid, $serverpid, $clientpid);
  my ($stream_listener, $stream_client);
  my ($broadcast_handle, %client_ports, $this_port);
  my ($clientreg_xmit, $clientreg_recv);
  my ($thisline);
  my ($done);
  my ($has_message, $sender_ip, $message);
  my ($fname, $fdata_p, $isok);
  my ($readok, $bytes_read, $stringdata, $thisdata);

  $stream_port = $_[0];
  $command_xmit = undef;

  # FIXME - No error checking on any of the "new socket" or "new process"
  # operations.

  if (defined $stream_port)
  {
    # Get a pipe for the caller to communicate with the manager with.
    ($command_recv, $command_xmit) = NCAM_GetNewPipe();

    # Get a new handshaking port, and record the port number.
    # Do this before any forking occurs, as this isn't MT-safe.
    $this_port = NCAM_GetNextListenPort();

    # Set up the manager thread.
    $managerpid = fork();

    if (0 == $managerpid)
    {
      NCAM_SetProcessName('mjpeg-manager');

      # We're the manager. Close the command transmit handle.
      close($command_xmit);

      # Get a pipe for the server to tell the manager about clients with.
      ($clientreg_recv, $clientreg_xmit) = NCAM_GetNewPipe();

      # Set up the server thread.
      $serverpid = fork();

      if (0 == $serverpid)
      {
        NCAM_SetProcessName('mjpeg-server');

        # We're the server.

        # Close the command receive handle. That's for the manager.
        close($command_recv);
        # Likewise close the client registration receive handle.
        close($clientreg_recv);

        # Set up a UDP listening socket so that we can learn about frames.
        $broadcast_handle = NCAM_GetListenSocket($this_port);

        # Redirect SIGPIPE, because we'll see it when clients disconnect.
        $SIG{PIPE} = sub {};

        # Set up a listening TCP socket.
        $stream_listener = NCAM_GetListenStreamSocket($stream_port);

        # Spin on accept() until killed or told to shut down.
        $done = 0;
        while( (!$done) && accept($stream_client, $stream_listener) )
        {
          # We have a new client connection.

          # Report the new client to the manager.
          # This shouldn't block (the other end is buffered).
          print $clientreg_xmit "add $this_port\n";

          # Set binary mode, and send the header.
          binmode $stream_client, ':raw';
          syswrite($stream_client, $NCAM_mjpeg_global_header);

# FIXME - Diagnostics.
#print STDERR "-- ($this_port) Sent header.\n";

          # Spin, sending the client frames as they become available.

          $isok = 1;

          while ( $isok && (!$done) )
          {
            # Wait for a new frame to become available.
            $has_message = 0;
            while (!$has_message)
            {
              NCAM_Yield();

              ($has_message, $sender_ip, $message) =
                NCAM_CheckReceiveSocket($broadcast_handle);
            }

            # We have a message from the manager.

# FIXME - Diagnostics.
#chomp($message);
#print STDERR "-- ($this_port) Command: $message.\n";


            # Read anything pending from the client.
            # This should just be the GET command, so reading it one byte
            # at a time is okay.
            # FIXME - The javascript movie-player firehoses GET packets!

            $readok = 1;
            $stringdata = '';
            while ($readok && NCAM_HandleCanRead($stream_client))
            {
              $thisdata = '';
              $bytes_read = sysread($stream_client, $thisdata, 1);
              if ( (!(defined $bytes_read)) || (1 > $bytes_read) )
              { $readok = 0; }
              else
              { $stringdata .= $thisdata; }
            }
            # Just discard whatever it was we've read.


            # Process the message from the manager.
            # If this is a shutdown message, shut down. Otherwise
            # transmit the frame.
            if ($message =~ m/shutdown/i)
            {
              $done = 1;
            }
            elsif ($message =~ m/^\s*(.*\S)/)
            {
              # Try to read this image. This returns undef on failure.
              $fname = $1;
              $fdata_p = NCAM_ReadBinaryFiles([ $fname ]);
              if (defined $fdata_p)
              {
                # This should be a list of one element (a reference to the
                # image we loaded).
                $fdata_p = $$fdata_p[0];

                # Try to transmit this frame, with appropriate wrapping.
                # This will fail if the client has disconnected.
                $isok = NCAM_SendMJPEGFrame($stream_client, $fdata_p);
                if (!$isok)
                {
# FIXME - Diagnostics.
#print STDERR "-- ($this_port) Client disconnected.\n";
                }
              }
            }

            # Keep spinning, transmitting frames.
          }


          # The client has disconnected, or we've been told to shut down.

          # If the client is still connected, shut down the client socket.
          if ($isok)
          {
            # Close and shut down the client socket.
            NCAM_CloseSocket($stream_client);
          }

          # If we're not shutting down, report that we've lost this
          # client.
          if (!$done)
          {
            # This shouldn't block (the other end is buffered).
            print $clientreg_xmit "delete $this_port\n";
          }


          # Keep spinning, accepting client connections.
        }


        # We've been told to shut down.

        # Close our listening socket.
        NCAM_CloseSocket($broadcast_handle);

        # End this process (the client thread) here.
        exit(0);
      }
      else
      {
        # We're the manager.

        # Close the client registration transmit handle. We just receive.
        close($clientreg_xmit);

        # Set up our UDP broadcast socket.
        $broadcast_handle = NCAM_GetTransmitSocket();
        # Name notwithstanding, it does not need the broadcast bit.

        # Initialize the list of client UDP ports.
        %client_ports = ();

        # Read the command stream, relaying filenames, until shutdown.
        # We're also listening for client registrations (and deletions).
        $done = 0;
        while (!$done)
        {
          NCAM_Yield();

          # Poll the client registration channel.
          # FIXME - This had better be non-blocking!
          if (NCAM_HandleCanRead($clientreg_recv))
          {
            $thisline = <$clientreg_recv>;

            if ($thisline =~ m/add\s+(\d+)/)
            {
              $client_ports{$1} = 1;
            }
            elsif ($thisline =~ m/delete\s+(\d+)/)
            {
              if (defined $client_ports{$1})
              { delete $client_ports{$1}; }
            }
# FIXME - Diagnostics.
#chomp($thisline);
#print STDERR "-- Client registration: $thisline\n";
          }

          # Poll the command channel.
          # FIXME - This had better be non-blocking!
          if (NCAM_HandleCanRead($command_recv))
          {
            $thisline = <$command_recv>;

            if ($thisline =~ m/shutdown/i)
            {
              $done = 1;
# FIXME - Diagnostics.
#chomp($thisline);
#print STDERR "-- Filename/Command: $thisline\n";
            }
            elsif ($thisline =~ m/^\s*(.*\S)/)
            {
              $thisline = $1;
              foreach $this_port (keys %client_ports)
              {
                NCAM_SendSocket($broadcast_handle,
                  inet_ntoa(INADDR_LOOPBACK),
                  $this_port, $thisline);
              }
            }
          }
# FIXME - Diagnostics.
#chomp($thisline);
#print STDERR "-- Filename/Command: $thisline\n";
        }


        # We've been told to terminate.

        # Before doing anything else, shut down the server.
        # Otherwise it spawns new clients that we don't know about.
        kill 'TERM', $serverpid;
        NCAM_SleepMillis(1000);
        kill 'KILL', $serverpid;

        # Next, tell the clients to shut down.
        foreach $this_port (keys %client_ports)
        {
          NCAM_SendSocket($broadcast_handle, inet_ntoa(INADDR_LOOPBACK),
            $this_port, "shutdown");
# FIXME - Diagnostics
#print STDERR "-- Shutting down $this_port.\n";
        }

        # Close our broadcast socket.
        NCAM_CloseSocket($broadcast_handle);
      }

      # End this process (the manager thread) here.
      exit(0);
    }
  }

  return $command_xmit;
}



#
# Main Program
#


# Report success.
1;



#
# This is the end of the file.
#
