function [ isok intensity ] = ...
  ncVid_getOneFrameIntensity( fname, htiles, vtiles )

% function [ isok intensity ] = ...
%   ncVid_getOneFrameIntensity( fname, htiles, vtiles )
%
% This function reads the specified image file, divides it into a grid of
% tiles, and reports the average intensity of colour components within each
% tile.
%
% "fname" is the name of the file to read from, with path.
% "htiles" is the horizontal grid size.
% "vtiles" is the vertical grid size.
%
% "isok" is true if the image file was read and false otherwise.
% "intensity" is a structure with one field per component, indexed by
%   component label (e.g. 'red', 'grn', 'blu', 'mag', etc). Each field
%   contains a matrix indexed by [h,v] containing average component intensity.


isok = false;
intensity = struct();

if isfile(fname)

  isok = true;

  thisimage = imread(fname);
  [ imgvsize imghsize imgcompsize ] = size(thisimage);


  % FIXME - Blithely assume that one-component images are greyscale.
  % This will try to interpret palette-mapped as greyscale, which will result
  % in garbage output if that happens.
  % Also assume that 3-component images are RGB. If that's mistaken, output
  % will still be sensible but labels will be incorrect.

  complist = {};
  if 1 == imgcompsize
    complist = { 'mag' };
  elseif 3 ==imgcompsize
    complist = { 'red', 'grn', 'blu' };
  else
    for cidx = 1:imgcompsize
      complist{cidx} = sprintf('comp%d', cidx);
    end
  end


  % Get tile boundaries.
  % Tiles go from bin(k) to bin(k+1)-1.

  hbins = round( linspace(1,(imghsize+1),(htiles+1)) );
  vbins = round( linspace(1,(imgvsize+1),(vtiles+1)) );


  % Get per-tile average component values for each channel.

  for cidx = 1:imgcompsize

    thisgrid = [];

    for hidx = 1:htiles
      hmin = hbins(hidx);
      hmax = hbins(hidx+1) - 1;

      for vidx = 1:vtiles
        vmin = vbins(vidx);
        vmax = vbins(vidx+1) - 1;

        thistile = thisimage(vmin:vmax, hmin:hmax, cidx);
        thistile = double(thistile);
        thisgrid(hidx,vidx) = mean(mean(thistile));
      end
    end

    intensity.(complist{cidx}) = thisgrid;

  end

end



% Done.

end


%
% This is the end of the file.
