#!/usr/bin/perl
#
# NeuroCam management script - Post-processing library.
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
# Imported Constants
#

# FIXME - Doing this the messy way. Any imported variables need appropriate
# "our" declarations.

our (@NCAM_session_slots);
our ($stitchinfo_composite_p, $stitchslots_composite_p);
our ($stitchinfo_monitor_p);


#
# Public Constants
#

# FIXME - Doing this the messy way. Anywhere that uses this needs to have
# a corresponding "our" declaration.

# Flags indicating the presence of USB mounts/partitions.
our ($NCAM_flag_usb1, $NCAM_flag_usb2, $NCAM_flag_usbbogus);
$NCAM_flag_usb1 = 0x01;
$NCAM_flag_usb2 = 0x02;
$NCAM_flag_usbbogus = 0x80;



#
# Constants
#

# Repository metadata filename.

my ($metafilename);
$metafilename = 'metadata.txt';


# Tuning parameters for the timing analysis.

my ($lowres_width, $lowres_height);
my ($hpf_window);
my ($seek_window_frames);
my ($oset_bin_size, $oset_bin_group_radius);
my ($series_time_hint_weight);

# Downsampled resolution. Image will be stretched to match this aspect ratio.
# This should be as small as possible while still having the flash dominate
# its tile.
$lowres_width = 16;
$lowres_height = 12;

# High-pass filter decay window (frames).
# The strobe should be a one-frame event; two at most.
$hpf_window = 5;

# Number of frames to use for the initial analysis.
# This should be small enough to fit in memory without difficulty.
$seek_window_frames = 3000;

# Number of ms per offset bin.
$oset_bin_size = 10;
# Offset bins are grouped for a moving-window average, by +/- this amount.
$oset_bin_group_radius = 2;

# Hint weight for the time search.
# The normalized squared distance from the hint is multiplied by this value.
# To ignore everything outside 0.1x the range, set it to 100, for instance.
$series_time_hint_weight = 25;


# Kludge workarounds.

# This is needed due to Mint using an old version of PerlMagick.
my ($fake_greyscale);
$fake_greyscale = 1;

# ffmpeg command.
# Mint uses "avconv", a fork of ffmpeg.
my ($ffmpeg_cmd);
$ffmpeg_cmd = 'avconv';

# Video encoding flags.

# FIXME - Mint 18's ffmpeg doesn't like "libx264" or "libopenh264".
# Codec list says "mpeg2video" and "mpeg4" are ok.
# FIXME - Check this again with Mint 18's "avconv" fork!

# NOTE - Bit rate 200k looks awful, 1M looks decent but is only 2.5x
# compressed vs jpegs. 600k is ok for single streams but not composite.
# Going with 1M. Compression ratio is better than 2.5x for most streams.

# NOTE - 2021 videos are 1080p at 15 fps; 1M looks awful. JPEG rate is
# 2.5 MByte/sec (25 Mbit). 10 Mbit should be sufficient.

my ($vidsuffix, $vidcodec, $vidbitrate);

$vidsuffix = '.mp4';
$vidcodec = 'mpeg4';
$vidbitrate = '10M';

#$vidbitrate = '1000k';
#$vidcodec = 'libx264';

#$vidsuffix = '.mpeg';
#$vidcodec = 'mpeg2video';


# Debugging tattle switches.

my ($debug_tattle_timing);
$debug_tattle_timing = 1;

my ($debug_tattle_gpio);
$debug_tattle_gpio = 0;

my ($debug_tattle_timemath);
$debug_tattle_timemath = 0;

my ($debug_tattle_timeseries);
$debug_tattle_timeseries = 0;

my ($debug_write_timeseries_pics, $debug_time_scratchdir);
my ($debug_timepics_hpf);
$debug_write_timeseries_pics = 0;
$debug_time_scratchdir = '/tmp/timedebug';
# 0 for raw images, 1 for HPF images.
$debug_timepics_hpf = 0;



#
# Functions
#


# Reads a log file.
# This accepts a list of files that _may_ exist, and reads the first that
# _does_ exist.
# Arg 0 is the name of the repository directory containing the log files.
# Arg 1 points to a list of filenames to check.
# Returns a pointer to an array containing log file text, or undef on failure.

sub NCAM_ReadLogFile
{
  my ($repodir, $fnames_p, $logdata_p);
  my ($thisfname);

  $repodir = $_[0];
  $fnames_p = $_[1];

  $logdata_p = undef;

  if ( (defined $repodir) && (defined $fnames_p) )
  {
    foreach $thisfname (@$fnames_p)
    {
      $thisfname = $repodir . '/' . $thisfname;

      if ( (!(defined $logdata_p)) && (-e $thisfname) )
      {
        if (!open(INFILE, "<$thisfname"))
        {
          print STDERR
  "### [NCAM_ReadLogFile]  Unable to read from \"$thisfname\".\n";
        }
        else
        {
          $logdata_p = [];
          @$logdata_p = <INFILE>;
          close(INFILE);
        }
      }
    }
  }

  return $logdata_p;
}



# Merges events from two logs into one log.
# This can be used to sort a log by giving an empty array for one argument.
# Arg 0 points to an array of log strings.
# Arg 1 points to an array of log strings.
# Returns a pointer to a merged array of log strings.

sub NCAM_MergeLogs
{
  my ($firstlog_p, $secondlog_p, $newlog_p);
  my (%linehash, $thisline, $lasttime, $thistime, $thislist_p);

  $firstlog_p = $_[0];
  $secondlog_p = $_[1];

  $newlog_p = undef;

  if ( (defined $firstlog_p) && (defined $secondlog_p) )
  {
    # Add events from each log to the line hash.
    # NOTE - Events without timestamps are assigned the previous timestamp.
    # Any given timestamp may have multiple events.
    # The earliest timestamp should be (0 - worst-case timing shift).

    %linehash = ();

    # First log.

    $lasttime = -1000000;
    foreach $thisline (@$firstlog_p)
    {
      $thistime = $lasttime;
      if ($thisline =~ m/^\((\d+)\)/)
      { $thistime = $1; }

      $lasttime = $thistime;

      # Each hash bucket holds a _list_ of events.

      $thislist_p = $linehash{$thistime};

      if (!(defined $thislist_p))
      {
        $thislist_p = [];
        $linehash{$thistime} = $thislist_p;
      }

      push @$thislist_p, $thisline;
    }

    # Second log.

    $lasttime = -1000000;
    foreach $thisline (@$secondlog_p)
    {
      $thistime = $lasttime;
      if ($thisline =~ m/^\((\d+)\)/)
      { $thistime = $1; }

      $lasttime = $thistime;

      # Each hash bucket holds a _list_ of events.

      $thislist_p = $linehash{$thistime};

      if (!(defined $thislist_p))
      {
        $thislist_p = [];
        $linehash{$thistime} = $thislist_p;
      }

      push @$thislist_p, $thisline;
    }

    # Read out log events in sorted order.
    # Even if they don't have timestamps, they're _hashed_ by time.

    $newlog_p = [];

    foreach $thistime (sort {$a <=> $b} keys %linehash)
    {
      $thislist_p = $linehash{$thistime};

      foreach $thisline (@$thislist_p)
      {
        push @$newlog_p, $thisline;
      }
    }

    # Done.
  }

  return $newlog_p;
}



# Analyzes GPIO timing signals within a log file.
# Arg 0 points to an array containing the log file text.
# Returns (period, offset) of the timing signal, or undef if not found.

sub NCAM_AnalyzeGPIOTime
{
  my ($logfile_p, $period, $offset);
  my ($thisline);
  my (%gplist, $gptime, $gpname, $gpvalue, $gprec_p, $gpcount);
  my (@shortlist);
  my (%events);
  my ($thistime, $lasttime, $thisval);
  my (%deltas, $thisdelta_p, $thiscount, $thisavg);
  my (@symbols, $shortest);

  $logfile_p = $_[0];

  $period = undef;
  $offset = undef;

  if (defined $logfile_p)
  {
    # First pass: Isolate potential GPIO signals of interest.
    # These are "output" type registers that cycle between two values.
    # FIXME - This selection criterion will fail if we build complicated
    # GPIO units!
    %gplist = ();
    foreach $thisline (@$logfile_p)
    {
      if ($thisline =~ m/MSG gpio (\S+) O: (\S+)/)
      {
        $gpname = $1;
        # This can stay as a hex string; we don't actually interpret it.
        $gpvalue = $2;

        $gprec_p = $gplist{$gpname};
        if (!(defined $gprec_p))
        {
          $gprec_p = {};
          $gplist{$gpname} = $gprec_p;
        }

        # Keep a tally of the number of times each symbol appears.
        # FIXME - We aren't using this now, but it may be needed later.
        $gpcount = $$gprec_p{$gpvalue};
        if (!(defined $gpcount))
        { $gpcount = 0; }

        $gpcount++;
        $$gprec_p{$gpvalue} = $gpcount;
      }
    }

    # FIXME - Verbose diagnostics.
    if ( 0 && $debug_tattle_gpio )
    {
      print STDERR "-- GPIO candidate long-list:\n";
      foreach $gpname (sort keys %gplist)
      { print STDERR "  $gpname\n"; }
    }

    @shortlist = ();

    foreach $gpname (sort keys %gplist)
    {
      $gprec_p = $gplist{$gpname};
      if (2 == scalar(keys %$gprec_p))
      {
        push @shortlist, $gpname;
      }
    }

    # FIXME - Verbose diagnostics.
    if (0 && $debug_tattle_gpio)
    {
      print STDERR "-- GPIO candidate short-list:\n";
      foreach $gpname (@shortlist)
      { print STDERR "  $gpname\n"; }
    }

    # FIXME - Just take the first entry in the short list.
    # What we _should_ be doing is looking for matched symbol counts within
    # a candidate and use some other method to differentiate candidates.
    $gpname = $shortlist[0];


    # Proceed if we found a candidate.
    if (defined $gpname)
    {
      if ($debug_tattle_gpio)
      { print STDERR "-- GPIO timing signal is on \"$gpname\".\n"; }

      # Second pass: Figure out the pulse period, duration, and offset.
      # NOTE - This needs to be robust against dropped packets.

      # FIXME - The right way to do this is a Fourier analysis. Instead,
      # we'll use an ad-hoc approach that can be perturbed by missing packets.


      # Extract the event sequence.

      %events = ();
      foreach $thisline (@$logfile_p)
      {
        if ($thisline =~ m/^\((\d+)\).*MSG gpio (\S+) O: (\S+)/)
        {
          if ($2 eq $gpname)
          {
            $gptime = $1;
            $gpvalue = $3;

            $events{$gptime} = hex($gpvalue);
          }
        }
      }


      # Measure gap durations.

      %deltas = ();
      $lasttime = undef;

      foreach $thistime (sort {$a <=> $b} keys %events)
      {
        $thisval = $events{$thistime};

        if (defined $lasttime)
        {
          $thisdelta_p = $deltas{$thisval};
          if (!(defined $thisdelta_p))
          {
            $thisdelta_p = { 'first' => $thistime, 'count' => 0, 'avg' => 0 };
            $deltas{$thisval} = $thisdelta_p;
          }

          $$thisdelta_p{count}++;
          $$thisdelta_p{avg} += $thistime - $lasttime;
        }

        $lasttime = $thistime;
      }

      foreach $thisval (keys %deltas)
      {
        $thisdelta_p = $deltas{$thisval};
        if (0 < $$thisdelta_p{count})
        {
          $$thisdelta_p{avg} /= $$thisdelta_p{count};
        }
      }

      @symbols = sort {$a <=> $b} keys %deltas;


      # The period is the sum of the gap durations.
      # The shortest gap is the pulse.
      # Time zero is the _middle_ of that pulse.

      $period = 0;
      $shortest = undef;
      foreach $thisval (@symbols)
      {
        $period += $deltas{$thisval}{avg};

        if (!(defined $shortest))
        { $shortest = $thisval; }
        elsif ($deltas{$thisval}{avg} < $deltas{$shortest}{avg})
        { $shortest = $thisval; }
      }

      if ( (defined $shortest) && (0 < $period) )
      {
        # We've identified the symbol with the shortest gap _preceding_ it.
        # The first instance of this symbol is the _end_ of the synch pulse.

        $offset = $deltas{$shortest}{first} - 0.5 * $deltas{$shortest}{avg};
      }
      else
      {
        # We couldn't find enough pulses to extract timing.
        $period = undef;
        $offset = undef;
      }
    }
  }

  return ($period, $offset);
}



# Extracts a high-pass-filtered data series corresponding to one tile
# (one pixel of the thumbnailed image).
# Raw samples are normalized to (0..1). HPFd will be (-1..+1) at worst.
# Arg 0 points to the list of frame thumbnails (with metadata).
# Arg 1 is the tile index to use (pixel index in raster-scan order).
# Returns a pointer to an array of {time, rawval, hpfval} tuples.

sub NCAM_MakeHPFSeries
{
  my ($imagelist_p, $tileidx, $series_p);
  my ($hsize, $vsize, $hidx, $vidx);
  my ($thisrec_p, $thisimage, $thistime);
  my ($thisval, @pixvals);
  my ($lpfval, $oldcoeff, $newcoeff);

  $imagelist_p = $_[0];
  $tileidx = $_[1];

  $series_p = [];

  if ( (defined $imagelist_p) && (defined $tileidx)
    # Make sure we have at least one image.
    && (defined $$imagelist_p[0]) )
  {
    # Get image geometry.
    $thisrec_p = $$imagelist_p[0];
    $thisimage = $$thisrec_p{thumbnail};
    $hsize = $thisimage->Get('width');
    $vsize = $thisimage->Get('height');

    # Turn the tile index into pixel coordinates.
    $hidx = $tileidx % $hsize;
    $vidx = int((0.1 + $tileidx) / $hsize);

    # Walk through the image sequence extracting data for this pixel.
    # Don't normalize it, but do convert it to greyscale if it isn't already.

    $lpfval = undef;
    $newcoeff = 1.0 / $hpf_window;
    $oldcoeff = 1.0 - $newcoeff;

    foreach $thisrec_p (@$imagelist_p)
    {
      $thisimage = $$thisrec_p{thumbnail};
      $thistime = $$thisrec_p{time};

      # FIXME - I _think_ this is zero-based, but I'm not certain.
      @pixvals =
        $thisimage->GetPixel('x' => $hidx, 'y' => $vidx, 'normalize' => 'true');
      $thisval = $pixvals[0];
      if ($fake_greyscale)
      {
        # FIXME - Assuming this is RGB/BGR, not ARGB!
        # This should always be true for jpeg input.
        $thisval = sqrt( ($pixvals[0] * $pixvals[0])
          + ($pixvals[1] * $pixvals[1]) + ($pixvals[2] * $pixvals[2]) );
      }

      # Low-pass filter this value.
      if (!(defined $lpfval))
      {
        $lpfval = $thisval;
      }
      else
      {
        $lpfval *= $oldcoeff;
        $lpfval += $newcoeff * $thisval;
      }

      # Store the high-pass value (sample minus lpf) and time.
      push @$series_p,
        { 'time' => $thistime, 'rawval' => $thisval,
          'hpfval' => ($thisval - $lpfval) };
    }
  }

  return $series_p;
}



# Estimates the offset of the strobe signal within a data series.
# This also returns the "evidence" value for that offset, for comparison
# with other series.
# A hint and hint weight are provided. A weight of 0 ignores the hint.
# Evidence is penalized by the normalized squared distance from the hint,
# multiplied by the hint weight and maximum observed evidence value.
# Arg 0 points to an array of data series tuples.
# Arg 1 is the strobe period.
# Returns (offset, evidence).

sub NCAM_EstimateSeriesTimeReal
{
  my ($series_p, $period, $hint_value, $hint_weight, $offset, $evidence);
  my ($sample_p, $thistime, $thisval);
  my ($perquot, $bincount, $realbinsize, $binidx);
  my (@histogram, @histscratch);
  my ($bestbin, $bestval, $scanidx, $scanbin);
  my ($maxevidence, $thisdist, $maxdist, $weightcoeff, $hintbin);

  $series_p = $_[0];
  $period = $_[1];
  $hint_value = $_[2];
  $hint_weight = $_[3];

  $offset = undef;
  $evidence = undef;

  if ( (defined $series_p) && (defined $period)
    && (defined $hint_value) && (defined $hint_weight) )
  {
    # Initialize the histogram.
    # This is actually a Hough-style evidence table, not a histogram.

    # The bin size should evenly divide the period.
    $bincount = int($period / $oset_bin_size);
    $realbinsize = (0.001 + $period) / $bincount;

    @histogram = ();
    for ($binidx = 0; $binidx < $bincount; $binidx++)
    { $histogram[$binidx] = 0.0; }


    # Walk through samples, adding evidence to bins.

    foreach $sample_p (@$series_p)
    {
      $thistime = $$sample_p{time};
      $thisval = $$sample_p{hpfval};

      # The period is not necessarily an integer.
      # Do modulo arithmetic manually to handle this.
      $perquot = int($thistime / $period);
      $thistime -= $perquot * $period;

      # Figure out what bin we're in.
      # Bear in mind that the time is now non-integer.
      $binidx = int($thistime / $realbinsize);

      # Add this sample to the bin.
      # Evidence may be positive or negative; we don't care.
      $histogram[$binidx] += $thisval;
    }


    # Perform a moving-window average.
    # Extract the maximum uncorrected evidence value while we're at it.

    @histscratch = ();
    $maxevidence = undef;

    for ($binidx = 0; $binidx < $bincount; $binidx++)
    {
      $thisval = 0;

      for ($scanidx = -$oset_bin_group_radius;
        $scanidx <= $oset_bin_group_radius;
        $scanidx++)
      {
        $scanbin = ($binidx + $scanidx + $bincount) % $bincount;
        $thisval += $histogram[$scanbin];
      }

      $thisval /= (1 + $oset_bin_group_radius + $oset_bin_group_radius);

      $histscratch[$binidx] = $thisval;

      if (!(defined $maxevidence))
      { $maxevidence = $thisval; }
      elsif ($thisval > $maxevidence)
      { $maxevidence = $thisval; }
    }

    @histogram = @histscratch;


    # Apply a distance-based penalty based on the hint value.
    # The penalty scales with the square of the distance from the hint.
    # At the maximum possible distance, it's (hint weight) * (max evidence).

    $maxdist = 0.5 * $bincount;

    $weightcoeff = $hint_weight / ($maxdist * $maxdist);
    if (1.0e-6 < $maxevidence)
    { $weightcoeff /= $maxevidence; }

    # Do non-integer modulo arithemetic manually.
    $perquot = int($hint_value / $period);
    $thistime = $hint_value - $perquot * $period;
    $hintbin = int($thistime / $realbinsize);

    # Apply the penalty.
    for ($binidx = 0; $binidx < $bincount; $binidx++)
    {
      $thisdist = ($binidx + $bincount - $hintbin) % $bincount;
      if ($thisdist > $maxdist)
      { $thisdist = $bincount - $thisdist; }

      $histogram[$binidx] -= $thisdist * $thisdist * $weightcoeff;
    }


    # Find the bin with the most evidence.

    $bestbin = undef;
    $bestval = undef;

    if ($debug_tattle_timeseries)
    { print STDERR "-- Offset histogram/evidence table:\n"; }

    for ($binidx = 0; $binidx < $bincount; $binidx++)
    {
      $thisval = $histogram[$binidx];

      if (!( (defined $bestbin) && (defined $bestval) ))
      {
        $bestbin = $binidx;
        $bestval = $thisval;
      }
      elsif ($thisval > $bestval)
      {
        $bestbin = $binidx;
        $bestval = $thisval;
      }

      if ($debug_tattle_timeseries)
      {
        print STDERR sprintf(' %4d: %5.2f', $binidx, $thisval);
        if ( 0 == (($binidx + 1) % 6) )
        { print STDERR "\n"; }
      }
    }

    if ( $debug_tattle_timeseries && (0 != ($bincount % 6)) )
    { print STDERR "\n"; }

    # Convert this back into an offset.
    # Align this with the _middle_ of the bin.

    $offset = ($bestbin + 0.5) * $realbinsize;
    $evidence = $bestval;
  }


  return ($offset, $evidence);
}



# Estimates the offset of the strobe signal within a data series.
# This also returns the "evidence" value for that offset, for comparison
# with other series.
# A blind estimate is performed, with no offset hint.
# Arg 0 points to an array of data series tuples.
# Arg 1 is the strobe period.
# Returns (offset, evidence).

sub NCAM_EstimateSeriesTimeBlind
{
  my ($series_p, $period, $offset, $evidence);

  $series_p = $_[0];
  $period = $_[1];

  $offset = undef;
  $evidence = undef;

  if ( (defined $series_p) && (defined $period) )
  {
    ($offset, $evidence) =
      NCAM_EstimateSeriesTimeReal($series_p, $period, 0.0, 0.0);
  }

  return ($offset, $evidence);
}



# Estimates the offset of the strobe signal within a data series.
# This also returns the "evidence" value for that offset, for comparison
# with other series.
# This accepts an offset hint, which is given a preconfigured weight.
# Arg 0 points to an array of data series tuples.
# Arg 1 is the strobe period.
# Arg 2 is the expected offset value.
# Returns (offset, evidence).

sub NCAM_EstimateSeriesTimeHint
{
  my ($series_p, $period, $hint_offset, $offset, $evidence);

  $series_p = $_[0];
  $period = $_[1];
  $hint_offset = $_[2];

  $offset = undef;
  $evidence = undef;

  if ( (defined $series_p) && (defined $period) && (defined $hint_offset) )
  {
    ($offset, $evidence) =
      NCAM_EstimateSeriesTimeReal($series_p, $period,
        $hint_offset, $series_time_hint_weight);
  }

  return ($offset, $evidence);
}



# Calculates an estimate of strobe offset within a set of frames.
# This is done without any previous analysis of the image stream.
# FIXME - The offset is assumed to be constant within this frame set!
# Arg 0 points to the list of frame thumbnails (with metadata).
# Arg 1 is the strobe period extracted from GPIO communication.
# Returns (offset, tile id).

sub NCAM_EstimateStreamTimeBlind
{
  my ($imagelist_p, $gpio_period, $image_offset, $besttile);
  my ($hsize, $vsize, $hidx, $vidx, $tileidx);
  my (%tileseries);
  my ($thisoffset, $bestoffset, $thisevidence, $bestevidence);
  my ($thisrec_p, $thisimage);

  $imagelist_p = $_[0];
  $gpio_period = $_[1];

  $image_offset = undef;
  $besttile = undef;

  if ( (defined $imagelist_p) && (defined $gpio_period)
    # Make sure we have at least one image.
    && (defined $$imagelist_p[0]) )
  {
    # Get image geometry.
    $thisrec_p = $$imagelist_p[0];
    $thisimage = $$thisrec_p{thumbnail};
    $hsize = $thisimage->Get('width');
    $vsize = $thisimage->Get('height');

    # First pass: extract per-tile streams and high-pass filter them.

    %tileseries = ();

    $tileidx = 0;
    for ($vidx = 0; $vidx < $vsize; $vidx++)
    {
      for ($hidx = 0; $hidx < $hsize; $hidx++)
      {
        $tileseries{$tileidx} = NCAM_MakeHPFSeries($imagelist_p, $tileidx);
        $tileidx++;
      }
    }


    # FIXME - Diagnostics.
    # Write all of the sequences to files as greyscale images.
    # Convert this to an animation as well.

    if ($debug_write_timeseries_pics)
    {
      my ($cmd, $result);
      my ($sampidx);
      my ($fname);
      my ($thisval);

      $cmd = 'rm -rf ' . $debug_time_scratchdir;
      $result = `$cmd`;
      $cmd = 'mkdir ' . $debug_time_scratchdir;
      $result = `$cmd`;

      for ($sampidx = 0; defined $tileseries{0}[$sampidx]; $sampidx++)
      {
        $fname = sprintf('%s/grey%04d.pgm', $debug_time_scratchdir, $sampidx);
        if (open(PFILE, ">$fname"))
        {
          print PFILE "P2\n$hsize $vsize\n255\n";

          for ($vidx = 0; $vidx < $vsize; $vidx++)
          {
            for ($hidx = 0; $hidx < $hsize; $hidx++)
            {
              $tileidx = ($vidx * $hsize) + $hidx;

              if ($debug_timepics_hpf)
              {
                # NOTE - rawval is 0..1, hpfval is -1..+1.
                $thisval = $tileseries{$tileidx}[$sampidx]{hpfval};
                $thisval = int( (1.0 + $thisval) * 0.5 * 256.0 );
              }
              else
              {
                # NOTE - rawval is 0..1, hpfval is -1..+1.
                $thisval = $tileseries{$tileidx}[$sampidx]{rawval};
                $thisval = int( $thisval * 256.0 );
              }

              if (0 > $thisval)
              { $thisval = 0; }
              elsif (255 < $thisval)
              { $thisval = 255; }

              print PFILE sprintf('%4d', $thisval);
            }
            print PFILE "\n";
          }

          close(PFILE);
        }
      }

      $cmd = $ffmpeg_cmd . ' -r 30 -f image2 -i ' . $debug_time_scratchdir
        . '/grey%04d.pgm -an -b 100k -vcodec mpeg4 -pix_fmt yuv420p '
        . $debug_time_scratchdir . '/grey.mp4';
      $result = `$cmd`;
    }


    # Second pass: Evaluate each series, picking the one with the best
    # evidence of its conclusion.

    $bestoffset = undef;
    $bestevidence = undef;
    $besttile = undef;

    if ($debug_tattle_timemath)
    { print STDERR "-- Tile strobe magnitudes:\n"; }

    foreach $tileidx (sort {$a <=> $b } keys %tileseries)
    {
      ($thisoffset, $thisevidence) =
        NCAM_EstimateSeriesTimeBlind($tileseries{$tileidx}, $gpio_period);

      if (!( (defined $bestoffset) && (defined $bestevidence) ))
      {
        $bestoffset = $thisoffset;
        $bestevidence = $thisevidence;
        $besttile = $tileidx;
      }
      elsif ($thisevidence > $bestevidence)
      {
        $bestoffset = $thisoffset;
        $bestevidence = $thisevidence;
        $besttile = $tileidx;
      }

      if ($debug_tattle_timemath)
      {
        print STDERR sprintf(' %4.2f', $thisevidence);

        if ( 0 == (($tileidx + 1) % $hsize) )
        { print STDERR "\n"; }
      }
    }

    $image_offset = $bestoffset;
  }

  return ($image_offset, $besttile);
}



# Calculates an estimate of strobe offset within a set of frames.
# The tile to test and an expected approximate offset are provided as hints.
# FIXME - The offset is assumed to be constant within this frame set!
# Arg 0 points to the list of frame thumbnails (with metadata).
# Arg 1 is the tile to check.
# Arg 2 is the strobe period extracted from GPIO communication.
# Arg 3 is the expected offset value.
# Returns the calculated offset.

sub NCAM_EstimateStreamTimeHint
{
  my ($imagelist_p, $tileidx, $gpio_period, $hint_offset, $image_offset);
  my ($tileseries_p);
  my ($evidence);

  $imagelist_p = $_[0];
  $tileidx = $_[1];
  $gpio_period = $_[2];
  $hint_offset = $_[3];

  $image_offset = $hint_offset;

  if ( (defined $imagelist_p) && (defined $tileidx)
    && (defined $gpio_period) && (defined $hint_offset)
    # Make sure we have at least one image.
    && (defined $$imagelist_p[0]) )
  {
    # Extract and high-pass-filter the desired tile's stream.
    $tileseries_p = NCAM_MakeHPFSeries($imagelist_p, $tileidx);

    # Evaluate the series to find the offset, with bias towards offsets
    # close to the hint value.
    ($image_offset, $evidence) =
      NCAM_EstimateSeriesTimeHint($tileseries_p, $gpio_period, $hint_offset);
  }

  return $image_offset;
}



# Adjusts timestamps for a single video feed.
# Arg 0 is the repository directory name.
# Arg 1 is the name of the feed.
# Arg 2 points to an array containing the uncorrected log file text.
# Returns a pointer to a hash mapping uncorrected lines to corrected lines.

sub NCAM_AdjustTimestampsOneStream
{
  my ($repodir, $feed, $logfile_p, $corrections_p);
  my ($lidx, $thisline, $thistime, $thislabel, $thisnum, $thisfile);
  my ($thisimage, $imagerec_p, $imagelist_p, $imagecount);
  my ($gpio_period, $gpio_offset, $imgperiod, $imgoffset, $tilehint);
  my ($firstlist_p, $secondlist_p, $halfsize, $newline);

  $repodir = $_[0];
  $feed = $_[1];
  $logfile_p = $_[2];

  $corrections_p = {};

  if ( (defined $repodir) && (defined $feed) && (defined $logfile_p) )
  {
    # Extract the timing signal's period and offset.
    # FIXME - Doing this for every feed is redundant.
    ($gpio_period, $gpio_offset) = NCAM_AnalyzeGPIOTime($logfile_p);

    if (!( (defined $gpio_period) && (defined $gpio_offset) ))
    {
      if ($debug_tattle_timing)
      {
        print STDERR "-- [$feed]  Unable to extract GPIO timing signal.\n";
      }
    }
    else
    {
      # FIXME - Diagnostics.
      if ($debug_tattle_timing)
      {
        print STDERR
          sprintf('-- [%s]  GPIO period:  %.1f ms    Offset: %.1f ms' . "\n",
            $feed, $gpio_period, $gpio_offset);
      }


      # First pass: Get the first few thousand frames and extract approximate
      # timing parameters.

      $imagecount = 0;
      $imagelist_p = [];

      for ($lidx = 0;
        ($imagecount < $seek_window_frames)
          && (defined ($thisline = $$logfile_p[$lidx]));
        $lidx++)
      {
        if ($thisline =~ m/^\((\d+)\)\s+\[(\w+)\]\s+frame\s+(\d+)\s+(\S+)/)
        {
          $thistime = $1;
          $thislabel = $2;
          $thisnum = $3;
          $thisfile = $4;

          if ($thislabel eq $feed)
          {
            # This is a frame that we care about.
            # Make a greyscale thumbnail and save it.

            $thisfile = $repodir . '/' . $thisfile;

# FIXME - Diagnostics.
if (!( ( -e $thisfile ) && ( -s $thisfile ) ))
{
print STDERR "-- Can't find \"$thisfile\"!\n";
}

            $imagecount++;

            $thisimage = Image::Magick->new();
            $thisimage->Read($thisfile);
# FIXME - "scale" forces box filtering and is fast.
# "resize" is slower even with box filtering.
            $thisimage->Scale(width=>$lowres_width, height=>$lowres_height);
#            $thisimage->Resize(width=>$lowres_width, height=>$lowres_height,
#              filter=>Box);

            if (!$fake_greyscale)
            {
# FIXME - This fails! Web says it's due to an older version installed.
              $thisimage->Grayscale();
            }

            # FIXME - Blindly trust that PerlMagick freed up the memory that
            # was being used for the original pixel data. Otherwise we may have
            # much higher memory demand than expected.

            $imagerec_p =
            {
              'time' => $thistime,
              'seqnum' => $thisnum,
              'fname' => $thisfile,
              'thumbnail' => $thisimage
            };

            push @$imagelist_p, $imagerec_p;

            undef $imagerec_p;
            undef $thisimage;
          }
        }
      }

      # Calculate an estimate of the timing parameters from this set of frames.
      # FIXME - The GPIO period is assumed to be accurate (a good assumption)
      # and the image stream's time shift is assumed to be constant (a bad
      # assumption, but it should hold within this window).
      ($imgoffset, $tilehint) =
        NCAM_EstimateStreamTimeBlind($imagelist_p, $gpio_period);
      $imgperiod = $gpio_period;


      # FIXME - Diagnostics.
      if ($debug_tattle_timing)
      {
        print STDERR
          sprintf(
'-- [%s]  Estimated period:  %.1f ms    Offset: %.1f ms   Tile:  %d' . "\n",
            $feed, $imgperiod, $imgoffset, $tilehint);
      }


      # Second pass: If the first pass worked, walk through the entire image
      # stream and adjust timestamps.

      # Build half-lists.
      # Every time we fill up both, concatenate them, process them, and then
      # discard the earlier half-list.

      $imagecount = 0;
      $imagelist_p = [];

      $firstlist_p = [];
      $secondlist_p = [];
      $halfsize = $seek_window_frames >> 1;

      for ($lidx = 0;
        defined ($thisline = $$logfile_p[$lidx]);
        $lidx++)
      {
        if ($thisline =~ m/^\((\d+)\)\s+\[(\w+)\]\s+frame\s+(\d+)\s+(\S+)/)
        {
          $thistime = $1;
          $thislabel = $2;
          $thisnum = $3;
          $thisfile = $4;

          if ($thislabel eq $feed)
          {
            # This is a frame that we care about.
            # Make a greyscale thumbnail and save it.

            $thisfile = $repodir . '/' . $thisfile;

# FIXME - Diagnostics.
if (!( ( -e $thisfile ) && ( -s $thisfile ) ))
{
print STDERR "-- Can't find \"$thisfile\"!\n";
}

            $thisimage = Image::Magick->new();
            $thisimage->Read($thisfile);
# FIXME - "scale" forces box filtering and is fast.
# "resize" is slower even with box filtering.
            $thisimage->Scale(width=>$lowres_width, height=>$lowres_height);
#            $thisimage->Resize(width=>$lowres_width, height=>$lowres_height,
#              filter=>Box);

            if (!$fake_greyscale)
            {
# FIXME - This fails! Web says it's due to an older version installed.
              $thisimage->Grayscale();
            }

            # FIXME - Blindly trust that PerlMagick freed up the memory that
            # was being used for the original pixel data. Otherwise we may have
            # much higher memory demand than expected.

            $imagerec_p =
            {
              'time' => $thistime,
              'seqnum' => $thisnum,
              'fname' => $thisfile,
              'rawline' => $thisline,
              'thumbnail' => $thisimage
            };

            # Add this image to the second half-list.
            push @$secondlist_p, $imagerec_p;
            $imagecount++;

            undef $imagerec_p;
            undef $thisimage;
          }
        }

        # If we just filled the second half-list, or if we reached the end
        # of input, flip the buffers and do processing.

        if ( ($imagecount >= $halfsize)
          || (!(defined $$logfile_p[$lidx + 1])) )
        {
          # At end-of-list, this may go negative, but we don't care.
          $imagecount -= $halfsize;

          # Concatenate the buffers. The first one might be empty; that's
          # fine.

          @$imagelist_p = @$firstlist_p;
          push @$imagelist_p, @$secondlist_p;

          # Extract a timing estimate for this buffer.
          # We have a previously-detected offset and a tile hint in-hand.
          $imgoffset =
            NCAM_EstimateStreamTimeHint($imagelist_p, $tilehint,
              $gpio_period, $imgoffset);

          # FIXME - Diagnostics.
          if ($debug_tattle_timing)
          {
            print STDERR
              sprintf('-- [%s]  Segment offset:  %.1f ms' . "\n",
                $feed, $imgoffset);
          }

          # Note changed lines in our corrections hash.
          # FIXME - The second buffer is the only one with new content,
          # even if this is our first pass.

          foreach $imagerec_p (@$secondlist_p)
          {
            $thisline = $$imagerec_p{rawline};

            $newline = $thisline;
            if ($thisline =~ m/^\((\d+)\)(.*)/s)
            {
              $thistime = $1;
              $thistime = int(0.5 + $thistime + $gpio_offset - $imgoffset);
              $newline = '(' . $thistime . ')' . $2;
              $$corrections_p{$thisline} = $newline;
            }
            else
            {
              # This really shouldn't happen.
              print STDERR "### [NCAM_AdjustTimestampsOneStream]  "
                . "Trying to edit a line without a timestamp.\n";
            }
          }

          # Shuffle the buffers, dropping the oldest.
          $firstlist_p = $secondlist_p;
          $secondlist_p = [];
        }
      }

      # Free up processing variables to ensure garbage collection occurs.
      # Some of these should already be freed, but be thorough.
      undef $firstlist_p;
      undef $secondlist_p;
      undef $imagelist_p;
      undef $imagerec_p;

      # Done.
    }
  }

  return $corrections_p;
}


# Adjusts timestamps for all face and scene video feeds.
# This reads from "logfile.txt" and creates "logfile-timed.txt".
# Lines are moved so that timestamps are still monotonic.
# Arg 0 is the repository directory name.
# Arg 1 is a port number to send progress reports to.
# Returns a pointer to an array containing the revised logfile.

sub NCAM_AdjustTimestampsAllStreams
{
  my ($repodir, $port, $newlog_p);
  my ($logdata_p, $thisline);
  my (%feedlist, $thisfeed);
  my ($corrections_p);
  my ($lidx);
  my ($thistime, $lasttime, %linehash, $thislist_p);
  my ($sockhandle, $netinfo_p, $hostip);

  $repodir = $_[0];
  $port = $_[1];

  $newlog_p = undef;

  if ( (defined $repodir) && (defined $port)
    && (defined ($logdata_p = NCAM_ReadLogFile($repodir, [ 'logfile.txt' ]))) )
  {
    # Get a socket for progress reports.
    $sockhandle = NCAM_GetTransmitSocket();
    $netinfo_p = NCAM_GetNetworkInfo();
    $hostip = $$netinfo_p{hostip};


    # First pass: extract the names of all _recorded_ streams.
    # This will include the monitor stream.

    %feedlist = ();

    foreach $thisline (@$logdata_p)
    {
      if ($thisline =~ m/^\(\d+\)\s+\[(\w+)\]\s+frame\s+\d+\s+\S+/)
      {
        $thisfeed = $1;
        $feedlist{$thisfeed} = 1;
      }
    }


    # Second pass: process all _canonical_ slots that we actually saw.
    # This builds an initial version of the new log data.

    @$newlog_p = @$logdata_p;

    foreach $thisfeed (@NCAM_session_slots)
    {
      # FIXME - Don't process the game feed.
      # FIXME - We still need a way to align game frames!
      if ( (defined $feedlist{$thisfeed}) && ('Game' ne $thisfeed) )
      {
        # FIXME - Just send the stream name as the progress report for now.
        NCAM_SendSocket($sockhandle, $hostip, $port, "progress $thisfeed");

        $corrections_p =
          NCAM_AdjustTimestampsOneStream($repodir, $thisfeed, $logdata_p);

        # Apply the corrections from this stream.
        for ($lidx = 0; defined ($thisline = $$newlog_p[$lidx]); $lidx++)
        {
          if (defined $$corrections_p{$thisline})
          { $$newlog_p[$lidx] = $$corrections_p{$thisline}; }
        }
      }
    }


    # Third pass: Shuffle the log file so that it's in timestamp order.
    # The merge function will do this if given an empty second list.

    $newlog_p = NCAM_MergeLogs($newlog_p, []);

    # Write the new logfile.
    if (open(OUTFILE, ">$repodir/logfile-timed.txt"))
    {
      print OUTFILE @$newlog_p;
      close(OUTFILE);
    }
  }

  return $newlog_p;
}



# Builds a "Composite" stream that stitches together all standard streams.
# This is pretty much the monitor stream with timestamps and no dropped
# frames.
# This reads from "logfile-timed.txt" or "logfile.txt", and creates
# "logfile-composited.txt".
# Arg 0 is the repository directory path.
# Arg 1 is a port number to send progress reports to.
# No return value.

sub NCAM_BuildCompositeFrames
{
  my ($repodir, $logdata_p, $port, $newlog_p);
  my ($period, %slotnames);
  my (%recentframes, $framecount, $framemax);
  my ($thisline, $thistime, $thisslot, $thisfile, $nexttime);
  my ($command, $result);
  my ($sockhandle, $netinfo_p, $hostip);

  $repodir = $_[0];
  $port = $_[1];

  $newlog_p = undef;

  if ( (defined $repodir) && (defined $port)
    && (defined ($logdata_p = NCAM_ReadLogFile($repodir,
      [ 'logfile-timed.txt', 'logfile.txt' ]))) )
  {
    # Remember that period is in milliseconds, not seconds.
    $period = 1000.0 / 30;
    %recentframes = ();
    # Mplayer convention is to start counting at frame 1.
    # Initialize to 0, because we're guaranteed to increment at least once.
    $framecount = 0;
    # Frame 1 is at time 0.
    # Alternatively it could be time period/2, but ffplay starts at 0.
    $nexttime = 0;

    $newlog_p = [];

    %slotnames = ();
    foreach $thisslot (@NCAM_session_slots)
    { $slotnames{$thisslot} = 1; }

    # Create the output directory. Remove it if it already existed.
    $command = "rm -rf $repodir/Composite";
    $result = `$command`;
    $command = "mkdir $repodir/Composite";
    $result = `$command`;

    # Get a socket for progress reports.
    $sockhandle = NCAM_GetTransmitSocket();
    $netinfo_p = NCAM_GetNetworkInfo();
    $hostip = $$netinfo_p{hostip};

    # Estimate how many frames we'll be emitting, for progress reports.
    # FIXME - This estimate may be off!
    $thistime = 0;
    foreach $thisline (@$logdata_p)
    {
      if ($thisline =~ m/^\((\d+)\)\s+\[\w+\]\s+frame\s+\d+\s+\S+/)
      {
        $thistime = $1;
      }
    }
    $framemax = int((0.999 + $thistime) / $period);


    # Process the logfile.

    foreach $thisline (@$logdata_p)
    {
      if ($thisline =~ m/^\((\d+)\)\s+\[(\w+)\]\s+frame\s+\d+\s+(\S+)/)
      {
        $thistime = $1;
        $thisslot = $2;
        $thisfile = $3;

        if (defined $slotnames{$thisslot})
        {
          # This is a frame we want to keep track of.

          $recentframes{$thisslot} = "$repodir/$thisfile";

          # If we're at the point at which we should emit a frame, do so.
          if ($thistime >= $nexttime)
          {
            # Bump the next-frame time until it's in the future.
            # Increment the frame count each time. This gives a sparse
            # list, but that's better than wasting disk space.
            do
            {
              $nexttime += $period;
              $framecount++;
            }
            while ($nexttime <= $thistime);


            # Emit this frame.

            $thisfile = 
              sprintf('Composite/%08d.jpg', $framecount);

            NCAM_CreateStitchedImage("$repodir/$thisfile", \%recentframes,
              $stitchinfo_composite_p, $stitchslots_composite_p,
              "$thistime ms");

            push @$newlog_p,
              "($thistime) [Composite]  frame $framecount  $thisfile\n";


            # Send a progress report to the manager.
            NCAM_SendSocket($sockhandle, $hostip, $port,
              "progress $framecount/$framemax");
          }
        }
      }
    }

    # Merge the new and old log files.
    $newlog_p = NCAM_MergeLogs($logdata_p, $newlog_p);

    # Clean up sockets.
    NCAM_CloseSocket($sockhandle);

    # Write the new logfile.
    if (open(OUTFILE, ">$repodir/logfile-composited.txt"))
    {
      print OUTFILE @$newlog_p;
      close(OUTFILE);
    }
  }
}



# Checks a frame directory for missing frames in sequence and adds symlinks
# for those frames.
# Arg 0 is the directory to scan.
# Returns a pointer to a list of symlinks created.

sub NCAM_AddMissingFrameNos
{
  my ($framedir, $symlinks_p);
  my ($origdir);
  my (@flist, $thisfile, $prevfile);
  my ($thisnum, $prevnum, $numidx);
  my ($prefix, $suffix, $digits, $newname, $oldnameshort);
  my ($scanfirst, $scanlast);

  $framedir = $_[0];
  $symlinks_p = [];

  if (defined $framedir)
  {
    $framedir .= '/';

    if (-d $framedir)
    {
      # FIXME - We have to enter the frame directory to do symlinking.
      $origdir = cwd();
      chdir $framedir;

      # FIXME - Filter by image type.
      # NOTE - Do not use "ls *.jpg". "*.jpg" hits the arg count limit.
      @flist = `ls|grep jpg`;

      @flist = sort @flist;
      $prevfile = undef;
      $prevnum = undef;

      foreach $thisfile ( @flist )
      {
        # Any valid frame filename should match this.
        # Trim padding and newlines while we're at it.
        if ($thisfile =~ m/^\s*(.*?)(\d+)(\D*?)\s*$/)
        {
          # Extract name template information.
          $prefix = $1;
          $thisnum = $2;
          $suffix = $3;

          $digits = length($thisnum);

          # Keep the trimmed version of the name. Newlines are bad.
          $thisfile = $prefix . $thisnum . $suffix;


          # Check to see if we need to add frames.

          # There are two situations we might encounter: gaps between
          # numbers, or a starting frame index greater than one.
          # Handle both.

          $scanfirst = undef;
          $scanlast = undef;

          if ( (defined $prevfile) && (defined $prevnum) )
          {
            # We've already seen at least one frame.
            if ($thisnum > ($prevnum + 1))
            {
              $scanfirst = $prevnum + 1;
              $scanlast = $thisnum - 1;
            }
          }
          else
          {
            # This is the first frame we've seen.
            if ($thisnum > 1)
            {
              $scanfirst = 1;
              $scanlast = $thisnum - 1;
            }
          }


          # Add frames if necessary.

          if ( (defined $scanfirst) && (defined $scanlast) )
          {
            for ($numidx = $scanfirst; $numidx <= $scanlast; $numidx++)
            {
              # FIXME - This should interpolate filenames correctly, but
              # is not perfect.

              $newname = $prefix
                . sprintf('%0' . $digits . 'd', $numidx)
                . $suffix;

              # Duplicate future frames if we don't have past frames.
              if (!(defined $prevfile))
              { $prevfile = $thisfile; }

              symlink $prevfile, $newname;

              # Make sure to prepend the frame directory to returned names.
              push @$symlinks_p, $framedir . $newname;
# FIXME - Diagnostics.
#print STDERR "-- added: \"$newname\" -> \"$prevfile\"\n";
            }
          }
        }

        $prevfile = $thisfile;
        $prevnum = $thisnum;
      }

      # Finished building symlinks.

      chdir $origdir;
    }
  }

# FIXME - Diagnostics.
#print STDERR "-- Added " . scalar(@$symlinks_p) . " symlinks.\n";

  return $symlinks_p;
}



# This removes specified symlink files (actually any files listed).
# Arg 0 points to a list of files, with paths.
# No return value.

sub NCAM_PruneSymlinks
{
  my ($files_p);
  my ($thisfile);

  $files_p = $_[0];

  if (defined $files_p)
  {
    foreach $thisfile (@$files_p)
    {
# FIXME - Diagnostics.
#print STDERR "-- removing \"$thisfile\".\n";

      if (-e $thisfile)
      {
        unlink $thisfile;
      }
    }
  }

# FIXME - Diagnostics.
#print STDERR "-- Removed " . scalar(@$files_p) . " files.\n";
}



# Guesses at the frame rate for a directory containing frames.
# It does this by looking one level up for the log file and analyzing it.
# If this fails, it falls back to a default frame rate.
# Arg 0 is the repository directory path.
# Arg 1 is the subdirectory name containing the images.
# Returns a frame rate.

sub NCAM_GuessFrameRate
{
  my ($repodir, $slotname, $rate);
  my ($logdata_p, $thisline);
  my ($thistime, $thisslot, $thisnum);
  my ($firstnum, $firsttime, $lastnum, $lasttime);

  $repodir = $_[0];
  $slotname = $_[1];
  $rate = 30;

  if ( (defined $repodir) && (defined $slotname)
    && (-d $repodir) && (-d "$repodir/$slotname") )
  {
    # Strip leading or trailing slashes from the slot name.
    if ($slotname =~ m/^.*\/(\S+)\/*$/)
    { $slotname = $1; }


    # Process log data.

    $logdata_p = NCAM_ReadLogFile($repodir,
      [ 'logfile-composited.txt', 'logfile-timed.txt', 'logfile.txt' ]);

    if (defined $logdata_p)
    {
      $firstnum = undef;
      $firsttime = undef;

      foreach $thisline ( @$logdata_p )
      {
        # FIXME - This makes some assumptions about filenames.
        if ( $thisline =~
  m/^\s*\((\d+)\)\s+\[(\w+)\]\s+frame\s+\d+\s+\w+\/.*?(\d+)\D+\s*$/ )
        {
          $thistime = $1;
          $thisslot = $2;
          $thisnum = $3;

          if ($thisslot eq $slotname)
          {
            $lastnum = $thisnum;
            $lasttime = $thistime;

            if (!( (defined $firstnum) && (defined $firsttime) ))
            {
              $firstnum = $thisnum;
              $firsttime = $thistime;
            }
# FIXME - Diagnostics.
#print STDERR ".. ($thistime)  [$slotname]  frame $thisnum\n";
          }
        }
      }

      # Finished processing log data.


      # Try to extract a frame rate.

      if (!( (defined $firstnum) && (defined $firsttime) ))
      {
        # FIXME - Diagnostics.
#        print STDERR
#          "-- Couldn't find any frames for slot \"$slotname\".\n";
      }
      elsif ( ($firstnum == $lastnum) || ($firsttime == $lasttime) )
      {
        # FIXME - Diagnostics.
#        print STDERR
#          "-- Only found one frame for slot \"$slotname\".\n";
      }
      else
      {
        # We have enough information to get an average frame rate.
        $rate = ($lastnum - $firstnum) / ($lasttime - $firsttime);
        # Time was milliseconds; adjust for that.
        $rate *= 1000.0;

# FIXME - Diagnostics.
#print STDERR  "[$slotname]  time: $firsttime - $lasttime ms"
#."  framenos: $firstnum - $lastnum\n";

        # FIXME - Diagnostics.
        print STDERR sprintf('-- [%s]  Exact frame rate: %.2f fps'."\n",
          $slotname, $rate);

        # Round this to the nearest integer.
        $rate = int($rate + 0.5);

        # FIXME - Reject this if it's too low.
        if (5 > $rate)
        { $rate = 5; }
      }
    }
  }

  return $rate;
}



# Resizes a stream's frames, storing the modified frames in a new directory.
# This is intended to be used to edit the monitor stream's frames to be a
# consistent size.
# Arg 0 is the source directory path.
# Arg 1 is the target directory path (must exist and be empty).
# Arg 2 is the resolution to change frames to.
# No return value.

sub NCAM_ResizeFrames
{
  my ($srcdir, $dstdir, $resolution);
  my (@filelist, $thisfile);
  my ($cmd, $result);

  $srcdir = $_[0];
  $dstdir = $_[1];
  $resolution = $_[2];

  if ( (defined $srcdir) && (defined $dstdir) && (defined $resolution) )
  {
    if ( (-d $srcdir) && (-d $dstdir) )
    {
      # Change this to "force this resolution including aspect ratio".
      if ($resolution =~ m/(\d+)x(\d+)/)
      { $resolution = $1 . '!x' . $2 . '!'; }

      # Single-quote the resolution to prevent "!" from being parsed.
      $resolution = "'" . $resolution . "'";

      # Process the files.
      @filelist = `ls $srcdir`;
      foreach $thisfile (@filelist)
      {
        # Strip trailing newline.
        chomp($thisfile);

        # "-resize" is slow, "-scale" is faster and averages, "-sample"
        # does no averaging at all when shrinking but picks a pixel instead.
        $cmd =
  "convert -scale $resolution $srcdir/$thisfile $dstdir/$thisfile";
# FIXME - Diagnostics.
#print "-- \"$cmd\"\n";
        $result = `$cmd`;
      }
    }
  }
}



# Transcodes a series of frames into a movie.
# This creates symlinks for missing frames during transcoding, removing
# them afterwards.
# Arg 0 is the repository directory path.
# Arg 1 is the subdirectory name containing the images.
# Arg 2 is the base name of the output file to create.
# Arg 3 is a port number to send progress reports to.
# No return value.

sub NCAM_TranscodeFrameset
{
  my ($repodir, $slotname, $obase, $port);
  my ($sockhandle, $netinfo_p, $hostip);
  my ($framecount);
  my ($outfname);
  my ($cmd, $result);
  my ($symlinks_p);
  my ($framerate);
  my ($doresize, $resizeres, $srcdir, $tmpdir);

  $repodir = $_[0];
  $slotname = $_[1];
  $obase = $_[2];
  $port = $_[3];

  if ( (defined $repodir) && (defined $slotname)
    && (defined $obase) && (defined $port) )
  {
    # Get a socket for progress reports.
    $sockhandle = NCAM_GetTransmitSocket();
    $netinfo_p = NCAM_GetNetworkInfo();
    $hostip = $$netinfo_p{hostip};


    # Initialize source and resizing information.
    $doresize = 0;
    $resizeres = $$stitchinfo_monitor_p{fullsize};
    $srcdir = "$repodir/$slotname";
    $tmpdir = "$repodir/tempdir";

    # Figure out whether we need to resize the frames.
    # This is expensive, so only do it where we need to.
    # NOTE - Assume the monitor stream always needs to be resized.
    if ('Monitor' eq $slotname)
    { $doresize = 1; }


    # Try to guess the frame rate. This falls back to a default value
    # on failure.
    $framerate = NCAM_GuessFrameRate($repodir, $slotname);

    # Resize, if needed.
    if ($doresize)
    {
      # Create a temporary directory.
      $result = `rm -rf $tmpdir`;
      mkdir $tmpdir;

      # Resize the frames.

      # FIXME - We don't get progress reports from the resize function.
      # Just send the stream name as the progress report for now.
      NCAM_SendSocket($sockhandle, $hostip, $port,
        "progress resizing $slotname");

      NCAM_ResizeFrames($srcdir, $tmpdir, $resizeres);

      # Point to the temporary directory as the new source.
      $srcdir = $tmpdir;
    }

    # Make sure we have a contiguous sequence of frames.
    $symlinks_p = NCAM_AddMissingFrameNos($srcdir);

    # Estimate how many frames we'll be emitting, for progress reports.
    $framecount = `ls $srcdir|grep jpg|wc`;
    if ($framecount =~ m/(\d+)/)
    { $framecount = $1; }
    else
    { $framecount = 0; }


    # Set up for the conversion.

    $outfname = $obase . $vidsuffix;
    # NOTE - $vidcodec and $vidbitrate have been moved to "constants".

    # Remove the target file if present.
    $cmd = 'rm -f ' . $outfname;
    $result = `$cmd`;


    # Perform the conversion.
    # FIXME - Need to capture and parse stderr output for the progress report!
    # We want to look for "frame=\s*(\d+)".
    # This might _not_ have newlines; ffmpeg homes instead, I think.

    # FIXME - Just send the stream name as the progress report for now.
    NCAM_SendSocket($sockhandle, $hostip, $port, "progress $slotname");

    # FIXME - Redirecting stderr is a good idea, as CLI invocation gives spam.
    # FIXME - Assuming a fixed framerate!
    # FIXME - Forcing a suffix on the output.
    $cmd =
      $ffmpeg_cmd
      . ' -r ' . $framerate . ' -f image2 '
      . '-i ./' . $srcdir . '/%08d.jpg '
      . '-an -b ' . $vidbitrate . ' '
      . '-vcodec ' . $vidcodec . ' -pix_fmt yuv420p '
      . $outfname;

    # FIXME - Diagnostics.
#    print STDERR $cmd . "\n";

    $result = `$cmd`;
    # FIXME - Diagnostics.
#    $result = `$cmd 2>/tmp/ffmpeg.log`;


    # Remove the symlinks we added above.
    NCAM_PruneSymlinks($symlinks_p);

    # If we made a temporary directory, nuke it.
    if (-d $tmpdir)
    { $result = `rm -rf $tmpdir`; }

    # Release the progress report socket.
    NCAM_CloseSocket($sockhandle);

    # Done.
  }
}



# Reads cached metadata information for a repository.
# Arg 0 is the repository's root directory path (containing session folders).
# Returns a pointer to a hash of session folder metadata entries, or undef
# on error.

sub NCAM_FetchRepositoryMetadata
{
  my ($repodir, $metalut_p);
  my ($fname, @fdata, $thisline);
  my ($thismeta_p);

  $repodir = $_[0];
  $metalut_p = undef;

  if ((defined $repodir) && (-d $repodir))
  {
    $fname = $repodir . '/' . $metafilename;

    if (open(INFILE, "<$fname"))
    {
      @fdata = <INFILE>;
      close(INFILE);

      $metalut_p = {};

      foreach $thisline (@fdata)
      {
        # Note that size can be "N.NGB" or "??GB".
        if ($thisline =~
m/^\s*"(.*)"\s+(\d+)sec\s+(\S+)GB\s+(postyes|postno)\s+(archyes|archno)\s*$/
        )
        {
          # This is a valid metadata record. Extract it.
          $thismeta_p =
          {
            'folder' => $1,
            'timestamp' => $2,
            'size' => $3,
            'post' => ('postyes' eq $4 ? 1 : 0),
            'arch' => ('archyes' eq $5 ? 1 : 0)
          };

          $$metalut_p{$$thismeta_p{folder}} = $thismeta_p;
        }
      }
    }
  }

  return $metalut_p;
}



# Returns easily-calculated metadata for a given session folder.
# This includes checking for post-processing/archiving.
# NOTE - The folder doesn't have to exist (archive-only is ok).
# Arg 0 is the repository's root directory path (containing session folders).
# Arg 1 is the name of the session folder to update.
# Returns a pointer to a metadata entry hash.

sub NCAM_GetFastFolderMetadata
{
  my ($repodir, $folder, $thismeta_p);
  my ($timestamp, $postflag, $archflag);
  my ($filetostat);
  my ($stat_dev, $stat_ino, $stat_mode, $stat_nlink);
  my ($stat_uid, $stat_gid, $stat_rdev, $stat_size);
  my ($stat_atime, $stat_mtime, $stat_ctime, $stat_blksize, $stat_blocks);

  $repodir = $_[0];
  $folder = $_[1];
  $thismeta_p = undef;

  if ( (defined $repodir) && (defined $folder)
    && (-d $repodir) )
  {
    # Get timestamp via fstat().

    # Stat the folder if we have one, and the archive if not.
    $filetostat = "$repodir/$folder";
    if (!(-d $filetostat))
    {
      $filetostat = "$repodir/$folder.tar";
    }

    # Fall back to safe defaults if we can't stat a file.
    $timestamp = 0;

    if (-e $filetostat)
    {
      ( $stat_dev, $stat_ino, $stat_mode, $stat_nlink,
        $stat_uid, $stat_gid, $stat_rdev, $stat_size,
        $stat_atime, $stat_mtime, $stat_ctime,
        $stat_blksize, $stat_blocks )
        = stat($filetostat);

      $timestamp = $stat_mtime;
    }


    # Check for achiving and post-processing.
    # FIXME - Solely looking for "Composite.mp4/mpeg/mpg" to test post.

    $postflag = 0;
    $archflag = 0;

    if ( (-d "$repodir/$folder") &&
      ((-e "$repodir/$folder/Composite.mp4")
        || (-e "$repodir/$folder/Composite.mpeg")
        || (-e "$repodir/$folder/Composite.mpg")) )
    { $postflag = 1; }

    if (-e "$repodir/$folder.tar")
    { $archflag = 1; }

    # Build a valid metadata entry.
    # Size is unknown. This is ok.
    # FIXME - A "does this folder exist?" flag would be nice.
    $thismeta_p =
    {
      'folder' => $folder,
      'timestamp' => $timestamp,
      'post' => $postflag,
      'arch' => $archflag,
      'size' => '??'
    };
  }

  return $thismeta_p;
}



# Checks to see if two folder metadata records differ.
# This is used to determine if metadata is stale.
# NOTE: This _ignores_ size, as it's intended to check _fast_ metadata.
# Arg 0 is the first record to compare.
# Arg 1 is the second record to compare.
# Returns 0 if the records match and 1 if the records differ.

sub NCAM_DoesFolderMetadataDiffer
{
  my ($firstrec_p, $secondrec_p, $differ);

  $firstrec_p = $_[0];
  $secondrec_p = $_[1];

  $differ = undef;

  if ((defined $firstrec_p) && (defined $secondrec_p))
  {
    $differ = 0;

    # Folder name and size are strings. Everything else is integer.
    # NOTE - We're ignoring size (which is '??' for fast metadata).
    # NOTE - Folder names had _better_ match, for stale-metadata tests.
    if ( ($$firstrec_p{folder} ne $$secondrec_p{folder})
      || ($$firstrec_p{timestamp} != $$secondrec_p{timestamp})
      || ($$firstrec_p{post} != $$secondrec_p{post})
      || ($$firstrec_p{arch} != $$secondrec_p{arch}) )
    {
      $differ = 1;
    }
  }

  return $differ;
}



# Checks to see if cached repository metadata is stale.
# Arg 0 is the repository's root directory path (containing session folders).
# Returns 1 if an update is needed and 0 if not.

sub NCAM_IsRepositoryMetadataStale
{
  my ($repodir, $need_update);
  my ($fname);
  my ($metalut_p, $oldmeta_p, $newmeta_p);
  my (@dirlist, $direntry, $folder);
  my (%seenlist);

  $repodir = $_[0];
  $need_update = 0;

  if ((defined $repodir) && (-d $repodir))
  {
    # Read the cached metadata (may be stale or even missing).
    $metalut_p = NCAM_FetchRepositoryMetadata($repodir);

    if (!(defined $metalut_p))
    {
      $need_update = 1;
    }
    else
    {
      # Walk through all of the folders that are actually in the repository,
      # checking that metadata exists and matches.

      %seenlist = ();

      @dirlist = `ls --color=none $repodir/`;
      foreach $direntry (@dirlist)
      {
        # Match the repository name _and_ .tar files.
        # Check our duplicates list to avoid processing twice.
        if ($direntry =~ m/^(ncam-\S+\d)(\.tar)?\s*$/)
        {
          $folder = $1;

          if (!(defined $seenlist{$folder}))
          {
            $seenlist{$folder} = 1;

            $oldmeta_p = $$metalut_p{$folder};
            $newmeta_p = NCAM_GetFastFolderMetadata($repodir, $folder);

            if ( (!(defined $oldmeta_p))
              || NCAM_DoesFolderMetadataDiffer($oldmeta_p, $newmeta_p) )
            {
              $need_update = 1;
            }
          }
        }
      }

      # Walk through all of the metadata entries, checking that we actually
      # have corresponding files or folders.

      foreach $folder (keys %$metalut_p)
      {
        if (!( defined $seenlist{$folder} ))
        {
          $need_update = 1;
        }
      }
    }
  }

  return $need_update;
}



# Updates cached metadata for a repository (creating metadata if needed).
# This may take a while if it has to recalculate repository size.
# Arg 0 is the repository's root directory path (containing session folders).
# Arg 1 (optional), if defined and nonzero, forces all entries to update.
# Returns a pointer to a hash of session folder metadata entries, or undef
# on error.

sub NCAM_UpdateRepositoryMetadata
{
  my ($repodir, $doforce, $metalut_p);
  my ($fname);
  my ($oldmeta_p, $newmeta_p);
  my (@dirlist, $direntry);
  my ($folder, $size);
  my (%seenlist);

  $repodir = $_[0];
  $doforce = $_[1];
  $metalut_p = undef;

  if ((defined $repodir) && (-d $repodir))
  {
    # Read the cached metadata (may be stale or even missing).

    $metalut_p = NCAM_FetchRepositoryMetadata($repodir);

    if (!(defined $metalut_p))
    {
      $metalut_p = {};
    }


    # Update our "force" flag.
    if ((defined $doforce) && $doforce)
    { $doforce = 1; }
    else
    { $doforce = 0; }


    # Walk through all of the folders that are actually in the repository,
    # updating metadata.

    %seenlist = ();
    @dirlist = `ls --color=none $repodir/`;
    foreach $direntry (@dirlist)
    {
      # Match the repository name _and_ .tar files.
      # Check our duplicates list to avoid processing twice.
      if ($direntry =~ m/^(ncam-\S+\d)(\.tar)?\s*$/)
      {
        $folder = $1;

        if (!(defined $seenlist{$folder}))
        {
          $seenlist{$folder} = 1;

          $oldmeta_p = $$metalut_p{$folder};
          $newmeta_p = NCAM_GetFastFolderMetadata($repodir, $folder);

          # If we don't have an entry, or if this entry is stale, recreate it.
          if ( (!(defined $oldmeta_p))
            || NCAM_DoesFolderMetadataDiffer($oldmeta_p, $newmeta_p)
            || $doforce )
          {
            # We already have a new entry; it just needs the size.

            # This will return one or two lines (depending on archive status).
            # Note that we're asking for megabytes here, not gigabytes.
            $size =
          `du --block-size=1000000 -s $repodir/$folder $repodir/$folder.tar`;

            if ($size =~ m/^(\d+)\s+.*^(\d+)/ms)
            {
              $size = $1 + $2;
              $size = sprintf('%.1f', $size / 1000);
            }
            elsif ($size =~ m/^(\d+)/ms)
            {
              $size = $1;
              $size = sprintf('%.1f', $size / 1000);
            }
            else
            { $size = '??'; }

            $$newmeta_p{size} = $size;

            # Save the updated entry in the hash.
            $$metalut_p{$folder} = $newmeta_p;
          }
        }
      }
    }


    # Write the revised metadata.

    $fname = $repodir . '/' . $metafilename;

    if (open(OUTFILE, ">$fname"))
    {
      # Emit in descending lexical order.
      foreach $folder (sort {$b cmp $a} keys %$metalut_p)
      {
        # Only emit metadata for files or folders that still exist.
        if (defined $seenlist{$folder})
        {
          $oldmeta_p = $$metalut_p{$folder};

          # NOTE - The "size" field can be "N.N" or "??". Both are valid.
          print OUTFILE sprintf( '"%s" %dsec %sGB %s %s'."\n",
            $$oldmeta_p{folder}, $$oldmeta_p{timestamp}, $$oldmeta_p{size},
            ($$oldmeta_p{post} ? 'postyes' : 'postno'),
            ($$oldmeta_p{arch} ? 'archyes' : 'archno') );
        }
      }

      close(OUTFILE);
    }
  }

  return $metalut_p;
}



# FIXME - USB mountpoint is a magic constant!
# Making it a normal constant would be even uglier.


# Queries the presence of external drive hardware.
# This doesn't check mounting state.
# No arguments.
# Returns a bit vector of NCAM_flag_usbN values.

sub NCAM_IsExternalDrivePlugged
{
  my ($is_plugged);
  my (@partlist, @fslist, $partline, $fsline);
  my ($usbpartition, $mountpoint, $thispartition, $partsize);

  $is_plugged = 0;

  @fslist = `grep usb /etc/fstab`;
  @partlist = `cat /proc/partitions`;

  foreach $fsline (@fslist)
  {
    if ($fsline =~ m/\/dev\/(\S+)\s+(\/usb\S*)/)
    {
      $usbpartition = $1;
      $mountpoint = $2;

      foreach $partline (@partlist)
      {
        if ($partline =~ m/^\s*\d+\s+\d+\s+(\d+)\s+(\S+)\s*$/)
        {
          $partsize = $1;
          $thispartition = $2;

          if ($usbpartition eq $thispartition)
          {
            if ('/usb' eq $mountpoint)
            { $is_plugged |= $NCAM_flag_usb1; }
            elsif ('/usb2' eq $mountpoint)
            { $is_plugged |= $NCAM_flag_usb2; }
            else
            { $is_plugged |= $NCAM_flag_usbbogus; }
          }
        }
      }
    }
  }

  return $is_plugged;
}



# Queries the mounting state of the external drive.
# No arguments.
# Returns a bit vector of NCAM_flag_usbN values.

sub NCAM_IsExternalDriveMounted
{
  my ($is_mounted);
  my (@mountlist, $mountline);
  my ($mountdev, $mountpoint);

  $is_mounted = 0;

  @mountlist = `grep usb /etc/mtab`;

  foreach $mountline (@mountlist)
  {
    if ($mountline =~ m/^\s*(\/dev\/\S+)\s+(\/usb\S*)\s+/)
    {
      $mountdev = $1;
      $mountpoint = $2;

      if ('/usb' eq $mountpoint)
      { $is_mounted |= $NCAM_flag_usb1; }
      elsif ('/usb2' eq $mountpoint)
      { $is_mounted |= $NCAM_flag_usb2; }
      else
      { $is_mounted |= $NCAM_flag_usbbogus; }
    }
  }

  return $is_mounted;
}



# Reports the mountpoint of a mounted external drive.
# No arguments.
# Returns the mountpoint path or undef if no drive is mounted.

sub NCAM_GetExternalMountpoint()
{
  my ($mountflags, $mountpoint);

  $mountflags = NCAM_IsExternalDriveMounted();

  # If we have a _known_ external drive mounted, report it.
  # Give priority to /usb2 over /usb, to handle EFI drives.

  $mountpoint = undef;

  if ($mountflags & $NCAM_flag_usb2)
  { $mountpoint = '/usb2'; }
  elsif ($mountflags & $NCAM_flag_usb1)
  { $mountpoint = '/usb'; }

  return $mountpoint;
}



# Forces disk synchronization. This may take a while.
# No arguments.
# No return value.

sub NCAM_ForceDiskSync
{
  my ($result);

  $result = `sync`;
}



# Mounts an external drive, if detected and not already mounted.
# If a repository root directory is specified, attempts to create that
# directory if it doesn't already exist.
# Arg 0 is the repository root directory path (relative to the mountpoint).
# This may be undefined.
# No return value.

sub NCAM_MountExternalDrive
{
  my ($plugflags, $mountflags, $mountpoint);
  my ($reporoot);
  my ($cmd, $result);

  $reporoot = $_[0];

  $plugflags = NCAM_IsExternalDrivePlugged();
  $mountflags = NCAM_IsExternalDriveMounted();


  # If any _known_ external drive is already mounted, unmount it.
  if ( $mountflags & (~$NCAM_flag_usbbogus) )
  { NCAM_UnmountExternalDrive(); }


  # If we have a _known_ external drive that's plugged but not mounted,
  # mount it. Give priority to /usb2 over /usb, to handle EFI drives.

  $mountpoint = undef;

  if ($plugflags & $NCAM_flag_usb2)
  { $mountpoint = '/usb2'; }
  elsif ($plugflags & $NCAM_flag_usb1)
  { $mountpoint = '/usb'; }

  if (defined $mountpoint)
  {
    $result = `mount $mountpoint`;

    # Create a repository folder if we don't already have one.
    if (defined $reporoot)
    {
      if (!(-d "$mountpoint/$reporoot"))
      {
        $cmd = "mkdir $mountpoint/$reporoot";
        $result = `$cmd`;
        $cmd = "chmod 1777 $mountpoint/$reporoot";
        $result = `$cmd`;
      }
    }
  }
}



# Unmounts an external drive, if mounted.
# This forces disk synchronization, which may take a while.
# No arguments.
# No return value.

sub NCAM_UnmountExternalDrive
{
  my ($mountflags);
  my ($result);

  $mountflags = NCAM_IsExternalDriveMounted();

  if ($mountflags)
  {
    NCAM_ForceDiskSync();

    if ($mountflags & $NCAM_flag_usb1)
    { $result = `umount /usb`; }

    if ($mountflags & $NCAM_flag_usb2)
    { $result = `umount /usb2`; }
  }
}



#
# Main Program
#


# Report success.
1;



#
# This is the end of the file.
#
