#!/bin/bash

ORIGDIR=orig

if [ ! -e $ORIGDIR/marker ]
then
  echo "Can't find $ORIGDIR."
else

  # Construct cropped images.
  rm -f *jpg
  convert -crop 800x600+600+500 +repage \
    $ORIGDIR/*791.jpg gpio-closed.jpg
  convert -rotate 90 -geometry 768x1024 -crop 600x600+100+300 +repage \
    $ORIGDIR/*795.jpg gpio-open.jpg

fi


# Done.
