# Attention Circuits Control Laboratory - NeuroCam daemon and client scripts
# Quick and dirty development notes.
Written by Christopher Thomas.


## Overview

This document gives a rough overview of the NeuroCam source folder. Detailed
information should be in the developer manual, but that's not likely to be
updated any time soon, so I'm adding rough notes as a stopgap measure.

The NeuroCam software was built to be modular. There's a control daemon,
which listens for commands via UDP and which starts other daemons to handle
specific tasks. The user interface is a separate application; a web version
and a command-line version are provided as reference implementations.

The idea is that the UI can be modified without having to change the
back-end, and vice versa.

The NeuroCam software is further divided into application/daemon code and
library code, with common functions being moved to libraries and high-level
logic remaining in the application or daemon code.


## Daemon and Utility Files

* `neurocam-cgi.pl` --
Top-level web application script. This is invoked as a CGI script to run
the NeuroCam web interface.

* `neurocam-cli.pl` --
Top-level command-line application script. This is run from the command line
to control the NeuroCam.

* `neurocam-daemon.pl` --
Camera capture daemon. **FIXME** - I think this also collects UDP messages,
but I'd have to doublecheck.

* `neurocam-gpio.pl` --
GPIO "blink box" daemon. This checks for new USB serial ports and probes
for "Blink Box" GPIO devices. If found, they're configured to blink and
also monitored for TTL events, with blink events and TTL events forwarded
as UDP messages to the NeuroCam, and TTL control signals generating UDP
control commands to the NeuroCam.

* `neurocam-manager.pl` --
Top-level NeuroCam daemon. This listens for UDP commands and takes
appropriate actions when commands are received (starting/stopping other
daemons, performing post-processing, etc).

* `neurocam-postprocess.pl` --
Post-processing back-end utility. This performs the requested post-processing
operations on the specified data folders, sending UDP progress messages to
the specified port.

* `neurocam-shutdown.pl` --
This shuts down the computer (via "`shutdown -P now`") after a brief delay.
This is launched as a background process by the CGI script when the user
clicks the "shutdown" button (so that the "shutting down" page has time to
be sent and the NeuroCam scripts have time to gracefully close).


## Library Files

* `neurocam-libcam.pl` --
These functions detect and manipulate USB-connected cameras.

* `neurocam-libdebug.pl` --
These are helper functions intended to assist writing debug code.

* `neurocam-libfocus.pl` --
These functions perform auto-focusing manually (by sweeping focus and
picking the value that had the highest mean squared derivative in-frame).

* `neurocam-libmanage.pl` --
These are helper functions for detecting, communicating with, and restarting
the manager daemon.

* `neurocam-libmjpeg.pl` --
These are helper functions for image-casting MJPEG video streams.

* `neurocam-libmt.pl` --
These are helper functions for writing multi-process applications.
_(NOTE - A "thread" shares memory with other threads. A "process" has its
own address space and its own memory. The `fork()` command gives you a
new process, not a new thread.)_

* `neurocam-libnetwork.pl` --
These are helper functions for writing applications that communicate using
UDP ports. This library also tracks port numbers assigned to various
NeuroCam functions.

* `neurocam-libpost.pl` --
These are helper functions that implement post-processing of NeuroCam data
folders.

* `neurocam-libsession.pl` --
These are helper functions for creating, reading, and modifying session
configuration metadata for NeuroCam recording session.

* `neurocam-libstitch.pl` --
These are helper functions for compositing raw video feeds into the
"monitoring" and "composited" feeds.

* `neurocam-libweb.pl` --
These are low-level helper functions for generating web forms and responses
for the user interface CGI script.


## Other Files

* `copyweb.sh` --
This copies the NeuroCam scripts to the "`www`" folder and sets up
appropriate sub-folders and symbolic links.

* `debug-closeall` --
This transmits shutdown/halt commands to all NeuroCam daemons.

* `debug-killall` --
This calls "`debug-closeall`", waits, then calls "`killall`" on all named
NeuroCam processes, waits again, then calls "`killall -9`" on all named
NeuroCam processes. This is intended to clean up if the NeuroCam software
doesn't shut down cleanly.

* `debug-probeall` --
This sends UDP query commands to ports that the NeuroCam listens to, asking
for responses to be sent to port 7777 (which "`debug-snoop`" listens to).

* `debug-snoop` --
This listens for UDP messages on port 7777, echoing anything received to
the user.

* `document-perl.pl` --
This attempts to automatically generate documentation for the specified Perl
scripts, by looking for comments with specific context around them. This
only works for code that folllows the same style I use, and isn't perfect
even for that, but it's better than having no documentation at all.

* `fakeunity.pl` --
This sends a video stream and/or heartbeat UDP messages to the NeuroCam
software. This is the same sort of data that an experiment game application
would send. Type "`./fakeunity.pl`" for documentation.

* `makedocs` --
This runs "`document-perl.pl`" to generate documentation for NeuroCam
Perl files. The resulting documentation is placed in the "`autogen-docs`"
folder. This documentation is far from perfect but is much better than
nothing. It's the equivalent of looking at well-commented header files
for C code.


## Folders

* `animdata` --
This folder contains frames for generating a test video stream of a spinning
hypercube. Use "`./fakeunity.pl --imagecast=animdata`" to use it.

* `assets` --
This folder contains a web page that redirects to the NeuroCam CGI script.
It's used by the "`copyweb.sh`" script.

* `autogen-docs` --
The "`makedocs`" script places documentation in this folder.

* `www` --
This is a symbolic link to the local machine's web folder (by default
`/var/www/html`). The "`copyweb.sh`" script moves web files here for
testing.


_This is the end of the file._
