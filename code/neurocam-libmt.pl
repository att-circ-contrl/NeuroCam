#!/usr/bin/perl
#
# NeuroCam management script - Multithreading library.
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
# Functions
#


# Sets the process name.
# NOTE - This makes "kill everything" scripts a bit trickier.
# Arg 0 is the new name for the process.
# Returns the old name.

sub NCAM_SetProcessName
{
  my ($newname, $oldname);

  $newname = $_[0];

  $oldname = $0;

  if (defined $newname)
  {
    # FIXME - This wraps prctl() on newer versions of Perl, but not older.
    # Old versions will show inconsistent results with different tools.
    $0 = $newname;
  }

  return $oldname;
}



# Forces a yield.
# FIXME - This deliberately has nonzero delay!
# We're getting CPU hogging with zero delay.
# No arguments.
# No return value.

sub NCAM_Yield
{
  # Sleep for at least the specified number of microseconds.
  # NOTE - Busy-waiting with 0.1, 0.3, and 1.0 ms took about 10%, 5%, and 2%
  # cpu on my development system.

  # System timeslice granularity seems to be about 0.1 ms, with explicit
  # timeslice clocking at about 1 ms if I understand correctly.
  # So, this could take about 1 ms worst-case.

  Time::HiRes::usleep(300);
}



#
# Main Program
#


# Report success.
1;



#
# This is the end of the file.
#
