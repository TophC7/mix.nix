# Infrastructure utilities namespace
{ lib }: lib.fs.importAndMerge ./. { inherit lib; }
