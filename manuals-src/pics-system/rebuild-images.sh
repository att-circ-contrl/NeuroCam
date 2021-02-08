#!/bin/bash

# Construct cropped images.

ORIGFIRST=orig
ORIGSECOND=orig-2

if [ ! -e $ORIGFIRST/marker ]
then
  echo "Can't find $ORIGFIRST."
elif [ ! -e $ORIGSECOND/marker ]
then
  echo "Can't find $ORIGSECOND."
else

rm -f *jpg

# First set of pictures, without the GPIO box.

#convert -geometry 1024x768 -crop 1024x380+0+185 +repage \
#	orig/*833.jpg sys-all-a.jpg
#convert -geometry 1024x768 -crop 1024x300+0+300 +repage \
#	orig/*834.jpg sys-all-b.jpg
convert -crop 960x720+600+550 +repage -geometry 480x360 \
	orig/*837.jpg sys-router-front.jpg
convert -geometry 1024x768 -crop 1024x400+0+0 +repage \
	orig/*839.jpg sys-router-back.jpg
convert -crop 1280x820+350+200 +repage -geometry 640x410 \
	orig/*841.jpg sys-cameras.jpg
convert -geometry 1024x768 -crop 800x400+150+140 +repage \
	orig/*844.jpg sys-comp-front.jpg
convert -geometry 1024x768 -crop 800x400+150+140 +repage \
	orig/*846.jpg sys-comp-back.jpg

# Second set of pictures, with the GPIO box.

#convert -geometry 1024x768 -crop 960x360+20+300 +repage \
#	orig-2/*855.jpg sys-all-c.jpg
convert -crop 600x450+720+640 +repage \
	orig-2/*858.jpg sys-gpio.jpg
convert -geometry 1024x768 -crop 1024x400+0+250 +repage \
	orig-2/*861.jpg sys-all-d.jpg

fi


# Done.
