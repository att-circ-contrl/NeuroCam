#!/usr/bin/perl
#
# NeuroCam management script - Command-line invocation UI.
# Written by Christopher Thomas.
#
# This project is Copyright (c) 2021 by Vanderbilt University, and is released
# under the Creative Commons Attribution-ShareAlike 4.0 International License.

#
# Includes
#

use strict;
use warnings;
use Time::HiRes;
use POSIX;
use Socket;
use Image::Magick;

# Path fix needed for more recent Perl versions.
use lib ".";

require "neurocam-libmt.pl";
require "neurocam-libcam.pl";
require "neurocam-libfocus.pl";
require "neurocam-libnetwork.pl";
require "neurocam-libsession.pl";
require "neurocam-libweb.pl";



#
# Shared Variables
#

# FIXME - Doing this the messy way. Any imported variables need appropriate
# "our" declarations.

our (@NCAM_session_slots);
our (%NCAM_default_settings);



#
# Functions
#


# Displays a list of resolutions and frame rates.
# Arg 0 points to the resolution/rate hash.
# No return value.

sub PrintListOfModes
{
  my ($sizes_p);
  my ($thissize, $rates_p, $thisrate);

  $sizes_p = $_[0];

  if (!(defined $sizes_p))
  {
    print "### [PrintListOfModes]  Bad arguments.\n";
  }
  else
  {
    foreach $thissize (NCAM_SortByResolution(keys %$sizes_p))
    {
      print sprintf('  %9s :', $thissize);
      $rates_p = $$sizes_p{$thissize};
      foreach $thisrate (@$rates_p)
      {
        print "  $thisrate Hz";
      }
      print "\n";
    }
  }
}


# Displays a list of exposures hashed by resolutions and frame rates.
# Arg 0 points to the resolution/rate hash.
# No return value.

sub PrintListOfExposures
{
  my ($sizes_p);
  my ($thissize, $rates_p, $thisrate);

  $sizes_p = $_[0];

  if (!(defined $sizes_p))
  {
    print "### [PrintListOfExposures]  Bad arguments.\n";
  }
  else
  {
    foreach $thissize (NCAM_SortByResolution(keys %$sizes_p))
    {
      print sprintf('  %9s :  ', $thissize);
      $rates_p = $$sizes_p{$thissize};
      foreach $thisrate (sort {$b <=> $a} keys %$rates_p)
      {
        print "  $thisrate Hz: " . $$rates_p{$thisrate};
      }
      print "\n";
    }
  }
}


# Displays metadata information about one camera.
# Argument 0 points to the camera's metadata hash.
# No return value.

sub PrintCameraMetadata
{
  my ($meta_p);
  my ($exposure, $sizes_p);

  $meta_p = $_[0];

  if (!(defined $meta_p))
  {
    print "### [PrintCameraMetadata]  Bad arguments.\n";
  }
  else
  {
    print "\n";
    print "Device: " . $$meta_p{device} . "\n";
    print "Model:  " . $$meta_p{model} . "\n";
    print "Resolutions:\n";

    PrintListOfModes($$meta_p{sizes});

    # FIXME - Report pre-configured desired-exposure here?
    print "Exposure range:  " . $$meta_p{exposure}{min} . "-"
      . $$meta_p{exposure}{max} . " by " . $$meta_p{exposure}{step}
      . ", set to " . $$meta_p{exposure}{currentval}
      . ", default " . $$meta_p{exposure}{default}
# FIXME - Manual mode index just looks confusing in the readout.
#      . "  (manual mode: " . $$meta_p{exposure}{manual} . ")";
      . "\n";

    # List focus settings, if available.
    print "Focus modes available:"
      . ($$meta_p{focus}{havemanual} ? "  manual" : "")
      . ($$meta_p{focus}{haveauto} ? "  auto" : "")
      . ($$meta_p{focus}{havemanual} || $$meta_p{focus}{haveauto} ?
        "" : "  (none)")
      . "\n";
    if ($$meta_p{focus}{havemanual})
    {
      print "Focus range:  " . $$meta_p{focus}{min} . "-"
        . $$meta_p{focus}{max} . " by " . $$meta_p{focus}{step}
        . ", set to " . $$meta_p{focus}{currentval}
        . ", default " . $$meta_p{exposure}{default}
        . "\n";
    }

    # Show what we think we want for this camera.
    # This is either the best default available, or from the session config.

    print "Desired resolution:  " . $$meta_p{desiredsize}
      . "  " . $$meta_p{desiredrate} . " Hz\n";
    print "Desired exposure:  " . $$meta_p{desiredexp} . "\n";
    if ($$meta_p{focus}{havemanual})
    {
      print "Desired focus:  " . $$meta_p{desiredfocus} . "\n";
    }


    # If we have a list of well-behaved resolutions, provide it.
    if (defined $$meta_p{defaultmodes})
    {
      print "Well-behaved resolutions at exposure "
        . $$meta_p{exposure}{default} . ":\n";
      PrintListOfModes($$meta_p{defaultmodes});
    }

    # If we have a list of well-behaved exposure settings, provide it.
    if (defined $$meta_p{exposurelut})
    {
      print "Maximum exposures for well-behaved capture:\n";
      PrintListOfExposures($$meta_p{exposurelut});
    }

    print "\n";
  }
}


# Displays metadata information about all cameras.
# Argument 0 points to the hash of camera metadata hashes.
# No return value.

sub PrintCameraList
{
  my ($cameras_p);
  my ($thisdevice);

  $cameras_p = $_[0];

  if (!(defined $cameras_p))
  {
    print "### [PrintCameraList]  Bad arguments.\n";
  }
  else
  {
    foreach $thisdevice (sort keys %$cameras_p)
    {
      PrintCameraMetadata($$cameras_p{$thisdevice});
    }
  }
}



# Probes for a list of well-behaved resolutions/frame rates for a camera.
# This is added to the camera's metadata hash.
# Arg 0 points to the camera's metadata hash.
# No return value.

sub ProbeCameraModes
{
  my ($meta_p);
  my ($exposure, $supported_p);

  $meta_p = $_[0];

  if (!(defined $meta_p))
  {
    print "### [ProbeCameraModes]  Bad arguments.\n";
  }
  else
  {
    # Print a banner, so that the user doesn't think this hung.
    print "-- Probing " . $$meta_p{device}
      . " to see which camera modes are well-behaved.\n";

    # Use the default exposure value, not the current value.
    $exposure = $$meta_p{exposure}{default};
    $supported_p = NCAM_GetFormatsGivenExposure($meta_p, $exposure);

    # Store the list of well-behaved modes.
    $$meta_p{defaultmodes} = $supported_p;
  }
}



# Probes exposures for each supported mode for a camera, to determine the
# maximum well-behaved exposure setting.
# This is added to the camera's metadata hash.
# Arg 0 points to the camera's metadata hash.
# No return value.

sub ProbeCameraExposures
{
  my ($meta_p);
  my ($sizes_p, $rates_p, $thissize, $thisrate);
  my ($exp_cap);
  my ($thisexp, $exp_rates_p, $exp_sizes_p);

  $meta_p = $_[0];

  if (!(defined $meta_p))
  {
    print "### [ProbeCameraExposures]  Bad arguments.\n";
  }
  else
  {
    # Print a banner, so that the user doesn't think this hung.
    print "-- Probing " . $$meta_p{device}
      . " to find well-behaved exposure settings.\n";

    $exp_cap = $$meta_p{exposure}{default};
    $sizes_p = $$meta_p{sizes};

    $exp_sizes_p = {};
    $$meta_p{exposurelut} = $exp_sizes_p;

    foreach $thissize (NCAM_SortByResolution(keys %$sizes_p))
    {
      $exp_rates_p = {};

      $rates_p = $$sizes_p{$thissize};
      foreach $thisrate (@$rates_p)
      {
        $thisexp = NCAM_GetExposureGivenFormat($meta_p,
          $thissize, $thisrate, $exp_cap);

        if (defined $thisexp)
        {
          $$exp_rates_p{$thisrate} = $thisexp;

          # Make sure this rate hash is recorded.
          # Doing this multiple times is harmless and simplifies code.
          $$exp_sizes_p{$thissize} = $exp_rates_p;
        }
      }
    }
  }
}



# Sweeps the focus range for the desired mode for a camera, to determine
# which focus value gives the sharpest results.
# This is added to the camera's metadata hash.
# Arg 0 points to the camera's metadata hash.
# Arg 1 is a filename to write probe gnuplot data to (may be undef).
# No return value.

sub ProbeCameraFocus
{
  my ($meta_p, $fname);
  my ($exp_wanted, $size_wanted, $rate_wanted);
  my ($focus_wanted, $fdata_p);
  my ($thisfocus, $thisfom);

  $meta_p = $_[0];
  $fname = $_[1];  # May be undef.

  if (!(defined $meta_p))
  {
    print "### [ProbeCameraFocus]  Bad arguments.\n";
  }
  else
  {
    # Print a banner, so that the user doesn't think this hung.
    print "-- Probing " . $$meta_p{device}
      . " to find well-behaved focus settings.\n";

    $exp_wanted = $$meta_p{desiredexp};
    $size_wanted = $$meta_p{desiredsize};
    $rate_wanted = $$meta_p{desiredrate};

    # Wrap the library function.
    ($focus_wanted, $fdata_p) =
      NCAM_SweepFocus($meta_p, $size_wanted, $rate_wanted, $exp_wanted);

    $$meta_p{desiredfocus} = $focus_wanted;

    if (defined $fname)
    {
      if (!open(GFILE, ">$fname"))
      {
        print "### [ProbeCameraFocus]  Unable to write to \"$fname\".\n";
      }
      else
      {
        print GFILE sprintf('# %5s  %8s'."\n", 'Focus', 'FOM');

        foreach $thisfocus (sort {$a <=> $b} keys %$fdata_p)
        {
          $thisfom = $$fdata_p{$thisfocus};
          print GFILE sprintf('  %5d  %8.6f'."\n", $thisfocus, $thisfom);
        }

        close(GFILE);
      }
    }
  }
}



# Writes session configuration information to stdout.
# Arg 0 points to the session configuration hash.
# No return value.

sub PrintSessionConfig
{
  my ($session_p, $text_p);

  $session_p = $_[0];

  if (!(defined $session_p))
  {
    print "### [PrintSessionConfig]  Bad arguments.\n";
  }
  else
  {
    $text_p = NCAM_SessionConfigToText($session_p);
    print @$text_p;
  }
}



# Processes command-line arguments.
# No arguments.
# Returns a hash of option-flags and other argument data, or undef on error.

sub ProcessArgs
{
  my ($options_p);
  my ($thisarg);
  my ($had_errors);

  $had_errors = 0;

  # Set reasonable defaults.
  $options_p =
  {
    'monitorfile' => $NCAM_default_settings{monitorfile},
    'monitorport' => $NCAM_default_settings{monitorport},
    'cmdport' => $NCAM_default_settings{cmdport}
  };

  # Parse arguments.
  foreach $thisarg (@ARGV)
  {
    if ($thisarg =~ m/--(\S+?)=(.*?)\s*$/)
    {
      $$options_p{$1} = $2;
    }
    elsif ($thisarg =~ m/--(\S+)/)
    {
      $$options_p{$1} = 1;
    }
    else
    {
      # FIXME - This may eventually be used for something, but not yet.
      print "###  Unrecognized argument: \"$thisarg\".\n";
      $had_errors = 1;
    }
  }

  if ($had_errors)
  {
    $options_p = undef;
    print "Use \"--help\" for help.\n";
  }

  return $options_p;
}



# Displays a help screen.
# No arguments.
# No return value.

sub PrintHelp
{
  print << "Endofblock";

NeuroCam management script - Command-line version.
Written by Christopher Thomas.

Usage:  neurocam-cli.pl (options)

Valid options:

--help   - Displays this help screen.
--info   - Displays information about all connected cameras.

--probemodes      - Tests to see which supported modes are well-behaved.
--probeexposure   - Tests to see exposure values needed for good behavior.
--probefocus      - Sweeps the focus range to see which value works best.

--sessionconfig=<file>   - Reads from a session configuration file.
--emitsessionconfig      - Writes (new/old) session configuration to stdout.
--emitconfigpage=<dir>   - Writes configuration web page parts to a direcory.
                           This is a template; CGI calls are stubbed out.
--emitfocusfile=<prefix> - Writes focus sweep data to the specified file.
                           This forces --probefocus.

--monitorfile=<name>   - File portion of the URL to offer the monitor feed on.
--monitorport=<nnnn>   - Port to offer the monitor feed on.

--cmdport=<nnnn>     - Port on which the daemon should accept commands.

Endofblock

  # FIXME - More commands go here.
}



#
# Main Program
#

my ($options_p);
my ($cameras_p, $network_p, $thisdevice);
my ($session_p, $errstr);
my ($had_command);
my ($scratch);


# Process arguments to figure out what we're supposed to do.
$options_p = ProcessArgs();


# Before doing anything else, see if we have a command.
$had_command = 0;

if (defined $options_p)
{
  if ( (defined $$options_p{info})
    || (defined $$options_p{emitsessionconfig})
    || (defined $$options_p{emitconfigpage})
    || (defined $$options_p{emitfocusfile})
  )
  {
    $had_command = 1;
  }

  # Set up implied commands.
  if (defined $$options_p{emitfocusfile})
  { $$options_p{probefocus} = 1; }
}


# Proceed only if we're actually doing something. Otherwise just show
# the help screen.

if ($had_command)
{
  # Things look okay so far.
  # Get the list of available video devices.

  $cameras_p = NCAM_GetCameraList();

  # Get the list of advertised remote devices.
  # FIXME - Use the default game port (should be 8888).
  $network_p =
    NCAM_ProbeNetworkDevices($NCAM_default_settings{talkquerylist}, 2000);

  # Probe for augmented metadata if requested.

  foreach $thisdevice (sort keys %$cameras_p)
  {
    if (defined $$options_p{probemodes})
    {
      ProbeCameraModes($$cameras_p{$thisdevice});
    }

    if (defined $$options_p{probeexposure})
    {
      ProbeCameraExposures($$cameras_p{$thisdevice});
    }

    if (defined $$options_p{probefocus})
    {
      $scratch = $$options_p{emitfocusfile};
      if (defined $scratch)
      {
        if ($thisdevice =~ m/(\d+)/)
        { $scratch .= $1; }
        $scratch .= '.gpdata';
      }

      ProbeCameraFocus($$cameras_p{$thisdevice}, $scratch);
    }
  }


  $session_p = undef;

  # If we were told to use a configuration hash, use it.
  # This returns undef on error.
  if (defined $$options_p{sessionconfig})
  {
    ($session_p, $errstr) =
      NCAM_ReadSessionConfigFile($$options_p{sessionconfig});

    if (!(defined $session_p))
    { print '### ' . $errstr; }
  }

  # Build a default session configuration hash if we don't already have one.
  if (!(defined $session_p))
  {
    $session_p = NCAM_CreateNewSessionConfig($cameras_p, $network_p,
      $$options_p{monitorfile}, $$options_p{monitorport},
      $$options_p{cmdport});
    NCAM_PopulateSlotsByDefault($session_p);
  }


  # Process any commands found.

  if (defined $$options_p{info})
  {
    # Emit information about each detected camera.
    # This may have been updated by previous probe operations.
    PrintCameraList($cameras_p);
  }

  if (defined $$options_p{emitsessionconfig})
  {
    # Emit session configuration file data to stdout.
    PrintSessionConfig($session_p);
  }

  if (defined $$options_p{emitconfigpage})
  {
    # Write a CGI configuration page and auxiliary files.
    $scratch = $$options_p{emitconfigpage} . '/config.html';
    if (!open(OUTFILE, ">$scratch"))
    {
      print "### Unable to write to \"$scratch\".\n";
    }
    else
    {
      # Session, aux path (unix), aux path (web page relative), error message
      # (may be undef).
      $scratch = 
        NCAM_GenerateConfigPage($session_p, $$options_p{emitconfigpage}, '');
      print OUTFILE $scratch;
      close(OUTFILE);
    }
  }


  # Perform cleanup.

  NCAM_ShutdownNetwork();
}
elsif (defined $options_p)
{
  # We either had no command, or --help.
  # (Failure to parse parameters/lack of an option hash is already handled.)

  PrintHelp();
}



#
# This is the end of the file.
#
