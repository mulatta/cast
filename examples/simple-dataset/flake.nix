{
  description = "Simple CAST dataset example";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    systems.url = "github:nix-systems/default";
    cast = {
      url = "path:../..";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    cast,
    systems,
    ...
  }: let
    forAllSystems = f:
      nixpkgs.lib.genAttrs (import systems) (system:
        f {
          inherit system;
          pkgs = nixpkgs.legacyPackages.${system};
        });
  in {
    packages = forAllSystems (_: let
      # CAST configuration with explicit storePath
      # For production, use flake-parts options instead (see database-registry example)
      castLib = cast.lib.configure {
        storePath = builtins.getEnv "HOME" + "/.cache/cast";
      };
    in rec {
      # Example dataset using pre-existing manifest
      example-dataset = castLib.mkDataset {
        name = "simple-example";
        version = "1.0.0";
        manifest = ./manifest.json;
      };

      # Default package
      default = example-dataset;
    });

    # Dev shell with the dataset available
    devShells = forAllSystems ({
      system,
      pkgs,
    }: {
      default = pkgs.mkShell {
        buildInputs = [
          self.packages.${system}.example-dataset
        ];

        shellHook = ''
          echo "Simple example dataset loaded!"
          echo "Dataset path: $CAST_DATASET_SIMPLE_EXAMPLE"
          echo "Manifest: $CAST_DATASET_SIMPLE_EXAMPLE_MANIFEST"
          echo ""
          echo "Available files:"
          ls -lh "$CAST_DATASET_SIMPLE_EXAMPLE"
        '';
      };
    });
  };
}
