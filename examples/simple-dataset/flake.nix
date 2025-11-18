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
      # Example dataset using pre-existing manifest
      example-dataset = cast.lib.mkDataset {
        name = "simple-example";
        version = "1.0.0";
        manifest = ./manifest.json;
        # Use CAST_STORE environment variable (requires --impure flag)
        # Example: CAST_STORE=$HOME/.cache/cast nix build --impure .#example-dataset
        storePath = null; # Will use CAST_STORE env var or default
      };

      # Default package
      default = self.packages.${system}.example-dataset;
    };

    # Dev shell with the dataset available
    devShells.${system}.default = pkgs.mkShell {
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
  };
}
