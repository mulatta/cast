{
  description = "CAST Bioinformatics Transformation Builders Examples";

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
        # Configure CAST storage path
        cast.storePath =
          if builtins.getEnv "CAST_STORE" != ""
          then builtins.getEnv "CAST_STORE"
          else "/tmp/cast-bioinformatics";

        packages = let
          # ══════════════════════════════════════════════════════════════
          # Sample FASTA Dataset
          # ══════════════════════════════════════════════════════════════

          # Create a sample protein FASTA dataset for demonstration
          sampleFastaDataset = pkgs.stdenv.mkDerivation {
            name = "sample-proteins";
            version = "1.0.0";

            dontUnpack = true;
            dontBuild = true;

            installPhase = ''
              mkdir -p $out/data

              # Create sample protein FASTA file
              cat > $out/data/proteins.fasta <<'EOF'
              >sp|P12345|PROT1_HUMAN Sample protein 1
              MKTAYIAKQRQISFVKSHFSRQLEERLGLIEVQAPILSRVGDGTQDNLSGAEKAVQVKVKALPDAQFEVVHSLAKWKRQTLGQHDFSAGEGLYTHMKALRPDEDRLSPLHSVYVDQWDWERVMGDGERQFSTLKSTVEAIWAGIKATEAAVSEEFGLAPFLPDQIHFVHSQELLSRYPDLDAKGRERAIAKDLGAVFLVGIGGKLSDGHRHDVRAPDYDDWSTPSELGHAGLNGDILVWNPVLEDAFELSSMGIRVDADTLKHQLALTGDEDRLELEWHQALLRGEMPQTIGGGIGQSRLTMLLLQLPHIGQVQAGVWPAAVRESVPSLL
              >sp|P67890|PROT2_HUMAN Sample protein 2
              MAALSGGGGGGAEPGQALFNGDMEPEAGAGAGAAASSAADPAIPEEVWNIKQMIKLTQEHIEALLDKFGGEHNPPSIYLEAYEEYTSKLDALQQREQQLLESLGNGTDFSVSSSASMDTVTSSSSSSLSVLPSSLSVASVIEPPLSEPQSPTSPEHSSVSPSQLSPPASPPPPPPPPPPPPKKKRRPEEEEEKDEPQQQQPPPPPPPKKKRRPEEEEDEDMDMDMDMDMMDMDMDMDMDMDMDMDMDPPPQKGTTRRPPPHHTTTT
              >sp|Q11111|PROT3_MOUSE Sample protein 3
              MAEGEITTFTALTEKFNLPPGNYKKPKLLYCSNGGHFLRILPDGTVDGTRDRSDQHIQLQLSAESVGEVYIKSTETGQYLAMDTSGLLYGSQTPSEECLFLERLEENHYNTYTSKKHAEKNWFVGLKKNGSCKRGPRTHYGQKAILFLPLPV
              >sp|Q22222|PROT4_YEAST Sample protein 4
              MVSKGEELFTGVVPILVELDGDVNGHKFSVSGEGEGDATYGKLTLKFICTTGKLPVPWPTLVTTLTYGVQCFSRYPDHMKQHDFFKSAMPEGYVQERTIFFKDDGNYKTRAEVKFEGDTLVNRIELKGIDFKEDGNILGHKLEYNYNSHNVYIMADKQKNGIKVNFKIRHNIEDGSVQLADHYQQNTPIGDGPVLLPDNHYLSTQSALSKDPNEKRDHMVLLEFVTAAGITLGMDELYK
              EOF

              # Create manifest
              cat > $out/manifest.json <<'EOF'
              {
                "schema_version": "1.0",
                "dataset": {
                  "name": "sample-proteins",
                  "version": "1.0.0",
                  "description": "Sample protein sequences for testing bioinformatics tools"
                },
                "source": {
                  "url": "generated://example-proteins",
                  "download_date": "2024-01-01T00:00:00Z"
                },
                "contents": [],
                "transformations": []
              }
              EOF
            '';
          };

          # ══════════════════════════════════════════════════════════════
          # Sample Archive Dataset (for extractArchive example)
          # ══════════════════════════════════════════════════════════════

          sampleArchiveDataset = pkgs.stdenv.mkDerivation {
            name = "sample-archive";
            version = "1.0.0";

            buildInputs = [pkgs.gnutar pkgs.gzip];

            dontUnpack = true;

            buildPhase = ''
              # Create test data
              mkdir -p testdata
              echo ">seq1" > testdata/sequences.fasta
              echo "ATCGATCGATCG" >> testdata/sequences.fasta
              echo "metadata" > testdata/info.txt

              # Create tar.gz archive
              tar czf proteins.tar.gz testdata/
            '';

            installPhase = ''
              mkdir -p $out/data
              cp proteins.tar.gz $out/data/

              cat > $out/manifest.json <<'EOF'
              {
                "schema_version": "1.0",
                "dataset": {
                  "name": "sample-archive",
                  "version": "1.0.0",
                  "description": "Sample archived dataset"
                },
                "source": {
                  "url": "generated://example-archive"
                },
                "contents": [],
                "transformations": []
              }
              EOF
            '';
          };
        in rec {
          # ══════════════════════════════════════════════════════════════
          # Example 1: MMseqs2 Database
          # ══════════════════════════════════════════════════════════════

          example-mmseqs = castLib.toMMseqs {
            name = "sample-proteins-mmseqs";
            src = sampleFastaDataset;
            fastaFile = "proteins.fasta";
            createIndex = true;
          };

          # ══════════════════════════════════════════════════════════════
          # Example 2: BLAST Database (Protein)
          # ══════════════════════════════════════════════════════════════

          example-blast-prot = castLib.toBLAST {
            name = "sample-proteins-blast";
            src = sampleFastaDataset;
            fastaFile = "proteins.fasta";
            dbType = "prot";
            title = "Sample Protein Database";
            parseSeqids = true;
          };

          # ══════════════════════════════════════════════════════════════
          # Example 3: Diamond Database
          # ══════════════════════════════════════════════════════════════

          example-diamond = castLib.toDiamond {
            name = "sample-proteins-diamond";
            src = sampleFastaDataset;
            fastaFile = "proteins.fasta";
          };

          # ══════════════════════════════════════════════════════════════
          # Example 4: Extract Archive
          # ══════════════════════════════════════════════════════════════

          example-extract = castLib.extractArchive {
            name = "sample-extracted";
            src = sampleArchiveDataset;
            archiveFile = "proteins.tar.gz";
            stripComponents = 0;
          };

          # ══════════════════════════════════════════════════════════════
          # Example 5: Transformation Pipeline
          # ══════════════════════════════════════════════════════════════

          # Pipeline: Extract archive → Convert to MMseqs2
          example-pipeline = let
            # Step 1: Extract archive
            extracted = castLib.extractArchive {
              name = "pipeline-extracted";
              src = sampleArchiveDataset;
              archiveFile = "proteins.tar.gz";
              stripComponents = 1;
            };

            # Step 2: Convert extracted FASTA to MMseqs2
            mmseqsDb = castLib.toMMseqs {
              name = "pipeline-mmseqs";
              src = extracted;
              fastaFile = "sequences.fasta";
              createIndex = false;
            };
          in
            mmseqsDb;

          # ══════════════════════════════════════════════════════════════
          # Example 6: Multi-format Export
          # ══════════════════════════════════════════════════════════════

          # Create all three search tool formats from same source
          # (useful for tools with different format requirements)
          example-all-formats = castLib.symlinkSubset {
            name = "sample-all-formats";
            paths = [
              {
                name = "mmseqs";
                path = example-mmseqs;
              }
              {
                name = "blast";
                path = example-blast-prot;
              }
              {
                name = "diamond";
                path = example-diamond;
              }
            ];
          };

          # Default package for quick testing
          default = example-mmseqs;
        };

        # ══════════════════════════════════════════════════════════════
        # Development Shells
        # ══════════════════════════════════════════════════════════════

        devShells = {
          # Shell with all bioinformatics tools available
          default = pkgs.mkShell {
            buildInputs = with pkgs; [
              mmseqs2
              blast
              diamond
            ];

            shellHook = ''
              echo "Bioinformatics Tools Environment"
              echo "================================="
              echo "Available tools:"
              echo "  - mmseqs2: ${pkgs.mmseqs2.version}"
              echo "  - blast: ${pkgs.blast.version}"
              echo "  - diamond: ${pkgs.diamond.version}"
              echo ""
              echo "Example datasets available:"
              echo "  nix build .#example-mmseqs"
              echo "  nix build .#example-blast-prot"
              echo "  nix build .#example-diamond"
              echo "  nix build .#example-all-formats"
            '';
          };

          # Shell with specific database loaded
          with-mmseqs = pkgs.mkShell {
            buildInputs = [
              pkgs.mmseqs2
              config.packages.example-mmseqs
            ];

            shellHook = ''
              echo "MMseqs2 database loaded"
              echo "Database path: $CAST_DATASET_SAMPLE_PROTEINS_MMSEQS"
            '';
          };
        };
      };
    };
}
