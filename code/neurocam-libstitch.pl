#!/usr/bin/perl
#
# NeuroCam management script - Image stitching library.
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

# Exported variables.

# FIXME - Doing this the messy way. Anywhere that uses this needs to have
# a corresponding "our" declaration.

# Geometry description hashes used for various purposes.
# These point to appropriate private constants.

our ($stitchinfo_monitor_p, $stitchslots_monitor_p);
our ($stitchinfo_preview_p, $stitchslots_preview_p);
our ($stitchinfo_composite_p, $stitchslots_composite_p);


# Imported variables.

# FIXME - Doing this the messy way. Any imported variables need appropriate
# "our" declarations.

our (@NCAM_session_slots);



#
# Private Constants
#


# Geometry description hashes for various configuration options.
# Geometry can be 2x3 or 3x2, with small/medium/large resolution.
my (%stitchslots_3x2, %stitchslots_2x3);
my (%stitchinfo_3x2_sm, %stitchinfo_3x2_md, %stitchinfo_3x2_lg);
my (%stitchinfo_2x3_sm, %stitchinfo_2x3_md, %stitchinfo_2x3_lg);


# Assign pointers to appropriate geometry definitions.

$stitchinfo_monitor_p = \%stitchinfo_2x3_md;
$stitchinfo_preview_p = \%stitchinfo_2x3_sm;
$stitchinfo_composite_p = \%stitchinfo_2x3_lg;

$stitchslots_monitor_p = \%stitchslots_2x3;
$stitchslots_preview_p = \%stitchslots_2x3;
$stitchslots_composite_p = \%stitchslots_2x3;


# Instatiation of geometry description hashes for various configurations.
# Image tiling lookup tables.

%stitchslots_3x2 =
(
  'SceneA' => { 'label' => 'Scene A', 'x' => 0, 'y' => 0 },
  'SceneB' => { 'label' => 'Scene B', 'x' => 1, 'y' => 0 },
  'SceneC' => { 'label' => 'Scene C', 'x' => 2, 'y' => 0 },
  'FaceA' => { 'label' => 'Face A', 'x' => 0, 'y' => 1 },
  'FaceB' => { 'label' => 'Face B', 'x' => 1, 'y' => 1 },
  'Game' => { 'label' => 'Game', 'x' => 2, 'y' => 1 }
);

%stitchslots_2x3 =
(
  'SceneA' => { 'label' => 'Scene A', 'x' => 0, 'y' => 0 },
  'SceneB' => { 'label' => 'Scene B', 'x' => 0, 'y' => 1 },
  'SceneC' => { 'label' => 'Scene C', 'x' => 0, 'y' => 2 },
  'FaceA' => { 'label' => 'Face A', 'x' => 1, 'y' => 0 },
  'FaceB' => { 'label' => 'Face B', 'x' => 1, 'y' => 1 },
  'Game' => { 'label' => 'Game', 'x' => 1, 'y' => 2 }
);

# NOTE - Stitching a 3x2 array of 16:9 looks _bad_.
# Make the full size image 16:9 or 4:3 instead.
# 16:9 gives a 3x2 array of 4:3, and 4:3 gives a 2x3 array of 16:9,
# more or less.

# 16:9 full (3x2 array of 4:3-ish)

%stitchinfo_3x2_sm =
(
  'fullsize' => '960x540', 'tilesize' => '320x270',
  'dx' => 320, 'dy' => 270, 'offx' => 0, 'offy' => 0,
  'fontsize' => 12
);

%stitchinfo_3x2_md =
(
  'fullsize' => '1280x720', 'tilesize' => '426x360',
  'dx' => 426, 'dy' => 360, 'offx' => 1, 'offy' => 0,
  'fontsize' => 18
);

%stitchinfo_3x2_lg =
(
  'fullsize' => '1920x1080', 'tilesize' => '640x540',
  'dx' => 640, 'dy' => 540, 'offx' => 0, 'offy' => 0,
  'fontsize' => 24
);

# 4:3 full (2x3 array of 16:9-ish)

%stitchinfo_2x3_sm =
(
  'fullsize' => '640x480', 'tilesize' => '320x160',
  'dx' => 320, 'dy' => 160, 'offx' => 0, 'offy' => 0,
  'fontsize' => 10
);

%stitchinfo_2x3_md =
(
  'fullsize' => '800x600', 'tilesize' => '400x200',
  'dx' => 400, 'dy' => 200, 'offx' => 0, 'offy' => 0,
  'fontsize' => 14
);

%stitchinfo_2x3_lg =
(
  'fullsize' => '1280x960', 'tilesize' => '640x320',
  'dx' => 640, 'dy' => 320, 'offx' => 0, 'offy' => 0,
  'fontsize' => 20
);



#
# Public Functions
#


# This assembles a stitched composite image from the specified source images.
# Arg 0 is the filename to write to.
# Arg 1 points to a hash of filenames to read from, indexed by slot label.
# Arg 2 points to the stitching geometry info hash.
# Arg 3 points to the stitching slot placement hash.
# Arg 4 (optional) is a string to place at the bottom of the stitched image.
# Returns 1 if successful and 0 if not.

sub NCAM_CreateStitchedImage
{
  my ($oname, $imglut_p, $stitchinfo_p, $stitchslots_p, $caption, $isok);
  my ($baseimage, $slotimage);
  my ($slotname, $placement_p, $thisimg);
  my ($osetx, $osety);

  $oname = $_[0];
  $imglut_p = $_[1];
  $stitchinfo_p = $_[2];
  $stitchslots_p = $_[3];
  # Caption is optional.
  $caption = $_[4];

  $isok = 0;

  if ( (defined $oname) && (defined $imglut_p)
    && (defined $stitchinfo_p) && (defined $stitchslots_p) )
  {
    # Initialize to a grey canvas.
    $baseimage = Image::Magick->new(size => $$stitchinfo_p{fullsize});
    $baseimage->ReadImage('canvas:grey30');

    # Tile in any slot images defined.
    foreach $slotname (@NCAM_session_slots)
    {
      $thisimg = $$imglut_p{$slotname};
      $placement_p = $$stitchslots_p{$slotname};

# FIXME - Diagnostics.
#if (defined $thisimg)
#{ print STDERR "-- $oname : $slotname : $thisimg\n"; }
#else
#{ print STDERR "-- $oname : $slotname : (null)\n"; }

      # Make sure we have a filename and that a file of nonzero size exists.
      if (!( (defined $thisimg) && (defined $placement_p) ))
      {
        # Empty slot.
      }
      elsif (!( ( -e $thisimg ) && ( -s $thisimg ) ))
      {
# FIXME - Diagnostics.
print STDERR "-- $oname : can't find $thisimg\n";
      }
      else
      {
# FIXME - Diagnostics.
#print STDERR "-- $oname : adding $thisimg\n";

        $slotimage = Image::Magick->new();
# FIXME - We need to handle image read failure gracefully!
        $slotimage->Read($thisimg);
# FIXME - "sample" forces point filtering and is fast.
# "resize" is slower even with point filtering.
        $slotimage->Sample(geometry => $$stitchinfo_p{tilesize});
#        $slotimage->Resize(geometry => $$stitchinfo_p{tilesize},
# FIXME - Point filtering is slightly faster, but visibly worse.
#          'filter' => 'Gaussian');
#          'filter' => 'Point');
        $slotimage->Annotate('text' => $$placement_p{label},
          'gravity' => 'North', 'stroke' => 'orange', 'fill' => 'orange',
          'pointsize' => $$stitchinfo_p{fontsize});

        # Calculate centering information for images.
        # Fold in stitchinfo offset while we're at it.
        $osetx = $slotimage->Get('width');
        $osetx = $$stitchinfo_p{dx} - $osetx;
        $osetx = ($osetx >> 1) + $$stitchinfo_p{offx};
        $osety = $slotimage->Get('height');
        $osety = $$stitchinfo_p{dy} - $osety;
        $osety = ($osety >> 1) + $$stitchinfo_p{offy};

        $baseimage->Composite('image' => $slotimage,
          'compose' => 'Over',
          'geometry' => sprintf('%s+%d+%d', $$stitchinfo_p{tilesize},
            $osetx + $$stitchinfo_p{dx} * $$placement_p{x},
            $osety + $$stitchinfo_p{dy} * $$placement_p{y})
        );

        undef $slotimage;
      }
    }

    # Add the caption, if we have one.
    if (defined $caption)
    {
      $baseimage->Annotate('text' => $caption,
        'gravity' => 'South', 'stroke' => 'orange', 'fill' => 'orange',
        'pointsize' => 2 * $$stitchinfo_p{fontsize});
    }

    # Write the image file.
    $baseimage->Write($oname);

    # Clean up.
    undef $baseimage;

    # If we managed to produce a file of nonzero size, assume success.
    if ( ( -e $oname ) && (-s $oname ) )
    { $isok = 1; }
  }

  return $isok;
}



# This assembles a composite-compatible image from a single source image.
# Arg 0 is the filename to write to.
# Arg 1 points to a hash of filenames to read from, indexed by slot label.
# This should have a single entry (only the first entry is read).
# Arg 2 points to the stitching geometry info hash.
# Arg 3 points to the stitching slot placement hash.
# Arg 4 (optional) is a string to place at the bottom of the stitched image.
# Returns 1 if successful and 0 if not.

sub NCAM_CreateSoloImage
{
  my ($oname, $imglut_p, $stitchinfo_p, $stitchslots_p, $caption, $isok);
  my ($baseimage, $slotimage);
  my (@labellist);
  my ($slotname, $prettyname, $thisimg);
  my ($osetx, $osety);

  $oname = $_[0];
  $imglut_p = $_[1];
  $stitchinfo_p = $_[2];
  $stitchslots_p = $_[3];
  # Caption is optional.
  $caption = $_[4];

  $isok = 0;

  if ( (defined $oname) && (defined $imglut_p)
    && (defined $stitchinfo_p) && (defined $stitchslots_p) )
  {
    # Initialize to a grey canvas.
    $baseimage = Image::Magick->new(size => $$stitchinfo_p{fullsize});
    $baseimage->ReadImage('canvas:grey30');

    # Get the filename and slot name.
    @labellist = sort {$a cmp $b} keys %$imglut_p;
    $slotname = $labellist[0];

    if (defined $slotname)
    {
      $thisimg = $$imglut_p{$slotname};

      # Try to get a pretty version of the slot name.
      # Fall back to copying it verbatim.
      $prettyname = $slotname;
      if (defined $$stitchslots_p{$slotname})
      {
        $prettyname = $$stitchslots_p{$slotname}{label};
      }

      # Make sure we have a filename and that a file of nonzero size exists.
      if (!(defined $thisimg))
      {
        # Empty slot.
      }
      elsif (!( ( -e $thisimg ) && ( -s $thisimg ) ))
      {
# FIXME - Diagnostics.
print STDERR "-- $oname : can't find $thisimg\n";
      }
      else
      {
        $slotimage = Image::Magick->new();
# FIXME - We need to handle image read failure gracefully!
        $slotimage->Read($thisimg);
# FIXME - "sample" forces point filtering and is fast.
# "resize" is slower even with point filtering.
        $slotimage->Sample(geometry => $$stitchinfo_p{fullsize});
#        $slotimage->Resize(geometry => $$stitchinfo_p{fullsize},
# FIXME - Point filtering is slightly faster, but visibly worse.
#          'filter' => 'Gaussian');
#          'filter' => 'Point');
        $slotimage->Annotate('text' => $prettyname,
          'gravity' => 'North', 'stroke' => 'orange', 'fill' => 'orange',
          'pointsize' => $$stitchinfo_p{fontsize});

        # Calculate centering information for images.
        # Fold in stitchinfo offset while we're at it.
        $osetx = $baseimage->Get('width') - $slotimage->Get('width');
        $osetx >>= 1;
        $osety = $baseimage->Get('height') - $slotimage->Get('height');
        $osety >>= 1;

        $baseimage->Composite('image' => $slotimage,
          'compose' => 'Over',
          'geometry' => sprintf('%s+%d+%d', $$stitchinfo_p{fullsize},
            $osetx, $osety)
        );

        undef $slotimage;
      }
    }

    # Add the caption, if we have one.
    if (defined $caption)
    {
      $baseimage->Annotate('text' => $caption,
        'gravity' => 'South', 'stroke' => 'orange', 'fill' => 'orange',
        'pointsize' => 2 * $$stitchinfo_p{fontsize});
    }

    # Write the image file.
    $baseimage->Write($oname);

    # Clean up.
    undef $baseimage;

    # If we managed to produce a file of nonzero size, assume success.
    if ( ( -e $oname ) && (-s $oname ) )
    { $isok = 1; }
  }

  return $isok;
}



#
# Main Program
#


# Report success.
1;



#
# This is the end of the file.
#
