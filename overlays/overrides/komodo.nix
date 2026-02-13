# Patch komodo 1.19.5 — fix Rust E0716 (format_args! temporary dropped while borrowed)
# Newer rustc in nixpkgs rejects the pattern; upstream fixed in v2.x but we match Core at 1.19.5
# Affected: bin/core/src/alert/discord.rs, bin/core/src/alert/mod.rs
{
  prev,
  ...
}:
{
  komodo = prev.komodo.overrideAttrs (oldAttrs: {
    postPatch = (oldAttrs.postPatch or "") + ''
      # Fix E0716: format_args! returns a temporary Arguments<'_> that doesn't
      # live long enough across if/else branches. Replace with format! (owned String).
      for f in bin/core/src/alert/discord.rs bin/core/src/alert/mod.rs; do
        substituteInPlace "$f" \
          --replace-fail 'format_args!("")' 'format!("")' \
          --replace-fail 'format_args!("\n{details}")' 'format!("\n{details}")'
      done
    '';

    nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [ prev.makeWrapper ];

    # Periphery shells out to `openssl` CLI for SSL cert generation
    postFixup = (oldAttrs.postFixup or "") + ''
      wrapProgram $out/bin/periphery \
        --prefix PATH : ${prev.lib.makeBinPath [ prev.openssl ]}
    '';
  });
}
