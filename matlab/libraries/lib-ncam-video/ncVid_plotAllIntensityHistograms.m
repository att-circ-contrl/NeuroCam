function ncVid_plotAllIntensityHistograms( intensities, deltas, ...
  plotdir, caselabel, casetitle )

% function ncVid_plotAllIntensityHistograms( intensities, deltas, ...
%   plotdir, caselabel, casetitle )
%
% This function plots intensity statistics for all streams, components, and
% tiles within a dataset.
%
% FIXME - Only plotting deltas, not absolute intensities, for now.
%
% "intensities" is a raw video intensity series structure, per RAWSERIES.txt.
% "deltas" is a video series intensity structure storing differences between
%   successive captured frames, per ncVid_getTileIntensitySeries().
% "plotdir" is the directory to save plot files to.
% "caselabel" is a label string to use when building filenames.
% "casetitle" is a human-readable label to add to plot titles.
%
% No return values.


thisfig = figure();


% FIXME - Black magic for plot tile size.
% Default saves as about 1200x900, but asking for that gets 2500x1900.
hplotsize = 640;
vplotsize = 480;


% Walk through the streams in sequence.

streamlist = fieldnames(deltas);
for sidx = 1:length(streamlist)

  thisstream = streamlist{sidx};
  complabels = fieldnames(deltas.(thisstream));
  [compnames compcolors] = ncVid_getComponentLegend(complabels);


  % Build full-image average component series.
  % Get bin limits while we're at it.

  avgseries = struct();
  compmax = -inf;
  compmin = inf;
  compdev = -inf;

  for cidx = 1:length(complabels)
    thiscomp = complabels{cidx};
    thisgrid = deltas.(thisstream).(thiscomp);

    [ hsize vsize tcount ] = size(thisgrid);

    % Average across the first two dimensions.
    % Make the result one-dimensional.
    gridavg = sum( sum(thisgrid,1), 2 );
    gridavg = squeeze(gridavg);
    gridavg = gridavg / (hsize * vsize);

    % Store the average for the next pass.
    avgseries.(thiscomp) = gridavg;

    % Get minimum and maximum values across all components and tiles.
    thismax = max(max(max(thisgrid)));
    thismin = min(min(min(thisgrid)));
    compmax = max(compmax, thismax);
    compmin = min(compmin, thismin);

    % Get the deviation.
    thisdev = std( reshape( thisgrid, 1, numel(thisgrid) ) );
    compdev = max(thisdev, compdev);
  end


  % Get reasonable histogram bins.
  bincount = 100;

% FIXME - Bin limits are way too far out going by tail values.
%  binedges = linspace(compmin, compmax, bincount + 1);

  binsigma = 6;
  binedges = linspace( -binsigma*compdev, binsigma*compdev, bincount + 1 );

  binmidpoints = 0.5 * ( binedges(1:bincount) + binedges(2:(bincount+1)) );


  % Make the average plot.

  figure(thisfig);
  clf('reset');
  % FIXME - Force position/size.
  set(thisfig, 'Position', [1 1 hplotsize vplotsize]);

  hold on;

  for cidx = 1:length(complabels)
    thiscomp = complabels{cidx};
    thisseries = avgseries.(thiscomp);
    [ hcounts hedges ] = histcounts(thisseries, binedges);
    plot( binmidpoints / compdev, hcounts, ...
      'Color', compcolors{cidx}, 'DisplayName', compnames{cidx} );
  end

  xlim(gca, [-binsigma binsigma]);
  set(gca, 'yscale', 'log');

  legend('Location', 'northeast');
  xlabel('Rate of Change (deviations)');
  ylabel('Histogram Count');
  title(sprintf('%s - Whole-Image Changes - %s', casetitle, thisstream));

  hold off;

  saveas( thisfig, sprintf( '%s%s%s-%s-average.png', ...
    plotdir, filesep, caselabel, thisstream ) );


  % Make per-tile subplots.

  figure(thisfig);
  clf('reset');
  % FIXME - Force position/size.
  set(thisfig, 'Position', [1 1 (hsize*hplotsize) (vsize*vplotsize)]);

  for hidx = 1:hsize
    for vidx = 1:vsize
      subplot( vsize, hsize, hidx + (vidx-1)*hsize );

      hold on;

      for cidx = 1:length(complabels)
        thiscomp = complabels{cidx};
        thisgrid = deltas.(thisstream).(thiscomp);
        thisseries = squeeze( thisgrid(hidx,vidx,:) );
        [ hcounts hedges ] = histcounts(thisseries, binedges);
        plot( binmidpoints / compdev, hcounts, ...
          'Color', compcolors{cidx}, 'DisplayName', compnames{cidx} );
      end

      hold off;

      xlim(gca, [-binsigma binsigma]);
      set(gca, 'yscale', 'log');

      legend('Location', 'northeast');
      xlabel('Rate of Change (deviations)');
      ylabel('Histogram Count');
      title(sprintf( '%s - Tile %d,%d - %s', ...
        casetitle, hidx, vidx, thisstream));
    end
  end

  saveas( thisfig, sprintf( '%s%s%s-%s-tiles.png', ...
    plotdir, filesep, caselabel, thisstream ) );

end


% Clean up.

close(thisfig);


% Done.

end


%
% This is the end of the file.
