# NeuroCam Experiment Monitoring System

## Overview

The NeuroCam is a set of scripts designed to aggregate video footage from
multiple cameras and to let a user monitor and annotate that footage in
real-time. Frame alignment is performed in post-processing, and video footage
is saved frame-by-frame to allow later analysis without motion-compression
artifacts.

**While this code is functional, there is a lot of room for improvement.**
This is documented in more detail in the "Idiosyncracies" section of this
document and in the "TODO" documentation in the code folder. Most of these
improvements will eventually happen, but refactoring NeuroCam is not
presently the lab's top priority.

The NeuroCam project is copyright (c) by Vanderbilt University, and is
released under the Creative Commons Attribution-ShareAlike 4.0 International
License.


## Quick-Start

The top-level Makefile automates common operations (under Ubuntu-derived
Linux, at least):

* Type "`make`" without arguments for the Makefile target list.

* To make a NeuroCam software install/update USB stick, put a USB stick in
your machine and type "`make installkey`".

* To rebuild the manuals (which should already be in the "`manuals`" folder),
type "`make manual`".

* To flash a "Blink Box" GPIO device using the firmware hex file, plug the
device into your computer and type "`make blinkbox-burn`".

* To rebuild the firmware for the "Blink Box" GPIO device, make sure
the "NeurAVR" project is installed and "`neuravr`" is symlinked at an
appropriate location (in the "`gpio/code`" folder or in the folder the
"`NeuroCam`" project is installed in), and type "`make blinkbox-hex`".


## Relevant Components

The following hardware and software components are provided:

* **Control daemon script.** This listens for commands on a UDP port, starts
and stops the camera daemon and GPIO daemon, and performs post-processing
tasks as requested.

* **Web interface script.** This is an old-school CGI script that provides a
GUI for configuring, controlling, and monitoring the output of the NeuroCam
control daemon.

* **Command-line interface program.** This is a command-line script that
can configure and command the NeuroCam control daemon.

* **"Blink Box" GPIO device.** This is a general-purpose TTL I/O box built
using Arduino hardware. The NeuroCam uses it to strobe LEDs for frame
synchronization and to listen for TTL signals (start/stop strobes and
annotation signals).

* **GPIO monitoring daemon.** This probes for "Blink Box" GPIO devices, and
if found, sets up LED strobing and translates GPIO inputs into appropriate
UDP commands that are sent to the NeuroCam control daemon.


The following helper scripts are provided:

* **Install and update scripts.** These are used to create NeuroCam software
installation USB sticks, which are then used to make new NeuroCams and to
update their software.

* **Utility scripts.** At present, this is a pair of scripts for sending UDP
packets and listening for UDP broadcasts. These are used for low-level
communication with the NeuroCam daemon for debugging purposes.


## Idiosyncracies

The following idiosyncracies are present (per "there is a lot of room for
improvement" in the overview section):

* Frame-grabbing has low jitter once it's been started but the individual
streams have time skew of up to 0.25 seconds relative to each other. This
is probably due to startup time of the frame-grabbing tool used (invoked via
shell call).

The workaround is to use LED strobing for frame alignment in post-processing.

* Compositing for monitoring and during post-processing takes far longer
than it should. This is probably due to using the Perl ImageMagick libraries
rather than writing a C utility using libjpeg to do it.

The workaround is to throw hardware at the problem (at least one core per
camera).

* Between capture time skew and compositing delay, there's about half a
second of time lag on the monitoring stream that the user sees. The frame
rate of the monitoring stream is also lower than the actual capture frame
rate (as the compositing process will drop frames as-needed; the frames
themselves are still saved).

The workaround is to click on a given individual feed in the web GUI to
select a specific raw feed, which is then forwarded without compositing,
if faster access is needed.

* The NeuroCam does not have a proper job manager (i.e. it isn't possible
to queue multiple operations). This is high on the list of features to
implement, but NeuroCam development is not presently the lab's top priority.

The workaround is to babysit the NeuroCam during post-processing and file
transfer. Folders (capture sessions) have to be processed, moved, or
deleted individually.

* The NeuroCam generates an absurdly large number of files (one per frame
per camera), and stores each camera's frames in a single directory.

This is intentional, but _many_ filesystems really hate having directories
with large numbers of files in them. In particular, the `exfat` filesystem
used on most external drives slows to a crawl, and the default Windows and
MacOS filesystems don't like it either. The default Linux filesystems
(`ext2`/`ext3`/`ext4`) are okay with it.

The workaround is to store NeuroCam folders as `.tar` archives when saving
them on external drives, and to process the frame data on Linux machines or
on other machines with suitable filesystems configured.

* The NeuroCam performs random access to an absurdly large number of files
during capture and post-processing.

This is intentional, and is unavoidable for data saved as individual frames.
It means that solid-state drives should be used when building NeuroCam
systems, as the seek time of magnetic drives would slow processing to a
crawl (and probably capture, too).


## Folders

This repository contains the following directories:

* `code` -- NeuroCam daemon and GUI scripts.
* `drawings` - Mechanical drawings (for the GPIO device).
* `gpio` -- Firmware source and PCB development files for the "Blink Box"
GPIO device.
* `hexfiles` -- Firmware binaries for the "Blink Box" GPIO device.
* `install-scripts` -- Scripts for building install/update USB sticks.
* `manuals` -- NeuroCam documentation.
* `manuals-src` -- Source for rebuilding NeuroCam documentation.
* `matlab` -- Matlab libraries for working with NeuroCam systems and data.
* `notes` -- Miscellaneous notes relevant to NeuroCam development.
* `schematics` - Schematics (for the GPIO device and lamp driver).
* `utils` -- Miscellaneous utility scripts for debugging the NeuroCam.


_This is the end of the file._
