#!/bin/bash

if [ ! -e www ]
then
  echo "###  Need 'www' symlink to create web directories!"
else


# Create the CGI directory tree if it's missing.

if [ ! -d www/auxfiles ]
then
  echo "Creating www/auxfiles."
  sudo mkdir www/auxfiles
  sudo chmod 1777 www/auxfiles
fi

if [ ! -d www/repositories ]
then
  echo "Creating www/repositories."
  sudo mkdir www/repositories
  sudo chmod 1777 www/repositories
fi

# Rebuild symlinks.
echo "Creating USB symlinks."
sudo rm -f www/usb www/usb2
sudo ln -s -t /var/www/html /usb
sudo ln -s -t /var/www/html /usb2


# Copy the redirect page and other asset files.

if [ ! -e www/index.html ]
then
  echo "Creating www/index.html."
  sudo cp assets/index.html www/index.html
  sudo chmod 644 www/index.html
fi


# Copy CGI files.

sudo cp *.pl www
sudo chmod 755 www/*.pl
sudo chmod 644 www/*lib*.pl
sudo mv www/*cgi.pl www/neurocam.cgi


# Done.

fi
