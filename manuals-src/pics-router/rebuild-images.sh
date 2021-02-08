#!/bin/bash

ORIGDIR=orig-n66u

if [ ! -e $ORIGDIR/marker ]
then
  echo "Can't find $ORIGDIR."
else
  rm -f *png
  # FIXME - Just copy the originals.
  cp $ORIGDIR/*png .
  # FIXME - We really should highlight appropriate parts of the GUI.
fi


# Done.
