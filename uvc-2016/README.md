# UVC Driver Notes

The 2016 version of the NeuroCam (running on Mint 17) had an issue where
certain cameras would attempt to grab all of the available USB bandwidth.
This folder contains the diff made to "`uvc_video.c`" to address that issue,
along with additional notes.

For further details, see `notes/NOTES-uvc`.

Systems based on later versions of Mint did not appear to have this issue.

_This is the end of the file._
