{
  description = "CAST transformation examples";

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
      # Example 1: Simple file copy transformation
      example-copy = let
        # Create source dataset
        sourceDataset = cast.lib.mkDataset {
          name = "source-data";
          version = "1.0.0";
          manifest = ./source-manifest.json;
          storePath = "/tmp/cast-transform-test";
        };
      in
        cast.lib.transform {
          name = "copy-transform";
          src = sourceDataset;

          # Simple builder that copies files to output
          builder = ''
            echo "Copying files from $SOURCE_DATA to $CAST_OUTPUT"
            cp -r "$SOURCE_DATA"/* "$CAST_OUTPUT/"
            echo "Files copied successfully"
          '';
        };

      # Example 2: Text transformation (uppercase)
      example-uppercase = let
        sourceDataset = cast.lib.mkDataset {
          name = "source-data";
          version = "1.0.0";
          manifest = ./source-manifest.json;
          storePath = "/tmp/cast-transform-test";
        };
      in
        cast.lib.transform {
          name = "uppercase-transform";
          src = sourceDataset;

          builder = ''
            echo "Transforming text files to uppercase"
            for file in "$SOURCE_DATA"/*.txt; do
              if [ -f "$file" ]; then
                basename=$(basename "$file")
                tr '[:lower:]' '[:upper:]' < "$file" > "$CAST_OUTPUT/$basename"
                echo "Transformed: $basename"
              fi
            done
          '';
        };

      # Example 3: Chained transformations
      example-chain = let
        # First transformation: copy
        step1 = self.packages.${system}.example-copy;

        # Second transformation: uppercase the copied files
        step2 = cast.lib.transform {
          name = "chain-uppercase";
          src = step1;

          builder = ''
            echo "Second stage: Converting to uppercase"
            for file in "$SOURCE_DATA"/*.txt; do
              if [ -f "$file" ]; then
                basename=$(basename "$file")
                tr '[:lower:]' '[:upper:]' < "$file" > "$CAST_OUTPUT/$basename"
              fi
            done
          '';
        };
      in step2;

      # Default package
      default = self.packages.${system}.example-copy;
    };
  };
}
