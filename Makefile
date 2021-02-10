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
	rm -f manuals/*pdf
	make -C manuals-src clean all
	mv manuals-src/*pdf manuals

# This rebuilds the hex file, copies it, then cleans up again.
blinkbox-hex:
	make -C gpio/code -f Makefile.neuravr clean hex
	make -C gpio/code -f Makefile.neuravr clean

blinkbox-burn:
	make -C hexfiles gpio-burnard

#
# This is the end of the file.
