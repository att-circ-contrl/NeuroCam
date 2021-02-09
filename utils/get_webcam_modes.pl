#!/usr/bin/perl
# This fetches lsusb data for webcams, and reports supported sizes/fps.
# Written by Christopher Thomas.
#
# Usage:  get_webcam_modes (options)
#
# Options:
# --help           Displays this screen.
# --device=BB:DD   Queries bus BB, device DD.
#
# By default, this program displays information for all webcams.
#


#
# Includes

use strict;



#
# Functions


# Reads and processes command-line arguments.
# No arguments.
# Returns a pointer to a configuration hash, or undef if we should abort.

sub ProcessArgs
{
  my ($options_p);
  my ($thisarg);
  my ($is_ok);

  $options_p = {};
  $is_ok = 1;

  foreach $thisarg (@ARGV)
  {
    if ($thisarg =~ m/^--help/)
    {
      $is_ok = 0;
    }
    elsif ($thisarg =~ m/^--device=(\d+:\d+)$/)
    {
      $$options_p{usbaddr}=$1;
    }
    else
    {
      print "###  Unknown option \"$thisarg\".\n";
      $is_ok = 0;
    }
  }

  if (!$is_ok)
  {
    $options_p = undef;
  }

  return $options_p;
}



# Fetches a list of USB webcam devices.
# Arg 0 points to the options hash.
# Returns a pointer to a device hash mapping "bus:device" addresses to names.

sub GetUSBDeviceList
{
  my ($options_p, $devlist_p);
  my (@usblist, $thisline);
  my ($busid, $devid, $name, $thiskey, $forcekey);

  $options_p = $_[0];
  $devlist_p = {};

  if (!(defined $options_p))
  {
    print "### [GetUSBDeviceList]  Bad arguments.\n";
  }
  else
  {
    @usblist = `lsusb`;

    $forcekey = $$options_p{usbaddr};
    if (defined $forcekey)
    {
      if ($forcekey =~ m/(\d+):(\d+)/)
      {
        $forcekey = sprintf('%03d:%03d', $1, $2);
      }
      else
      {
        print "### [GetUSBDeviceList]  Unable to parse \"$forcekey\".\n";
        $forcekey = undef;
      }
    }

    foreach $thisline (@usblist)
    {
      chomp($thisline);

      if ($thisline =~ m/Bus\s+(\d+)\s+Device\s+(\d+):\s+ID\s+\S+\s+(.*\S)/)
      {
        $busid = $1;
        $devid = $2;
        $name = $3;

        $thiskey = sprintf('%03d:%03d', $busid, $devid);

        if (defined $forcekey)
        {
          # Only add the requested device.
          # Add it no matter what it is, though.
          if ($thiskey eq $forcekey)
          {
            $$devlist_p{$thiskey} = $name;
          }
        }
        else
        {
          # Add all webcam devices.
          if (ConfirmWebcam($thiskey))
          {
            $$devlist_p{$thiskey} = $name;
          }
        }
      }
      else
      {
        print "### [GetUSBDeviceList] Couldn't parse USB line:\n\""
          . $thisline . "\"\n";
      }
    }
  }

  return $devlist_p;
}



# Confirms that a USB device is a webcam.
# Arg 0 is a string of the form "bus id:device id".
# Returns 1 if this is a webcam and 0 if not.

sub ConfirmWebcam
{
  my ($usbdevid, $is_webcam);
  my (@usbdetails, $thisline);

  $usbdevid = $_[0];
  $is_webcam = 0;

  if (!(defined $usbdevid))
  {
    print "### [ConfirmWebcam]  Bad arguments.\n";
  }
  else
  {
    @usbdetails = `lsusb -s $usbdevid -v 2>/dev/null`;

    foreach $thisline (@usbdetails)
    {
      if ($thisline =~ m/VideoStreaming Interface Descriptor/)
      {
        $is_webcam = 1;
      }
    }
  }

  return $is_webcam;
}



# Queries and displays a device's video modes.
# Arg 0 is a string of the form "bus id:device id".
# Arg 1 is a human-readable device name.
# Arg 2 points to the options hash.
# No return value.

sub PrintDeviceModes
{
  my ($usbdevid, $devname, $options_p);
  my (@usbdetails, $thisline);
  my ($thiswidth, $thisheight, $thisformat, $thisrate, $defaultrate);

  $usbdevid = $_[0];
  $devname = $_[1];
  $options_p = $_[2];

  if (!( (defined $usbdevid) && (defined $devname) && (defined $options_p) ))
  {
    print "### [PrintDeviceModes]  Bad arguments.\n";
  }
  else
  {
    print "=== ($usbdevid)  $devname\n";

    @usbdetails = `lsusb -s $usbdevid -v 2>/dev/null`;

    $thiswidth = undef;
    $thisheight = undef;
    $thisformat = undef;
    $thisrate = undef;
    $defaultrate = undef;

    foreach $thisline (@usbdetails)
    {
      if ($thisline =~ m/VideoStreaming Interface Descriptor/)
      {
        # Start a new mode set.
        $thiswidth = undef;
        $thisheight = undef;
        $thisformat = undef
        $thisrate = undef;
        $defaultrate = undef;

        # Add whitespace.
        print "\n";
      }
      elsif ($thisline =~ m/\s+wWidth\s+(\d+)/)
      {
        $thiswidth = $1;
      }
      elsif ($thisline =~ m/\s+wHeight\s+(\d+)/)
      {
        $thisheight = $1;
      }
      elsif ($thisline =~ m/\s+bDescriptorSubtype\s+\d+\s+\(\S+_(\S+)\)/)
      {
        $thisformat = $1;
      }
      elsif ($thisline =~ m/\s+dwDefaultFrameInterval\s+(\d+)/)
      {
        $defaultrate = $1;
      }
      elsif ($thisline =~ m/\s+dwFrameInterval.*\s(\d+)/)
      {
        $thisrate = $1;

        if ( (defined $thiswidth) && (defined $thisheight) )
        {
          printf('  %9s    %2d Hz',
            sprintf('%dx%d', $thiswidth, $thisheight),
            int(0.5 + (10000000.0 / $thisrate))
          );

          if ((defined $defaultrate) && ($defaultrate == $thisrate))
          {
            print " *    $thisformat\n";
          }
          else
          {
            print "      $thisformat\n";
          }
        }
        else
        {
          print "### [PrintDeviceModes]  Incomplete mode information.\n";
        }
      }
    }
  }
}



#
# Main Program

my ($options_p);
my ($devlist_p, $thisdev);


$options_p = ProcessArgs();


if (!(defined $options_p))
{
  print << "Endofblock";

 This fetches lsusb data for webcams, and reports supported sizes/fps.
 Written by Christopher Thomas.

 Usage:  get_webcam_modes (options)

 Options:
 --help           Displays this screen.
 --device=BB:DD   Queries bus BB, device DD.

 By default, this program displays information for all webcams.

Endofblock
}
else
{
  $devlist_p = GetUSBDeviceList($options_p);

  foreach $thisdev (sort keys %$devlist_p)
  {
    PrintDeviceModes($thisdev, $$devlist_p{$thisdev}, $options_p);
  }
}


#
# This is the end of the file.
