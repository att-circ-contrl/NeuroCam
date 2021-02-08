#!/usr/bin/perl
# NeuroCam Installer - Helper script.
# Written by Christopher Thomas.
#
# Copyright (c) 2021 by Vanderbilt University. This work is released under
# the Creative Commons Attribution-ShareAlike 4.0 International License.


#
# Includes
#

use strict;
use warnings;



#
# Functions
#


# This looks for the device currently mounted in /usb and adds an 
# appropriate entry to /etc/fstab.
# If it can't find a mounted device, it makes plausible guesses.
# This creates two mountpoints, to handle EFI/non-EFI drive cases.
# No arguments.
# No return value.

sub DoTweakFstab
{
  my ($cmd, $result);
  my ($usbdrive);
  my (@fslines, $thisline);


  # First, identify what the USB drive device is.
  # This should either be sdb (one hard drive) or sdc (two hard drives).

  $usbdrive = undef;

  # See if we have anything mounted in /usb. Use that if so.

  $result = `grep usb /etc/mtab`;
  if ($result =~ m/^\s*(\/dev\/\S+?)\d+\s+\/usb\s+/)
  {
    $usbdrive = $1;
# FIXME - Diagnostics.
print "== Detected mounted USB device ($usbdrive).\n";
  }

  # If we don't have any usb devices mounted, check fstab.
  # Try sdb if that isn't a hard drive. Try sdc if that isn't a hard drive.
  # If both of those are hard drives, give up.
  # Ignore usb mountpoints in fstab - we're removing/changing those.

  if (!(defined $usbdrive))
  {
    $result = `grep sdb1 /etc/fstab`;

    if ( ($result =~ m/usb/) || (!($result =~ m/sdb1/)) )
    { $usbdrive = '/dev/sdb'; }
    else
    {
      $result = `grep sdc1 /etc/fstab`;

      if ( ($result =~ m/usb/) || (!($result =~ m/sdc1/)) )
      { $usbdrive = '/dev/sdc'; }
    }
# FIXME - Diagnostics.
if (defined $usbdrive)
{ print "== Guessed USB device ($usbdrive).\n"; }
  }

  # If we couldn't find the USB drive device, complain.
  if (!(defined $usbdrive))
  {
    print "###  Couldn't identify USB drive device.\n";
  }



  # Second, edit /etc/fstab.
  # Remove /usb and /usb2 if they're present.
  # Add /usb and /usb2 if we succeeded in finding the usb device name.

  if (!( open(INFILE, "</etc/fstab") ))
  {
    print "###  Unable to read from \"/etc/fstab\".\n";
  }
  else
  {
    @fslines = <INFILE>;
    close(INFILE);

    if (!( open(OUTFILE, ">/etc/fstab") ))
    {
      print "###  Unable to write to \"/etc/fstab\".\n";
    }
    else
    {
      # Copy existing entries, stripping usb drive mountpoints if present.
      foreach $thisline (@fslines)
      {
        # NOTE - We're using a different delimiter, as the device name
        # contains "/".
        if ( ($thisline =~ m|\s/usb\s|) || ($thisline =~ m|\s/usb2\s|) )
        {
          # USB mountpoint. Silently strip this line.
        }
        elsif ($thisline =~ m/to run scripts off USB drives/)
        {
          # USB mounting comment. Silently strip this line.
        }
        else
        {
          # Copy this line.
          print OUTFILE $thisline;

          # Complain if it provides a duplicate definition of the USB drive.
          # NOTE - We're using a different delimiter, as the device name
          # contains "/".
          if ($thisline =~ m|$usbdrive|)
          {
            print ".. WARNING: USB device \"$usbdrive\" is already in fstab:\n";
            print $thisline;
          }
        }
      }

      # Add the usb drive mountpoints.
      if (defined $usbdrive)
      {
        print OUTFILE
"# NOTE - mount manually with \"-o exec\" to run scripts off USB drives.\n";
        print OUTFILE $usbdrive . "1\t/usb\tauto\tnoauto,user\t0\t0\n";
        print OUTFILE $usbdrive . "2\t/usb2\tauto\tnoauto,user\t0\t0\n";

        print '.. Added ' . $usbdrive . '1 and ' . $usbdrive
          . "2 to /etc/fstab as /usb and /usb2.\n";
      }

      # Done.
      close(OUTFILE);
      chmod oct('644'), '/etc/fstab';
    }

  }



  # Create the mountpoints if they don't already exist.

  if (!( -d "/usb" ))
  { $result = `mkdir /usb`; }

  if (!( -d "/usb2" ))
  { $result = `mkdir /usb2`; }


  # Done.
}



sub DoTweakApache
{
  my ($cmd, $result);
  my (@fdata, $thisline, $lidx);
  my ($saw_cgi, $need_write);


  # Enable the modules we want.
  # MIME should already be enabled. Enabling again doesn't hurt.
  # Disable "userdir" if it's enabled.

  print ".. Configuring Apache modules.\n";

  $result = `a2dismod userdir`;
  $result = `a2enmod cgi`;
  $result = `a2enmod mime`;


  # Edit the MIME config file to recognize ".cgi" as a file type.
  # This is normally present but commented out.

  if (!open(MIMEFILE, '</etc/apache2/mods-enabled/mime.conf'))
  {
    print "### Unable to read from /etc/apache2/mods-enabled/mime.conf.\n";
  }
  else
  {
    @fdata = ();
    @fdata = <MIMEFILE>;
    close(MIMEFILE);

    # FIXME - Blithely assume that there's only one "AddHandler cgi-script"
    # line.
    $saw_cgi = 0;
    $need_write = 0;

    for ($lidx = 0; defined ($thisline = $fdata[$lidx]); $lidx++)
    {
      if ($thisline =~ m/^(\s*)#(\s*AddHandler\s+cgi-script\s+\.cgi.*)/)
      {
        # This line was commented. Uncomment it.
        # NOTE - Remember that "." didn't grab the trailing newline.
        $fdata[$lidx] = $1 . $2 . "\n";
        $saw_cgi = 1;
        $need_write = 1;
      }
      elsif ($thisline =~ m/^\s*AddHandler\s+cgi-script\s+\.cgi/)
      {
        # CGI scripts are already enabled.
        $saw_cgi = 1;
        print ".. CGI handler is already configured.\n";
      }
    }

    # If we haven't seen an AddHandler line, add one.
    # FIXME - Kludging this by adding a newline rather than inserting a
    # new scalar.
    if (!$saw_cgi)
    {
      for ($lidx = 0; defined ($thisline = $fdata[$lidx]); $lidx++)
      {
        if ($thisline =~ m/^(\s*<\/IfModule\>.*)/)
        {
          # NOTE - Remember that "." didn't grab the trailing newline.
          $fdata[$lidx] = "\tAddHandler cgi-script .cgi\n" . $1 . "\n";
          $need_write = 1;
        }
      }
    }

    # Write the file back out again.
    if ($need_write)
    {
      if (!open(MIMEFILE, '>/etc/apache2/mods-enabled/mime.conf'))
      {
        print "### Unable to write to /etc/apache2/mods-enabled/mime.conf.\n";
      }
      else
      {
        print MIMEFILE @fdata;
        close(MIMEFILE);

        print ".. Wrote changes to /etc/apache2/mods-enabled/mime.conf.\n";
      }
    }
  }


  # Edit the CGI serving config file to serve from /var/www/html.

  if (!open(CGIFILE, '</etc/apache2/conf-enabled/serve-cgi-bin.conf'))
  {
    print "### Unable to read from /etc/apache2/conf-enabled/serve-cgi-bin.conf.\n";
  }
  else
  {
    @fdata = ();
    @fdata = <CGIFILE>;
    close(CGIFILE);

    $saw_cgi = 0;
    $need_write = 0;

    for ($lidx = 0; defined ($thisline = $fdata[$lidx]); $lidx++)
    {
      if ($thisline =~ m/^(.*<\s*Directory\s+")(.*?)("\s*>.*)$/)
      {
        $saw_cgi = 1;
        if ('/var/www/html' eq $2)
        {
          print ".. CGI directory is already configured.\n";
        }
        else
        {
          # NOTE - Remember that "." didn't grab the trailing newline.
          $fdata[$lidx] = $1 . '/var/www/html' . $3 . "\n";
          $need_write = 1;
        }
      }
    }

    if (!$saw_cgi)
    {
      # No way to recover from this, so let the user deal with it.
      print "### Couldn't find CGI serving directory in /etc/apache2/conf-enabled/serve-cgi-bin.conf.\n";
    }

    # Write the file back out again.
    if ($need_write)
    {
      if (!open(CGIFILE, '>/etc/apache2/conf-enabled/serve-cgi-bin.conf'))
      {
        print "### Unable to write to /etc/apache2/conf-enabled/serve-cgi-bin.conf.\n";
      }
      else
      {
        print CGIFILE @fdata;
        close(CGIFILE);

        print ".. Wrote changes to /etc/apache2/conf-enabled/serve-cgi-bin.conf.\n";
      }
    }
  }


  # Done.
}



#
# Main Program
#

my ($cmd, $result);

$result = `whoami`;
chomp $result;

if ($result ne 'root')
{
  print "### This script must be run as root.\n";
}
else
{
  DoTweakFstab();

  DoTweakApache();
}



#
# This is the end of the file.
#
