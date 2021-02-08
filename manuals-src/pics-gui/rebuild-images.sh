#!/bin/bash

ORIGDIR=orig-20170511

if [ ! -e $ORIGDIR/marker ]
then
  echo "Can't find $ORIGDIR."
else
  rm -f *png
  # FIXME - Just copy the originals.
  cp $ORIGDIR/*png .
fi


# Done.
