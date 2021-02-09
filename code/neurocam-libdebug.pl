#!/usr/bin/perl
#
# NeuroCam management script - Debug routines.
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
# Functions
#

# This accepts a structure reference, and returns a scalar containing text
# describing the contents of the structure.
# This is human-readable, and can be reconstructed via TextToStructure().
# Arg 0 points to the structure to analyze.
# Arg 1 (optional) is an indentation prefix string.
# Returns a scalar containing multiple lines of text.

sub NCAM_StructureToText
{
  my ($structure_p, $prefix, $result);
  my ($typestr);
  my ($hashkey, $hashval);
  my ($listidx, $listval);

  $structure_p = $_[0];
  $prefix = $_[1];
  $result = '';

  if (defined $structure_p)
  {
    if (!(defined $prefix))
    { $prefix = ''; }

    # Increase indent level.
    $prefix .= '  ';

    # Figure out what we're dealing with.
    $typestr = ref($structure_p);

    # Emit the structure.

    # The first line of the return value has no prefix.
    # The last line of the return value has no newline.
    # This is so that we can emit lists and hashes properly.

    if ('' eq $typestr)
    {
      # This is a scalar.
      $result = '(scalar) "' . $structure_p . '"';
    }
    elsif ('SCALAR' eq $typestr)
    {
      # This is a scalar reference.
      $result = '(scalar ref) "' . $$structure_p . '"';
    }
    elsif ('ARRAY' eq $typestr)
    {
      # This is a list.
      $result = '(list)' . "\n";

      # FIXME - Blithely assume this starts at 0.
      for ($listidx = 0;
        defined ($listval = $$structure_p[$listidx]);
        $listidx++)
      {
        $result .= $prefix . $listidx . ' :  '
          . NCAM_StructureToText($$structure_p[$listidx], $prefix)
          . "\n";
      }

      $result .= $prefix . '(end of list)';
    }
    elsif ('HASH' eq $typestr)
    {
      # This is a hash.
      $result = '(hash)' . "\n";

      foreach $hashkey (sort keys %$structure_p)
      {
        $hashval = $$structure_p{$hashkey};

        $result .= $prefix . $hashkey . ' ->  '
          . NCAM_StructureToText($$structure_p{$hashkey}, $prefix)
          . "\n";
      }

      $result .= $prefix . '(end of hash)';
    }
    else
    {
      $result .= $prefix . '(err) "' . scalar($structure_p) . '"' . "\n";
    }
  }

  return $result;
}



# FIXME - NCAM_TextToStructure NYI.



#
# Main Program
#


# Report success.
1;



#
# This is the end of the file.
#
