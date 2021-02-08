#!/bin/bash
# NeuroCam installer.
# Written by Christopher Thomas.
#
# Copyright (c) 2021 by Vanderbilt University. This work is released under
# the Creative Commons Attribution-ShareAlike 4.0 International License.

USERNAME=`whoami`

if [ ! "$USERNAME" = "root" ]
then

echo "### This script must be run as root."

else


# First pass: Make sure all necessary packages are installed.

echo "-- Updating existing packages."

apt-get --yes update
apt-get --yes upgrade

echo "-- Installing new packages."

apt-get --yes install libproc-daemon-perl
apt-get --yes install mplayer
apt-get --yes install v4l-utils
apt-get --yes install perlmagick
apt-get --yes install libav-tools
apt-get --yes install apache2
apt-get --yes install imagemagick
apt-get --yes install cu
apt-get --yes install openssh-server
apt-get --yes install exfat-fuse
apt-get --yes install exfat-utils


# Second pass: Perform what system tweaking we can via shell script.

echo "-- Updating permissions."

if ! grep -q neurocam-admin /etc/passwd
then

adduser neurocam-admin
echo "...Added neurocam-admin user."

fi

usermod --append --groups video,dialout,www-data neurocam-admin
usermod --append --groups video,dialout www-data

chmod u+s /sbin/mount.exfat-fuse
chmod u+s /sbin/shutdown
# FIXME - This replaces "shutdown" on Mint 18. Introduces security holes!
chmod u+s /bin/systemctl


# Set up the web directory.
# This should point to /data if possible.

if [ -e /data ]
then

if [ -e /var/www/html ]
then
# FIXME - Don't try to determine whether we already have a backup or
# whether we've already symlinked; just move the old dir/symlink to a
# new backup label.
mv /var/www/html /var/www/html-`date +%Y%m%d%H%M%S`
fi

ORIGDIR=`pwd`
cd /var/www
ln -s /data html
chmod 755 /data
cd $ORIGDIR

fi

# If we have the old Apache default page, move it to a different name.
if [ -e /var/www/html/index.html ] \
&& grep --silent -i apache /var/www/html/index.html
then

mv /var/www/html/index.html /var/www/html/index-apache.html
echo "...Moved default index.html to index-apache.html."

fi


# Third pass: Run the helper script to edit configuration files and 
# perform other shenanigans.

echo "-- Updating configuration."

if [ -e /usb/neurocam-install/scripts/do-install-helper.pl ]
then
/usb/neurocam-install/scripts/do-install-helper.pl
else
echo "### Can\'t find helper script /usb/neurocam-install/scripts/do-install-helper.pl."
fi


# Fourth pass: Install NeuroCam files.

echo "-- Installing NeuroCam files."

if [ -e /usb/neurocam-install/scripts/do-update.sh ]
then
/usb/neurocam-install/scripts/do-update.sh
else
echo "### Can\'t find update script /usb/neurocam-install/scripts/do-update.sh."
fi


# Fifth pass: Restart appropriate services.

echo "-- Restarting services."

/etc/init.d/apache2 restart

# FIXME - We might want to do a reboot just to be safe.
#shutdown -r now


# Done.

echo "-- Done."


fi

# This is the end of the file.
