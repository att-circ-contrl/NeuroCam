#!/bin/bash

ORIGDIR=orig-20170404

if [ ! -e $ORIGDIR/marker ]
then
  echo "Can't find $ORIGDIR."
else
  rm -f *jpg
  convert -crop 1024x768+500+300 +repage -geometry 512x384 \
    orig-20170404/*799.jpg c920-led.jpg

fi


# Done.
