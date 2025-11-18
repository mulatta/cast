{
  description = "CAST Dataset Registry - Multi-version database management";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-parts.url = "github:hercules-ci/flake-parts";
    systems.url = "github:nix-systems/default";
    cast = {
      url = "path:../..";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    flake-parts,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = import inputs.systems;

      # Import CAST flakeModule
      imports = [inputs.cast.flakeModules.default];

      perSystem = {
        config,
        pkgs,
        castLib, # Automatically injected by CAST flakeModule
        ...
      }: {
        # Configure CAST storage path
        cast.storePath = builtins.getEnv "HOME" + "/.cache/cast";

        # Database registry packages with all versions
        # Using namespaced package names for multi-version support
        packages = let
          # Helper to create all versioned packages
          test-db-versions = {
            "test-db-1.0.0" = castLib.mkDataset {
              name = "test-db";
              version = "1.0.0";
              manifest = ./manifests/test-db-1.0.0.json;
            };

            "test-db-1.1.0" = castLib.mkDataset {
              name = "test-db";
              version = "1.1.0";
              manifest = ./manifests/test-db-1.1.0.json;
            };

            "test-db-2.0.0" = castLib.mkDataset {
              name = "test-db";
              version = "2.0.0";
              manifest = ./manifests/test-db-2.0.0.json;
            };
          };

          uniprot-versions = {
            "uniprot-2024-01" = castLib.mkDataset {
              name = "uniprot";
              version = "2024-01";
              manifest = ./manifests/uniprot-2024-01.json;
            };

            "uniprot-2024-02" = castLib.mkDataset {
              name = "uniprot";
              version = "2024-02";
              manifest = ./manifests/uniprot-2024-02.json;
            };
          };
        in
          test-db-versions
          // uniprot-versions
          // {
            # Convenience aliases for latest versions
            test-db-latest = test-db-versions."test-db-2.0.0";
            test-db-stable = test-db-versions."test-db-1.1.0";
            uniprot-latest = uniprot-versions."uniprot-2024-02";

            default = test-db-versions."test-db-2.0.0";
          };

        # Example: Development shell with specific database version
        devShells = {
          # Shell with latest test-db
          default = pkgs.mkShell {
            buildInputs = [config.packages."test-db-2.0.0"];
            shellHook = ''
              echo "Test DB v2.0.0 loaded"
              echo "Path: $CAST_DATASET_TEST_DB"
            '';
          };

          # Shell with v1.1.0 for compatibility testing
          legacy = pkgs.mkShell {
            buildInputs = [config.packages."test-db-1.1.0"];
            shellHook = ''
              echo "Test DB v1.1.0 (legacy) loaded"
              echo "Path: $CAST_DATASET_TEST_DB"
            '';
          };

          # Shell with multiple versions for migration testing
          migration = pkgs.mkShell {
            buildInputs = [
              config.packages."test-db-1.1.0"
              config.packages."test-db-2.0.0"
            ];
            shellHook = ''
              echo "Multi-version environment loaded"
              echo "Old version: $CAST_DATASET_TEST_DB_VERSION"
              echo "New version: $CAST_DATASET_TEST_DB_VERSION"
              echo "Note: Both versions use same env var names"
            '';
          };
        };
      };
    };
}
