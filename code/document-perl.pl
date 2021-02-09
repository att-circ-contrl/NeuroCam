#!/usr/bin/perl
# Written by Christopher Thomas.
#
# This script tries to autogenerate "header file" type documentation for
# Perl scripts that I've written.
#
# It does this by looking for comment blocks immediately above subroutine 
# and global variable declarations.
#
# Usage:  document-perl.pl <input files>
#
# Output is written to stdout.
#


#
# Includes
#

use strict;



#
# Functions
#

# Displays a help screen.
# No arguments.
# No return value.

sub PrintHelp
{
  print << "Endofblock";

 This script tries to autogenerate "header file" type documentation for
 Perl scripts that I've written.

 It does this by looking for comment blocks immediately above subroutine 
 and global variable declarations.

 Usage:  document-perl.pl <input files>

 Output is written to stdout.

Endofblock
}



# Emits documentation describing the script itself.
# Arg 0 is the name of the script file.
# Arg 1 points to an array of comment text.
# No return value.

sub ProcessGlobalDocs
{
  my ($fname, $comments_p);
  my ($thisline);

  $fname = $_[0];
  $comments_p = $_[1];

  if (!( (defined $fname) && (defined $comments_p) ))
  {
    print "### [ProcessGlobalDocs]  Bad arguments.\n";
  }
  else
  {
    # FIXME - Have prettier options available later (html, LaTeX).

    # Text output.

    print "(script)  $fname\n";
    foreach $thisline (@$comments_p)
    {
      print "$thisline\n";
    }
    print "\n";
  }
}



# Emits documentation for a subroutine.
# Arg 0 is the name of the subroutine.
# Arg 1 points to an array of comment text.
# No return value.

sub ProcessSubroutine
{
  my ($sname, $comments_p);
  my ($thisline);

  $sname = $_[0];
  $comments_p = $_[1];

  if (!( (defined $sname) && (defined $comments_p) ))
  {
    print "### [ProcessSubroutine]  Bad arguments.\n";
  }
  else
  {
    # FIXME - Have prettier options available later (html, LaTeX).

    # Text output.

    print "\n";
    print "(sub)  $sname\n";
    foreach $thisline (@$comments_p)
    {
      print "$thisline\n";
    }
    print "\n";
  }
}



# Emits documentation for one or more global variables.
# Arg 0 is a string containing a comma-delimited list of variable names.
# Arg 1 points to an array of comment text.
# No return value.

sub ProcessGlobalVars
{
  my ($vlist, $comments_p);
  my ($thisline);

  $vlist = $_[0];
  $comments_p = $_[1];

  if (!( (defined $vlist) && (defined $comments_p) ))
  {
    print "### [ProcessGlobalVars]  Bad arguments.\n";
  }
  else
  {
    # FIXME - Have prettier options available later (html, LaTeX).

    # FIXME - Not parsing the variable list.

    # Text output.

    print "\n";
    print "(var)  $vlist\n";
    foreach $thisline (@$comments_p)
    {
      print "$thisline\n";
    }
    print "\n";
  }
}



#
# Main Program
#

my ($fidx, $thisfile);
my (@fdata, $thisline, $thisarg);
my ($comments_p, $in_comment);
my ($at_start, $in_preamble);


if (!(defined $ARGV[0]))
{
  PrintHelp();
}
else
{
  for ($fidx = 0; defined ($thisfile = $ARGV[$fidx]); $fidx++)
  {
    if (!open(INFILE, "<$thisfile"))
    {
      print "### Unable to read from \"$thisfile\".\n";
    }
    else
    {
      undef @fdata;
      @fdata = <INFILE>;
      close(INFILE);

      $comments_p = [];
      $in_comment = 0;
      $at_start = 1;
      $in_preamble = 1;

      foreach $thisline (@fdata)
      {
        if ($thisline =~ m/^\s*#\s*(.*)$/)
        {
          $thisline = $1;

          if (!$in_comment)
          {
            $comments_p = [];
            $in_comment = 1;
          }

          # Keep whitespace.
          # Drop "#!/usr/bin/perl" (anything with "#!").
#          if ( ($thisline =~ m/(.*\S)/)
          if (!($thisline =~ m/^\s*!/))
          {
            push @$comments_p, $1;
          }
        }
        else
        {
          # Not in a comment.
          $in_comment = 0;

          if ($at_start)
          {
            $at_start = 0;

            ProcessGlobalDocs($thisfile, $comments_p);
          }
          elsif ($thisline =~ m/^\s*sub\s*(\S+)/)
          {
            # Subroutine declaration.

            $thisarg = $1;
            $in_preamble = 0;

            ProcessSubroutine($thisarg, $comments_p);
          }
          elsif ( $in_preamble && ($thisline =~ m/^\s*my\s*\(([^)]*)/))
          {
            # Global variable declaration in preamble.
            # FIXME - Only counting "my". Other cases exist.

            # FIXME - Not handling multi-line declarations!
            # These exist, so this is a problem.
            # The right thing to do is keep appending until ")", then 
            # process.

            # FIXME - This should also handle multiple-"my" cases!
            # We should delay processing until we see something that's not
            # a variable declaration.

            $thisarg = $1;

            ProcessGlobalVars($thisarg, $comments_p);
          }


          # If we've seen anything but whitespace, reset comments.
          if ($thisline =~ m/\S/)
          {
            $comments_p = [];
          }
        }

        # Finished with this line.
      }
    }
  }
}


#
# This is the end of the file.
#
