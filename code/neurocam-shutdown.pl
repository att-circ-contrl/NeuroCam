#!/usr/bin/perl
#
# NeuroCam helper script - System shutdown.
# Written by Christopher Thomas.
#
# This waits 2 seconds, then shuts down.
# It's intended to be called via NCAM_LaunchDaemon().
#
# This project is Copyright (c) 2021 by Vanderbilt University, and is released
# under the Creative Commons Attribution-ShareAlike 4.0 International License.

#
# Includes
#

use strict;
use warnings;


#
# Main Program
#

my ($result);

sleep(2);
$result = `shutdown -P now`;


#
# This is the end of the file.
#
