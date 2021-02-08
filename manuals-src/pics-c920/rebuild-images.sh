#!/bin/bash

ORIGDIR=hand-processed

if [ ! -e $ORIGDIR/marker ]
then
  echo "Can't find $ORIGDIR."
else
  rm -f *jpg
  # Convert to JPEG.
  cd $ORIGDIR
  for F in *png
  do
    convert $F ../`echo $F|sed -e s/png/jpg/`
  done
  cd ..
fi


# Done.
