# Attention Circuits Control Laboratory - Makefile for burning hex files.
# Written by Christopher Thomas.

#
# Configuration.

UNOFLAGS=-p m328p

# This looks for an Atmel AVR ISP Mk 2.
ISPFLAGS=-c avrispv2 -P usb

# This looks for a boot loader (pretending to be a stk500).
# FIXME - This blithely assumes we're on the first USB serial device and
# are using Linux Mint 18's naming conventions.
# FIXME - Some clones are /dev/ttyUSB0, not /dev/ttyACM0.
# NOTE - We need "-D" to cancel flash erase, as the boot loader refuses to
# erase itself.
ARDFLAGS=-c stk500 -P /dev/ttyACM0 -D


#
# Hex files.

HEXGPIO=ncam_gpio.hex


#
# Targets.

default: helpscreen

helpscreen:
	@echo ""
	@echo "Targets:   gpio-burnisp  gpio-burnard  test"
	@echo ""


gpio-burnisp: $(HEXGPIO)
	avrdude $(ISPFLAGS) $(UNOFLAGS) -U flash:w:$(HEXGPIO):i

gpio-burnard: $(HEXGPIO)
	avrdude $(ARDFLAGS) $(UNOFLAGS) -U flash:w:$(HEXGPIO):i


# Using "cu -h" for manual echo.
# FIXME - Some clones are /dev/ttyUSB0, not /dev/ttyACM0.
test:
	cu -h -l /dev/ttyACM0 -s 115200


#
# This is the end of the file.
