# Common transformation builders for bioinformatics databases
#
# These builders provide convenient wrappers for common database format conversions.
# Each builder is a function that takes a configured CAST library and returns
# a transformation function.
{
  lib,
  pkgs,
  ...
}: rec {
  # ════════════════════════════════════════════════════════════════
  # MMseqs2 Transformation
  # ════════════════════════════════════════════════════════════════

  # Convert FASTA to MMseqs2 database format
  #
  # MMseqs2 (Many-against-Many sequence searching) is a software suite
  # for fast and sensitive protein sequence searching and clustering.
  #
  # Example:
  #   toMMseqs castLib {
  #     name = "ncbi-nr-mmseqs";
  #     src = ncbiNrFasta;
  #     fastaFile = "nr.fasta";
  #   }
  #
  # Parameters:
  #   - name: Name of the output database
  #   - src: Source dataset containing FASTA file(s)
  #   - fastaFile: Name of the FASTA file to convert (optional, auto-detected if only one .fasta/.fa file)
  #   - createIndex: Whether to create index (default: true)
  #   - indexParams: Additional parameters for createindex (default: "")
  #
  # Returns: Dataset derivation with MMseqs2 database
  toMMseqs = castLib: {
    name,
    src,
    fastaFile ? null,
    createIndex ? true,
    indexParams ? "",
  }:
    castLib.transform {
      inherit name src;

      builder = ''
        set -euo pipefail

        echo "=== MMseqs2 Database Creation ==="

        # Find FASTA file
        ${
          if fastaFile != null
          then ''
            FASTA_FILE="$SOURCE_DATA/${fastaFile}"
            if [ ! -f "$FASTA_FILE" ]; then
              echo "Error: FASTA file not found: ${fastaFile}"
              echo "Available files in SOURCE_DATA:"
              ls -la "$SOURCE_DATA"
              exit 1
            fi
          ''
          else ''
            # Auto-detect FASTA file
            FASTA_FILES=$(find "$SOURCE_DATA" -type f \( -name "*.fasta" -o -name "*.fa" -o -name "*.faa" \))
            FASTA_COUNT=$(echo "$FASTA_FILES" | wc -l)

            if [ "$FASTA_COUNT" -eq 0 ]; then
              echo "Error: No FASTA files found in SOURCE_DATA"
              echo "Available files:"
              ls -la "$SOURCE_DATA"
              exit 1
            elif [ "$FASTA_COUNT" -gt 1 ]; then
              echo "Error: Multiple FASTA files found. Please specify fastaFile parameter."
              echo "Found files:"
              echo "$FASTA_FILES"
              exit 1
            fi

            FASTA_FILE=$(echo "$FASTA_FILES" | head -1)
            echo "Auto-detected FASTA file: $FASTA_FILE"
          ''
        }

        echo "Input FASTA: $FASTA_FILE"
        echo "Output directory: $CAST_OUTPUT"

        # Create MMseqs2 database
        echo "Creating MMseqs2 database..."
        ${pkgs.mmseqs2}/bin/mmseqs createdb \
          "$FASTA_FILE" \
          "$CAST_OUTPUT/db"

        echo "Database created: $CAST_OUTPUT/db"

        ${
          if createIndex
          then ''
            # Create index for faster searches
            echo "Creating database index..."
            TMP_DIR=$(mktemp -d)
            ${pkgs.mmseqs2}/bin/mmseqs createindex \
              "$CAST_OUTPUT/db" \
              "$TMP_DIR" \
              ${indexParams}

            rm -rf "$TMP_DIR"
            echo "Index created"
          ''
          else ''
            echo "Skipping index creation (createIndex = false)"
          ''
        }

        echo "MMseqs2 database ready: $CAST_OUTPUT/db"
      '';

      params = {
        inherit fastaFile createIndex indexParams;
        tool = "mmseqs2";
        version = pkgs.mmseqs2.version or "unknown";
      };
    };

  # ════════════════════════════════════════════════════════════════
  # BLAST Transformation
  # ════════════════════════════════════════════════════════════════

  # Convert FASTA to BLAST database format
  #
  # BLAST (Basic Local Alignment Search Tool) is the most widely used
  # sequence similarity search tool in bioinformatics.
  #
  # Example:
  #   toBLAST castLib {
  #     name = "ncbi-nr-blast";
  #     src = ncbiNrFasta;
  #     fastaFile = "nr.fasta";
  #     dbType = "prot";
  #   }
  #
  # Parameters:
  #   - name: Name of the output database
  #   - src: Source dataset containing FASTA file(s)
  #   - fastaFile: Name of the FASTA file to convert (optional, auto-detected)
  #   - dbType: Database type - "prot" for protein, "nucl" for nucleotide (default: "prot")
  #   - parseSeqids: Parse sequence IDs (default: true)
  #   - title: Database title (default: name)
  #   - extraArgs: Additional makeblastdb arguments (default: "")
  #
  # Returns: Dataset derivation with BLAST database
  toBLAST = castLib: {
    name,
    src,
    fastaFile ? null,
    dbType ? "prot",
    parseSeqids ? true,
    title ? name,
    extraArgs ? "",
  }:
    castLib.transform {
      inherit name src;

      builder = ''
        set -euo pipefail

        echo "=== BLAST Database Creation ==="

        # Validate dbType
        if [[ "${dbType}" != "prot" && "${dbType}" != "nucl" ]]; then
          echo "Error: dbType must be 'prot' or 'nucl', got: ${dbType}"
          exit 1
        fi

        # Find FASTA file
        ${
          if fastaFile != null
          then ''
            FASTA_FILE="$SOURCE_DATA/${fastaFile}"
            if [ ! -f "$FASTA_FILE" ]; then
              echo "Error: FASTA file not found: ${fastaFile}"
              echo "Available files in SOURCE_DATA:"
              ls -la "$SOURCE_DATA"
              exit 1
            fi
          ''
          else ''
            # Auto-detect FASTA file
            FASTA_FILES=$(find "$SOURCE_DATA" -type f \( -name "*.fasta" -o -name "*.fa" -o -name "*.faa" -o -name "*.fna" \))
            FASTA_COUNT=$(echo "$FASTA_FILES" | wc -l)

            if [ "$FASTA_COUNT" -eq 0 ]; then
              echo "Error: No FASTA files found in SOURCE_DATA"
              exit 1
            elif [ "$FASTA_COUNT" -gt 1 ]; then
              echo "Error: Multiple FASTA files found. Please specify fastaFile parameter."
              echo "Found files:"
              echo "$FASTA_FILES"
              exit 1
            fi

            FASTA_FILE=$(echo "$FASTA_FILES" | head -1)
            echo "Auto-detected FASTA file: $FASTA_FILE"
          ''
        }

        echo "Input FASTA: $FASTA_FILE"
        echo "Database type: ${dbType}"
        echo "Output directory: $CAST_OUTPUT"

        # Create BLAST database
        echo "Creating BLAST database..."
        ${pkgs.blast}/bin/makeblastdb \
          -in "$FASTA_FILE" \
          -dbtype ${dbType} \
          -out "$CAST_OUTPUT/blastdb" \
          -title "${title}" \
          ${lib.optionalString parseSeqids "-parse_seqids"} \
          ${extraArgs}

        echo "BLAST database created: $CAST_OUTPUT/blastdb"

        # List created files
        echo "Created files:"
        ls -lh "$CAST_OUTPUT"
      '';

      params = {
        inherit fastaFile dbType parseSeqids title extraArgs;
        tool = "blast";
        version = pkgs.blast.version or "unknown";
      };
    };

  # ════════════════════════════════════════════════════════════════
  # Diamond Transformation
  # ════════════════════════════════════════════════════════════════

  # Convert FASTA to Diamond database format
  #
  # Diamond is a sequence aligner for protein and translated DNA searches,
  # up to 20,000x faster than BLAST while maintaining similar sensitivity.
  #
  # Example:
  #   toDiamond castLib {
  #     name = "ncbi-nr-diamond";
  #     src = ncbiNrFasta;
  #     fastaFile = "nr.fasta";
  #   }
  #
  # Parameters:
  #   - name: Name of the output database
  #   - src: Source dataset containing FASTA file(s)
  #   - fastaFile: Name of the FASTA file to convert (optional, auto-detected)
  #   - taxonmap: Path to taxonomy mapping file (optional)
  #   - taxonnodes: Path to taxonomy nodes file (optional)
  #   - taxonnames: Path to taxonomy names file (optional)
  #   - extraArgs: Additional makedb arguments (default: "")
  #
  # Returns: Dataset derivation with Diamond database
  toDiamond = castLib: {
    name,
    src,
    fastaFile ? null,
    taxonmap ? null,
    taxonnodes ? null,
    taxonnames ? null,
    extraArgs ? "",
  }:
    castLib.transform {
      inherit name src;

      builder = ''
        set -euo pipefail

        echo "=== Diamond Database Creation ==="

        # Find FASTA file
        ${
          if fastaFile != null
          then ''
            FASTA_FILE="$SOURCE_DATA/${fastaFile}"
            if [ ! -f "$FASTA_FILE" ]; then
              echo "Error: FASTA file not found: ${fastaFile}"
              echo "Available files in SOURCE_DATA:"
              ls -la "$SOURCE_DATA"
              exit 1
            fi
          ''
          else ''
            # Auto-detect FASTA file
            FASTA_FILES=$(find "$SOURCE_DATA" -type f \( -name "*.fasta" -o -name "*.fa" -o -name "*.faa" \))
            FASTA_COUNT=$(echo "$FASTA_FILES" | wc -l)

            if [ "$FASTA_COUNT" -eq 0 ]; then
              echo "Error: No FASTA files found in SOURCE_DATA"
              exit 1
            elif [ "$FASTA_COUNT" -gt 1 ]; then
              echo "Error: Multiple FASTA files found. Please specify fastaFile parameter."
              echo "Found files:"
              echo "$FASTA_FILES"
              exit 1
            fi

            FASTA_FILE=$(echo "$FASTA_FILES" | head -1)
            echo "Auto-detected FASTA file: $FASTA_FILE"
          ''
        }

        echo "Input FASTA: $FASTA_FILE"
        echo "Output directory: $CAST_OUTPUT"

        # Build makedb command
        MAKEDB_CMD="${pkgs.diamond}/bin/diamond makedb --in $FASTA_FILE --db $CAST_OUTPUT/diamond"

        ${lib.optionalString (taxonmap != null) ''
          if [ -f "$SOURCE_DATA/${taxonmap}" ]; then
            MAKEDB_CMD="$MAKEDB_CMD --taxonmap $SOURCE_DATA/${taxonmap}"
            echo "Using taxonmap: ${taxonmap}"
          else
            echo "Warning: taxonmap specified but not found: ${taxonmap}"
          fi
        ''}

        ${lib.optionalString (taxonnodes != null) ''
          if [ -f "$SOURCE_DATA/${taxonnodes}" ]; then
            MAKEDB_CMD="$MAKEDB_CMD --taxonnodes $SOURCE_DATA/${taxonnodes}"
            echo "Using taxonnodes: ${taxonnodes}"
          else
            echo "Warning: taxonnodes specified but not found: ${taxonnodes}"
          fi
        ''}

        ${lib.optionalString (taxonnames != null) ''
          if [ -f "$SOURCE_DATA/${taxonnames}" ]; then
            MAKEDB_CMD="$MAKEDB_CMD --taxonnames $SOURCE_DATA/${taxonnames}"
            echo "Using taxonnames: ${taxonnames}"
          else
            echo "Warning: taxonnames specified but not found: ${taxonnames}"
          fi
        ''}

        ${lib.optionalString (extraArgs != "") ''
          MAKEDB_CMD="$MAKEDB_CMD ${extraArgs}"
        ''}

        # Create Diamond database
        echo "Creating Diamond database..."
        echo "Command: $MAKEDB_CMD"
        eval "$MAKEDB_CMD"

        echo "Diamond database created: $CAST_OUTPUT/diamond.dmnd"

        # Show database info
        ${pkgs.diamond}/bin/diamond dbinfo --db "$CAST_OUTPUT/diamond.dmnd"
      '';

      params = {
        inherit fastaFile taxonmap taxonnodes taxonnames extraArgs;
        tool = "diamond";
        version = pkgs.diamond.version or "unknown";
      };
    };

  # ════════════════════════════════════════════════════════════════
  # Utility: Extract Archive
  # ════════════════════════════════════════════════════════════════

  # Extract common archive formats
  #
  # Supports: .tar.gz, .tgz, .tar.bz2, .tar.xz, .zip
  #
  # Example:
  #   extractArchive castLib {
  #     name = "ncbi-nr-extracted";
  #     src = ncbiNrArchive;
  #     archiveFile = "nr.tar.gz";
  #   }
  extractArchive = castLib: {
    name,
    src,
    archiveFile ? null,
    stripComponents ? 0,
  }:
    castLib.transform {
      inherit name src;

      builder = ''
        set -euo pipefail

        echo "=== Archive Extraction ==="

        # Find archive file
        ${
          if archiveFile != null
          then ''
            ARCHIVE_FILE="$SOURCE_DATA/${archiveFile}"
            if [ ! -f "$ARCHIVE_FILE" ]; then
              echo "Error: Archive file not found: ${archiveFile}"
              exit 1
            fi
          ''
          else ''
            # Auto-detect archive
            ARCHIVE_FILES=$(find "$SOURCE_DATA" -type f \( \
              -name "*.tar.gz" -o -name "*.tgz" -o \
              -name "*.tar.bz2" -o -name "*.tar.xz" -o \
              -name "*.zip" \))
            ARCHIVE_COUNT=$(echo "$ARCHIVE_FILES" | wc -l)

            if [ "$ARCHIVE_COUNT" -eq 0 ]; then
              echo "Error: No archive files found"
              exit 1
            elif [ "$ARCHIVE_COUNT" -gt 1 ]; then
              echo "Error: Multiple archives found. Please specify archiveFile."
              echo "$ARCHIVE_FILES"
              exit 1
            fi

            ARCHIVE_FILE=$(echo "$ARCHIVE_FILES" | head -1)
            echo "Auto-detected archive: $ARCHIVE_FILE"
          ''
        }

        echo "Extracting: $ARCHIVE_FILE"
        echo "Output directory: $CAST_OUTPUT"

        # Determine archive type and extract
        case "$ARCHIVE_FILE" in
          *.tar.gz|*.tgz)
            ${pkgs.gnutar}/bin/tar xzf "$ARCHIVE_FILE" -C "$CAST_OUTPUT" \
              --strip-components=${toString stripComponents}
            ;;
          *.tar.bz2)
            ${pkgs.gnutar}/bin/tar xjf "$ARCHIVE_FILE" -C "$CAST_OUTPUT" \
              --strip-components=${toString stripComponents}
            ;;
          *.tar.xz)
            ${pkgs.gnutar}/bin/tar xJf "$ARCHIVE_FILE" -C "$CAST_OUTPUT" \
              --strip-components=${toString stripComponents}
            ;;
          *.zip)
            ${pkgs.unzip}/bin/unzip -q "$ARCHIVE_FILE" -d "$CAST_OUTPUT"
            ;;
          *)
            echo "Error: Unsupported archive format"
            exit 1
            ;;
        esac

        echo "Extraction complete"
        echo "Extracted files:"
        ls -lh "$CAST_OUTPUT"
      '';

      params = {
        inherit archiveFile stripComponents;
        tool = "extract";
      };
    };
}
