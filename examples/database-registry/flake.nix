{
  description = "Database Registry with flake-parts - CAST Example";

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

      perSystem = {
        config,
        pkgs,
        ...
      }: let
        # ════════════════════════════════════════
        # CAST Configuration
        # ════════════════════════════════════════
        # Configure CAST with explicit configuration
        # This demonstrates the pure configuration pattern
        castConfig = {
          storePath = "/data/lab-databases";
          # Note: preferredDownloader will be used in future fetchDatabase implementation
          preferredDownloader = "aria2c";
        };

        # Create configured CAST library
        castLib = inputs.cast.lib.configure castConfig;
      in {
        packages = {
          # Example 1: NCBI NR database
          ncbi-nr = castLib.mkDataset {
            name = "ncbi-nr";
            version = "2024-01-15";
            manifest = ./manifests/ncbi-nr.json;
          };

          # Example 2: UniProt database
          uniprot = castLib.mkDataset {
            name = "uniprot";
            version = "2024-01";
            manifest = ./manifests/uniprot.json;
          };

          # Example 3: Transformation - Convert NCBI NR to MMseqs2 format
          ncbi-nr-mmseqs = castLib.transform {
            name = "ncbi-nr-mmseqs";
            src = config.packages.ncbi-nr;

            builder = pkgs.writeShellScript "to-mmseqs" ''
              echo "Converting NCBI NR to MMseqs2 format"

              # Find FASTA file in source data
              fasta_file=$(find "$SOURCE_DATA" -name "*.fasta" -o -name "*.fa" | head -1)

              if [ -z "$fasta_file" ]; then
                echo "Error: No FASTA file found in $SOURCE_DATA"
                exit 1
              fi

              echo "Creating MMseqs2 database from: $fasta_file"

              # For demonstration, we'll create a simple converted file
              # In production, this would use: mmseqs createdb $fasta_file $CAST_OUTPUT/db
              mkdir -p "$CAST_OUTPUT"
              echo "MMseqs2 database placeholder (would use: mmseqs createdb)" > "$CAST_OUTPUT/db.mmseqs"
              echo "Source: $fasta_file" >> "$CAST_OUTPUT/db.mmseqs"
            '';
          };

          # Example 4: Transformation - Convert UniProt to BLAST format
          uniprot-blast = castLib.transform {
            name = "uniprot-blast";
            src = config.packages.uniprot;

            builder = pkgs.writeShellScript "to-blast" ''
              echo "Converting UniProt to BLAST format"

              fasta_file=$(find "$SOURCE_DATA" -name "*.fasta" -o -name "*.fa" | head -1)

              if [ -z "$fasta_file" ]; then
                echo "Error: No FASTA file found"
                exit 1
              fi

              # Placeholder for: makeblastdb -in $fasta_file -dbtype prot
              mkdir -p "$CAST_OUTPUT"
              echo "BLAST database placeholder" > "$CAST_OUTPUT/blastdb"
            '';
          };

          # Default package
          default = config.packages.ncbi-nr;
        };

        # Development shell with databases
        devShells = {
          default = pkgs.mkShell {
            buildInputs = [
              config.packages.ncbi-nr
              config.packages.uniprot
            ];

            shellHook = ''
              echo "=== Database Registry Development Shell ==="
              echo ""
              echo "CAST Configuration:"
              echo "  Storage Path: ${castConfig.storePath}"
              echo "  Downloader:   ${castConfig.preferredDownloader}"
              echo ""
              echo "Available Databases:"
              echo "  - NCBI NR:  $CAST_DATASET_NCBI_NR"
              echo "  - UniProt:  $CAST_DATASET_UNIPROT"
              echo ""
              echo "Transformed versions:"
              echo "  - nix build .#ncbi-nr-mmseqs"
              echo "  - nix build .#uniprot-blast"
            '';
          };
        };
      };
    };
}
