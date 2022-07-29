function [ intensities deltas ] = ...
  ncVid_getTileIntensitySeries( config, indir, framemeta )

% function [ intensities deltas ] = ...
%   ncVid_getTileIntensitySeries( config, indir, framemeta )
%
% This function builds component intensity series for each video stream
% described by "framemeta".
%
% "config" is a configuration structure, per ALIGNCONFIG.txt.
% "indir" is the root directory for this NeuroCam repository; this should
%   be the folder that has "logfile.txt".
% "framemeta" is a repository frame metadata structure, per FRAMEMETA.txt.
%
% "intensities" is a raw video intensity series structure, per RAWSERIES.txt.
% "deltas" is a video intensity series structure, per RAWSERIES.txt, that
%   stores the rate of change of component intensity between frames, computed
%   as "diff(tile intensity) ./ diff(timestamps)".


% Initialize output.
intensities = struct();
deltas = struct();


% Force sanity.
config = ncVid_fillMissingAlignConfig(config);

% Extract configuration that we're going to be repeatedly looking up.
dotattle = ~config.quiet;
htiles = config.tilegrid(1);
vtiles = config.tilegrid(2);


% Get a list of streams that we're processing.
streamlist = fieldnames(framemeta);


% First pass:
% Walk through the streams, reading frames and storing intensities.

for sidx = 1:length(streamlist)
  thisstream = streamlist{sidx};
  if ismember(thisstream, config.blacklist)
    if dotattle
      disp([ '-- Skipping "' thisstream '".' ]);
    end
  else

    if dotattle
      disp([ '-- Processing "' thisstream '".' ]);
    end

    % We only care about the list of filenames; ignore other metadata.
    thisflist = framemeta.(thisstream).fnames;

    % Do a sanity-check first, in case directories were renamed.
    % Catch empty directories here too (shouldn't happen).
    if length(thisflist) < 1
      % This shouldn't happen, since the stream IDs are taken from the
      % frame list, but check for it anyways.
      disp([ '###  Stream "' thisstream '" has no frames.' ]);
    elseif ~isfile( [ indir filesep thisflist{1} ] )
      % This will happen if people rename directories, which they do.
      disp([ '###  Can''t find first frame in stream "' thisstream '".' ]);
      disp([ '("' indir filesep thisflist{1} '")' ]);
    else
      % This stream's folder seems to be okay, but still check for missing
      % frames so we can bail out for unexpected truncation.
      % This will happen for test folders where we copied the full logfile
      % but only a subset of the frames.

      isok = true;
      for fidx = 1:length(thisflist)
        if isok

          if dotattle && (1 == mod(fidx,100))
            disp(sprintf('.. Frame %d...', fidx));
          end

          thisfile = [ indir filesep thisflist{fidx} ];

          [ isok frameintensity ] = ...
            ncVid_getOneFrameIntensity(thisfile, htiles, vtiles);

          if ~isok
            disp([ '###  Unexpected end of stream "' thisstream '".' ]);
            disp([ '(Couldn''t read "' thisfile '".)' ]);
          else
            if 1 == fidx
              intensities.(thisstream) = frameintensity;
            else
              complist = fieldnames(frameintensity);
              for cidx = 1:length(complist)
                thiscomp = complist{cidx};
                intensities.(thisstream).(thiscomp)(:,:,fidx) = ...
                  frameintensity.(thiscomp);
              end
            end
          end

        end
      end
    end

  end
end


if dotattle
  disp('-- Computing deltas.');
end


streamlist = fieldnames(intensities);

for sidx = 1:length(streamlist)
  thisstream = streamlist{sidx};
  thistimes = framemeta.(thisstream).times;

  streamintensities = intensities.(thisstream);
  complist = fieldnames(streamintensities);

  for cidx = 1:length(complist)
    thiscomp = complist{cidx};

    for hidx = 1:htiles
      for vidx = 1:vtiles
        thisintseries = intensities.(thisstream).(thiscomp)(hidx,vidx,:);
        % NOTE - Dimensionality of difference series need to agree.
        thisintseries = transpose(squeeze(thisintseries));

        thisdiff = diff(thisintseries) ./ diff(thistimes);
        deltas.(thisstream).(thiscomp)(hidx,vidx,:) = thisdiff;
      end
    end
  end
end


if dotattle
  disp('-- Finished processing streams.');
end


% Done.

end


%
% This is the end of the file.
