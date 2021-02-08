# Attention Circuits Control Laboratory - NeuroCam project
# Top-level Makefile.
# Written by Christopher Thomas.
# Copyright (c) 2021 by Vanderbilt University. This work is released under
# the Creative Commons Attribution-ShareAlike 4.0 International License.

default: helpscreen

helpscreen:
	@echo ""
	@echo "Targets:   installkey  manual  blinkbox-hex  blinkbox-burn"
	@echo ""

installkey:
	install-scripts/make-installkey.sh

manual:

blinkbox-hex:

blinkbox-burn:

#
# This is the end of the file.
