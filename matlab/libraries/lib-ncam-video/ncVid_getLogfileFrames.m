function framemeta = ncVid_getLogfileFrames( logfile )

% function framemeta = ncVid_getLogfileFrames( logfile )
%
% This function parses a NeuroCam log file and extracts frame filenames
% and timings for each recorded video stream.
%
% "logfile" is the filename of the log file to process (including path).
%
% "framemeta" is a structure indexed by video stream label containing
%   per-stream structures with the following fields (per FRAMEMETA.txt):
%   "indices" is a vector storing frame numbers for recorded frames.
%   "times" is a vector containing frame timestamps (in seconds).
%   "fnames" is a cell array containing frame image filenames (including
%     paths).
%


% Initialize output.
framemeta = struct();


% Read the raw log file data.
logtext = fileread(logfile);

% Get all frame record lines.
% These get broken into token sequences.
% Frame record lines have the form "(time) [stream]  frame (frame)  fname".
logframes = regexp( logtext, ...
  '\((\d+)\)\s+\[(\w+)\]\s+frame\s+(\d+)\s+(\S+)', 'tokens' );


% Walk through the frame records, storing metadata for each frame.

for lidx = 1:length(logframes)

  thisrec = logframes{lidx};

  % Convert from ms to seconds.
  thistime = 1e-3 * str2double(thisrec{1});
  thisstream = thisrec{2};
  thisfidx = str2double(thisrec{3});
  thisfname = thisrec{4};

  if ~isfield(framemeta, thisstream)
    framemeta.(thisstream) = ...
      struct( 'indices', [], 'times', [], 'fnames', {{}} );
  end

  thisentry = 1 + length( framemeta.(thisstream).indices );
  framemeta.(thisstream).indices(thisentry) = thisfidx;
  framemeta.(thisstream).times(thisentry) = thistime;
  framemeta.(thisstream).fnames{thisentry} = thisfname;

end


% Done.

end


%
% This is the end of the file.
