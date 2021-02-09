#!/usr/bin/perl
#
# NeuroCam management script - Camera control library.
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
# Public Constants
#

# FIXME - Doing this the messy way. Anywhere that uses this needs to have
# a corresponding "our" declaration.

# These lists are sorted in descending order.
our (@NCAM_sizes_wanted, @NCAM_rates_wanted);

@NCAM_sizes_wanted =
(
  # Large sizes that we want for research.
  '1920x1440', '1920x1080',
  '1280x960', '1280x720',
  # Intermediate sizes that are usually supported.
  # 960 and 1024 are redundant, but it's rare to find 4:3 and 16:9
  # both supported for one horizontal resolution.
  '1024x768', '1024x576',
  '960x720', '960x540',
  # Small sizes useful for testing.
  '640x480', '640x360'
);

# FIXME - We take the minimum and maximum from this, but otherwise don't
# use it anywhere. Instead, we get the combined set of frame rates used
# by connected cameras.
# Webcams normally support 15, 20, 24, 25, and 30. Use multiples of these.
@NCAM_rates_wanted = ( 120, 100, 80, 60, 50, 40, 30, 24, 20, 15);



#
# Public Functions
#

# This looks for /dev/videoX devices and fetches metadata for them.
# No arguments.
# Returns a pointer to a hash of metadata hash pointers, indexed by dev name.

sub NCAM_GetCameraList
{
  my ($cameras_p);
  my ($cmd, $result);
  my ($thisdev);

  # Default to an empty hash.
  $cameras_p = {};


  # See what video devices exist.

  $cmd = 'ls --color=none /dev/video* 2>/dev/null';
  $result = `$cmd`;

  while ($result =~ m/(\/dev\/video\d+)(.*)/s)
  {
    $thisdev = $1;
    $result = $2;

    $$cameras_p{$thisdev} = NCAM_GetCameraMetadata($thisdev);
  }


  # Return the hash of camera metadata hashes.
  return $cameras_p;
}



# Looks up a device's name using lsusb.
# Arg 0 is the vendor ID to search for.
# Arg 1 is the device ID to search for.
# Returns a model string, or undef on error.

sub NCAM_LookUpVendorDevID
{
  my ($vendorid, $deviceid, $modelname);
  my ($result, $thisline);
  my ($thisvendor, $thisdevice, $thismodel);

  $modelname = undef;

  $vendorid = $_[0];
  $deviceid = $_[1];

  if ( (defined $vendorid) && (defined $deviceid) )
  {
    $result = `lsusb`;

    while ($result =~ m/(\S.*?)$(.*)/ms)
    {
      $thisline = $1;
      $result = $2;

      if ($thisline =~ m/: ID (\S\S\S\S):(\S\S\S\S) (.*\S)/)
      {
        $thisvendor = $1;
        $thisdevice = $2;
        $thismodel = $3;

        if ( ($thisvendor eq $vendorid) && ($thisdevice eq $deviceid) )
        {
          $modelname = $thismodel;
        }
      }
    }
  }

  return $modelname;
}



# Fetches metadata for one specific camera device.
# FIXME - This may be Logitech-specific! Test with other cameras.
# Arg 0 is the camera device name (/dev/videoX).
# Returns a metadata hash pointer.

sub NCAM_GetCameraMetadata
{
  my ($devname, $meta_p);
  my ($cmd, $result);
  my ($modelname);
  my ($thisline);
  my ($formatlist_p, $thisformat, $ratelist_p, $thisrate);
  my (@scratchlist);
  my (%formatswanted, $minrate, $maxrate);


  $devname = $_[0];
  $meta_p = {};

  if (defined $devname)
  {
    # Store the device name.

    $$meta_p{device} = $devname;


    # Initialize format lookup table and frame rate range.

    %formatswanted = ();
    foreach $thisformat (@NCAM_sizes_wanted)
    { $formatswanted{$thisformat} = 1; }

    $minrate = undef;
    $maxrate = undef;
    foreach $thisrate (@NCAM_rates_wanted)
    {
      if ( (!(defined $minrate)) || ($thisrate < $minrate) )
      { $minrate = $thisrate; }

      if ( (!(defined $maxrate)) || ($thisrate > $maxrate) )
      { $maxrate = $thisrate; }
    }


    # Get the model number.
    # FIXME - If we can decode the "Bus info" string usefully, we might
    # be able to get consistent camera ordering, but it doesn't seem to
    # relate to "lsusb" output.
    # This is a shame, because lsusb's vendor/model info is nicer.

    $$meta_p{model} = '--unknown--';
    $cmd = 'v4l2-ctl --device=' . $devname . ' --info';
    $result = `$cmd`;

    if ($result =~ m/Card type\s+:\s+(.*?)\s*$/m)
    {
      $modelname = $1;
      $$meta_p{model} = $modelname;

      # Sanity check: If this comes back "UVC Camera (vendor:device)",
      # see what lsusb says it is.
      if ($modelname =~ m/UVC Camera \((\S+):(\S+)\)/)
      {
        $modelname = NCAM_LookUpVendorDevID($1, $2);

        if (defined $modelname)
        {
          $$meta_p{model} = $modelname;
        }
      }
    }


    # Check for supported formats that we care about.

    $$meta_p{sizes} = {};
    $cmd = 'v4l2-ctl --device=' . $devname . ' --list-framesizes=MJPG';
    $result = `$cmd`;

    while ($result =~ m/(\d+x\d+)(.*)/s)
    {
      $thisformat = $1;
      $result = $2;

      if (defined $formatswanted{$thisformat})
      {
        $$meta_p{sizes}{$thisformat} = [];
      }
    }

    $formatlist_p = $$meta_p{sizes};
    foreach $thisformat (keys %$formatlist_p)
    {
      if ($thisformat =~ m/(\d+)x(\d+)/)
      {
        $cmd = 'v4l2-ctl --device=' . $devname
           . ' --list-frameintervals=width=' . $1
           . ',height=' . $2 . ',pixelformat=MJPG';
        $result = `$cmd`;

        $ratelist_p = $$formatlist_p{$thisformat};
        while ($result =~ m/(\d+)\.\d+\s+fps(.*)/s)
        {
          $thisrate = $1;
          $result = $2;

          if ( ($thisrate >= $minrate) && ($thisrate <= $maxrate) )
          {
            push @$ratelist_p, $thisrate;
          }
        }
      }
    }


    # Set the desired resolution to the largest available, at the
    # highest nominally-supported frame rate.

    $formatlist_p = $$meta_p{sizes};
    @scratchlist = NCAM_SortByResolution(keys %$formatlist_p);
    $$meta_p{desiredsize} = $scratchlist[0];
    # FIXME - If we have no modes we care about, there's no default mode.
    if (defined $$meta_p{desiredsize})
    {
      $ratelist_p = $$formatlist_p{$$meta_p{desiredsize}};
      @scratchlist = sort {$b <=> $a} @$ratelist_p;
      $$meta_p{desiredrate} = $scratchlist[0];
    }


    # Check for exposure control info.
    # Likewise for focus control info.
    # NOTE - These are not guaranteed to be present, especially focus!

    $$meta_p{exposure} = {};
    $$meta_p{focus} = { 'haveauto' => 0, 'havemanual' => 0 };

    $cmd = 'v4l2-ctl --device=' . $devname . ' --list-ctrls-menus';
    $result = `$cmd`;

    while ($result =~ m/(\S.*?)$(.*)/ms)
    {
      $thisline = $1;
      $result = $2;

      # Absolute exposure is an integer control.
      if ($thisline =~
  m/exposure_absolute.*min=(\d+)\s+max=(\d+)\s+step=(\d+)\s+default=(\d+)\s+value=(\d+)/)
      {
        $$meta_p{exposure}{min} = $1;
        $$meta_p{exposure}{max} = $2;
        $$meta_p{exposure}{step} = $3;
        $$meta_p{exposure}{default} = $4;
        $$meta_p{exposure}{currentval} = $5;

        # Save the _default_ exposure as the desired exposure.
        $$meta_p{desiredexp} = $$meta_p{exposure}{default};
      }

      # Automatic exposure is a menu control.
      # FIXME - Blithely assuming that it's the only menu control with
      # a description including the word "manual"!
      if ($thisline =~ m/(\d+):.*manual/i)
      {
        $$meta_p{exposure}{manual} = $1;
      }

      # Absolute focus is an integer control.
      if ($thisline =~
  m/focus_absolute.*min=(\d+)\s+max=(\d+)\s+step=(\d+)\s+default=(\d+)\s+value=(\d+)/)
      {
        $$meta_p{focus}{min} = $1;
        $$meta_p{focus}{max} = $2;
        $$meta_p{focus}{step} = $3;
        $$meta_p{focus}{default} = $4;
        $$meta_p{focus}{currentval} = $5;

        # Default to auto-focus.
        # NOTE - We may not have this!
        $$meta_p{desiredfocus} = 'auto';

        # Record the fact that we have manual focus control.
        $$meta_p{focus}{havemanual} = 1;
      }

      # If we have the ability to set auto-focus, record that.
      if ($thisline =~ m/focus_auto/)
      {
        $$meta_p{focus}{haveauto} = 1;
      }
    }
  }

  return $meta_p;
}



# Sets a camera's exposure (forcing manual mode as a side effect).
# This re-detects (and stores) the resulting exposure value, which may
# differ from the value requested.
# Arg 0 points to the camera's metadata hash.
# Arg 1 is the exposure value to set.
# Returns the actual exposure value set, or undef on error.

sub NCAM_SetExposure
{
  my ($meta_p, $exp_desired);
  my ($stepdiff);
  my ($cmd, $result);
  my ($exp_resulting);

  $meta_p = $_[0];
  $exp_desired = $_[1];

  $exp_resulting = undef;

  if ( (defined $meta_p) && (defined $exp_desired) )
  {
    # Sanity-check the requested exposure value.

    if ($exp_desired < $$meta_p{exposure}{min})
    { $exp_desired = $$meta_p{exposure}{min}; }
    if ($exp_desired > $$meta_p{exposure}{max})
    { $exp_desired = $$meta_p{exposure}{max}; }

    $stepdiff = $exp_desired - $$meta_p{exposure}{min};
    $stepdiff %= $$meta_p{exposure}{step};
    $exp_desired -= $stepdiff;

# FIXME - Diagnostics.
#print "-- Asked for exposure $exp_desired;";

    # Issue the request.
    # NOTE - Do this in two steps, just in case it needs it. Focus did.
    $cmd = 'v4l2-ctl --device=' . $$meta_p{device}
      . ' --set-ctrl exposure_auto=' . $$meta_p{exposure}{manual};
    $result = `$cmd`;
    $cmd = 'v4l2-ctl --device=' . $$meta_p{device}
      . ' --set-ctrl exposure_absolute=' . $exp_desired;
    $result = `$cmd`;

    # See what exposure we actually ended up with.
    $cmd = 'v4l2-ctl --device=' . $$meta_p{device} . ' --list-ctrls';
    $result = `$cmd`;

    if ($result =~ m/exposure_absolute.*?value=(\d+)/s)
    {
      $exp_resulting = $1;
      $$meta_p{exposure}{currentval} = $exp_resulting;

# FIXME - Diagnostics.
#print " got $exp_resulting.\n";
    }

# FIXME - Diagnostics.
#else { print " failed!\n"; }
  }

  return $exp_resulting;
}



# Sets a camera's focus (forcing auto/manual mode as a side effect).
# If 'auto' is specified, the mode is set to automatic.
# If a number is specified, the mode is set to manual.
# This re-detects (and stores) the resulting focus value, which may
# differ from the value requested.
# Arg 0 points to the camera's metadata hash.
# Arg 1 is the focus value to set.
# Returns the actual focus value set, or undef on error.

sub NCAM_SetFocus
{
  my ($meta_p, $focus_desired);
  my ($stepdiff);
  my ($cmd, $result);
  my ($focus_resulting);

  $meta_p = $_[0];
  $focus_desired = $_[1];

  $focus_resulting = undef;

  if ( (defined $meta_p) && (defined $focus_desired) )
  {
    if ( ($focus_desired =~ m/(\d+)/) && $$meta_p{focus}{havemanual} )
    {
      $focus_desired = $1;

      # Sanity-check the requested focus value.

      if ($focus_desired < $$meta_p{focus}{min})
      { $focus_desired = $$meta_p{focus}{min}; }
      if ($focus_desired > $$meta_p{focus}{max})
      { $focus_desired = $$meta_p{focus}{max}; }

      $stepdiff = $focus_desired - $$meta_p{focus}{min};
      $stepdiff %= $$meta_p{focus}{step};
      $focus_desired -= $stepdiff;
    }
    elsif ($focus_desired eq 'auto')
    {
      # Handle requests for "auto" gracefully even if we don't have hardware
      # support for auto-focus.
      # If we don't have _manual_ support either, fail.
      if (!$$meta_p{focus}{haveauto})
      {
        if ($$meta_p{focus}{havemanual})
        {
          $focus_desired = $$meta_p{focus}{default};
        }
        else
        {
          $focus_desired = 'bogus';
        }
      }
    }
    else
    {
      $focus_desired = 'bogus';
    }

# FIXME - Diagnostics.
#print "-- Asked for focus \"$focus_desired\";";


    # Issue the request.

    if ('auto' eq $focus_desired)
    {
      $cmd = 'v4l2-ctl --device=' . $$meta_p{device}
        . ' --set-ctrl focus_auto=1';
      $result = `$cmd`;
    }
    elsif ($focus_desired =~ m/\d+/)
    {
      # We have to do this in two steps.
      $cmd = 'v4l2-ctl --device=' . $$meta_p{device}
        . ' --set-ctrl focus_auto=0';
      $result = `$cmd`;
      $cmd = 'v4l2-ctl --device=' . $$meta_p{device}
        . ' --set-ctrl focus_absolute=' . $focus_desired;
      $result = `$cmd`;
    }
    else
    {
      # Bogus or unsatisfiable request.
      # Do nothing.
    }


    # See what we actually ended up with.
    $cmd = 'v4l2-ctl --device=' . $$meta_p{device} . ' --list-ctrls';
    $result = `$cmd`;

    # First record the manual focus value, if we have one.
    if ($result =~ m/focus_absolute.*?value=(\d+)/s)
    {
      $focus_resulting = $1;
      $$meta_p{focus}{currentval} = $focus_resulting;
    }

    # If we're in auto-focus mode, report that instead.
    if ($result =~ m/focus_auto.*?value=(\d+)/)
    {
      if (0 != $1)
      {
        $focus_resulting = 'auto';
        $$meta_p{focus}{currentval} = $focus_resulting;
      }
    }


# FIXME - Diagnostics.
#if (defined $focus_resulting)
#{ print " got $focus_resulting.\n"; }
#else { print " failed!\n"; }
  }

  return $focus_resulting;
}



# Performs a capture test from a camera.
# The first return value is 1 if capture was acceptable and 0 if not.
# Remaining return values are the number of good and dropped frames.
# FIXME - Good and bad frame counts might be mplayer-specific!
# Arg 0 points to the camera's metadata hash.
# Arg 1 is the desired resolution.
# Arg 2 is the desired frame rate.
# Returns (good/bad flag, processed frames, dropped frames).

sub NCAM_TestCapture
{
  my ($meta_p, $resolution, $framerate, $is_ok, $frames_good, $frames_bad);
  my ($width, $height);
  my ($cmd, $result);

# FIXME - Diagnostics switches and tuning parameters.
my ($use_files, $identify_files, $tattle_frames);
my ($number_of_times, $acquisition_seconds, $minimum_good_bad_ratio);
$use_files = 1;
$identify_files = 0;
$tattle_frames = 0;
$number_of_times = 1;
$acquisition_seconds = 5;
# FIXME - Tune the minium acceptable good/bad ratio for more forgiving tests.
$minimum_good_bad_ratio = 15;

  $meta_p = $_[0];
  $resolution = $_[1];
  $framerate = $_[2];

  $is_ok = 0;
  $frames_good = 0;
  $frames_bad = 0;

  if ( (defined $meta_p) && (defined $resolution) && (defined $framerate) )
  {
    if ($resolution =~ m/(\d+)x(\d+)/)
    {
      $width = $1;
      $height = $2;

# FIXME - Run this multiple times to avoid startup glitching.
my ($idx);
for ($idx = 0; $idx < $number_of_times; $idx++)
{

# FIXME - Set up and tear down a scratch directory for file outout.
if ($use_files)
{
$result = `rm -rf /tmp/vtemp`;
$result = `mkdir /tmp/vtemp`;
}

      # Try to capture 5 seconds' worth of frame data.
      $cmd = 'mplayer tv:// -tv device=' . $$meta_p{device}
        . ':width=' . $width . ':height=' . $height
        . ':outfmt=mjpeg:fps=' . $framerate
#        . ' -vo null'
# FIXME - Optionally use a scratch directory.
. ($use_files ? ' -vo jpeg:outdir=/tmp/vtemp' : ' -vo null')
# FIXME - Make this less than 5 seconds for testing.
        . ' -quiet -nosound -frames ' . int($framerate * $acquisition_seconds)
        . ' 2>/dev/null';
      $result = `$cmd`;

      # Sift through this for the benchmark information.
      if ($result =~
  m/(-?\d+) frames successfully processed, (-?\d+) frames dropped/s)
      {
        $frames_good = $1;
        $frames_bad = $2;
# FIXME - Diagnostics.
if ($tattle_frames)
{
print ".. $resolution\@$framerate: $frames_good:$frames_bad\n";
}

        if ( $frames_good > ($minimum_good_bad_ratio * $frames_bad) )
        {
          $is_ok = 1;
        }
      }

# FIXME - Check image resolution directly.
if ($use_files && $identify_files)
{
$result = `identify /tmp/vtemp/*0001.jpg`;
if ($result =~ m/(\d+x\d+)/)
{ print "  (image was $1)\n"; }
else
{ print "  (couldn't identify image)\n"; }
}

# FIXME - Tear down scratch directory.
if ($use_files)
{
$result = `rm -rf /tmp/vtemp`;
}

# End of multiple-times loop.
}
    }
  }

  return ($is_ok, $frames_good, $frames_bad);
}



# Lists the resolution/frame rate combinations a given exposure supports,
# for a given camera. Returns exposure to its old setting after probing.
# Arg 0 points to the camera's metadata hash.
# Arg 1 is the desired exposure setting.
# Returns a pointer to a hash of frame rate lists indexed by resolution.

sub NCAM_GetFormatsGivenExposure
{
  my ($meta_p, $exp_desired, $supported_p);
  my ($exp_old);
  my ($size_queue_p, $rate_queue_p, $probesize, $proberate);
  my ($supported_rates_p);
  my ($acceptable, $frames_good, $frames_bad);

  $supported_p = {};

  $meta_p = $_[0];
  $exp_desired = $_[1];

  if ( (defined $meta_p) && (defined $exp_desired) && (defined $supported_p) )
  {
    # Save the old exposure and set the new one.
    $exp_old = $$meta_p{exposure}{currentval};
    NCAM_SetExposure($meta_p, $exp_desired);

    # Walk through all resolution/rate combinations, testing each.
    $size_queue_p = $$meta_p{sizes};
    foreach $probesize (keys %$size_queue_p)
    {
      $rate_queue_p = $$size_queue_p{$probesize};
      # The rate queue is nominally already sorted in descending order.

      $supported_rates_p = [];

      # FIXME - BFI search. We _should_ a) stop when we get all frames
      # and b) try to _estimate_ the maximum speed to skip intermediates.

      # FIXME - Forcing descending order just in case this _isn't_ sorted.
      foreach $proberate (sort {$b <=> $a} @$rate_queue_p)
      {
        ($acceptable, $frames_good, $frames_bad) =
          NCAM_TestCapture($meta_p, $probesize, $proberate);

        if ($acceptable)
        {
          push @$supported_rates_p, $proberate;
        }
      }

      if (0 < int(@$supported_rates_p))
      {
        # We had at least one valid mode. Record this resolution.
        $$supported_p{$probesize} = $supported_rates_p;
      }
    }

    # Restore the old exposure.
    NCAM_SetExposure($meta_p, $exp_old);
  }

  return $supported_p;
}



# Returns the maximum exposure setting that works with a given resolution
# and frame rate. This may not exceed a specified input value.
# Arg 0 points to the camera's metadata hash.
# Arg 1 is the desired resolution.
# Arg 2 is the desired frame rate.
# Arg 3 is the maximum permitted exposure setting.
# Returns the resulting exposure setting, or undef if one couldn't be found.

sub NCAM_GetExposureGivenFormat
{
  my ($meta_p, $resolution, $framerate, $exp_cap, $exp_needed);
  my ($exp_old);
  my ($fence_min, $fence_max, $fence_probe);
  my ($acceptable, $frames_good, $frames_bad);

  # Cap the number of steps we use.
  # Otherwise fine-grained exposure could take forever to test.
  my ($max_steps, $step_count);
  $max_steps = 8;

  $exp_needed = undef;

  $meta_p = $_[0];
  $resolution = $_[1];
  $framerate = $_[2];
  $exp_cap = $_[3];

  if ( (defined $meta_p) && (defined $resolution) && (defined $framerate)
    && (defined $exp_cap) )
  {
    # Save the old exposure.
    $exp_old = $$meta_p{exposure}{currentval};


    # Do a binary search through available exposure settings.

    $fence_min = $$meta_p{exposure}{min};
    $fence_max = $$meta_p{exposure}{max};
    if ( ($exp_cap < $fence_max) && ($exp_cap > $fence_min) )
    {
      $fence_max = $exp_cap;
    }


    $fence_probe = ($fence_min + $fence_max) >> 1;
    for ($step_count = 0;
      ($step_count < $max_steps)
      && ($fence_probe != $fence_min) && ($fence_probe != $fence_max);
      $step_count++)
    {
      NCAM_SetExposure($meta_p, $fence_probe);

      ($acceptable, $frames_good, $frames_bad) =
        NCAM_TestCapture($meta_p, $resolution, $framerate);

      if ($acceptable)
      {
        # Record and perturb up.
        $exp_needed = $fence_probe;
        $fence_min = $fence_probe;
        $fence_probe = ($fence_probe + $fence_max) >> 1;
      }
      else
      {
        # Perturb down without recording.
        $fence_max = $fence_probe;
        $fence_probe = ($fence_probe + $fence_min) >> 1;
      }
    }


    # Restore the old exposure.
    NCAM_SetExposure($meta_p, $exp_old);
  }

  return $exp_needed;
}



# Grabs a single frame from a camera.
# NOTE - This takes considerably longer than one frame period (not real-time).
# Arg 0 points to the camera's metadata hash.
# Arg 1 is the desired resolution.
# Arg 2 is the filename to write to.
# Returns 1 if successful and 0 if not.

sub NCAM_GrabFrame
{
  my ($meta_p, $resolution, $outname, $is_ok);
  my ($width, $height);
  my ($cmd, $result);

  $meta_p = $_[0];
  $resolution = $_[1];
  $outname = $_[2];

  $is_ok = 0;

  if ( (defined $meta_p) && (defined $resolution) && (defined $outname) )
  {
    if ($resolution =~ m/(\d+)x(\d+)/)
    {
      $width = $1;
      $height = $2;

      # Set up and tear down a scratch directory for frames.

      $result = `rm -rf /tmp/vtemp`;
      $result = `mkdir /tmp/vtemp`;

      # Try to capture a single frame.
      # Frame rate doesn't really matter; set it to something common.

      $cmd = 'mplayer tv:// -tv device=' . $$meta_p{device}
        . ':width=' . $width . ':height=' . $height
        . ':outfmt=mjpeg:fps=15'
        . ' -vo jpeg:outdir=/tmp/vtemp'
        . ' -quiet -nosound -frames 1'
        . ' 2>/dev/null';
      $result = `$cmd`;

      # Check to see that we did get an image from this.

      $result = `identify /tmp/vtemp/*0001.jpg`;
      if ($result =~ m/(\d+x\d+)/)
      {
        $is_ok = 1;
      }

      # Move the file and tear down scratch directory.

      if ($is_ok)
      {
        $cmd = 'mv -f /tmp/vtemp/*0001.jpg ' . $outname;
        $result = `$cmd`;
      }

      $result = `rm -rf /tmp/vtemp`;
    }
  }

  return $is_ok;
}



# Grabs a single frame from a remote MJPEG stream.
# NOTE - This takes considerably longer than one frame period (not real-time).
# Arg 0 is the URL of the MJPEG stream. This should end with ".mjpg".
# Arg 1 is the filename to write to.
# Returns 1 if successful and 0 if not.

sub NCAM_GrabStreamFrame
{
  my ($url, $outname, $is_ok);
  my ($cmd, $result);

  $url = $_[0];
  $outname = $_[1];

  $is_ok = 0;

  if ( (defined $url) && (defined $outname) )
  {
    # Set up and tear down a scratch directory for frames.

    $result = `rm -rf /tmp/vtemp`;
    $result = `mkdir /tmp/vtemp`;

    # Try to capture a single frame.

    $cmd = 'mplayer -demuxer lavf ' . $url
      . ' -vo jpeg:outdir=/tmp/vtemp'
      . ' -quiet -nosound -frames 1'
      . ' 2>/dev/null';
    $result = `$cmd`;

    # Check to see that we did get an image from this.

    $result = `identify /tmp/vtemp/*0001.jpg`;
    if ($result =~ m/(\d+x\d+)/)
    {
      # FIXME - This would be a good time to save resolution info too.
      $is_ok = 1;
    }

    # Move the file and tear down scratch directory.

    if ($is_ok)
    {
      $cmd = 'mv -f /tmp/vtemp/*0001.jpg ' . $outname;
      $result = `$cmd`;
    }

    $result = `rm -rf /tmp/vtemp`;
  }

  return $is_ok;
}



# Sorts a list of resolutions in sensible order (descending).
# Arguments are the unsorted list (by value).
# Returns (by value) a list in sorted order.

sub NCAM_SortByResolution
{
  my ($thisres, $width, $height, @result);
  my ($hlut_p, $vlist_p);

  @result = ();

  $hlut_p = {};

  while (defined ($thisres = shift @_))
  {
    if ($thisres =~ m/(\d+)x(\d+)/)
    {
      $width = $1;
      $height = $2;

      $vlist_p = $$hlut_p{$width};
      if (!(defined $vlist_p))
      {
        $vlist_p = [];
        $$hlut_p{$width} = $vlist_p;
      }

      push @$vlist_p, $height;
    }
  }

  foreach $width (sort {$b <=> $a} keys %$hlut_p)
  {
    $vlist_p = $$hlut_p{$width};

    foreach $height (sort {$b <=> $a} @$vlist_p)
    {
      $thisres = $width . 'x' . $height;
      push @result, $thisres;
    }
  }

  return @result;
}



# Finds the resolution within a list that's closest to a given resolution.
# Arg 0 is the resolution to look for.
# Remaining arguments are an unsorted list (by value).
# Returns an appropriate resolution from the list.

sub NCAM_FindClosestResolution
{
  my ($desired, $result);
  my ($thiserr, $besterr);
  my ($thisres);
  my ($thiswidth, $thisheight, $wantwidth, $wantheight);
  my ($bigwidth, $smallwidth, $bigheight, $smallheight);

  $desired = shift @_;
  $result = undef;

  if ( (defined $desired) && (defined $_[0]) )
  {
    if ($desired =~ m/(\d+)x(\d+)/)
    {
      $wantwidth = $1;
      $wantheight = $2;

      $besterr = undef;

      foreach $thisres (@_)
      {
        if ($thisres =~ m/(\d+)x(\d+)/)
        {
          $thiswidth = $1;
          $thisheight = $2;

          # Overlay the rectangles; non-overlapping area is the error.
          # NOTE - For wildly different sizes, this favours small resolutions.

          $thiserr = undef;

          ($smallwidth, $bigwidth) =
            sort {$a <=> $b} ($thiswidth, $wantwidth);
          ($smallheight, $bigheight) =
            sort {$a <=> $b} ($thisheight, $wantheight);

          if ( (($thiswidth < $wantwidth) && ($thisheight < $wantheight))
            || (($thiswidth > $wantwidth) && ($thisheight > $wantheight)) )
          {
            # Strictly overlapping.
            $thiserr = $bigwidth * $bigheight - $smallwidth * $smallheight;
          }
          else
          {
            # Partly overlapping.
            # Could also be exactly equal, but this'll still work for that.
            $thiserr = ($bigwidth - $smallwidth) * $smallheight
              + ($bigheight - $smallheight) * $smallwidth;
          }

          if (defined $thiserr)
          {
            if ( (!(defined $besterr)) || ($thiserr < $besterr) )
            {
              $result = $thisres;
              $besterr = $thiserr;
            }
          }

          # Done with this resolution.
        }
      }
    }
  }

  return $result;
}



#
# Main Program
#



# Report success.
1;



#
# This is the end of the file.
#
