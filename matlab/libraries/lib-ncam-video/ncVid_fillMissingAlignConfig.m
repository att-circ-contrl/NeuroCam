function newconfig = ncVid_fillMissingAlignConfig( oldconfig )

% function newconfig = ncVid_fillMissingAlignConfig( oldconfig )
%
% This fills in any missing fields in a frame alignment configuration
% structure with reasonable default values.
%
% Configuration structure fields are described in ALIGNCONFIG.txt.
%
% "oldconfig" is the configuration structure to augment. Pass "struct()" to
%   get a valid configuration structure with entirely default values.
%
% "newconfig" is the augmented configuration structure.
%


% Initialize.
newconfig = oldconfig;


% Set reasonable default values for any missing fields.

if ~isfield(newconfig, 'avgeventinterval')
  newconfig.avgeventinterval = 1;
end

if ~isfield(newconfig, 'blacklist')
  newconfig.blacklist = { 'Monitor', 'Composited' };
end

if ~isfield(newconfig, 'maxframes')
  newconfig.maxframes = inf;
end

if ~isfield(newconfig, 'quiet')
  newconfig.quiet = false;
end

if ~isfield(newconfig, 'tilegrid')
  newconfig.tilegrid = [ 1 1 ];
end


% Done.

end


%
% This is the end of the file.
