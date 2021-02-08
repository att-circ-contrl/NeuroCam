# Attention Circuits Control Laboratory - NeuroCam manual - Makefile
# Written by Christopher Thomas.
# Copyright (c) 2021 by Vanderbilt University. This work is released under
# the Creative Commons Attribution-ShareAlike 4.0 International License.


BASENAME=neurocam-manual
GUIDENAME=neurocam-guide
IRNAME=webcam-ir-howto

DOCBITS=\
	boilerplate.tex				\
	$(BASENAME)-user-intro.tex		\
	$(BASENAME)-user-setup.tex		\
	$(BASENAME)-user-gui.tex		\
	$(BASENAME)-user-repo.tex		\
	$(BASENAME)-user-handshake.tex		\
	$(BASENAME)-maint-machine.tex		\
	$(BASENAME)-maint-router.tex		\
	$(BASENAME)-maint-gpio.tex		\
	$(BASENAME)-maint-cameras.tex		\
	$(BASENAME)-aux-c920.tex		\
	$(BASENAME)-dev-machine.tex		\
	$(BASENAME)-dev-netcomm.tex		\
	$(BASENAME)-dev-structs.tex		\
	$(BASENAME)-dev-funcs.tex		\
	$(BASENAME)-dev-progs.tex		\
	$(BASENAME).tex


default: helpscreen

# NOTE - Not mentioning "tclean", "force", "pics", or "pclean".
# FIXME - "pics" only rebuilds medium-res images on my system! It'll stop
# harmlessly if it doesn't find the original images directory.
# FIXME - "pclean" will remove images without checking to see if they can
# be rebuilt!
helpscreen:
	@echo ""
	@echo "Targets:   guide  manual  ir  all  clean"
	@echo ""

force: clean guide manual

all: manual guide ir

manual: $(BASENAME).pdf
guide:: $(GUIDENAME).pdf
ir: $(IRNAME).pdf

clean: tclean
	rm -f $(BASENAME).pdf
	rm -f $(GUIDENAME).pdf
	rm -f $(IRNAME).pdf

tclean:
	rm -f $(BASENAME).log $(BASENAME).aux $(BASENAME).toc
	rm -f $(GUIDENAME).log $(GUIDENAME).aux $(GUIDENAME).toc
	rm -f $(IRNAME).log $(IRNAME).aux $(IRNAME).toc
	rm -f texput.*


$(BASENAME).pdf: $(DOCBITS)
	pdflatex $(BASENAME).tex
	pdflatex $(BASENAME).tex
	make tclean

$(GUIDENAME).pdf: $(DOCBITS) $(GUIDENAME).tex
	pdflatex $(GUIDENAME).tex
	pdflatex $(GUIDENAME).tex
	make tclean

$(IRNAME).pdf: $(DOCBITS) $(IRNAME).tex
	pdflatex $(IRNAME).tex
	pdflatex $(IRNAME).tex
	make tclean


pics:
	make -C pics-gui
	make -C pics-c920
	make -C pics-cam
	make -C pics-gpio
	make -C pics-system
	make -C pics-router

pclean:
	make -C pics-gui clean
	make -C pics-c920 clean
	make -C pics-cam clean
	make -C pics-gpio clean
	make -C pics-system clean
	make -C pics-router clean


# This is the end of the file.
