# Wrap komodo-periphery with openssl on PATH (shells out for SSL cert generation)
{
  prev,
  ...
}:
{
  komodo = prev.komodo.overrideAttrs (oldAttrs: {
    nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [ prev.makeWrapper ];
    postFixup = (oldAttrs.postFixup or "") + ''
      wrapProgram $out/bin/periphery \
        --prefix PATH : ${prev.lib.makeBinPath [ prev.openssl ]}
    '';
  });
}
