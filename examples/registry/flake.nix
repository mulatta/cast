{
  description = "CAST Dataset Registry - Multi-version database management";

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

    # CAST configuration with explicit storePath
    # For production with flake-parts options, see the database-registry example (Task 12)
    castLib = cast.lib.configure {
      storePath = builtins.getEnv "HOME" + "/.cache/cast";
    };
  in {
    # Database registry with multiple versions
    databases = {
      # Example: Test database with multiple versions
      test-db = {
        "1.0.0" = castLib.mkDataset {
          name = "test-db";
          version = "1.0.0";
          manifest = ./manifests/test-db-1.0.0.json;
        };

        "1.1.0" = castLib.mkDataset {
          name = "test-db";
          version = "1.1.0";
          manifest = ./manifests/test-db-1.1.0.json;
        };

        "2.0.0" = castLib.mkDataset {
          name = "test-db";
          version = "2.0.0";
          manifest = ./manifests/test-db-2.0.0.json;
        };
      };

      # Example: Protein database versions
      uniprot = {
        "2024-01" = castLib.mkDataset {
          name = "uniprot";
          version = "2024-01";
          manifest = ./manifests/uniprot-2024-01.json;
        };

        "2024-02" = castLib.mkDataset {
          name = "uniprot";
          version = "2024-02";
          manifest = ./manifests/uniprot-2024-02.json;
        };
      };
    };

    # Convenience packages pointing to latest versions
    packages = forAllSystems (_: {
      test-db-latest = self.databases.test-db."2.0.0";
      test-db-stable = self.databases.test-db."1.1.0";
      uniprot-latest = self.databases.uniprot."2024-02";

      default = self.databases.test-db."2.0.0";
    });

    # Example: Development shell with specific database version
    devShells = forAllSystems ({pkgs}: {
      # Shell with latest test-db
      default = pkgs.mkShell {
        buildInputs = [self.databases.test-db."2.0.0"];
        shellHook = ''
          echo "Test DB v2.0.0 loaded"
          echo "Path: $CAST_DATASET_TEST_DB"
        '';
      };

      # Shell with v1.1.0 for compatibility testing
      legacy = pkgs.mkShell {
        buildInputs = [self.databases.test-db."1.1.0"];
        shellHook = ''
          echo "Test DB v1.1.0 (legacy) loaded"
          echo "Path: $CAST_DATASET_TEST_DB"
        '';
      };

      # Shell with multiple versions for migration testing
      migration = pkgs.mkShell {
        buildInputs = [
          self.databases.test-db."1.1.0"
          self.databases.test-db."2.0.0"
        ];
        shellHook = ''
          echo "Multi-version environment loaded"
          echo "Old version: $CAST_DATASET_TEST_DB_VERSION"
          echo "New version: $CAST_DATASET_TEST_DB_VERSION"
          echo "Note: Both versions use same env var names"
        '';
      };
    });
  };
}
