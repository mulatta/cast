{
  description = "CAST transformation examples";

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
    packages = forAllSystems ({
      system,
      pkgs,
    }: let
      # CAST configuration
      castLib = cast.lib.configure {};
      packagesAttrs = rec {
        # Example 1: Simple file copy transformation
        example-copy = let
          # Create simple source dataset with actual files (not CAS)
          sourceDataset = pkgs.stdenv.mkDerivation {
            name = "source-data";
            version = "1.0.0";

            dontUnpack = true;
            dontBuild = true;

            installPhase = ''
              mkdir -p $out/data
              echo "hello world!" > $out/data/hello.txt
              echo "world" > $out/data/world.txt

              # Create a simple manifest
              cat > $out/manifest.json <<'EOF'
              {
                "schema_version": "1.0",
                "dataset": {
                  "name": "source-data",
                  "version": "1.0.0",
                  "description": "Simple test dataset"
                },
                "source": {
                  "url": "generated://test-data"
                },
                "contents": [],
                "transformations": []
              }
              EOF
            '';
          };
        in
          castLib.transform {
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
          # Create simple source dataset with actual files
          sourceDataset = pkgs.stdenv.mkDerivation {
            name = "source-data";
            version = "1.0.0";

            dontUnpack = true;
            dontBuild = true;

            installPhase = ''
              mkdir -p $out/data
              echo "hello world!" > $out/data/hello.txt
              echo "world" > $out/data/world.txt

              cat > $out/manifest.json <<'EOF'
              {
                "schema_version": "1.0",
                "dataset": {"name": "source-data", "version": "1.0.0"},
                "source": {"url": "generated://test"},
                "contents": [],
                "transformations": []
              }
              EOF
            '';
          };
        in
          castLib.transform {
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
          step2 = castLib.transform {
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
        in
          step2;

        # Default package
        default = example-copy;
      };
    in
      packagesAttrs);
  };
}
