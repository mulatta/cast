{
  description = "Simple CAST dataset example";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-parts.url = "github:hercules-ci/flake-parts";
    systems.url = "github:nix-systems/default";
    cast = {
      url = "path:../..";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = import inputs.systems;

      # Import CAST flakeModule for automatic castLib injection
      imports = [inputs.cast.flakeModules.default];

      perSystem = {
        config,
        pkgs,
        castLib, # Automatically injected by CAST flakeModule
        ...
      }: {
        # Configure CAST storage path (per-system)
        cast.storePath = builtins.getEnv "HOME" + "/.cache/cast";

        packages = rec {
          # Example dataset using pre-existing manifest
          # castLib is automatically configured with cast.storePath
          example-dataset = castLib.mkDataset {
            name = "simple-example";
            version = "1.0.0";
            manifest = ./manifest.json;
          };

          # Default package
          default = example-dataset;
        };

        # Dev shell with the dataset available
        devShells.default = pkgs.mkShell {
          buildInputs = [
            config.packages.example-dataset
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
      };
    };
}
