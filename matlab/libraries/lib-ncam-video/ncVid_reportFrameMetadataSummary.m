function summary = ncVid_reportFrameMetadataSummary( framemeta )

% function summary = ncVid_reportFrameMetadataSummary( framemeta )
%
% This function produces a human-readable summary of a NeuroCam frame
% metadata structure (returned by ncVid_getLogfileFrames()).
%
% "framemeta" is the NeuroCam frame metadata structure.
%
% "summary" is a character array containing a human-readable summary message.


% Initialize output.
summary = '';


% Figure out what streams are present.
snames = fieldnames(framemeta);

summary = sprintf( 'Found %d streams.\n', length(snames) );

% Walk through the streams, reporting metadata for each.
for sidx = 1:length(snames)

  thisstream = snames{sidx};

  thisindices = framemeta.(thisstream).indices;
  thistimes = framemeta.(thisstream).times;
  % FIXME - Don't report filenames.

  bannerline = sprintf( 'Stream "%s":\n', thisstream );
  dataline = sprintf( ...
  '  entries:  %d    frames:  %d - %d    times:  %.1f - %.1f seconds\n', ...
    length(thisindices), min(thisindices), max(thisindices), ...
    min(thistimes), max(thistimes) );

  summary = [ summary bannerline dataline ];

end


% Done.

end


%
% This is the end of the file.
