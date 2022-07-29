% Video-alignment test script.
% Written by Christopher Thomas.
% This wraps NeuroCam video alignment functions.


%
% Initialization

clear;
close all;

addpath('libraries');
addPathsNeuroCam();

% We're going to need exputil's alignment routines.
% We probably won't use looputil, but exputil might depend on it.

%addpath('lib-looputil');
%addPathsLoopUtil();

%addpath('lib-exputil');
%addPathsExpUtilsCjt();



%
% Constants

% Input case information.
indir = 'footage/ncam-bard-20211210-short';
caselabel = 'bard';
casetitle = 'Bard 20211210';

% Output directories.
outdir = 'output';
plotdir = 'plots';

% The image is optionally divided into a grid, with each grid tile having
% its own event stream.
%tilegrid = [ 1 1 ];
tilegrid = [ 4 3 ];

% The auto-tuning function will try to generate events this often (per tile).
%eventintervalsecs = 0.3;
eventintervalsecs = 1;
%eventintervalsecs = 3;

% Set this to a finite value to test on a subset of the frames.
%maxframes = inf;
maxframes = 1000;



%
% Main Program


config = ...
  struct( 'tilegrid', tilegrid, 'avgeventinterval', eventintervalsecs, ...
    'maxframes', maxframes );
aligndata = ncVid_getFolderAlignment(config, indir, outdir, plotdir, ...
  caselabel, casetitle);


%
% This is the end of the file.
