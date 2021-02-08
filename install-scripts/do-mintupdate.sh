#!/bin/bash
# NeuroCam package update script.
# Written by Christopher Thomas.
# This tells Mint to update everything it can, and then tweaks permissions
# on the "shutdown" command.
#
# FIXME - As of Mint 18, "shutdown" is replaced with "systemctl". Making
# that user-executable is almost certainly a large security hole, but we're
# doing it anyways. This is one of the many reasons the NeuroCam should not
# be directly exposed to the internet.
#
# Copyright (c) 2021 by Vanderbilt University. This work is released under
# the Creative Commons Attribution-ShareAlike 4.0 International License.


USERNAME=`whoami`

if [ "$USERNAME" = "root" ]
then

echo "-- Updating package list."
apt-get --yes update
echo "-- Updating packages."
apt-get --yes upgrade
echo "-- Changing permissions on 'shutdown' and 'systemctl'."
echo "   NOTE - The latter may introduce security holes!"

chmod u+s /sbin/mount.exfat-fuse
chmod u+s /sbin/shutdown
# FIXME - This replaces "shutdown" on Mint 18. Introduces security holes!
chmod u+s /bin/systemctl

echo "-- Finished updating."

else

echo "### This script must be run as root."

fi

# This is the end of the file.
