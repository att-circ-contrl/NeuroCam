function configreport = ncVid_reportAlignConfig( config )

% function configreport = ncVid_reportAlignConfig( config )
%
% This function produces a human-readable summary of a frame alignment
% configuration structure.
%
% "config" is a configuration structure, per ALIGNCONFIG.txt.
%
% "configreport" is a character array containing a human-readable description.


% Initialize output.
configreport = '';


% Banner.
configreport = [ configreport sprintf('-- Align config begins:\n') ];


% Diagnostic parameters.

if config.quiet
  configreport = [ configreport sprintf('Diagnostics:  Quiet\n') ];
else
  configreport = [ configreport sprintf('Diagnostics:  Enabled\n') ];
end

if isfinite(config.maxframes)
  configreport = [ configreport ...
    sprintf('Truncating streams to %d frames.\n', config.maxframes) ];
else
  configreport = [ configreport sprintf('Not truncating streams.\n') ];
end


% Processing parameters.

thislist = config.blacklist;
configreport = [ configreport 'Streams ignored:  ' ];
for lidx = 1:length(thislist)
  configreport = [ configreport '  "' thislist{lidx} '"' ];
end
configreport = [ configreport sprintf('\n') ];

configreport = [ configreport sprintf( ...
  'Tile grid:   %d x %d\n', config.tilegrid(1), config.tilegrid(2) ) ];


% Tuning parameters.

configreport = [ configreport sprintf( ...
  'Tuning hint:   %.2f seconds per event\n', config.avgeventinterval ) ];


% Banner.
configreport = [ configreport sprintf('-- Align config ends.\n') ];


% Done.

end


%
% This is the end of the file.
