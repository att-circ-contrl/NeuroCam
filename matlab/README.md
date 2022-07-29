# NeuroCam Experiment Monitoring System - Matlab Libraries

## Overview

This is a set of Matlab libraries and test scripts written to support the
use of the NeuroCam system.

These files are part of the NeuroCam project.
This project is Copyright (c) 2021 by Vanderbilt University, and is released
under the Creative Commons Attribution-ShareAlike 4.0 International License.


## Libraries

* `lib-ncam-video` --
Library for reading video frame information from a repository and for
extracting information about rapid brightness changes, to use for time
alignment.


## Sample Code

Sample code scripts are intended to illustrate how the libraries are used.
These also include my development test scripts. The following scripts are
provided:

* `do_align.m` --
Performs video frame alignment on a dataset using brightness changes in the
images (rather than LED blinks). This is intended to catch situations where
a computer monitor in view changes its depicted scene (a large change in
brightness in a one-frame time step). This should catch LED blinks too.


_This is the end of the file._
