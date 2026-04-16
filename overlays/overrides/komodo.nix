# Patch + wrap komodo:
#  - Bump rustc recursion_limit so komodo_core's axum router type resolves
#  - Wrap periphery with openssl on PATH (shells out for SSL cert generation)
{
  prev,
  ...
}:
{
  komodo = prev.komodo.overrideAttrs (oldAttrs: {
    nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [ prev.makeWrapper ];

    postPatch = (oldAttrs.postPatch or "") + ''
      # Deep axum router layouts bust rustc's default query depth (128).
      # Must live at crate root — RUSTFLAGS can't set recursion_limit on stable.
      for f in bin/core/src/main.rs bin/periphery/src/main.rs; do
        if [ -f "$f" ] && ! grep -q 'recursion_limit' "$f"; then
          sed -i '1i #![recursion_limit = "1024"]' "$f"
        fi
      done
    '';

    postFixup = (oldAttrs.postFixup or "") + ''
      wrapProgram $out/bin/periphery \
        --prefix PATH : ${prev.lib.makeBinPath [ prev.openssl ]}
    '';
  });
}
