{
  description = "CAST: Content-Addressed Storage Tool";
  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = import inputs.systems;
      imports = [
        ./dev/formatter.nix
        ./dev/shell.nix
      ];

      perSystem = {
        lib,
        self',
        system,
        ...
      }: {
        _module.args.pkgs = import inputs.nixpkgs {
          inherit system;
          overlays = [
            inputs.rust-overlay.overlays.default
          ];
          config.allowUnfree = true;
        };

        checks = let
          packages = lib.mapAttrs' (n: lib.nameValuePair "package-${n}") self'.packages;
          devShells = lib.mapAttrs' (n: lib.nameValuePair "devShell-${n}") self'.devShells;
        in
          {inherit (self') formatter;} // packages // devShells;
      };

      flake = {
        # CAST library functions for Nix
        lib = import ./lib {
          inherit (inputs.nixpkgs) lib;
          pkgs = import inputs.nixpkgs {
            system = "x86_64-linux";
            overlays = [inputs.rust-overlay.overlays.default];
          };
        };
      };
    };

  inputs = {
    # keep-sorted start
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
    flake-parts.url = "github:hercules-ci/flake-parts";
    nix-ai-tools.url = "github:numtide/nix-ai-tools";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
    rust-overlay.url = "github:oxalica/rust-overlay";
    systems.url = "github:nix-systems/default";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    # keep-sorted end
  };
}
