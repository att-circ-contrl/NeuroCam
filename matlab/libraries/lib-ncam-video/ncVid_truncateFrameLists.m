function newmeta = ncVid_truncateFrameLists(framemeta, maxframes)

% function newmeta = ncVid_truncateFrameLists(framemeta, maxframes)
%
% This function truncates the lists of frames within a frame metadata
% structure to have at most the specified number of frames per stream.
%
% "framemeta" is a frame metadata structure, per FRAMEMETA.txt.
% "maxframes" is the maximum number of frames to retain.
%
% "newmeta" is a truncated copy of "framemeta".


newmeta = framemeta;

streamlist = fieldnames(newmeta);
for sidx = 1:length(streamlist)

  thisstream = streamlist{sidx};
  thismeta = newmeta.(thisstream);

  thislength = length(thismeta.indices);
  newlength = min(thislength, maxframes);

  thismeta.indices = thismeta.indices(1:newlength);
  thismeta.times = thismeta.times(1:newlength);
  thismeta.fnames = thismeta.fnames(1:newlength);

  newmeta.(thisstream) = thismeta;

end


% Done.

end


%
% This is the end of the file.
