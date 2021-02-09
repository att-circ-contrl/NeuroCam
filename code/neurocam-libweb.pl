#!/usr/bin/perl
#
# NeuroCam management script - Web content library.
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

# Base folder in the web directory that contains repository folders.
our ($NCAM_cgi_repository_base, $NCAM_cgi_usb_repository_base);
$NCAM_cgi_repository_base = 'repositories';
$NCAM_cgi_usb_repository_base = 'ncam-repositories';

# User-readable release version for the NeuroCam software.
# FIXME - This should be somewhere more central than here.
our ($NCAM_cgi_version);
$NCAM_cgi_version = 'v.2018-07-11';

# Configuration switch indicating whether we're doing a move or a copy.
our ($NCAM_cgi_do_move_delete);
$NCAM_cgi_do_move_delete = 0;



#
# Shared Variables
#

# FIXME - Doing this the messy way. Any imported variables need appropriate
# "our" declarations.

our (@NCAM_session_slots);
our (%NCAM_default_settings);
our (%NCAM_exposure_stops);

our ($stitchinfo_preview_p, $stitchslots_preview_p);



#
# Constants
#

# Web page templates, to search-and-replace on.
# NOTE - "<< 'foo'", with single-quotes, treats content as literal.
# No escaping is needed; use normal HTML without worry.

my ($page_config);
my ($page_config_deventry, $page_config_streamentry, $page_config_talkentry);
my ($page_config_cellimage, $page_config_cellempty);

# Auxiliary information for the config page's monitor preview.
my (%monitor_preview_lut);
%monitor_preview_lut =
( 'CELLSCENEA' => 'SceneA', 'CELLSCENEB' => 'SceneB', 'CELLSCENEC' => 'SceneC',
  'CELLFACEA' => 'FaceA', 'CELLFACEB' => 'FaceB', 'CELLGAME' => 'Game' );

my ($page_monitor);
my ($page_monitor_buttons_3x2, $page_monitor_buttons_2x3);
my ($page_monitor_control, $page_monitor_video);

my ($page_browser);
my ($page_browser_table);
my ($page_browser_eject);
my ($page_browser_eject_done);
my ($page_browser_entry);
my ($page_browser_foldview);
my ($page_browser_download);
my ($page_browser_move);
my ($page_browser_post);

my ($page_busy);
my ($page_busy_cancelbutton);

my ($page_shutdown);

my ($page_textmessage);
my ($page_frameexit);
my ($page_redirect);


# Configuration page.
# Substitute DEVLIST with device entries, STREAMLIST with stream entries,
# and TALKERLIST with talker entries.
# Substitute PREVIEWIMAGE with the stitched image to display.
# Substitute TIMESTAMP with a unique string (anything) to force a re-fetch.
# ERRMSG is the error message, if any. Use a blank string if none.
# AUTORESOLUTION and AUTOFRAMERATE are option lists for the desired
# resolution and frame rate when auto-setting cameras or setting all sizes.
# EXPOSURE is an opton list for the desired exposure when setting all sizes.
# Device list entries ($page_config_deventry):
# Substitute IMAGEFILE and DEVICENAME (multiple). Option lists are RESOLUTION,
# FRAMERATE, EXPOSURE, and SLOTNAME. DEVTAG is multiply-substituted. PORT is
# hidden.
# Substitute TIMESTAMP with a unique string (anything) to force a re-fetch.
# Stream list entries ($page_config_streamentry):
# Substitute IMAGEFILE, STREAMURL (multiple),STREAMLABEL (multiple), and
# STREAMTAG (multiple). Option list is SLOTNAME.
# PORT and DELAY are hidden.
# Substitute TIMESTAMP with a unique string (anything) to force a re-fetch.
# Talker entries ($page_config_talkentry):
# Substitute TALKADDRESS, TALKTAG (multiple), and TALKLABEL (multiple).
# TALKCHECKED is "" or "checked".
# TALKKEY, TALKHOST, TALKPORT, and MYPORT are hidden.

$page_config = << 'Endofblock';
<!DOCTYPE html>
<html>
<head>
<title>NeuroCam Session Configuration</title>
<meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">
<meta http-equiv="Pragma" content="no-cache">
<meta http-equiv="Expires" content="0">
</head>
<body>

<center><font size="+3">NeuroCam Session Configuration</font></center><br>
<center><font size="-2">NCAMVERSION</font></center><br>

<form action="neurocam.cgi" method="post">
<input type="hidden" name="callingpage" value="config">

<table width="100%" border="0">
<tr>


<!-- Camera column -->

<td width="20%" valign="top">

<b>Cameras:</b><br>
<br>
<!-- Device list begins. -->
DEVLIST
<!-- Device list ends. -->


<!-- Stream and message column -->

<td width="25%" valign="top">

<b>Streams:</b><br>
<br>

<!-- FIXME - Stub out "add new stream" control. We don't have a handler for
it, and if handshaking works properly it shouldn't be needed. -->
<!--
<input type="submit" name="command" value="Add New Stream:">
-->
<!-- Be careful with "size=.."; it can mangle column widths. -->
<!--
<input type="text" name="newstreamurl">
<br>
<br>
-->

<!-- Stream list begins. -->
STREAMLIST
<!-- Stream list ends. -->

<br>
<br>

<b>Message Sources:</b><br>
<br>
<!-- Talker list begins. -->
TALKERLIST
<!-- Talker list ends. -->


<!-- Preview and control column -->

<td width="50%" valign="top">

<!-- Monitor preview begins. -->
<center><img src="PREVIEWIMAGE?dummy=TIMESTAMP"><br></center>
<!-- Monitor preview ends. -->

<!-- Control panel begins. -->
<table width="100%" border="0">

<tr>
<td colspan="3">
<font color="red">ERRMSG</font><br>

<tr>
<td><input type="submit" name="command" value="Refresh Preview"><br>
<td bgcolor="#40c040">
<input type="submit" name="command" value="Switch to Repository Browser"><br>
<td bgcolor="#40c040">
<input type="submit" name="command" value="Start"><br>

<tr>
<td><input type="submit" name="command" value="Probe Devices"><br>
<td>
<td>

<tr>
<td><input type="submit" name="command" value="Auto-Assign Slots"><br>
<td colspan="2">
<input type="submit" name="command" value="Adjust Exposure">
for
<select name="autovidsize">
AUTORESOLUTION
</select>
<select name="autovidrate">
AUTOFRAMERATE
</select> fps

<tr>
<td colspan="2">
<input type="submit" name="command" value="Set Cameras">
to
<select name="allvidsize">
AUTORESOLUTION
</select>
<select name="allvidrate">
AUTOFRAMERATE
</select> fps
with Exp <select name="allvidexp">
EXPOSURE
</select>
<td bgcolor="#c04040">
<input type="submit" name="command" value="Restart Manager">

<tr>
<td colspan="2">&nbsp;
<td bgcolor="#c04040">
<input type="submit" name="command" value="Shut Down"><br>


</table>
<!-- Control panel ends. -->


</table>

</form>

</body>
</html>
Endofblock


$page_config_deventry = << 'Endofblock';
<table width="100%">
<tr>
<td width="40%" valign="top">

<!-- FIXME - Force a fixed width image.>
<img width="100%" src="IMAGEFILE?dummy=TIMESTAMP"><br>
-->
<img width="192" src="IMAGEFILE?dummy=TIMESTAMP"><br>

<td valign="top">
<b>DEVICENAME</b><br>
<input type="hidden" name="viddevDEVTAG" value="DEVICENAME">
<input type="hidden" name="vidportDEVTAG" value="PORT">
<!-- Exposure list is auto-generated from metadata each time. -->
<select name="vidsizeDEVTAG">
RESOLUTION
</select>
<select name="vidrateDEVTAG">
FRAMERATE
</select> fps
<br>
Exp <select name="videxpDEVTAG">
EXPOSURE
</select>
<br>
<select name="vidslotDEVTAG">
SLOTNAME
</select>
<br>
</table>
Endofblock


$page_config_streamentry = << 'Endofblock';
<table width="100%">
<tr>
<td width="25%" valign="top">

<!-- FIXME - Force a fixed width image.>
<img width="100%" src="IMAGEFILE?dummy=TIMESTAMP"><br>
-->
<img width="192" src="IMAGEFILE?dummy=TIMESTAMP"><br>

<td valign="top">
<b>Stream: STREAMLABEL</b><br>
(STREAMURL)<br>
<input type="hidden" name="streamurlSTREAMTAG" value="STREAMURL">
<input type="hidden" name="streamportSTREAMTAG" value="PORT">
<input type="hidden" name="streamlabelSTREAMTAG" value="STREAMLABEL">
<!-- FIXME - Delay should be a proper input! -->
<input type="hidden" name="streamdelaySTREAMTAG" value="DELAY">
<select name="streamslotSTREAMTAG">
SLOTNAME
</select><br>
</table>
Endofblock


$page_config_talkentry = << 'Endofblock';
<b>Message source: TALKLABEL</b>
(enable:
<input type="checkbox" name="talkenabledTALKTAG" value="enabled" TALKCHECKED>)<br>
(TALKADDRESS)<br>
<input type="hidden" name="talkkeyTALKTAG" value="TALKKEY">
<input type="hidden" name="talkhostTALKTAG" value="TALKHOST">
<input type="hidden" name="talkportTALKTAG" value="TALKPORT">
<input type="hidden" name="talkmyportTALKTAG" value="MYPORT">
<input type="hidden" name="talklabelTALKTAG" value="TALKLABEL">
Endofblock


# Monitor page.
# NOTE - $page_monitor_control and $page_monitor_video are both embedded
# via frames (contents returned via their own CGI calls).
# In $page_monitor_control, subsitute ERRMSG if there's an error.
# Substitute BUTTONS with $page_monitor_buttons_3x2 or _2x3.
# In $page_monitor_video, substitute HOSTNAME, MONITORPORT, and
# MONITORFILENAME. GEOMETRY is either empty or "width=NN height=NN".
# Substitute TIMESTAMP with a unique string (anything) to force a re-fetch.
# FIXME - Doing this trick with an mjpeg fetch is asking for trouble.

$page_monitor = << 'Endofblock';
<!DOCTYPE html>
<html>
<head>
<title>NeuroCam Session Monitor</title>
<meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">
<meta http-equiv="Pragma" content="no-cache">
<meta http-equiv="Expires" content="0">
</head>

<!-- NOTE - "frameset" _replaces_ "body". -->

<frameset cols="25%,75%">
<frame
  src="neurocam.cgi?destpage=controlpane&dummy=TIMESTAMP"
  frameborder="0" scrolling="no">
<frame src="neurocam.cgi?destpage=videopane&dummy=TIMESTAMP"
  frameborder="0" scrolling="no">
</frameset>

</html>
Endofblock


# NOTE - One of these gets substituted into the control panel.
# Which one depends on how the image array is set up.

$page_monitor_buttons_3x2 = << 'Endofblock';
<tr>
<td><input type="submit" name="command" value="Scene A">
<td><input type="submit" name="command" value="Scene B">
<td><input type="submit" name="command" value="Scene C">
<tr>
<td><input type="submit" name="command" value="Face A">
<td><input type="submit" name="command" value="Face B">
<td><input type="submit" name="command" value="Game">
Endofblock

$page_monitor_buttons_2x3 = << 'Endofblock';
<tr>
<td><input type="submit" name="command" value="Scene A">
<td><input type="submit" name="command" value="Face A">
<tr>
<td><input type="submit" name="command" value="Scene B">
<td><input type="submit" name="command" value="Face B">
<tr>
<td><input type="submit" name="command" value="Scene C">
<td><input type="submit" name="command" value="Game">
Endofblock


$page_monitor_control = << 'Endofblock';
<!DOCTYPE html>
<html>
<head>
<title>NeuroCam Session Monitor - Control Pane</title>
<meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">
<meta http-equiv="Pragma" content="no-cache">
<meta http-equiv="Expires" content="0">
</head>
<body>

<!-- Annotation form. This is the main control panel. -->

<form action="neurocam.cgi" method="post">
<input type="hidden" name="callingpage" value="controlpane">

<b>Add Marker:</b><br>
<table border="0">
BUTTONS
</table>

<br>
<br>
<input type="text" name="notetext" size="40"><br>
<input type="submit" name="command" value="Annotate">

<br>
<br>
<font color="red">ERRMSG</font><br>
<br>

<table border="0">
<tr>
<td bgcolor="#c04040">
<input type="submit" name="command" value="End Session" target="_top">
&nbsp;&nbsp;
</table><br>

</form>

<!-- Input feed switching form. -->

<form action="neurocam.cgi" method="post">
<input type="hidden" name="callingpage" value="controlfeed">

<br>
<br>
<br>

<b>Select Video Feed:</b><br>
<table border="0">
BUTTONS
</table>

<table border="0">
<td><input type="submit" name="command" value="Combined Feed">
</table>

</form>

</body>
</html>
Endofblock


$page_monitor_video = << 'Endofblock';
<!DOCTYPE html>
<html>
<head>
<title>NeuroCam Session Monitor - Video Pane</title>
<meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">
<meta http-equiv="Pragma" content="no-cache">
<meta http-equiv="Expires" content="0">
</head>
<body>

<!-- FIXME - This won't work on internet explorer! -->
<!-- This can be addressed by allowing the user to select the slower
  javascript version of this page. -->
<!-- FIXME - The ?dummy=string trick _should_ be safe, but is still ugly. -->
<img src="http://HOSTNAME:MONITORPORT/MONITORFILENAME?dummy=TIMESTAMP"
GEOMETRY>

</body>
</html>
Endofblock



# Repository browsing page.
# In $page_browser, substitute ERRMSG with an error message (if any),
# and DISKLIST with one or more copies of $page_browser_table.
# in $page_browser_table, substitute DISKNAME with a human-readable drive
# label, DISKGIGS with disk space free, and REPOLIST with zero or more
# copies of $page_browser_entry. DISKEJECT is either $page_browser_eject or
# "". FOLDTITLE is either "Session Folder" or "Archive Package", and
# POSTTITLE is either "Post-Processing" or "".
# In $page_browser_entry, substitute REPOTOP (multiple copies) with the base
# repository path and REPOFOLDER (multiple copies) with the session's
# subdirectory name.
# FOLDERVIEW is substituted with $page_browser_foldview for local drives and
# $page_browser_download for USB drives.
# FOLDERGIGS is the size taken up by the repository and/or tar file, and
# FOLDERMOVE is either $page_browser_move or "".
# POSTBUTTON is either $page_browser_post or "".
# In $page_browser_foldview, substitute REPOTOP and REPOFOLDER per above.
# In $page_browser_download, REPOFILE gets substituted with the .tar filename.
# In $page_browser_move, TARGET is a human-readable destination (e.g. "USB").
# In $page_browser_post, POSTPROCNAME is "Post-Process" or
# "Redo Post-Processing".

$page_browser = << 'Endofblock';
<!DOCTYPE html>
<html>
<head>
<title>NeuroCam Repository Browser</title>
<meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">
<meta http-equiv="Pragma" content="no-cache">
<meta http-equiv="Expires" content="0">
</head>
<body>

<center><font size="+2">NeuroCam Repository</font></center><br>
<center><font size="-2">NCAMVERSION</font></center><br>

<br>
<table width="100%" border="0">

<tr>

<td width="15%">
<form action="neurocam.cgi" method="post">
<!-- We're doing a cold start of the browser page; command doesn't matter. -->
<input type="hidden" name="destpage" value="browser">
<input type="submit" name="command" value="Refresh"><br>
</form>

<td bgcolor="#40c040" width="15%">
<form action="neurocam.cgi" method="post">
<!-- For page switching, don't specify the caller; it's a cold start. -->
<input type="hidden" name="destpage" value="config">
<input type="submit" name="command" value="Switch to Configuration Page"><br>
</form>

<td width="50%">&nbsp;

<td bgcolor="#c04040" width="15%" align="right">
<form action="neurocam.cgi" method="post">
<input type="hidden" name="callingpage" value="browser">
<input type="hidden" name="destpage" value="browser">
<input type="submit" name="command" value="Restart Manager"><br>
</form>

<tr>
<td width="15%">
<form action="neurocam.cgi" method="post">
<input type="hidden" name="callingpage" value="browser">
<input type="hidden" name="destpage" value="browser">
<input type="submit" name="command" value="Recalc Sizes"><br>
</form>

<td valign="top" colspan="2">
<font color="red">ERRMSG</font>

<td bgcolor="#c04040" width="15%" align="right">
<form action="neurocam.cgi" method="post">
<!-- Jump directly to the shutdown page. -->
<!-- Cold start is fine for this too. -->
<input type="hidden" name="destpage" value="shutdown">
<input type="submit" name="command" value="Shut Down"><br>
</form>

</table>

DISKLIST

</body>
</html>
Endofblock

$page_browser_table = << 'Endofblock';

<br>
<br>

<table width="100%">
<tr>
<td width="15%">
<b>DISKNAME</b>
<td width="65%">
<center>Available disk space: DISKGIGS gigabytes</center>
<td width="15%">
DISKEJECT
</table>
<br>

<!-- FIXME - Subtable shenanigans is because we need to have one form per
row, and keep formatting consistent between rows and title row. -->

<table width="100%" border="0">

<tr>

<td width="25%">
<table width="100%" border="0">
<tr>
<td><b>FOLDTITLE</b>
</table>

<td width="70%">
<table width="100%" border="0">
<tr>
<td width="25%">&nbsp;
<td width="40%"><b>POSTTITLE</b>
<td width="30%">&nbsp;
</table>

REPOLIST

</table>

Endofblock

$page_browser_eject = << 'Endofblock';
<form action="neurocam.cgi" method="post">
<input type="hidden" name="callingpage" value="browser">
<input type="submit" name="command" value="Eject">
</form>
Endofblock

$page_browser_eject_done = << 'Endofblock';
<!DOCTYPE html>
<html>
<head>
<title>NeuroCam Repository Browser</title>
<meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">
<meta http-equiv="Pragma" content="no-cache">
<meta http-equiv="Expires" content="0">
</head>
<body>

<br>
<br>
<br>
<br>

<center>
<font size="+2">Media Ejected</font><br>
<br>
Please unplug the USB drive from the NeuroCam, and click to continue.<br>
<form action="neurocam.cgi" method="post">
<!-- For page switching, don't specify the caller; it's a cold start. -->
<input type="hidden" name="destpage" value="browser">
<input type="submit" name="command" value="Continue"><br>
</form>
</center>

</body>
</html>
Endofblock

$page_browser_entry = << 'Endofblock';
<!-- FIXME - Subtable shenanigans is because we need to have one form per
row, and keep formatting consistent between rows and title row. -->

<tr>

<td>
<table width="100%" border="0">
<tr>
FOLDERVIEW
(FOLDERGIGS GB)
</table>


<td>
<form action="neurocam.cgi" method="post">

<input type="hidden" name="callingpage" value="browser">
<input type="hidden" name="repotop" value="REPOTOP">
<input type="hidden" name="folder" value="REPOFOLDER">
<table width="100%" border="0">

<td width="25%">
FOLDERMOVE
&nbsp;

<td width="40%">
POSTBUTTON
&nbsp;

<td width="30%">
<input type="submit" name="command" value="Delete">
(<input type="checkbox" name="deletecheck" value="reallydelete">confirm)

</table>

</form>
Endofblock

$page_browser_foldview = << 'Endofblock';
<!-- "_blank" makes this open in a new tab. -->
<td><a href="REPOTOP/REPOFOLDER" target="_blank">REPOFOLDER</a>
Endofblock

$page_browser_download = << 'Endofblock';
<a href="REPOFILE">REPOFOLDER</a>
Endofblock

if ($NCAM_cgi_do_move_delete)
{
$page_browser_move = << 'Endofblock';
<input type="submit" name="command" value="Move to TARGET">
Endofblock
}
else
{
$page_browser_move = << 'Endofblock';
<input type="submit" name="command" value="Copy to TARGET">
Endofblock
}

$page_browser_post = << 'Endofblock';
<input type="submit" name="command" value="POSTPROCNAME">
(<input type="checkbox" name="synchcheck" value="useledsynch" checked>use
LED blinks)
Endofblock


# "Please wait for operation to finish" page.
# In $page_busy, substitute REALTARGET with the page to load when waiting
# finishes, OPNAME with the operation we're waiting on, and PROGRESS with
# a progress message (optional).
# Substitute TIMESTAMP with a unique string (anything) to force a re-fetch.
# Substitute CANCELBUTTON with either an empty string or the contents of
# $page_busy_cancelbutton, depending on whether the button is desired or not.
# Substitute ARGLIST with a series of "$argNAME=VALUE" pairs to pass to the
# fallthrough page. This may be "".
# In $page_busy_cancelbutton, substitute REALTARGET with the page to load
# when waiting finishes.

$page_busy = << 'Endofblock';
<!DOCTYPE html>
<html>
<head>
<!-- Reload this every 10 seconds to update the progress report. -->
<!-- Manually force the URL; otherwise we try re-posting the previous call. -->
<meta http-equiv="refresh" content="5; url=neurocam.cgi?callingpage=busy&fallthrough=REALTARGETARGLIST&dummy=TIMESTAMP">
<title>NeuroCam Processing In Progress</title>
<meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">
<meta http-equiv="Pragma" content="no-cache">
<meta http-equiv="Expires" content="0">
</head>
<body>

<center><font size="+2">Please Wait</font></center><br>

<br>
<br>
<br>
<br>

<center>
<table border="2" cellpadding="5">
<tr>
<td bgcolor="#d0ffd0">
<font size="+3">OPNAME PROGRESS</font>
CANCELBUTTON
</table>
</center><br>

</body>
</html>
Endofblock


$page_busy_cancelbutton = << 'Endofblock';
<tr>
<td><center>
<form action="neurocam.cgi" method="post">

<input type="hidden" name="callingpage" value="busy">
<input type="hidden" name="fallthrough" value="REALTARGET">

<input type="submit" name="command" value="Cancel">

</form>
</center>
Endofblock


# "Shutting down" page.
# Nothing to substitute.

$page_shutdown = << 'Endofblock';
<!DOCTYPE html>
<html>
<head>
<title>NeuroCam Shutting Down</title>
<meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">
<meta http-equiv="Pragma" content="no-cache">
<meta http-equiv="Expires" content="0">
</head>
<body>

<br>
<br>
<br>
<br>

<center>
<table border="2" cellpadding="5">
<tr>
<td bgcolor="#d0ffd0">
<font size="+3">Shutting Down</font>
</table>
<br>
When the NeuroCam power light is off, the system may be disconnected.<br>
</center>

</body>
</html>
Endofblock


# Generic message template page.
# Substitute MESSAGE for the text to display.

$page_textmessage = << 'Endofblock';
<!DOCTYPE html>
<html>
<head>
<title>NeuroCam CGI Script</title>
<meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">
<meta http-equiv="Pragma" content="no-cache">
<meta http-equiv="Expires" content="0">
</head>
<body>

<font size="+1">MESSAGE</font>

</body>
</html>
Endofblock


# Forced frame exit page.
# This causes the top-level window to reload the base URL with CGI arguments
# added. Substitute CGIARGS for the URL's argument string (everything after
# the ? mark).

$page_frameexit = << 'Endofblock';
<!DOCTYPE html>
<html>
<head>
<title>NeuroCam CGI Script</title>
<!-- This forces a full-window load of the base URL plus arguments. -->
<script language="JavaScript" type="text/javascript">
top.location.assign(location.href + "?CGIARGS");
</script>
<!-- Original: -->
<!-- if (top != self) top.location.href = location.href; -->
</head>
<body>

Page transition in progress.

</body>
</html>
Endofblock


# Forced transition page.
# This forces a redirect to the specified URL (given in "URL").
# This is _not_ a CGI call.

$page_redirect = << 'Endofblock';
<!DOCTYPE html>
<html>
<head>
<meta http-equiv="refresh" content="0; url=URL">
<title>NeuroCam CGI Script</title>
</head>
<body>

Redirect to <a href="URL">"URL"</a> in progress.

</body>
</html>
Endofblock



#
# Public Functions
#

# Transforms an arbitrary string into a filename- and web-safe string.
# Arg 0 is the string to translate.
# Returns the forced-safe string.

sub NCAM_MakeSafeFilename
{
  my ($iname, $result);

  $iname = $_[0];
  $result = undef;

  if (defined $iname)
  {
    # Only translate non-empty strings.
    if ($iname =~ m/^\s*(.*\S)/ms)
    {
      # Trim whitespace while we're at it.
      $result = $1;
      chomp($result);

      # Be draconian: anything that's not alphanumeric gets squashed.
      $result =~ s/\W/_/msg;

      # Done.
    }
  }

  return $result;
}



# Returns a default repository subdirectory name, based on the current time.
# No arguments.
# Returns a directory name string.

sub NCAM_GetDefaultRepoFolder
{
  my ($dirname);

  # Use YYYY-MM-DD-HH-MM. If you click twice within a minute, you're too fast.
  $dirname = POSIX::strftime('ncam-%Y-%m-%d-%H-%M', localtime());

  return $dirname;
}



# Converts a camera, stream, or talker identifier into a web-safe key
# for use in input field names.
# FIXME - This has a length limit and I may be exceeding that!
# Arg 0 is the identifier string to convert.
# Returns a short web-name-safe key.

sub NCAM_MakeSafeFieldLabel
{
  # FIXME - Just wrap the filename maker!
  # This will give names that are very long, but hopefully still valid.
  # The Wrong Way to do this is to use a hash. Collisions will happen but
  # won't be resolved in any particular order.
  # The Right Way to do this is to initialize a lookup table in deterministic
  # order before any use of it, but I'm not sure we can actually do that.

  return NCAM_MakeSafeFilename($_[0]);
}



# Builds a list of <option value="..."> tags for a <select> list.
# Arg 0 points to an array of possible option values.
# Arg 1 is the value to flag as the default.
# Returns a string containing HTML source.

sub NCAM_BuildOptionList
{
  my ($optlist_p, $default, $webtext);
  my ($thisopt);

  $optlist_p = $_[0];
  $default = $_[1];

  $webtext = '';

  if ((defined $optlist_p) && (defined $default))
  {
    foreach $thisopt (@$optlist_p)
    {
      $webtext .= '<option value="' . $thisopt . '"';

      if ($thisopt eq $default)
      { $webtext .= ' selected'; }

      $webtext .= '>' . $thisopt . '</option>' . "\n";
    }
  }

  return $webtext;
}



# Acquires thumbnail snapshots from cameras and video streams and builds a
# mock-up of the monitor screen.
# Arg 0 points to the session configuration hash.
# Arg 1 is the directory to place auxiliary files in.
# No return value.

sub NCAM_GenerateConfigThumbnails
{
  my ($session_p, $outdir);
  my ($cameras_p, $camname, $thiscam_p, $camlabel);
  my ($streams_p, $streamname, $thisstream_p, $streamlabel);
  my ($slots_p, $slotname, $thisslot_p, $previewslot);
  my (%camslotlut, %streamslotlut, %slotimagelut);
  my ($thisfname, $previewfnames_p);
  my ($cmd, $result);

  $session_p = $_[0];
  $outdir = $_[1];

  if ( (defined $session_p) && (defined $outdir) )
  {
    # Extract list pointers.
    $cameras_p = $$session_p{cameras};
    $streams_p = $$session_p{streams};
    $slots_p = $$session_p{slots};


    # Record slot assignments.

    %camslotlut = ();
    %streamslotlut = ();

    foreach $slotname (keys %$slots_p)
    {
      $thisslot_p = $$slots_p{$slotname};

      if ('camera' eq $$thisslot_p{type})
      {
        $camslotlut{$$thisslot_p{config}{device}} = $slotname;
      }
      elsif ('stream' eq $$thisslot_p{type})
      {
        $streamslotlut{$$thisslot_p{config}{url}} = $slotname;
      }
    }

    # Initialize thumbnail LUTs.
    %slotimagelut = ();


    # Clean out the thunmbnails directory.
    $cmd = "rm -f $outdir/*.jpg";
    $result = `$cmd`;


    # Build camera thumbnails.

    foreach $camname (sort keys %$cameras_p)
    {
      $thiscam_p = $$cameras_p{$camname};
      $camlabel = NCAM_MakeSafeFilename($camname);

      $slotname = $camslotlut{$camname};
      if (!(defined $slotname))
      { $slotname = 'none'; }

      # Build a thumbnail for this camera.
      # Set the exposure while we're at it.
      NCAM_SetExposureByStop($thiscam_p, $$thiscam_p{exp});
      $thisfname = $outdir . '/' . $camlabel . '.jpg';
      NCAM_GrabFrame($$thiscam_p{meta}, $$thiscam_p{size}, $thisfname);

      # Record the thumbnail's slot association.
      if ('none' ne $slotname)
      { $slotimagelut{$slotname} = $thisfname; }
    }


    # Build stream thumbnails.

    foreach $streamname (sort keys %$streams_p)
    {
      $thisstream_p = $$streams_p{$streamname};
      $streamlabel = NCAM_MakeSafeFilename($streamname);

      $slotname = $streamslotlut{$streamname};
      if (!(defined $slotname))
      { $slotname = 'none'; }

      # Build a thumbnail for this stream.
      $thisfname = $outdir . '/' . $streamlabel . '.jpg';
      NCAM_GrabStreamFrame($streamname, $thisfname);

      # Record the thumbnail's slot association.
      if ('none' ne $slotname)
      { $slotimagelut{$slotname} = $thisfname; }
    }


    # Build the monitor preview.
    # All needed images should now be in the LUT.

    # Collect a hash of image filenames. These are open() path space, not
    # web path space.
    $previewfnames_p = {};
    foreach $slotname (@NCAM_session_slots)
    {
      if (defined $slotimagelut{$slotname})
      {
        $$previewfnames_p{$slotname} = $slotimagelut{$slotname};
      }
    }

    # Build a stitched preview.
    $thisfname = $outdir . '/preview.jpg';
    NCAM_CreateStitchedImage($thisfname, $previewfnames_p,
      $stitchinfo_preview_p, $stitchslots_preview_p);


    # Make sure the new files are world-readable.
    $cmd = "chmod 644 $outdir/*";
    $result = `$cmd`;


    # Done.
  }
}



# Creates a CGI configuration web page and auxiliary files.
# Arg 0 points to the session configuration hash.
# Arg 1 is the directory to place auxiliary files in.
# Arg 2 is the relative URL prefix for the auxiliary file directory.
# This must have a trailing / if a non-empty string.
# Arg 3 is an error message to display (optional).
# Returns the configuration page's HTML.

sub NCAM_GenerateConfigPage
{
  my ($session_p, $outdir, $outprefix, $errmsg, $pagetext);
  my ($cameras_p, $camname, $thiscam_p, $camlabel);
  my ($streams_p, $streamname, $thisstream_p, $streamlabel);
  my ($talkers_p, $talkername, $thistalker_p, $talkerlabel);
  my ($slots_p, $slotname, $thisslot_p, $previewslot);
  my (%camslotlut, %streamslotlut, %slotimagelut);
  my ($cmd, $result);
  my ($thislisttext, $thisentrytext, $thisdatum, @datalist, $dataptr_p);
  my ($thisfname, $previewfnames_p);
  my (%camsizelut, %camratelut, @camsizelist, @camratelist);
  my ($thishash_p, $thislist_p, $thissize, $thisrate);
  my ($timestamp);

  $session_p = $_[0];
  $outdir = $_[1];
  $outprefix = $_[2];
  $errmsg = $_[3];
  $pagetext = '';

  # $errmsg may be undef.
  if ((defined $session_p) && (defined $outdir) && (defined $outprefix))
  {
    # Extract list pointers.
    $cameras_p = $$session_p{cameras};
    $streams_p = $$session_p{streams};
    $talkers_p = $$session_p{talkers};
    $slots_p = $$session_p{slots};


    # Get timestamp.
    # This is used as a salt string that's unique per call.
    $timestamp = NCAM_GetAbsTimeMillis();


    # Build slot lookup tables.

    %camslotlut = ();
    %streamslotlut = ();

    # Record the slot assignments the session hash already contains.
    foreach $slotname (keys %$slots_p)
    {
      $thisslot_p = $$slots_p{$slotname};

      if ('camera' eq $$thisslot_p{type})
      {
        $camslotlut{$$thisslot_p{config}{device}} = $slotname;
      }
      elsif ('stream' eq $$thisslot_p{type})
      {
        $streamslotlut{$$thisslot_p{config}{url}} = $slotname;
      }
    }

    # This image filename LUT gets filled in later.
    %slotimagelut = ();


    # Initialize output.
    $pagetext = $page_config;


    # Fill in version information.
    $pagetext =~ s/NCAMVERSION/$NCAM_cgi_version/;


    # Set the repository directory, or use a default if we don't have one
    # defined.
    $thisdatum = $$session_p{repodir};
    if (!(defined $thisdatum))
    {
      $thisdatum = NCAM_GetDefaultRepoFolder();
    }
    # FIXME - Squash the repository filename but good.
    $thisdatum = NCAM_MakeSafeFilename($thisdatum);
    $pagetext =~ s/REPODIR/$thisdatum/;


    # Fill in the last error that occurred, if any.
    if (defined $errmsg)
    {
      $pagetext =~ s/ERRMSG/$errmsg/;
    }
    else
    {
      $pagetext =~ s/ERRMSG//;
    }


    # Build the camera list.
    # Build camera resolution and frame rate LUTs while we're here.

    %camsizelut = ();
    %camratelut = ();

    $thislisttext = '';

    foreach $camname (sort keys %$cameras_p)
    {
      $thiscam_p = $$cameras_p{$camname};
      $camlabel = NCAM_MakeSafeFilename($camname);

      $slotname = $camslotlut{$camname};
      if (!(defined $slotname))
      { $slotname = 'none'; }


      # Update resolution information.
      if (defined $$thiscam_p{meta})
      {
        $thishash_p = $$thiscam_p{meta}{sizes};
        if (defined $thishash_p)
        {
          foreach $thissize (keys %$thishash_p)
          {
            $camsizelut{$thissize} = 1;
            $thislist_p = $$thishash_p{$thissize};
            foreach $thisrate (@$thislist_p)
            { $camratelut{$thisrate} = 1; }
          }
        }
      }


      # Build this entry.

      $thisentrytext = $page_config_deventry;

      # Options that aren't lists.
      # Some of these are used multiple times.
      # NOTE - Stubbed-out copies also require multiple substitutions!

      $thisdatum = $outprefix . $camlabel . '.jpg';
      $thisentrytext =~ s/IMAGEFILE/$thisdatum/g;

      $thisentrytext =~ s/DEVICENAME/$camname/g;

      $thisdatum = NCAM_MakeSafeFieldLabel($camname);
      $thisentrytext =~ s/DEVTAG/$thisdatum/g;

      $thisentrytext =~ s/PORT/$$thiscam_p{updateport}/;

      # These are option lists.
      # FIXME - Blithely assume our recorded values match available metadata.

      $dataptr_p = $$thiscam_p{meta}{sizes};
      @datalist = NCAM_SortByResolution(keys %$dataptr_p);
      $thisdatum = NCAM_BuildOptionList(\@datalist, $$thiscam_p{size});
      $thisentrytext =~ s/RESOLUTION/$thisdatum/;

      $dataptr_p = $$thiscam_p{meta}{sizes}{$$thiscam_p{size}};
      # This array is already in sorted order.
      $thisdatum = NCAM_BuildOptionList($dataptr_p, $$thiscam_p{rate});
      $thisentrytext =~ s/FRAMERATE/$thisdatum/;

      $dataptr_p = $$thiscam_p{explist};
      @datalist = sort {$b <=> $a} keys %$dataptr_p;
      $thisdatum = NCAM_BuildOptionList(\@datalist, $$thiscam_p{exp});
      $thisentrytext =~ s/EXPOSURE/$thisdatum/;

      @datalist = @NCAM_session_slots;
      push @datalist, 'none';
      $thisdatum = NCAM_BuildOptionList(\@datalist, $slotname);
      $thisentrytext =~ s/SLOTNAME/$thisdatum/;


      # Append this entry to the device list.
      $thislisttext .= $thisentrytext;
    }

    # Insert the camera list into the page.
    $pagetext =~ s/DEVLIST/$thislisttext/;

    # Reduce resolution and frame rate hashes to sorted lists (descending).
    @camsizelist = NCAM_SortByResolution(keys %camsizelut);
    @camratelist = sort {$b <=> $a} keys %camratelut;

    # Build the camera autoset and all-set menus.

    if (0 < scalar(@camsizelist))
    {
      $thisdatum = NCAM_BuildOptionList(\@camsizelist, $camsizelist[0]);
      $pagetext =~ s/AUTORESOLUTION/$thisdatum/g;
    }

    if (0 < scalar(@camratelist))
    {
      $thisdatum = NCAM_BuildOptionList(\@camratelist, $camratelist[0]);
      $pagetext =~ s/AUTOFRAMERATE/$thisdatum/g;
    }

    @datalist = sort {$b <=> $a} keys %NCAM_exposure_stops;
    $thisdatum = NCAM_BuildOptionList(\@datalist, '+0');
    $pagetext =~ s/EXPOSURE/$thisdatum/;


    # Build the stream list.

    $thislisttext = '';

    foreach $streamname (sort keys %$streams_p)
    {
      $thisstream_p = $$streams_p{$streamname};
      $streamlabel = NCAM_MakeSafeFilename($streamname);

      $slotname = $streamslotlut{$streamname};
      if (!(defined $slotname))
      { $slotname = 'none'; }


      # Build this entry.

      $thisentrytext = $page_config_streamentry;

      # Options that aren't lists.
      # Some of these are used multiple times.
      # NOTE - Stubbed-out copies also require multiple substitutions!

      $thisdatum = $outprefix . $streamlabel . '.jpg';
      $thisentrytext =~ s/IMAGEFILE/$thisdatum/g;

      $thisentrytext =~ s/STREAMURL/$streamname/g;

      # Hash the device ID to get a unique key.
      $thisdatum = NCAM_MakeSafeFieldLabel($streamname);
      $thisentrytext =~ s/STREAMTAG/$thisdatum/g;

      $thisentrytext =~ s/PORT/$$thisstream_p{updateport}/;
      $thisentrytext =~ s/DELAY/$$thisstream_p{delay}/;
      $thisentrytext =~ s/STREAMLABEL/$$thisstream_p{label}/g;

      # This is an option list.

      @datalist = @NCAM_session_slots;
      push @datalist, 'none';
      $thisdatum = NCAM_BuildOptionList(\@datalist, $slotname);
      $thisentrytext =~ s/SLOTNAME/$thisdatum/;


      # Append this entry to the device list.
      $thislisttext .= $thisentrytext;
    }

    # Insert the stream list into the page.
    $pagetext =~ s/STREAMLIST/$thislisttext/;


    # Insert the preview image into the page.
    $thisfname = $outdir . '/preview.jpg';
    $pagetext =~ s/PREVIEWIMAGE/$thisfname/;


    # Build the talker list.

    $thislisttext = '';

    foreach $talkername (sort keys %$talkers_p)
    {
      $thistalker_p = $$talkers_p{$talkername};
      # We don't need thumbnail previews for talkers, but keep this anyways.
      $talkerlabel = NCAM_MakeSafeFilename($talkername);


      # Build this entry.

      $thisentrytext = $page_config_talkentry;

      # Options that aren't lists.
      # Some of these are used multiple times.

      $thisentrytext =~ s/TALKADDRESS/$talkername/;

      # Hash the device ID to get a unique key.
      $thisdatum = NCAM_MakeSafeFieldLabel($talkername);
      $thisentrytext =~ s/TALKTAG/$thisdatum/g;

      # This should be checked if the talker is enabled.
      $thisdatum = ($$thistalker_p{enabled} ? 'checked' : '');
      # FIXME - Doing a global replace to get diagnostics showing.
      $thisentrytext =~ s/TALKCHECKED/$thisdatum/g;

      $thisentrytext =~ s/TALKKEY/$$thistalker_p{key}/;
      $thisentrytext =~ s/TALKHOST/$$thistalker_p{host}/;
      $thisentrytext =~ s/TALKPORT/$$thistalker_p{port}/;
      $thisentrytext =~ s/TALKLABEL/$$thistalker_p{label}/g;
      $thisentrytext =~ s/MYPORT/$$thistalker_p{myport}/;


      # Append this entry to the device list.
      $thislisttext .= $thisentrytext;
    }

    # Insert the stream list into the page.
    $pagetext =~ s/TALKERLIST/$thislisttext/;


    # Clean up all instances of TIMESTAMP.
    $pagetext =~ s/TIMESTAMP/$timestamp/g;


    # Done.
  }

  return $pagetext;
}



# Creates a monitoring web page.
# No arguments.
# Returns the monitor page's HTML.

sub NCAM_GenerateMonitorPage
{
  my ($timestamp, $pagetext);

  $pagetext = $page_monitor;

  # Clean up all instances of TIMESTAMP.
  $timestamp = NCAM_GetAbsTimeMillis();
  $pagetext =~ s/TIMESTAMP/$timestamp/g;

  return $pagetext;
}



# Creates a monitoring control pane web page.
# No arguments.
# Returns the control pane's HTML.

sub NCAM_GenerateControlPanePage
{
  my ($pagetext);

  # Initialize output.
  $pagetext = $page_monitor_control;

  # FIXME - Forcing button geometry. This should be a switched option!
  $pagetext =~ s/BUTTONS/$page_monitor_buttons_2x3/g;

  # FIXME - Assume no errors.
  $pagetext =~ s/ERRMSG//;

  return $pagetext;
}



# Creates a monitoring video pane web page.
# Arg 0 is the host to fetch the video from.
# Arg 1 is the port the video is streamed on.
# Arg 2 is the filename the video is offered via.
# Arg 3 is either undef (auto size) or an image size ("NNNxNNN").
# Returns the video pane's HTML.

sub NCAM_GenerateVideoPanePage
{
  my ($monitorhost, $monitorport, $monitorfilename, $imagesize, $pagetext);
  my ($timestamp);
  my ($width, $height);

  $monitorhost = $_[0];
  $monitorport = $_[1];
  $monitorfilename = $_[2];
  $imagesize = $_[3];  # This may be undef.
  $pagetext = '';

  if ( (defined $monitorhost) && (defined $monitorport)
    && (defined $monitorfilename) )
  {
    # Initialize output.
    $pagetext = $page_monitor_video;

    $pagetext =~ s/HOSTNAME/$monitorhost/;
    $pagetext =~ s/MONITORPORT/$monitorport/;
    $pagetext =~ s/MONITORFILENAME/$monitorfilename/;

    # Add the salt string to the image filename.
    $timestamp = NCAM_GetAbsTimeMillis();
    $pagetext =~ s/TIMESTAMP/$timestamp/;

    if ( (defined $imagesize) && ($imagesize =~ m/(\d+)x(\d+)/) )
    {
      $width = $1;
      $height = $2;

      # FIXME - Scale width but leave height alone to preserve aspect ratio.
      $pagetext =~ s/GEOMETRY/width=$width/;
    }
    else
    {
      $pagetext =~ s/GEOMETRY//;
    }

    # Done.
  }

  return $pagetext;
}



# Creates a repository browsing page.
# Arg 0 points to a list of top-level repository directory tuples. These
# have the form { name => (label), path => (path) }.
# Arg 1 is an error message to display (optional).
# Returns the browser page's HTML.

sub NCAM_GenerateBrowser
{
  my ($repolist_p, $errmsg, $pagetext);
  my ($repoinfo_p, $thislabel, $thisrepo);
  my ($alldisktext, $thisdisktext);
  my ($metalut_p, $thismeta_p);
  my (@dirlist, $repofolder);
  my ($thisentry, $allentries);
  my ($spacegigs, $has_post, $has_arch);
  my ($thiscontrol);
  my (@filelist);
  my ($have_usb, $in_usb);
  my (%folderlist);

  $repolist_p = $_[0];
  $errmsg = $_[1];

  $pagetext = '';

  if (defined $repolist_p)
  {
    $pagetext = $page_browser;


    # Fill in version information.
    $pagetext =~ s/NCAMVERSION/$NCAM_cgi_version/;


    # Fill in the error message if we have one.

    if (defined $errmsg)
    { $pagetext =~ s/ERRMSG/$errmsg/; }
    else
    { $pagetext =~ s/ERRMSG//; }


    # Preprocessing: determine whether or not a USB drive is connected.
    $have_usb = 0;
    foreach $repoinfo_p (@$repolist_p)
    {
      $thislabel = $$repoinfo_p{name};
      $thisrepo = $$repoinfo_p{path};

      if ($thisrepo =~ m/usb/)
      { $have_usb = 1; }
    }


    # Walk through the list of repositories.

    $alldisktext = '';

    foreach $repoinfo_p (@$repolist_p)
    {
      $thislabel = $$repoinfo_p{name};
      $thisrepo = $$repoinfo_p{path};


      # FIXME - Local vs USB kludge.
      $in_usb = 0;
      if ($thisrepo =~ m/usb/)
      { $in_usb = 1; }


      $thisdisktext = $page_browser_table;


      $thisdisktext =~ s/DISKNAME/$thislabel/;

      if ($in_usb)
      {
        $thisdisktext =~ s/DISKEJECT/$page_browser_eject/;
        $thisdisktext =~ s/FOLDTITLE/Archive Package/;
        $thisdisktext =~ s/POSTTITLE//;
      }
      else
      {
        $thisdisktext =~ s/DISKEJECT//;
        $thisdisktext =~ s/FOLDTITLE/Session Folder/;
        $thisdisktext =~ s/POSTTITLE/Post-Processing/;
      }


      # Note free space available.

      $spacegigs = `df --block-size=1000000 --output=avail $thisrepo/`;

      if ($spacegigs =~ m/(\d+)/s)
      {
        $spacegigs = $1;
        $spacegigs = sprintf('%.1f', $spacegigs / 1000);
      }
      else
      {
        $spacegigs = '??';
      }

      $thisdisktext =~ s/DISKGIGS/$spacegigs/;


      # Fetch metadata. This _should_ always be defined.
      # Handle failure gracefully anyways.

      $metalut_p = NCAM_FetchRepositoryMetadata($thisrepo);

      if (!(defined $metalut_p))
      { $metalut_p = {}; }


      # Build the repository list text.

      $allentries = '';
      %folderlist = ();
      @dirlist = `ls --color=none $thisrepo/`;

      foreach $repofolder (sort {$b cmp $a} @dirlist)
      {
        # Match repository folders _and_ .tar files.
        # Use %folderlist to avoid duplication.
        # Don't match any other auxiliary files that might be present.
        if ($repofolder =~ m/^(ncam-\S+\d)(\.tar)?\s*$/)
        {
          $repofolder = $1;

          if (!(defined $folderlist{$repofolder}))
          {
            # Mark this label as "seen".
            $folderlist{$repofolder} = 1;


            # Generate an entry for this folder/archive.
            $thisentry = $page_browser_entry;


            # Get metadata for this entry.
            # Fail gracefully if we can't find it.

            $spacegigs = '??';
            $has_post = 0;
            $has_arch = 0;

            $thismeta_p = $$metalut_p{$repofolder};
            if (defined $thismeta_p)
            {
              $spacegigs = $$thismeta_p{size};
              $has_post = $$thismeta_p{post};
              $has_arch = $$thismeta_p{arch};
            }


            # Fill in metadata for this entry.

            $thisentry =~ s/FOLDERGIGS/$spacegigs/;


            # Swap in either a folder-view link or an archive-download link.
            # FIXME - Assume that anything that has an archive is non-local.

            if ($has_arch)
            {
              $thisentry =~ s/FOLDERVIEW/$page_browser_download/;
            }
            else
            {
              $thisentry =~ s/FOLDERVIEW/$page_browser_foldview/;
            }


            # Fill in repository and tarball paths as appropriate.

            $thisentry =~ s/REPOTOP/$thisrepo/g;
            $thisentry =~ s/REPOFOLDER/$repofolder/g;
            $thisentry =~ s/REPOFILE/$thisrepo\/$repofolder.tar/;


            # "Move folder" control.

            $thiscontrol = '';
            if ($have_usb)
            {
              $thiscontrol = $page_browser_move;

              if ($in_usb)
              { $thiscontrol =~ s/TARGET/Local/; }
              else
              { $thiscontrol =~ s/TARGET/USB/; }
            }
            $thisentry =~ s/FOLDERMOVE/$thiscontrol/;


            # Post-processing controls, if local.
            # Name the "post-process" button appropriately.
            if ($in_usb)
            {
              $thisentry =~ s/POSTBUTTON//;
            }
            else
            {
              $thiscontrol = $page_browser_post;

              if ($has_post)
              {
                $thiscontrol =~ s/POSTPROCNAME/Redo Post-Processing/;
              }
              else
              {
                $thiscontrol =~ s/POSTPROCNAME/Post-Process/;
              }

              $thisentry =~ s/POSTBUTTON/$thiscontrol/;
            }


            # Done with this entry.
            $allentries .= $thisentry;
          }
        }
      }

      # Fill in the repository list text.
      $thisdisktext =~ s/REPOLIST/$allentries/;

      # Done with this disk.
      $alldisktext .= $thisdisktext;
    }

    # Fill in the list of disks.
    $pagetext =~ s/DISKLIST/$alldisktext/;
  }

  return $pagetext;
}



# Creates a "please wait for task to finish" page.
# Arg 0 is the string containing the task name (which may be "").
# Arg 1 is the string containing the current progress (which may be "").
# Arg 2 is the page to forward to when no longer busy.
# Arg 3 points to a hash of additional arguments to pass to the fallthrough
# page.
# Arg 4 (optional) is 'cancel' if there is to be a cancel button.
# Returns the message page's HTML.

sub NCAM_GenerateBusyPage
{
  my ($opname, $progress, $realtarget, $args_p, $wantcancel, $pagetext);
  my ($timestamp);
  my ($canceltext);
  my ($argtext, $thisarg);

  $opname = $_[0];
  $progress = $_[1];
  $realtarget = $_[2];
  $args_p = $_[3];
  # This may be undef:
  $wantcancel = $_[4];

  $pagetext = '';

  if ( (defined $opname) && (defined $progress)
    && (defined $realtarget) && (defined $args_p) )
  {
    $pagetext = $page_busy;

    $pagetext =~ s/OPNAME/$opname/;
    $pagetext =~ s/PROGRESS/$progress/;
    $pagetext =~ s/REALTARGET/$realtarget/;

    $argtext = '';
    foreach $thisarg (sort keys %$args_p)
    { $argtext .= '&arg' . $thisarg . '=' . $$args_p{$thisarg}; }
    $pagetext =~ s/ARGLIST/$argtext/;

    $timestamp = NCAM_GetAbsTimeMillis();
    $pagetext =~ s/TIMESTAMP/$timestamp/;

    $canceltext = '';
    if ((defined $wantcancel) && ('cancel' eq $wantcancel))
    {
      $canceltext = $page_busy_cancelbutton;
      $canceltext =~ s/REALTARGET/$realtarget/;
      # There's no fallthrough command for this; "cancel" was the command.
    }
    $pagetext =~ s/CANCELBUTTON/$canceltext/;
  }

  return $pagetext;
}



# Creates a "please remove your USB drive" message page.
# No arguments.
# Returns the message page's HTML.

sub NCAM_GenerateEjectPage
{
  # Nothing to substitute.
  return $page_browser_eject_done;
}



# Creates a "shutting down" message page.
# No arguments.
# Returns the message page's HTML.

sub NCAM_GenerateShutdownPage
{
  # Nothing to substitute.
  return $page_shutdown;
}



# Creates a generic user-message page.
# Arg 0 is the string containing the message.
# Returns the message page's HTML.

sub NCAM_GenerateMessagePage
{
  my ($message, $pagetext);

  $message = $_[0];
  $pagetext = '';

  if (defined $message)
  {
    $pagetext = $page_textmessage;

    $pagetext =~ s/MESSAGE/$message/;
  }

  return $pagetext;
}



# Creates a page with JavaScript code that immediately reassigns the top-level
# window's URL. The URL is set to this page's base URL with additional CGI
# arguments (which may be an empty string).
# Arg 0 is the CGI argument string ("name=value&name=value&...").
# Returns the transition page's HTML.

sub NCAM_GenerateFrameExitPage
{
  my ($argtext, $pagetext);

  $argtext = $_[0];
  $pagetext = '';

  if (defined $argtext)
  {
    $pagetext = $page_frameexit;

    $pagetext =~ s/CGIARGS/$argtext/;
  }

  return $pagetext;
}



# Creates a page with a redirect header that immediately transitions to a
# different page.
# Arg 0 is the URL to transition to.
# Returns the transition page's HTML.

sub NCAM_GenerateRedirectPage
{
  my ($url, $pagetext);

  $url = $_[0];
  $pagetext = '';

  if (defined $url)
  {
    $pagetext = $page_redirect;

    $pagetext =~ s/URL/$url/g;
  }

  return $pagetext;
}



# Parses config-page CGI parameters and alters an existing configuration
# accordingly.
# Arg 0 points to the session configuration hash.
# Arg 1 points to the CGI parameter hash.
# No return value.

sub NCAM_UpdateSessionFromCGI
{
  my ($session_p, $params_p);
  my ($thisparam, $thisval);
  my (%camlut, %streamlut, %talklut);
  my ($thistag, $thisfield, $thisitem_p);
  my ($camlist_p, $camname, $thiscam_p);
  my ($talklist_p);

  $session_p = $_[0];
  $params_p = $_[1];

  if ( (defined $session_p) && (defined $params_p) )
  {
    # First pass: Create lookup tables mapping tags to device names/URLs.
    # Only record entries that are present in the session config hash.

    %camlut = ();
    %streamlut = ();
    %talklut = ();

    foreach $thisparam (keys %$params_p)
    {
      $thisval = $$params_p{$thisparam};

      if ($thisparam =~ m/^viddev(\S+)/)
      {
        $thistag = $1;
        if (defined $$session_p{cameras}{$thisval})
        { $camlut{$thistag} = $thisval; }
      }

      if ($thisparam =~ m/^streamurl(\S+)/)
      {
        $thistag = $1;
        if (defined $$session_p{streams}{$thisval})
        { $streamlut{$thistag} = $thisval; }
      }

      if ($thisparam =~ m/^talkkey(\S+)/)
      {
        $thistag = $1;
        if (defined $$session_p{talkers}{$thisval})
        { $talklut{$thistag} = $thisval; }
      }
    }


    # Prepare for the second pass.
    # We have to clear slot assignments and disable talkers before rebuilding
    # the lists of assigned slots and enabled talkers.

    foreach $thisval (@NCAM_session_slots)
    {
      $$session_p{slots}{$thisval} = { 'type' => 'none' };
    }

    $talklist_p = $$session_p{talkers};
    foreach $thisval (keys %$talklist_p)
    {
      $thisitem_p = $$talklist_p{$thisval};
      $$thisitem_p{enabled} = 0;
    }


    # Second pass - Walk through the list again, copying data.
    # We already have the hash keys.

    foreach $thisparam (keys %$params_p)
    {
      $thisval = $$params_p{$thisparam};

      # FIXME - Ignore hidden controls, for now.
      # We only care about updating things the user changed.
      # FIXME - Remove these hidden fields, now that we've switched to files
      # for persistent data?

      if ($thisparam =~ m/^vid(size|rate|exp)(\S+)/)
      {
        $thisfield = $1;
        $thistag = $2;

        # NOTE - We can translate $thisfield if the web name and hash key
        # differ. This was the case for some of the hidden fields.

        if (defined $camlut{$thistag})
        {
          # FIXME - Assume the value is valid.
          $thisitem_p = $$session_p{cameras}{$camlut{$thistag}};
          if (defined $thisitem_p)
          { $$thisitem_p{$thisfield} = $thisval; }
        }
      }
      elsif ($thisparam =~ m/^stream(port|delay|label)(\S+)/)
      {
        $thisfield = $1;
        $thistag = $2;

        # FIXME - These are all hidden controls. Nothing to update?
        if (0)
#        if (defined $streamlut{$thistag})
        {
          $thisitem_p = $$session_p{streams}{$streamlut{$thistag}};
          if (defined $thisitem_p)
          { $$thisitem_p{$thisfield} = $thisval; }
        }
      }
      elsif ($thisparam =~ m/^talk(enabled)(\S+)/)
      {
        $thisfield = $1;
        $thistag = $2;

        if ('enabled' eq $thisfield)
        {
          $thisval = 1;
        }

        if (defined $talklut{$thistag})
        {
          $thisitem_p = $$session_p{talkers}{$talklut{$thistag}};
          if (defined $thisitem_p)
          { $$thisitem_p{$thisfield} = $thisval; }
        }
      }
      elsif ($thisparam =~ m/^vidslot(\S+)/)
      {
        $thistag = $1;

        if ( (defined $camlut{$thistag})
          && (defined $$session_p{slots}{$thisval}) )
        {
          $$session_p{slots}{$thisval} =
          {
            'type' => 'camera',
            'config' => $$session_p{cameras}{$camlut{$thistag}}
          };
        }
      }
      elsif ($thisparam =~ m/^streamslot(\S+)/)
      {
        $thistag = $1;

        if ( (defined $streamlut{$thistag})
          && (defined $$session_p{slots}{$thisval}) )
        {
          $$session_p{slots}{$thisval} =
          {
            'type' => 'stream',
            'config' => $$session_p{streams}{$streamlut{$thistag}}
          };
        }
      }
    }

    # Done.
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
