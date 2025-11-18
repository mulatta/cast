{
  description = "Simple CAST dataset example";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    cast = {
      url = "path:../..";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    cast,
  }: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
  in {
    packages.${system} = {
      # Example dataset using mkDataset
      example-dataset = cast.lib.mkDataset {
        name = "example-dataset";
        version = "2024-01-01";
        manifest = ./test-manifest.json;
        # Use a temporary store path for testing
        storePath = "/tmp/cast-test-store";
      };

      # Default package
      default = self.packages.${system}.example-dataset;
    };

    # Development shell showing environment variable usage
    devShells.${system}.default = pkgs.mkShell {
      name = "cast-example-shell";
      buildInputs = [self.packages.${system}.example-dataset];

      shellHook = ''
        echo "CAST Dataset Example Shell"
        echo "============================"
        if [ -n "$CAST_DATASET_EXAMPLE_DATASET" ]; then
          echo "✓ CAST_DATASET_EXAMPLE_DATASET = $CAST_DATASET_EXAMPLE_DATASET"
          echo "✓ CAST_DATASET_EXAMPLE_DATASET_VERSION = $CAST_DATASET_EXAMPLE_DATASET_VERSION"
          echo "✓ CAST_DATASET_EXAMPLE_DATASET_MANIFEST = $CAST_DATASET_EXAMPLE_DATASET_MANIFEST"
        else
          echo "✗ Environment variables not set"
        fi
      '';
    };
  };
}
