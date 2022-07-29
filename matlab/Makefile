# Video alignment test script - Makefile.
# Written by Christopher Thomas.

MATLAB=matlab
MATFLAGS=-nodisplay -nodesktop -nosplash
MATGUIFLAGS=-nodesktop -nosplash

default:
	@echo "Targets:   clean pclean run rungui gallery"

clean: pclean
	rm -f output/*

pclean:
	rm -f plots/*

run:
	$(MATLAB) $(MATFLAGS) -r "run('do_align.m');exit;"

rungui:
	@echo "FIXME - No GUI script yet."

gallery:
	cd plots; makegallery.pl --width=24% *png


# This is the end of the file.
