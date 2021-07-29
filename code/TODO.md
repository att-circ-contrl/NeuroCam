# Attention Circuits Control Laboratory - NeuroCam daemon and client scripts
# Change log, bug list, and feature request list.
Written by Christopher Thomas.


## Bugs and feature requests:

* Sometimes the video feed is a broken link (perhaps due to using an old
folder name, due to starting a new feed too quickly?).

* Make "NCAM_QueryCameraParamsRaw" and use it in libcam.pl.

* Modify GrabFrame and TestCapture to set camera state while running.

* Make a "RunCamera" function (with UDP update and fixed frame count options).

* Make a "ConfigureCamera" function to call before and after RunCamera.

* Give the NeuroCam a proper task queue.

* Make a headless processing client for the NeuroCam so that post-processing
can be done on workstations/servers.

* Restrict exposure settings for the Logitech c930 to allowed values.
Values that aren't "magic" values are immediately reset by the camera.

* First-time access with no cameras or game stream present gives a broken
image icon for the preview. "Refresh preview" fixes it.

* Pressing "cancel" when building a tarball removes post-processed data.

* Compositing is very time-consuming.

*  Resizing the monitor stream is somewhat time-consuming.

*  Some operations have no progress indicator. [break out into specific ops]

* Add a log file for post-processing.

* Add a log file for debugging. In /tmp is fine. (FIXME: no, that gets wiped)

* Add support for ethernet cameras.

* Look into gstreamer instead of ffmpeg for camera capture.

* Generate a warning when the hard drive fills up (or is low on space).

* Allow batch-copy, batch-move, and batch-delete of multiple files.
  ** This will be needed when we have more kiosks, to avoid babysitting.

* Allow monitoring without recording (for when the disk is full).

* Make the install script put the repository directory on /data but keep the
CGI/config directory local, so that filling the data disk doesn't lose 
configuration information.

* Adjust UI buttons to be usable on an iPad (and avoid "oops" scenarios).

* Allow per-camera "ignore synch LED", for situations where we only have LEDs
on some of the cameras.

* Have the NeuroCam check disk health via "smartctl" and report problems.

* Have the NeuroCam check temperature via
  "cat /sys/class/thermal/*zone/t[ye]*" and report problems.

* Update the post-processing command-line tools' help page to show that it
needs a reporting port when doing time alignment.

* When the system updates packages, permissions on "shutdown" can be reset.
Run "chmod u+s /sbin/shutdown" from our update script.

* The NeuroCam script allows all combinations of resolution and frame rate,
but some cameras (like the "ELP" ones from 2019) need specific combinations.
If the wrong combination is chosen, the camera vanishes from the device list.
Have the script sanity-check requested combinations against detected modes.

* Some cameras (like the Nexigo N980P) don't have exposure control. Make the
NeuroCam script tolerate missing controls.

* Make the NeuroCam save a list of available controls and check against the
list when updating camera settings.

* Make the NeuroCam adjust gain rather than exposure by default.


## Low priority bugs and feature requests:

* Fix all of the speed problems in the NeuroCam code. This will involve
writing various daemons in C (capturing and compositing, at minimum).

* Make the NeuroCam work with ethernet cameras (in addition to USB cameras).

* Make UDP commands to set and query camera configuration.

* Modify the web GUI to allow setting camera configuration while cameras are
running.

* Modify the web GUI to allow setting additional camera parameters besides
exposure.


## Abbreviated changelog (most recent changes first):

* 15 Feb 2021 --
Added vendor-specific metadata. Modified daemon capture code to set camera
configuration while the camera is running (as the c930 resets itself when
starting). Adjusted c930 default gain.

* 11 July 2018 --
_Metadata for deleted folders only goes away after "recalc sizes"._
Fixed; ghost entries are now marked as stale.

* 11 July 2018 --
_Deleting a USB folder (tarball) hangs._
Fixed.

* 11 July 2018 --
_USB tarballs have bad metadata (timestamp of 1 Jan 1970)._
Fixed.

* 03 July 2018 --
_Metadata for deleted folders remains present._
Fixed (I think).

* 03 July 2018 --
_ExFAT grinds to a halt with large numbers of files._
Modified CGI logic so that USB folders are stored as .tar archives.

* 27 June 2018 --
_EFI drives mount the EFI partition rather than the main partition._
Overhauled external drive routines to consider both cases. Added a second
mountpoint and symlink.

* 26 June 2018 --
_Shutdown page never renders._
Fixed by launching a shutdown script as a daemon, so that the
CGI script can terminate before the shutdown happens.

* 26 June 2018 --
_Software restart and machine shutdown are confusingly placed._
Buttons the user should be careful with are now red. Buttons
that change mode or are otherwise important are now green. Most have no
colour.

* 26 June 2018 --
_Installer doesn't set /data to web directory._
Fixed. Also made safe for multiple install invocations.

* 13 May 2018 --
_List of frames is truncated due to "ls *.jpg"._
Fixed by changing "ls *.jpg" to "ls|grep jpg" in libpost.pl.


This is the end of the file.
