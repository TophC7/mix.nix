# Flake-parts module for development shell
_: {
  perSystem =
    { pkgs, lib, ... }:
    {
      # Development shell for working on this library
      devShells.default = lib.mkDefault (
        pkgs.mkShell {
          name = "lib-nix-dev";

          packages = with pkgs; [
            # Nix tooling
            nil # Nix LSP
            nixfmt-rfc-style # Official Nix formatter
            statix # Nix linter
            deadnix # Find dead code

            # General dev tools
            git
          ];

          shellHook = ''
            echo "mix.nix development shell"
          '';
        }
      );

      # Formatter for `nix fmt`
      formatter = pkgs.nixfmt-rfc-style;
    };
}
