#!/bin/bash
# NeuroCam Installer - Install key script.
# Written by Christopher Thomas.
# This copies appropriate install files to a USB stick.
# NOTE - This should be run from within the neurocam development tree.
# It'll go upstream 0-2 steps to find the root, then give up.
#
# Copyright (c) 2021 by Vanderbilt University. This work is released under
# the Creative Commons Attribution-ShareAlike 4.0 International License.


# Find the USB mountpoint.

# FIXME - Handle Mint's normal mountpoint.
USERNAME=`whoami`
USBDIR=`find /media/$USERNAME -maxdepth 1|head -2|tail -1`

# Fall back to my normal USB mountpoint.
if [ "$USBDIR" = "" ]
then
USBDIR=/usb
fi


# Find the dev tree's root directory.

DEVDIR=.

if [ ! -e $DEVDIR/neurocam-root-marker.txt ]
then
DEVDIR=..
fi

if [ ! -e $DEVDIR/neurocam-root-marker.txt ]
then
DEVDIR=../..
fi


# Proceed if the dev tree root directory and USB mount point are both valid.

if [ ! -e $DEVDIR/neurocam-root-marker.txt ]
then

echo "### Unable to find development directory."

elif [ ! -d $USBDIR ]
then

echo "### Unable to find USB mountpoint."

else

# Proceed only if we can create an install directory.

echo "-- Creating NeuroCam installer in $USBDIR/neurocam-install."

# Remove the old install directory.
if [ -d $USBDIR/neurocam-install ]
then
rm -rf $USBDIR/neurocam-install
fi

# Create a new install directory.
mkdir $USBDIR/neurocam-install

if [ ! -d $USBDIR/neurocam-install ]
then

echo "### Unable to create install directory in $USBDIR."

else


# We have an install directory at /usb/neurocam-install.
# Copy over the code, resources, utilities, and scripts.
# Code and resources should be tarballed, rather than copied.

OLDDIR=`pwd`
cd $DEVDIR/code

tar -cvf $USBDIR/neurocam-install/neurocam-code-`date +%Y%m%d%H%M`.tar \
	*.pl		\
	*.sh		\
	debug*		\
	assets		\
	animdata	\
	1>/dev/null

cd $OLDDIR

mkdir $USBDIR/neurocam-install/utils
cp $DEVDIR/utils/udp* $USBDIR/neurocam-install/utils

mkdir $USBDIR/neurocam-install/scripts
cp $DEVDIR/install-scripts/*.sh $USBDIR/neurocam-install/scripts
cp $DEVDIR/install-scripts/*.pl $USBDIR/neurocam-install/scripts


echo "-- Committing changes to USB device."

sync

echo "-- Done."

# End of install dir test.
fi


# End of test for USB mountpoint and dev tree root.
fi


# This is the end of the file.
