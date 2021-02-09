#!/bin/bash

if (( $# == 0 ))
then

DEVICE=video0

else

DEVICE=$1

fi

WIDTH=1280
HEIGHT=720

if (( $# == 3 ))
then

WIDTH=$2
HEIGHT=$3

fi

mplayer tv:// \
  -tv device=/dev/$DEVICE:width=$WIDTH:height=$HEIGHT:outfmt=mjpeg:fps=30
