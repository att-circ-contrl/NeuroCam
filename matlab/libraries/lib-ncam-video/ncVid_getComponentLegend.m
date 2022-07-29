function [ namelist colorlist ] = ncVid_getComponentLegend( complist )

% function [ namelist colorlist ] = ncVid_getComponentLegend( complist )
%
% This function returns human-readable component names and plotting colors,
% given a list of component labels.
%
% "complist" is the list of component labels to translate.
%
% "namelist" is a list of human-readable names suitable for plot legends.
% "colorlist" is a cell array containing [ r g b ] plotting colors.


% Initialize output.
namelist = {};
colorlist = {};


% FIXME - Cheat, and handle special cases if we see them.
% This should actually cover all cases the library generates.

unknowncount = 0;

for cidx = 1:length(complist)
  thislabel = complist{cidx};
  thisname = sprintf('Unknown %d', unknowncount + 1);
  % FIXME - Default to shades of magenta for unknown components.
  thiscol = [ 1.0 0.3 1.0 ] * (0.5 + ( cidx / length(complist) ));

  if strcmp(thislabel, 'red')
    thisname = 'Red';
    thiscol = [ 0.7 0.3 0.4 ];
  elseif strcmp(thislabel, 'grn')
    thisname = 'Green';
    thiscol = [ 0.5 0.7 0.2 ];
  elseif strcmp(thislabel, 'blu')
    thisname = 'Blue';
    thiscol = [ 0.0 0.4 0.7 ];
  elseif strcmp(thislabel, 'mag')
    thisname = 'Magnitude';
    thiscol = [ 0.3 0.3 0.3 ];
  else
    comptokens = regexp( thislabel, 'comp(\d+)', 'tokens' );
    if ~isempty(comptokens)
      thisname = sprintf( 'Component %d', str2double(comptokens{1}{1}) );
      % FIXME - Leaving color as magenta.
    else
      % Falling back to "unknown"; increment the unknown counter.
      unknowncount = unknowncount + 1;
    end
  end

  namelist{cidx} = thisname;
  colorlist{cidx} = thiscol;
end



% Done.

end


%
% This is the end of the file.
