function aligndata = ncVid_getFolderalignment( ...
  config, indir, outdir, plotdir, caselabel, casetitle )

% function aligndata = ncVid_getFolderalignment( ...
%   config, indir, outdir, plotdir, caselabel, casetitle )
%
% This function is the top-level entry point for time-aligning a NeuroCam
% session folder.
%
% "config" is a configuration structure, per ALIGNCONFIG.txt.
% "indir" is the NeuroCam session folder (the folder that contains
%   logfile.txt).
% "outdir" is a folder to write extracted data to (or '' to suppress output).
% "plotdir" is a folder to write plots to (or '' to suppress output).
% "caselabel" is a label string to use when building filenames.
% "casetitle" is a human-readable label to add to plot titles.
%
% "aligndata" is a structure containing extracted information about the
%   video streams (the data that is normally saved to "outdir"). It has the
%   following fields:
%   "config" is a copy of the configuration structure with any missing
%     parameter values filled in.
%   "framemeta" is a copy of the raw NeuroCam frame-grab metadata, per
%     FRAMEMETA.txt.
%   "intensities" is a copy of the raw per-tile video intensity data, per
%     RAWSERIES.txt.
%   "deltas" is a copy of the frame-by-frame per-tile intensity changes,
%     per ncVid_getTileIntensitySeries(), with format per RAWSERIES.txt.


% FIXME - Debugging config.
debug_use_saved = true;


% Initialize output.
aligndata = struct();


% Sanity check plotting and data output.
wantoutput = (~isempty(outdir)) && isfolder(outdir);
wantplots = (~isempty(plotdir)) && isfolder(plotdir);


% Construct various filenames for saving data.

fnameconfig = [ outdir filesep caselabel '-config.mat' ];
fnameframemeta = [ outdir filesep caselabel '-framemeta.mat' ];
fnameintensity = [ outdir filesep caselabel '-intensities.mat' ];
fnamedelta = [ outdir filesep caselabel '-deltas.mat' ];


% Set reasonable default configuration values if not present.
config = ncVid_fillMissingAlignConfig(config);

% Store the updated configuration structure.
aligndata.config = config;
if wantoutput
  save( fnameconfig, 'config', '-v7.3' );
end


% Proceed, if we've found input.

logname = [ indir filesep 'logfile.txt' ];
if ~isfile(logname)
  if ~(config.quiet)
    disp([ '###  Couldn''t read "' logname '".' ]);
  end
else
  if ~(config.quiet)
    disp([ '-- Processing "' logname '".' ]);
  end


  % Tattle configuration.
  if ~(config.quiet)
    disp(ncVid_reportAlignConfig(config));
  end


  % Get frame metadata from the logfile.

  % FIXME - Load previously-saved if desired.
  if debug_use_saved && isfile(fnameframemeta)
    if ~(config.quiet)
      disp('.. Loading previously-computed frame metadata.');
    end
    load( fnameframemeta );
  else
    % Build frame metadata from the NeuroCam log.
    framemeta = ncVid_getLogfileFrames(logname);
  end

  % FIXME - Truncate the stream file lists if we're running a short test.
  if isfinite(config.maxframes)
    if ~(config.quiet)
      disp(sprintf( '.. Truncating streams to at most %d frames.', ...
        config.maxframes ));
    end
    framemeta = ncVid_truncateFrameLists(framemeta, config.maxframes);
  end

  if ~(config.quiet)
    disp(ncVid_reportFrameMetadataSummary(framemeta));
  end

  % Store the frame metadata.
  aligndata.framemeta = framemeta;
  if wantoutput
    save( fnameframemeta, 'framemeta', '-v7.3' );
  end


  % Get per-tile per-component intensity series.

  % FIXME - Load previously-saved if desired.
  if debug_use_saved && isfile(fnameintensity) && isfile(fnamedelta)
    if ~(config.quiet)
      disp('.. Loading previously-computed raw intensity series.');
    end
    load( fnameintensity );
    load( fnamedelta );
  else
    % Recompute intensity series from the raw video frames.
    [ intensities deltas ] = ...
      ncVid_getTileIntensitySeries(config, indir, framemeta);
  end

  % Store the raw intensities.
  aligndata.intensities = intensities;
  aligndata.deltas = deltas;
  if wantoutput
    save( fnameintensity, 'intensities', '-v7.3' );
    save( fnamedelta, 'deltas', '-v7.3' );
  end

  % Make histogram plots of the intensity series.
  if wantplots
    if ~(config.quiet)
      disp('.. Plotting intensity-change histograms.');
    end

    ncVid_plotAllIntensityHistograms( intensities, deltas, ...
      plotdir, caselabel, casetitle );
  end


% FIXME -NYI.


  if ~(config.quiet)
    disp([ '-- Finished processing "' logname '".' ]);
  end
end


% Done.

end


%
% This is the end of the file.
