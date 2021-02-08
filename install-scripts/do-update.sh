#!/bin/bash
# NeuroCam Installer - Update script.
# Written by Christopher Thomas.
# This copies fresh versions of the NeuroCam script from a USB stick.
#
# Copyright (c) 2021 by Vanderbilt University. This work is released under
# the Creative Commons Attribution-ShareAlike 4.0 International License.

USERNAME=`whoami`

if [ ! -d /usb/neurocam-install ]
then

echo "###  USB key not mounted."

elif [ ! "$USERNAME" = "root" ]
then

echo "### This script must be run as root."

else

echo "###  Reinstalling NeuroCam."

cd ~

echo "-- Copying files."

# Update scripts.
rm -rf neurocam-scripts
cp -r /usb/neurocam-install/scripts neurocam-scripts

# Update utilities.
rm -rf neurocam-utils
cp -r /usb/neurocam-install/utils neurocam-utils
# Create symlinks.
# We need "utils" for debugging scripts to work.
rm -f utils
ln -s neurocam-utils utils


# Update and reinstall code.

rm -rf neurocam-code
mkdir neurocam-code

OLDDIR=`pwd`
cd neurocam-code

# FIXME - We should only have one archive. Iterate just in case.
for F in /usb/neurocam-install/neurocam-code-*.tar
do
tar -xvf $F 1>/dev/null
done

cd $OLDDIR

echo "-- Reinstalling NeuroCam."

cd neurocam-code

rm -f www
ln -s /var/www/html www

./copyweb.sh

cd ~

echo "-- Committing changes to disk."

sync

echo "-- Done."

fi

# This is the end of the file.
