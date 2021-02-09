#!/usr/bin/perl
#
# NeuroCam management script - Session management library.
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

our ($NCAM_port_camdaemon_command, $NCAM_port_camdaemon_monitorstream);
our ($NCAM_port_game_query);
our ($NCAM_port_gpio_base);


#
# Public Constants
#

# FIXME - Doing this the messy way. Anywhere that uses this needs to have
# a corresponding "our" declaration.

our (@NCAM_session_slots);
our (%NCAM_slot_default_types);
our (%NCAM_default_settings);
our (%NCAM_exposure_stops);

# Ordered list of feeds to be displayed.
@NCAM_session_slots =
( 'SceneA', 'SceneB', 'SceneC', 'FaceA', 'FaceB', 'Game' );

# List of default slot types.
%NCAM_slot_default_types =
(
  'SceneA' => 'camera',
  'SceneB' => 'camera',
  'SceneC' => 'camera',
  'FaceA' => 'camera',
  'FaceB' => 'camera',
  'Game' => 'stream'
);

# Default settings for user-specified values.
%NCAM_default_settings =
(
  'monitorfile' => 'stream.mjpg',
  'monitorport' => $NCAM_port_camdaemon_monitorstream,
  'cmdport' => $NCAM_port_camdaemon_command,
  # FIXME - This list is a kludge. We need a way for multiple talkers on one
  # machine to share a query port via some intermediary (or peer to peer).
  'talkquerylist' => [ $NCAM_port_game_query, $NCAM_port_gpio_base ],
  # FIXME - Set this low for testing, large for production.
  # If the defaults can't be set, fall back to picking the biggest available.
  'defaultresolution' => '640x360',
  'defaultframerate' => '15'
#  'defaultresolution' => '1280x720',
#  'defaultframerate' => '30'
);

# Exposure stop names and scaling factors.
%NCAM_exposure_stops =
(
  # Span +/- 3 steps on the E6 series.
  # NOTE - Keys, when sorted, give lowest to highest exposures.
  '+3' => 3,
  '+2' => 2,
  '+1' => 1.5,
  '+0' => 1,
  '-1' => 0.7,
  '-2' => 0.5,
  '-3' => 0.3
);



#
# Public Functions
#


# Creates a list of exposure stops, from camera metadata.
# Arg 0 points to the camera's metadata hash.
# Returns a hash of exposures indexed by stop label.

sub NCAM_GetExposureStops
{
  my ($meta_p, $stops_p);
  my ($default);
  my ($thislabel);

  $meta_p = $_[0];
  $stops_p = {};

  if (defined $meta_p)
  {
    $default = $$meta_p{exposure}{default};

    foreach $thislabel (keys %NCAM_exposure_stops)
    {
      # FIXME - Not checking for quantization or clamping.
      $$stops_p{$thislabel} =
        int(0.5 + $default * $NCAM_exposure_stops{$thislabel});
    }
  }

  return $stops_p;
}



# Converts an absolute exposure value to an "exposure stop" label.
# Arg 0 is the value to be converted.
# Arg 1 points to the esposure stop hash.
# Returns an exposure stop label (hash key).

sub NCAM_ConvertExposureToStop
{
  my ($exposure, $stops_p, $label);
  my ($thislabel, $thisval, $thisratio, $bestratio);

  $exposure = $_[0];
  $stops_p = $_[1];
  $label = undef;

  if ( (defined $exposure) && (defined $stops_p) )
  {
    foreach $thislabel (keys %$stops_p)
    {
      $thisval = $$stops_p{$thislabel};

      if ((0 == $thisval) || (0 == $exposure))
      { $thisratio = 0; }
      elsif ($thisval < $exposure)
      { $thisratio = $thisval / $exposure; }
      else
      { $thisratio = $exposure / $thisval; }

      if (!(defined $label))
      {
        $bestratio = $thisratio;
        $label = $thislabel;
      }
      elsif ($thisratio > $bestratio)
      {
        $bestratio = $thisratio;
        $label = $thislabel;
      }
    }
  }

  return $label;
}



# Sets a camera's exposure by stop index.
# The current stop index in the camera device entry hash is updated.
# Arg 0 points to the camera's device entry in the session hash (not its
# metadata hash).
# Arg 1 is the stop index to set.
# No return value.

sub NCAM_SetExposureByStop
{
  my ($camera_p, $stopidx);
  my ($meta_p, $exposure);

  $camera_p = $_[0];
  $stopidx = $_[1];

  if ( (defined $camera_p) && (defined $stopidx) )
  {
    $meta_p = $$camera_p{meta};

    $exposure = $$camera_p{explist}{$stopidx};
    if (!(defined $exposure))
    { $exposure = $$meta_p{exposure}{default}; }

    NCAM_SetExposure($meta_p, $exposure);

    $exposure = $$meta_p{exposure}{currentval};
    $$camera_p{exp} =
      NCAM_ConvertExposureToStop($exposure, $$camera_p{explist});
  }
}



# Creates a session configuration hash with blank entries.
# This is typically used to set defaults prior to full initialization.
# No arguments.
# Returns a pointer to a new session configuration hash.

sub NCAM_CreateBlankSessionConfig
{
  my ($session_p);
  my ($thislabel);
  my ($slots_p, $cameras_p, $streams_p, $talkers_p);

  $slots_p = {};
  $cameras_p = {};
  $streams_p = {};
  $talkers_p = {};

  $session_p =
  {
    'slots' => $slots_p,
    'cameras' => $cameras_p,
    'streams' => $streams_p,
    'talkers' => $talkers_p,
    'monitorfile' => $NCAM_default_settings{monitorfile},
    'monitorport' => $NCAM_default_settings{monitorport},
    'cmdport' => $NCAM_default_settings{cmdport}
  };


  # Initialize slot pointers to "camera is off".

  foreach $thislabel (@NCAM_session_slots)
  {
    $$slots_p{$thislabel} =
    { 'type' => 'none' };
  }

  return $session_p;
}



# Creates a new session configuration hash, recording camera and stream
# devices but leaving slots empty.
# Arg 0 points to the hash of camera metadata hashes.
# Arg 1 points to the list of network device metadata hashes.
# Arg 2 is the file portion of the URL to offer the stitched monitor feed on.
# Arg 3 is the port to offer the stitched monitor feed on.
# Arg 4 is the port to listen for commands on.
# Returns a pointer to a new session configuration hash.

sub NCAM_CreateNewSessionConfig
{
  my ($cam_meta_p, $network_meta_p);
  my ($monitorfile, $monitorport, $cmdport, $session_p);
  my ($cam_list_p, $stream_list_p, $talker_list_p);
  my ($thisdev, $thismeta_p);
  my ($scratch, @scratchlist);
  my ($defaultsize, $defaultrate, $ratelist_p, %ratelut);

  $cam_meta_p = $_[0];
  $network_meta_p = $_[1];
  $monitorfile = $_[2];
  $monitorport = $_[3];
  $cmdport = $_[4];

  # Initialize to a sane configuration.
  $session_p = NCAM_CreateBlankSessionConfig();

  if ( (defined $cam_meta_p) && (defined $network_meta_p)
    && (defined $monitorfile) && (defined $monitorport)
    && (defined $cmdport) )
  {
    # Copy over argument-specified configuration.

    $$session_p{monitorfile} = $monitorfile;
    $$session_p{monitorport} = $monitorport;
    $$session_p{cmdport} = $cmdport;

    # Flag these ports as reserved.
    NCAM_FlagPortAsUsed($monitorport);
    NCAM_FlagPortAsUsed($cmdport);


    # Populate the camera list with detected cameras.

    $cam_list_p = $$session_p{cameras};

    foreach $thisdev (keys %$cam_meta_p)
    {
      $thismeta_p = $$cam_meta_p{$thisdev};

      # Only use cameras that have at least one valid mode.
      # Very old or very cheap cameras can have no desired modes.
      if (defined $$thismeta_p{desiredsize})
      {
        # Copy appropriate metadata.
        # Compute exposure stops for this camera.
        # Assign it a local unique port number to give frame updates to.
        $$cam_list_p{$thisdev} =
        {
          'device' => $thisdev,
          'size' => $$thismeta_p{desiredsize},
          'rate' => $$thismeta_p{desiredrate},
          'explist' => NCAM_GetExposureStops($thismeta_p),
          'exp' => NCAM_ConvertExposureToStop($$thismeta_p{desiredexp},
            NCAM_GetExposureStops($thismeta_p)),
          'updateport' => NCAM_GetNextListenPort(),
          'meta' => $thismeta_p
        };

        # FIXME - Override the camera's default resolution and frame rate
        # with _our_ default resolution and frame rate, if available.

        $defaultsize = $NCAM_default_settings{defaultresolution};
        $defaultrate = $NCAM_default_settings{defaultframerate};

        if (defined $$thismeta_p{sizes}{$defaultsize})
        {
          $$cam_list_p{$thisdev}{size} = $defaultsize;
        }

        # Get the available rates for whatever size we ended up with.
        $scratch = $$cam_list_p{$thisdev}{size};
        $ratelist_p = $$thismeta_p{sizes}{$scratch};

        %ratelut = ();
        foreach $scratch (@$ratelist_p)
        { $ratelut{$scratch} = 1; }

        if (defined $ratelut{$defaultrate})
        {
          # First try: the rate we want.
          $$cam_list_p{$thisdev}{rate} = $defaultrate;
        }
        elsif (defined $ratelut{$$thismeta_p{desiredrate}})
        {
          # Second try: the rate the camera wants.
          $$cam_list_p{$thisdev}{rate} = $$thismeta_p{desiredrate};
        }
        else
        {
          # Third try: the biggest of the rates that are actually available.
          @scratchlist = sort {$b <=> $a} @$ratelist_p;
          $$cam_list_p{$thisdev}{rate} = $scratchlist[0];
        }
      }
    }


    # Populate the stream list and talker list with detected network
    # entities.

    $stream_list_p = $$session_p{streams};
    $talker_list_p = $$session_p{talkers};

    foreach $thismeta_p (@$network_meta_p)
    {
      if ('stream' eq $$thismeta_p{type})
      {
        # Record the URL and metadata pointer for this stream.
        # Set latency to a reasonable default value. We can't detect this.
        # Assign it a local unique port number to give frame updates to.
        $scratch = $$thismeta_p{url};
        $$stream_list_p{$scratch} =
        {
          'url' => $scratch,
          'label' => $$thismeta_p{label},
          'delay' => 1000,
          'updateport' => NCAM_GetNextListenPort(),
          'meta' => $thismeta_p
        };
      }
      elsif ('talker' eq $$thismeta_p{type})
      {
        # Record the host and port for this message source.
        # Assign it a local unique port number to talk to.
        $scratch = $$thismeta_p{host} . ':' . $$thismeta_p{port};
        $$talker_list_p{$scratch} =
        {
          'key' => $scratch,
          'host' => $$thismeta_p{host},
          'port' => $$thismeta_p{port},
          'label' => $$thismeta_p{label},
          'myport' => NCAM_GetNextListenPort(),
          'enabled' => 0,
          'meta' => $thismeta_p
        };
      }
      # Otherwise silently ignore this entry.
    }
  }

  # Done.
  return $session_p;
}



# Attempts to ensure that at least one GPIO message source is enabled.
# Arg 0 points to the session configuration hash.
# No return value.

sub NCAM_EnableOneGPIOTalker
{
  my ($session_p);
  my ($talkers_p, $thislabel, $thistalker_p);
  my ($gpio_enabled_count);

  $session_p = $_[0];

  if (defined $session_p)
  {
    $talkers_p = $$session_p{talkers};
    $gpio_enabled_count = 0;

    # First pass: count enabled GPIO talkers.
    foreach $thislabel (keys %$talkers_p)
    {
      $thistalker_p = $$talkers_p{$thislabel};

      if ( ($$thistalker_p{label} =~ m/gpio/i) && $$thistalker_p{enabled} )
      {
        $gpio_enabled_count++;
      }
    }

    # Second pass: enable one GPIO device if we don't have one.
    foreach $thislabel (keys %$talkers_p)
    {
      if ( (1 > $gpio_enabled_count) && ($$thistalker_p{label} =~ m/gpio/i) )
      {
        $$thistalker_p{enabled} = 1;
        $gpio_enabled_count++;
      }
    }

    # Done.
  }
}



# Assigns unassigned devices to unassigned slots.
# Arg 0 points to the session configuration hash.
# No return value.

sub NCAM_PopulateUnassignedSlots
{
  my ($session_p);
  my ($cam_list_p, $stream_list_p, $slots_p);
  my (@camnames, @streamnames);
  my (%camsused, %streamsused);
  my ($thislabel, $thistype);
  my ($thisname);
  my (%streamsadded, $thishost);
  my ($talkers_p, $thistalker_p);

  $session_p = $_[0];

  if (defined $session_p)
  {
    # Get list pointers.

    $cam_list_p = $$session_p{cameras};
    $stream_list_p = $$session_p{streams};
    $slots_p = $$session_p{slots};

    # Initialize our checklist for looking for messengers.
    %streamsadded = ();


    # Make a checklist of cameras and streams that have already been
    # assigned slots.

    %camsused = ();
    %streamsused = ();

    foreach $thislabel (keys %$slots_p)
    {
      $thistype = $$slots_p{$thislabel}{type};

      if ('camera' eq $thistype)
      {
        $thisname = $$slots_p{$thislabel}{config}{device};
        if (defined $thisname)
        { $camsused{$thisname} = 1; }
      }
      elsif ('stream' eq $thistype)
      {
        $thisname = $$slots_p{$thislabel}{config}{url};
        if (defined $thisname)
        { $streamsused{$thisname} = 1; }
      }
    }


    # Populate the list of cameras and streams that _haven't_ been used,
    # in sorted order.

    @camnames = ();
    foreach $thisname (sort keys %$cam_list_p)
    {
      if (!(defined $camsused{$thisname}))
      { push @camnames, $thisname; }
    }

    @streamnames = ();
    foreach $thisname (sort keys %$stream_list_p)
    {
      if (!(defined $streamsused{$thisname}))
      { push @streamnames, $thisname; }
    }


    # Walk through the slot list in given-order.
    # Populate with new cameras and streams in _sorted_ order.

    foreach $thislabel (@NCAM_session_slots)
    {
      $thistype = $$slots_p{$thislabel}{type};

      # Only modify slots that are a) valid and b) unassigned.
      if ( (defined $thistype) && ('none' eq $thistype) )
      {
        $thistype = $NCAM_slot_default_types{$thislabel};

        if (defined $thistype)
        {
          # Pick from the appropriate list depending on slot type.

          if ('camera' eq $thistype)
          {
            $thisname = shift @camnames;

            if (defined $thisname)
            {
              $$slots_p{$thislabel} =
              {
                'type' => 'camera',
                'config' => $$cam_list_p{$thisname}
              };
            }
          }
          elsif ('stream' eq $thistype)
          {
            $thisname = shift @streamnames;

            if (defined $thisname)
            {
              $$slots_p{$thislabel} =
              {
                'type' => 'stream',
                'config' => $$stream_list_p{$thisname}
              };

              # Record the host offering this stream, so that we can enable
              # messages from it if we see it again.
              $thishost = $thisname;
              if ($thisname =~ m/http:\/\/(\S+?)[:\/]/)
              { $thishost = $1; }

              $streamsadded{$thishost} = $thisname;
            }
          }
          else
          {
            # Shouldn't happen. Leave the slot empty.
          }

          # Finished with this slot.
        }
      }
    }


    # Walk through the list of talkers, and enable any with hosts we're
    # using streams from.

    $talkers_p = $$session_p{talkers};

    foreach $thislabel (keys %$talkers_p)
    {
      $thistalker_p = $$talkers_p{$thislabel};
      $thishost = $$thistalker_p{host};

      if (defined $streamsadded{$thishost})
      {
        $$thistalker_p{enabled} = 1;
      }
    }
  }


  # Done.
  return $session_p;
}



# Populates session slots using detected devices in default order.
# Arg 0 points to the session configuration hash.
# No return value.

sub NCAM_PopulateSlotsByDefault
{
  my ($session_p);
  my ($slots_p);
  my ($thislabel);
  my ($talkers_p, $thistalker_p);

  $session_p = $_[0];

  if (defined $session_p)
  {
    $slots_p = $$session_p{slots};


    # Clear any existing slot assignments and disable any enabled talkers.

    foreach $thislabel (@NCAM_session_slots)
    {
      $$slots_p{$thislabel} =
      { 'type' => 'none' };
    }

    foreach $thislabel (keys %$talkers_p)
    {
      $thistalker_p = $$talkers_p{$thislabel};
      $$thistalker_p{enabled} = 0;
    }


    # Assign these now-unassigned devices to slots.
    NCAM_PopulateUnassignedSlots($session_p);


    # FIXME - Make sure we have at least one GPIO talker enabled, if any
    # are advertised. We need this for synchronization.
    NCAM_EnableOneGPIOTalker($session_p);
  }


  # Done.
  return $session_p;
}



# Walks through a session configuration and flags all used ports as reserved.
# Arg 0 points to the session configuration hash.
# No return value.

sub NCAM_SessionReservePorts
{
  my ($session_p);
  my ($thisport);
  my ($thislist_p, $thiskey, $thisentry_p);

  $session_p = $_[0];

  if (defined $session_p)
  {
    # Top level.
    if (defined ($thisport = $$session_p{monitorport}))
    { NCAM_FlagPortAsUsed($thisport); }
    if (defined ($thisport = $$session_p{cmdport}))
    { NCAM_FlagPortAsUsed($thisport); }

    # Camera list.
    $thislist_p = $$session_p{cameras};
    foreach $thiskey (keys %$thislist_p)
    {
      $thisentry_p = $$thislist_p{$thiskey};
      if (defined ($thisport = $$thisentry_p{updateport}))
      { NCAM_FlagPortAsUsed($thisport); }
    }

    # Stream list.
    $thislist_p = $$session_p{cameras};
    foreach $thiskey (keys %$thislist_p)
    {
      $thisentry_p = $$thislist_p{$thiskey};
      if (defined ($thisport = $$thisentry_p{updateport}))
      { NCAM_FlagPortAsUsed($thisport); }
    }

    # Message source list.
    $thislist_p = $$session_p{cameras};
    foreach $thiskey (keys %$thislist_p)
    {
      $thisentry_p = $$thislist_p{$thiskey};
      if (defined ($thisport = $$thisentry_p{myport}))
      { NCAM_FlagPortAsUsed($thisport); }
    }

    # Done.
  }
}



# Converts a session configuration into an array of strings.
# Arg 0 points to the session configuration hash.
# Returns a pointer to an array of strings.

sub NCAM_SessionConfigToText
{
  my ($session_p, $text_p);
  my ($cameras_p, $streams_p, $talkers_p, $slots_p);
  my ($thislabel);
  my ($dev_p, $thiskey, $thisval);
  my ($expstr, $expkey, $expval);
  my ($str_p, $talk_p);
  my ($slot_p);
  my ($scratch);

  $session_p = $_[0];
  $text_p = [];

  if (defined $session_p)
  {
    push @$text_p, "NeuroCam session configuration begins.\n";

    # Get list pointers.
    $cameras_p = $$session_p{cameras};
    $streams_p = $$session_p{streams};
    $talkers_p = $$session_p{talkers};
    $slots_p = $$session_p{slots};

    # Write non-list information as a preamble.
    push @$text_p, "\n";
    push @$text_p, "Monitor stream served as:  "
      . $$session_p{monitorfile} . "\n";
    push @$text_p, "  Monitor stream on port:  "
      . $$session_p{monitorport} . "\n";
    push @$text_p, "\nCommand port:  " . $$session_p{cmdport} . "\n";

    # Repository directory is optional.
    if (defined $$session_p{repodir})
    {
      push @$text_p, "\nRepository subdirectory:  " . $$session_p{repodir}
        . "\n";
    }

    # Write all cameras (sorted).
    # NOTE - This is mostly for diagnostics. Read-in ignores this.

    foreach $thislabel (sort keys %$cameras_p)
    {
      push @$text_p, "\nCamera $thislabel begins.\n";

      $dev_p = $$cameras_p{$thislabel};

      foreach $thiskey (sort keys %$dev_p)
      {
        $thisval =  $$dev_p{$thiskey};

        if ('explist' eq $thiskey)
        {
          $expstr = sprintf('  %10s:', $thiskey);
          foreach $expkey (sort {$a <=> $b} keys %$thisval)
          {
            $expval = $$thisval{$expkey};
            $expstr .= '  ' . $expkey . ' (' . $expval . ')';
          }
          $expstr .= "\n";

          push @$text_p, $expstr;
        }
        elsif ('meta' ne $thiskey)
        {
          push @$text_p, sprintf('  %10s:  %s'."\n", $thiskey, $thisval);
        }
      }

      push @$text_p, "Camera ends.\n";
    }

    # Write all streams (sorted).

    foreach $thislabel (sort keys %$streams_p)
    {
      push @$text_p, "\nStream $thislabel begins.\n";

      $str_p = $$streams_p{$thislabel};

      foreach $thiskey (sort keys %$str_p)
      {
        $thisval = $$str_p{$thiskey};

        if ('delay' eq $thiskey)
        {
          push @$text_p, sprintf('  %10s:  %s ms'."\n", $thiskey, $thisval);
        }
        elsif ('meta' ne $thiskey)
        {
          push @$text_p, sprintf('  %10s:  %s'."\n", $thiskey, $thisval);
        }
      }

      push @$text_p, "Stream ends.\n";
    }

    # Write all message sources (sorted).

    foreach $thislabel (sort keys %$talkers_p)
    {
      push @$text_p, "\nMessage source $thislabel begins.\n";

      $talk_p = $$talkers_p{$thislabel};

      foreach $thiskey (sort keys %$talk_p)
      {
        $thisval = $$talk_p{$thiskey};

        if ('meta' ne $thiskey)
        {
          push @$text_p, sprintf('  %10s:  %s'."\n", $thiskey, $thisval);
        }
      }

      push @$text_p, "Message source ends.\n";
    }

    # Write only the slots we're _supposed_ to have, in given order.
    # All we need to know is the keys to look up their associated devices.

    push @$text_p, "\nSlot list begins.\n";

    foreach $thislabel (@NCAM_session_slots)
    {
      $slot_p = $$slots_p{$thislabel};

      # Complain about missing slots, and then initialize safely.
      if (!(defined $slot_p))
      {
        push @$text_p, '# Missing slot content; forcing to empty.' . "\n";
        $slot_p = { 'type' => 'none' };
      }
      elsif (!(defined $$slot_p{type}))
      {
        push @$text_p, '# Corrupt slot content; forcing to empty.' . "\n";
        $slot_p = { 'type' => 'none' };
      }


      # Write the slot label, type, and key value.

      $scratch = '  Slot ' . $thislabel . ' (' . $$slot_p{type} . ')';

      if ('none' eq $$slot_p{type})
      {
        push @$text_p, $scratch . "\n";
      }
      elsif ('camera' eq $$slot_p{type})
      {
        push @$text_p, $scratch . ': ' . $$slot_p{config}{device} . "\n";
      }
      elsif ('stream' eq $$slot_p{type})
      {
        push @$text_p, $scratch . ': ' . $$slot_p{config}{url} . "\n";
      }
      else
      {
        push @$text_p, '# Unknown slot type "' . $$slot_p{type}
          . "\"; forcing to empty.\n";
        push @$text_p, '  Slot ' . $thislabel . ' (none)' . "\n";
      }


      # Finished with this slot.
    }

    push @$text_p, "Slot list ends.\n";

    push @$text_p, "\nNeuroCam session configuration ends.\n";
  }

  return $text_p;
}



# Parses an array of strings into a session configuration hash.
# Arg 0 points to the array of strings to parse.
# Returns ($session_p, $errstr).
# The session hash pointer is undef on error.

sub NCAM_TextToSessionConfig
{
  my ($text_p, $session_p, $errstr);
  my ($is_ok);
  my ($thisline, $lidx);
  my ($state, $thisitem_p, $thislist_p);
  my ($subhash_p, $thisarg);
  my ($slotlabel, $slottype);


  $text_p = $_[0];
  $session_p = undef;
  $errstr = "Bad arguments.\n";
  $is_ok = 0;


  if (defined $text_p)
  {
    # Initialize.
    $session_p = NCAM_CreateBlankSessionConfig();
    $state = 'start';
    $is_ok = 1;
    $thisitem_p = undef;
    $thislist_p = undef;


    # Walk through the text.
    for ($lidx = 0;
      $is_ok && (defined ($thisline = $$text_p[$lidx]));
      $lidx++)
    {
      # Pre-initialize the error string.
      $errstr = "(line " . ($lidx + 1) . ") ";

      # Parse this line.
      if ($thisline =~ m/^\s*#/)
      {
        # This is a comment. Ignore it no matter what.
      }
      elsif (!($thisline =~ m/\S/))
      {
        # This line is empty. Ignore it no matter what.
      }
      elsif ($thisline =~ m/^\s*NeuroCam session configuration begins/i)
      {
        if ('start' eq $state)
        { $state = 'toplevel'; }
        else
        {
          $is_ok = 0;
          $errstr .= "Config began twice.\n";
        }
      }
      elsif ($thisline =~ m/^\s*NeuroCam session configuration ends/i)
      {
        if ('toplevel' eq $state)
        { $state = 'done'; }
        else
        {
          $is_ok = 0;
          if ('done' eq $state)
          { $errstr .= "Config ended twice.\n"; }
          else
          { $errstr .= "Config ended while parsing sub-block.\n"; }
        }
      }
      elsif ( ('start' eq $state) || ('done' eq $state) )
      {
        # Ignore everything outside the session block.
      }
      elsif ('toplevel' eq $state)
      {
        if ($thisline =~ m/^\s*Monitor stream served as:\s+(.*\S)/i)
        {
          # NOTE - This might contain spaces! Make sure we can handle that.
          $$session_p{monitorfile} = $1;
        }
        elsif ($thisline =~ m/^\s*Monitor stream on port:\s+(\d+)/i)
        {
          $$session_p{monitorport} = $1;
        }
        elsif ($thisline =~ m/^\s*Command port:\s+(\d+)/i)
        {
          $$session_p{cmdport} = $1;
        }
        elsif ($thisline =~ m/^\s*Repository subdirectory:\s+(.*\S)/i)
        {
          # NOTE - This might contain spaces or other special characters!
          # Make sure there's downstream error checking for that.
          $$session_p{repodir} = $1;
        }
        elsif ($thisline =~ m/^\s*Camera \S+ begins./i)
        {
          $thisitem_p = {};
          $thislist_p = $$session_p{cameras};
          $state = 'camera';
        }
        elsif ($thisline =~ m/^\s*Stream\s+.*\S+ begins./i)
        {
          $thisitem_p = {};
          $thislist_p = $$session_p{streams};
          $state = 'stream';
        }
        elsif ($thisline =~ m/^\s*Message source \S+ begins./i)
        {
          $thisitem_p = {};
          $thislist_p = $$session_p{talkers};
          $state = 'talker';
        }
        elsif ($thisline =~ m/^\s*Slot list begins./i)
        {
          $thisitem_p = undef;
          $thislist_p = $$session_p{slots};
          $state = 'slots';
        }
        else
        {
          $is_ok = 0;
          $errstr .= "Unexpected content at top level:\n" . $thisline;
        }
      }
      elsif ('camera' eq $state)
      {
        if ( ($thisline =~ m/^\s*(device):\s+(\S+)/i)
          || ($thisline =~ m/^\s*(exp):\s+(\S+)/i)
          || ($thisline =~ m/^\s*(rate):\s+(\d+)/i)
          || ($thisline =~ m/^\s*(size):\s+(\d+x\d+)/i)
          || ($thisline =~ m/^\s*(updateport):\s+(\d+)/i)
        )
        {
          $$thisitem_p{$1} = $2;
        }
        elsif ($thisline =~ m/^\s*explist:\s+(.*\S)/i)
        {
          $subhash_p = {};
          $thisarg = $1;

          while ($thisarg =~ m/([\-+\d]+)\s+\((\d+)\)(.*)/)
          {
            $$subhash_p{$1} = $2;
            $thisarg = $3;
          }

          $$thisitem_p{explist} = $subhash_p;
          undef $subhash_p;
        }
        elsif ($thisline =~ m/^\s*Camera ends./i)
        {
          $thisarg = $$thisitem_p{device};
          if (defined $thisarg)
          {
            $$thislist_p{$thisarg} = $thisitem_p;
            undef $thisitem_p;
            undef $thislist_p;
            $state = 'toplevel';
          }
          else
          {
            $is_ok = 0;
            $errstr .= "Missing device name in Camera block.\n";
          }
        }
        else
        {
          $is_ok = 0;
          $errstr .= "Unexpected content in Camera block:\n" . $thisline;
        }
      }
      elsif ('stream' eq $state)
      {
        if ( ($thisline =~ m/^\s*(delay):\s+(\d+)/i)
          || ($thisline =~ m/^\s*(updateport):\s+(\d+)/i)
          || ($thisline =~ m/^\s*(url):\s+(.*\S)/i)
          || ($thisline =~ m/^\s*(label):\s+(.*\S)/i)
        )
        {
          # NOTE - URL read here may contain spaces.
          # Auto-probed ones don't any more.
          # NOTE - Label may contain spaces.
          $$thisitem_p{$1} = $2;
        }
        elsif ($thisline =~ m/^\s*Stream ends./i)
        {
          $thisarg = $$thisitem_p{url};
          if (defined $thisarg)
          {
            $$thislist_p{$thisarg} = $thisitem_p;
            undef $thisitem_p;
            undef $thislist_p;
            $state = 'toplevel';
          }
          else
          {
            $is_ok = 0;
            $errstr .= "Missing URL in Stream block.\n";
          }
        }
        else
        {
          $is_ok = 0;
          $errstr .= "Unexpected content in Stream block:\n" . $thisline;
        }
      }
      elsif ('talker' eq $state)
      {
        if ( ($thisline =~ m/^\s*(host):\s+(.*\S)/i)
          || ($thisline =~ m/^\s*(key):\s+(.*\S)/i)
          || ($thisline =~ m/^\s*(port):\s+(\d+)/i)
          || ($thisline =~ m/^\s*(label):\s+(.*\S)/i)
          || ($thisline =~ m/^\s*(myport):\s+(\d+)/i)
          || ($thisline =~ m/^\s*(enabled):\s+(\d+)/i)
        )
        {
          # NOTE - Label may contain spaces.
          $$thisitem_p{$1} = $2;
        }
        elsif ($thisline =~ m/^\s*Message source ends./i)
        {
          $thisarg = $$thisitem_p{key};
          if (defined $thisarg)
          {
            $$thislist_p{$thisarg} = $thisitem_p;
            undef $thisitem_p;
            undef $thislist_p;
            $state = 'toplevel';
          }
          else
          {
            $is_ok = 0;
            $errstr .= "Missing key in Message source block.\n";
          }
        }
        else
        {
          $is_ok = 0;
          $errstr .= "Unexpected content in Message source block:\n" . $thisline;
        }
      }
      elsif ('slots' eq $state)
      {
        if ($thisline =~ m/^\s*Slot (\w+) \((\w+)\):\s+(.*\S)/i)
        {
          $slotlabel = $1;
          $slottype = $2;
          $thisarg = $3;

          undef $subhash_p;

          if ('camera' eq $slottype)
          {
            $subhash_p = $$session_p{cameras}{$thisarg};
          }
          elsif ('stream' eq $slottype)
          {
            $subhash_p = $$session_p{streams}{$thisarg};
          }
          else
          {
            $is_ok = 0;
            $errstr .= "Unknown type \"$slottype\" in slot \"$slotlabel\".\n";
          }

          if ($is_ok)
          {
            if (defined $subhash_p)
            {
              $$thislist_p{$slotlabel} =
              {
                'type' => $slottype,
                'config' => $subhash_p
              };
            }
            else
            {
              $is_ok = 0;
              $errstr .= "Can't find $slottype named \"$thisarg\".\n";
            }
          }

          undef $subhash_p;
        }
        elsif ($thisline =~ m/^\s*Slot (\w+) \(none\)/i)
        {
          $slotlabel = $1;
          $$thislist_p{$slotlabel} = { 'type' => 'none' };
        }
        elsif ($thisline =~ m/^\s*Slot list ends./i)
        {
          # Check that all slots are defined.
          foreach $slotlabel (@NCAM_session_slots)
          {
            $subhash_p = $$thislist_p{$slotlabel};
            if (!(defined $subhash_p))
            {
              if ($is_ok)
              {
                $errstr .= "Missing slot \"$slotlabel\".\n";
              }
              $is_ok = 0;
            }
            undef $subhash_p;
          }

          $state = 'toplevel';
        }
        else
        {
          $is_ok = 0;
          $errstr .= "Unexpected content in Slot list block:\n" . $thisline;
        }
      }
      else
      {
        $is_ok = 0;
        $errstr .= "Unknown state \"$state\".\n";
      }
    }
  }


  # Return values depend on error state.
  if ($is_ok)
  {
    $errstr = "No error.\n";
  }
  else
  {
    $session_p = undef;
  }

  return ($session_p, $errstr);
}



# Attempts to read any missing camera metadata from the cameras listed in a
# session config hash. Cameras without metadata are pruned (and their slots
# released).
# Arg 0 points to the session configuration hash, which is modified.
# No return value.

sub NCAM_ConfirmSessionCameras
{
  my ($session_p);
  my ($cameras_p, $thisdev, $thiscam_p, $meta_p);
  my ($camera_bad);
  my ($ratelist_p, $thisrate);
  my ($thisexp);
  my ($slots_p, $slotname, $thisslot_p);

  $session_p = $_[0];

  if (defined $session_p)
  {
    $cameras_p = $$session_p{cameras};
    $slots_p = $$session_p{slots};

    foreach $thisdev (keys %$cameras_p)
    {
      $thiscam_p = $$cameras_p{$thisdev};
      $meta_p = $$thiscam_p{meta};

      if (!(defined $meta_p))
      {
        $camera_bad = 1;
        $meta_p = NCAM_GetCameraMetadata($thisdev);

        if (defined $meta_p)
        {
          # We didn't have metadata before, but do now.
          # Check that our nominal settings are valid. If not, we have the
          # wrong camera.

          # Check resolution.
          $ratelist_p = $$meta_p{sizes}{$$thiscam_p{size}};
          if (defined $ratelist_p)
          {
            foreach $thisrate (@$ratelist_p)
            {
              if ($thisrate == $$thiscam_p{rate})
              { $camera_bad = 0; }
            }
          }

          # If we don't have an exposure list, build one.
          # This happens when we're rebuilding from CGI data.
          if (!(defined $$thiscam_p{explist}))
          {
            $$thiscam_p{explist} = NCAM_GetExposureStops($meta_p);
          }

          # Check exposure.
          if (!$camera_bad)
          {
            $thisexp = $$thiscam_p{explist}{$$thiscam_p{exp}};
            if ( ($thisexp > $$meta_p{exposure}{max})
              || ($thisexp < $$meta_p{exposure}{min}) )
            { $camera_bad = 1; }
          }
        }

        # If there was a problem, prune this camera from the list.
        # Otherwise, save the metadata.
        if ($camera_bad)
        {
          # Remove the camera from the camera hash.
          delete $$cameras_p{$thisdev};

          # Set slots containing this camera to be empty.
          foreach $slotname (keys %$slots_p)
          {
            $thisslot_p = $$slots_p{$slotname};

            if ('camera' eq $$thisslot_p{type})
            {
              if ($thisdev eq $$thisslot_p{config}{device})
              {
                $thisslot_p = { 'type' => 'none' };
                $$slots_p{$slotname} = $thisslot_p;
              }
            }
          }
        }
        else
        {
          # Everything looks fine.
          $$thiscam_p{meta} = $meta_p;
        }
      }
    }
  }
}



# Updates a session configuration based on revised device metadata.
# Arg 0 points to the session configuration hash.
# Arg 1 points to a hash of camera metadata hashes.
# Arg 2 points to a list of network device metadata hashes.
# Returns a revised session configuration hash.

sub NCAM_ConfirmSessionDevices
{
  my ($session_p, $cameras_p, $network_p, $newsession_p);
  my ($thishash_p, $thisentryname, $thisentry_p);
  my ($scratch);
  my ($oldsize, $oldrate, $oldexp);
  my ($newcam_p);
  my ($ratelist_p, $thisrate, $found);

  $session_p = $_[0];
  $cameras_p = $_[1];
  $network_p = $_[2];

  $newsession_p = undef;

  if ( (defined $session_p) && (defined $cameras_p) && (defined $network_p) )
  {
    # Create a brand new session configuration hash based on the new data.
    $newsession_p = NCAM_CreateNewSessionConfig($cameras_p, $network_p,
      $$session_p{monitorfile}, $$session_p{monitorport},
      $$session_p{cmdport});

    # Copy over any compatible configuration information.

    # Slot assignments.
    $thishash_p = $$session_p{slots};
    foreach $thisentryname (keys %$thishash_p)
    {
      $thisentry_p = $$thishash_p{$thisentryname};

      if ('camera' eq $$thisentry_p{type})
      {
        $scratch = $$thisentry_p{config}{device};
        if (defined $$newsession_p{cameras}{$scratch})
        {
          $$newsession_p{slots}{$thisentryname} =
          {
            'config' => $$newsession_p{cameras}{$scratch},
            'type' => 'camera'
          };
        }
      }
      elsif ('stream' eq $$thisentry_p{type})
      {
        $scratch = $$thisentry_p{config}{url};
        if (defined $$newsession_p{streams}{$scratch})
        {
          $$newsession_p{slots}{$thisentryname} =
          {
            'config' => $$newsession_p{streams}{$scratch},
            'type' => 'stream'
          };
        }
      }
    }

    # Talker enable states.
    $thishash_p = $$session_p{talkers};
    foreach $thisentryname (keys %$thishash_p)
    {
      $thisentry_p = $$thishash_p{$thisentryname};

      if ($$thisentry_p{enabled})
      {
        if (defined $$newsession_p{talkers}{$thisentryname})
        {
          $$newsession_p{talkers}{$thisentryname}{enabled} = 1;
        }
      }
    }

    # Camera settings.
    $thishash_p = $$session_p{cameras};
    foreach $thisentryname (keys %$thishash_p)
    {
      $thisentry_p = $$thishash_p{$thisentryname};

      $oldsize = $$thisentry_p{size};
      $oldrate = $$thisentry_p{rate};
      $oldexp = $$thisentry_p{exp};

      $newcam_p = $$newsession_p{cameras}{$thisentryname};
      if (defined $newcam_p)
      {
        $ratelist_p = $$newcam_p{meta}{sizes}{$oldsize};
        if (defined $ratelist_p)
        {
          $found = 0;
          foreach $thisrate (@$ratelist_p)
          {
            if ($oldrate == $thisrate)
            { $found = 1; }
          }

          if ($found)
          {
            # Old resolution and frame rate are supported.
            $$newcam_p{size} = $oldsize;
            $$newcam_p{rate} = $oldrate;

            # Exposure is relative, so it's always supported.
            $$newcam_p{exp} = $oldexp;
          }
        }
      }
    }

    # FIXME - Make sure we have at least one GPIO talker enabled, if any
    # are advertised. We need this for synchronization.
    NCAM_EnableOneGPIOTalker($newsession_p);

    # Finished.
  }

  return $newsession_p;
}



# Reads session configuration from a file.
# Arg 0 is the name of the file to read.
# Returns ($session_p, $errstr).
# The session hash pointer is undef on error.

sub NCAM_ReadSessionConfigFile
{
  my ($fname, $session_p, $errstr);
  my (@fdata, $texterr);
  my ($is_ok);


  $fname = $_[0];
  $session_p = undef;
  $errstr = "Bad arguments.\n";
  $is_ok = 0;


  if (defined $fname)
  {
    if (!open(INFILE, "<$fname"))
    {
      $errstr = "Unable to read from \"$fname\".\n";
    }
    else
    {
      @fdata = <INFILE>;
      close(INFILE);

      ($session_p, $texterr) = NCAM_TextToSessionConfig(\@fdata);

      if (!(defined $session_p))
      {
        $errstr = "Unable to parse \"$fname\". Error given:\n" . $texterr;
      }
      else
      {
        # Blithely assume that we still have the same input devices/streams.
        $is_ok = 1;
        NCAM_ConfirmSessionCameras($session_p);
        NCAM_SessionReservePorts($session_p);
      }
    }
  }


  # Return values depend on error state.
  if ($is_ok)
  {
    $errstr = "No error.\n";
  }
  else
  {
    $session_p = undef;
  }

  return ($session_p, $errstr);
}



# Writes session configuration to a file.
# Arg 0 is the name of the file to write to.
# Arg 1 point so the session configuration hash.
# Returns 1 on success and 0 on failure.

sub NCAM_WriteSessionConfigFile
{
  my ($fname, $session_p, $is_ok);
  my ($fdata_p);


  $fname = $_[0];
  $session_p = $_[1];
  $is_ok = 0;


  if ( (defined $fname) && (defined $session_p) )
  {
    if (open(OUTFILE, ">$fname"))
    {
      $fdata_p = NCAM_SessionConfigToText($session_p);
      print OUTFILE @$fdata_p;
      close(OUTFILE);

      $is_ok = 1;
    }
  }

  return $is_ok;
}



#
# Main Program
#



# Report success.
1;



#
# This is the end of the file.
#
