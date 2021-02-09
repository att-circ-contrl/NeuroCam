#!/usr/bin/perl
#
# NeuroCam management script - Command-line post-processing tool.
# Written by Christopher Thomas.
#
# Usage:
#
#   neurocam-postprocess.pl  timing (repository directory) (port)
#   neurocam-postprocess.pl  composite (repository directory) (port)
#   neurocam-postprocess.pl  transcode (repository) (image subdir) (port)
#   neurocam-postprocess.pl  metadata (repository directory) (port)
#
# Valid operations are:
#
#     timing  - Synchronize image streams to a strobe signal.
#               This creates 'logfile-timed.txt'.
#
#  composite  - Build a stitched image stream with timestamps in "/Composite".
#               This uses 'logfile-timed.txt' over 'logfile.txt' if possible.
#
#  transcode  - Assemble a set of frames into a video stream.
#               This reads from (repository)/(subdir), and assembles
#               (subdir).mp4.
#
#   metadata  - Rebuilds metadata for a root repository.
#               This creates 'metadata.txt' in the root directory.
#
# Progress strings are sent to the specified port via UDP.
# These have the string "progress " as a prefix.
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

require "neurocam-libmt.pl";
require "neurocam-libcam.pl";
require "neurocam-libnetwork.pl";
require "neurocam-libsession.pl";
require "neurocam-libstitch.pl";
require "neurocam-libpost.pl";
# FIXME - Diagnostics.
require "neurocam-libdebug.pl";



#
# Shared Variables
#

# FIXME - Doing this the messy way. Any imported variables need appropriate
# "our" declarations.



#
# Functions
#



#
# Main Program
#

my ($operation, $repodir);
my ($port, $slotname);

$operation = shift @ARGV;
$repodir = shift @ARGV;

if (!( (defined $operation) && (defined $repodir) ))
{
  print << 'Endofblock';

 NeuroCam management script - Command-line post-processing tool.
 Written by Christopher Thomas.

 Usage:

   neurocam-postprocess.pl  timing (repository directory)
   neurocam-postprocess.pl  composite (repository directory) (port)
   neurocam-postprocess.pl  transcode (repository) (image subdir) (port)
   neurocam-postprocess.pl  metadata (repository directory) (port)

 Valid operations are:

     timing  - Synchronize image streams to a strobe signal.
               This creates 'logfile-timed.txt'.

  composite  - Build a stitched image stream with timestamps in "/Composite".
               This uses 'logfile-timed.txt' over 'logfile.txt' if possible.

  transcode  - Assemble a set of frames into a video stream.
               This reads from (repository)/(subdir), and assembles
               (subdir).mp4.

   metadata  - Rebuilds metadata for a root repository.
               This creates 'metadata.txt' in the root directory.

 Progress strings are sent to the specified port via UDP.
 These have the string "progress " as a prefix.

Endofblock
}
elsif ('timing' eq $operation)
{
  $port = shift @ARGV;

  if (!(defined $port))
  {
    print "###  Progress report port must be specified.\n";
  }
  else
  {
    print "-- Adjusting timestamps.\n";

    NCAM_AdjustTimestampsAllStreams($repodir, $port);

    print "-- Finished adjusting timestamps.\n";
  }
}
elsif ('composite' eq $operation)
{
  $port = shift @ARGV;

  if (!(defined $port))
  {
    print "###  Progress report port must be specified.\n";
  }
  else
  {
    print "-- Generating composite frames.\n";

    NCAM_BuildCompositeFrames($repodir, $port);

    print "-- Finished generating composite frames.\n";
  }
}
elsif ('transcode' eq $operation)
{
  $slotname = shift @ARGV;
  $port = shift @ARGV;

  if (!( (defined $slotname) && (defined $port) ))
  {
    print "###  Image directory and progress report port must be specified.\n";
  }
  else
  {
    print "-- Transcoding \"$slotname\".\n";

    NCAM_TranscodeFrameset($repodir, $slotname, "$repodir/$slotname", $port);

    print "-- Finished transcoding \"$slotname\".\n";
  }
}
elsif ('metadata' eq $operation)
{
  $port = shift @ARGV;

  if (!(defined $port))
  {
    print "###  Progress report port must be specified.\n";
  }
  else
  {
    print "-- Updating repository metadata.\n";

    # FIXME - Kludge progress.
    NCAM_SendAnonSocket('localhost', $port,
      "progress updating metadata (\"$repodir\")");

    NCAM_UpdateRepositoryMetadata($repodir);

    # FIXME - Kludge progress.
    NCAM_SendAnonSocket('localhost', $port,
      "progress finished updating (\"$repodir\")");

    print "-- Finished updating metadata.\n";
  }
}
else
{
  print "###  Unknown operation \"$operation\" requested.\n";
}



#
# This is the end of the file.
#
