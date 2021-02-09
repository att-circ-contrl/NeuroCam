#!/usr/bin/perl
#
# NeuroCam management script - Focus scan library.
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
# Constants
#

# Scratch filenames.
my ($frametmp);
$frametmp = '/tmp/frametemp.jpg';

# Diagnostics - saving focus sweep files.
my ($tattleframes, $tattleframeprefix);
$tattleframes = 1;
$tattleframeprefix = '/tmp/frametattle';


# Tuning parameters.

# We take a certain number of samples per sweep, and sub-range over the
# contiguous set of N that have the best total FOM.
my ($sweep_samples, $samples_kept);
$sweep_samples = 12;
$samples_kept = 4;

# We can do this in RGB space or monochrome.
# We can crop the edges of the image or not.
# We can apply a vignetting window or not.
# FIXME - A FIR to smooth out noise might be a good idea.
my ($use_rgb, $use_crop, $use_vignette);
$use_rgb = 0;
$use_crop = 1;
# FIXME - This isn't actually used.
$use_vignette = 0;



#
# Functions
#


# Calculates a focusing figure of merit for a given focus value.
# Larger FOMs are better. FOMs are floating-point values.
# FIXME - Using the frame-grab function, so rate isn't used!
# Arg 0 points to the camera's metadata hash.
# Arg 1 is the resolution to use.
# Arg 2 is the frame rate to use.
# Arg 3 is the exposure value to use.
# Arg 4 is the focus value to use.
# Returns the FOM for this focus value.

sub NCAM_CalcFocusFOM
{
  my ($meta_p, $size_wanted, $rate_wanted, $exp_wanted, $focus_wanted, $fom);
  my ($cmd, $result);
  my ($thisimage);
  my ($width, $height, $hidx, $vidx, $hofs, $vofs);
  my (%pixdata, @rgbvals);
  my ($dx, $dy, $count);
  my (@components, $thiscomp);

  $meta_p = $_[0];
  $size_wanted = $_[1];
  $rate_wanted = $_[2];
  $exp_wanted = $_[3];
  $focus_wanted = $_[4];

  $fom = undef;

  if ( (defined $meta_p) && (defined $size_wanted) && (defined $rate_wanted)
    && (defined $exp_wanted) && (defined $focus_wanted) )
  {
    NCAM_SetExposure($meta_p, $exp_wanted);
    NCAM_SetFocus($meta_p, $focus_wanted);

    # FIXME - Using the frame-grab function, so rate isn't used!
    $result = `rm -f $frametmp`;
    NCAM_GrabFrame($meta_p, $size_wanted, $frametmp);

    # FIXME - Making this able to handle multiple frames would be useful.
    # We'd have to be able to _grab_ a sequence of frames at a specified
    # frame rate to do that, though.


    # Read this image and store it in a form that's useful to us.
    # Optionally crop and/or vignette it during this process.
    # FIXME - Vignetting NYI.

    $thisimage = Image::Magick->new();
    $thisimage->Read($frametmp);

    $width = $thisimage->Get('width');
    $height = $thisimage->Get('height');

    # Tweak these values if we're cropping.
    $hofs = 0;
    $vofs = 0;
    if ($use_crop)
    {
      $hofs = $width >> 2;
      $vofs = $height >> 2;
      $width >>= 1;
      $height >>= 1;
    }

    %pixdata = ();

    for ($vidx = 0; $vidx < $height; $vidx++)
    {
      $pixdata{$vidx} = {};

      for ($hidx = 0; $hidx < $width; $hidx++)
      {
        # For JPEG input, this gives three components (no alpha).
        # The "normalize" flag forces a range of 0..1.
        @rgbvals = $thisimage->GetPixel(
          'x' => ($hidx + $hofs), 'y' => ($vidx + $vofs),
          'normalize' => 'true');

        if ($use_rgb)
        {
          # FIXME - Not sure if this is RGB or BGR.
          $pixdata{$vidx}{$hidx} =
            { 'r' => $rgbvals[0], 'g' => $rgbvals[1], 'b' => $rgbvals[2] };
        }
        else
        {
          # Use the magnitude.
          $pixdata{$vidx}{$hidx} =
            {
              'mag' => sqrt( ($rgbvals[0] * $rgbvals[0])
                + ($rgbvals[1] * $rgbvals[1]) + ($rgbvals[2] * $rgbvals[2]) )
            };
        }
      }
    }

    # Save a copy of this image if requested.
    if ($tattleframes)
    {
      $cmd = "cp $frametmp $tattleframeprefix"
        . sprintf('%05d', $focus_wanted) . ".jpg";
      $result = `$cmd`;
    }

    # Get rid of the raw image data.
    undef $thisimage;
    $result = `rm -f $frametmp`;


    # Extract a FOM from the image.

    # FIXME - Using first derivative. Noise may dominate this!

    $fom = 0.0;
    $count = 0;

    @components = ( 'mag' );
    if ($use_rgb)
    { @components = ( 'r', 'g', 'b' ); }

    for ($vidx = 1; $vidx < $height; $vidx++)
    {
      for ($hidx = 1; $hidx < $width; $hidx++)
      {
        foreach $thiscomp (@components)
        {
          $dx = $pixdata{$vidx}{$hidx}{$thiscomp}
            - $pixdata{$vidx}{$hidx - 1}{$thiscomp};
          $dy = $pixdata{$vidx}{$hidx}{$thiscomp}
            - $pixdata{$vidx - 1}{$hidx}{$thiscomp};

          # This adds two values in the range of 0..1 to the total.
          $fom += ($dx * $dx) + ($dy * $dy);
          $count += 2;
        }
      }
    }

    # Turn this back into a value in the range 0..1.
    if (0.1 < $count)
    { $fom /= $count; }

    # Done.
  }

  return $fom;
}



# Sweeps the focus range for a camera, to determine which focus value gives
# the sharpest results.
# Sweep data, in the form of a (focus value => figure of merit) hash, is
# also returned.
# FIXME - Using the frame-grab function, so rate isn't used!
# Arg 0 points to the camera's metadata hash.
# Arg 1 is the resolution to use.
# Arg 2 is the frame rate to use.
# Arg 3 is the exposure value to use.
# Returns (focus value, hash pointer).

sub NCAM_SweepFocus
{
  my ($meta_p, $size_wanted, $rate_wanted, $exp_wanted, $best_focus, $data_p);
  my (@focus_all, @focus_sweep, $thisfocus, $done);
  my ($fidx, $fcount, $fidmin, $fidmax, $fidstep);
  my ($thisfom, $bestfom);
  my ($cmd, $result);

  $meta_p = $_[0];
  $size_wanted = $_[1];
  $rate_wanted = $_[2];
  $exp_wanted = $_[3];

  $best_focus = undef;
  $data_p = {};

  if ( (defined $meta_p) && (defined $size_wanted) && (defined $rate_wanted)
    && (defined $exp_wanted) && (defined $$meta_p{focus}{havemanual}) )
  {
    # Clean out any previous tattle frames.
    if ($tattleframes)
    {
      $cmd = 'rm -f ' . $tattleframeprefix . '*';
      $result = `$cmd`;
    }

    # Build a list of all available focus values.
    @focus_all = ();
    for ($thisfocus = $$meta_p{focus}{min};
      $thisfocus <= $$meta_p{focus}{max};
      $thisfocus += $$meta_p{focus}{step})
    { push @focus_all, $thisfocus; }

    # Initialize sweep parameters.
    $data_p = {};
    $fcount = scalar(@focus_all);
    $fidmin = 0;
    $fidmax = $fcount - 1;
    $done = 0;

    # Keep narrowing down the sweep until we don't have new samples to check.
    while (!$done)
    {
      # Build this sweep's array index values.
      # Duplicate values are okay, so do this the simplest way.
      @focus_sweep = ();
      $fidstep = ($fidmax - $fidmin) / ($sweep_samples - 1);
      $fidstep += 0.00001;
      $fidx = $fidmin;
      for ($fcount = 0; $fcount < $sweep_samples; $fcount++)
      {
        push @focus_sweep, int($fidx);
        $fidx += $fidstep;
      }

      # Compute FOMs for the focus values for each index value.
      # If we see _no_ new values, we're done.
      $done = 1;
      foreach $fidx (@focus_sweep)
      {
        $thisfocus = $focus_all[$fidx];
        if (!(defined $$data_p{$thisfocus}))
        {
          # This is a new sample.
          $done = 0;
# FIXME - Diagnostics.
print "-- Checking \"$thisfocus\".\n";
          $$data_p{$thisfocus} = NCAM_CalcFocusFOM($meta_p,
            $size_wanted, $rate_wanted, $exp_wanted, $thisfocus);
        }
      }

      # Narrow the sweep range.
# FIXME - NYI.
# Leaving this alone results in no new samples, which is ok.
    }

    # Go through the results hash and find the focus value with the best FOM.
    # Do this in sorted order, so that results are consistent when we have
    # multiple settings with the same FOM.
    $bestfom = undef;
    $best_focus = undef;
    foreach $thisfocus (sort {$a <=> $b} keys %$data_p)
    {
      $thisfom = $$data_p{$thisfocus};

      if (!(defined $bestfom))
      {
        $bestfom = $thisfom;
        $best_focus = $thisfocus;
      }
      elsif ($thisfom > $bestfom)
      {
        $bestfom = $thisfom;
        $best_focus = $thisfocus;
      }
    }

    # Done.
  }

  return ($best_focus, $data_p);
}



#
# Main Program
#


# Report success.
1;



#
# This is the end of the file.
#
