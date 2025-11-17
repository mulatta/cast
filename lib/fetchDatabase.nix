# Download and register a database
# Downloads from URL, calculates hashes, stores in CAS, and creates dataset
{
  lib,
  pkgs,
  mkDataset,
  ...
}: {
  name,
  url,
  hash ? null,
  extract ? false,
  metadata ? {},
}: let
  # Determine version from metadata or use timestamp
  version = metadata.version or (builtins.substring 0 10 (builtins.currentTime or "unknown"));

  # Download and process the database
  fetchedData = pkgs.stdenv.mkDerivation {
    pname = "cast-fetch-${name}";
    inherit version;

    nativeBuildInputs = with pkgs;
      [
        curl
        b3sum
        jq
        coreutils
      ]
      ++ lib.optionals extract [
        gnutar
        gzip
        bzip2
        xz
        unzip
      ];

    # No source - we're downloading
    dontUnpack = true;

    # Pass parameters to build
    inherit url extract;
    downloadDate = builtins.currentTime or "1970-01-01T00:00:00Z";
    expectedHash =
      if hash != null
      then hash
      else "";

    buildPhase = ''
      runHook preBuild

      # Download with curl
      echo "Downloading from $url..."
      curl -L -f -o download "$url" \
        --write-out '%{http_code}|%{time_total}|%{size_download}' \
        > curl-stats.txt

      # Get Last-Modified header if available
      server_mtime=$(curl -I -L -s "$url" | grep -i '^Last-Modified:' | cut -d' ' -f2- | tr -d '\r' || echo "unknown")
      echo "$server_mtime" > server-mtime.txt

      # Calculate BLAKE3 hash of downloaded file
      archive_hash=$(b3sum download | cut -d' ' -f1)
      echo "Archive hash: blake3:$archive_hash"

      # Verify hash if provided
      if [ -n "$expectedHash" ]; then
        expected_stripped=$(echo "$expectedHash" | sed 's/^blake3://')
        if [ "$archive_hash" != "$expected_stripped" ]; then
          echo "Hash mismatch! Expected: $expectedHash, Got: blake3:$archive_hash"
          exit 1
        fi
      fi

      echo "blake3:$archive_hash" > archive-hash.txt

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out

      # Extract or copy based on extract flag
      if [ "$extract" = "1" ]; then
        echo "Extracting archive..."
        mkdir -p $out/extracted

        # Detect archive type and extract
        case "$url" in
          *.tar.gz|*.tgz)
            tar -xzf download -C $out/extracted
            ;;
          *.tar.bz2|*.tbz2)
            tar -xjf download -C $out/extracted
            ;;
          *.tar.xz|*.txz)
            tar -xJf download -C $out/extracted
            ;;
          *.tar)
            tar -xf download -C $out/extracted
            ;;
          *.zip)
            unzip -q download -d $out/extracted
            ;;
          *.gz)
            gunzip -c download > $out/extracted/$(basename "$url" .gz)
            ;;
          *)
            echo "Warning: Unknown archive format, copying as-is"
            cp download $out/extracted/$(basename "$url")
            ;;
        esac

        # Generate file inventory with hashes
        echo "Generating file inventory..."
        find $out/extracted -type f | while read -r file; do
          relpath=$(realpath --relative-to=$out/extracted "$file")
          size=$(stat -c%s "$file")
          filehash=$(b3sum "$file" | cut -d' ' -f1)
          executable=$(if [ -x "$file" ]; then echo "true"; else echo "false"; fi)

          jq -n \
            --arg path "$relpath" \
            --arg hash "blake3:$filehash" \
            --arg size "$size" \
            --argjson exec "$executable" \
            '{path: $path, hash: $hash, size: ($size | tonumber), executable: $exec}'
        done | jq -s '.' > $out/contents.json

      else
        echo "Storing archive without extraction..."
        mkdir -p $out/extracted
        cp download $out/extracted/$(basename "$url")

        # Single file inventory
        size=$(stat -c%s download)
        archive_hash=$(cat archive-hash.txt | sed 's/^blake3://')
        filename=$(basename "$url")

        jq -n \
          --arg path "$filename" \
          --arg hash "blake3:$archive_hash" \
          --arg size "$size" \
          '{path: $path, hash: $hash, size: ($size | tonumber), executable: false}' \
          | jq -s '.' > $out/contents.json
      fi

      # Generate manifest
      archive_hash=$(cat archive-hash.txt)
      server_mtime=$(cat server-mtime.txt)

      jq -n \
        --arg schema "1.0" \
        --arg name "${name}" \
        --arg version "${version}" \
        --arg desc "${metadata.description or "Downloaded from ${url}"}" \
        --arg url "$url" \
        --arg download_date "$downloadDate" \
        --arg server_mtime "$server_mtime" \
        --arg archive_hash "$archive_hash" \
        --slurpfile contents $out/contents.json \
        '{
          schema_version: $schema,
          dataset: {
            name: $name,
            version: $version,
            description: $desc
          },
          source: {
            url: $url,
            download_date: $download_date,
            server_mtime: $server_mtime,
            archive_hash: $archive_hash
          },
          contents: $contents[0],
          transformations: []
        }' > $out/manifest.json

      runHook postInstall
    '';

    passthru = {
      inherit url hash extract;
      manifestPath = "$out/manifest.json";
    };
  };
in
  # Return a dataset derivation using mkDataset
  mkDataset {
    inherit name version;
    manifest = "${fetchedData}/manifest.json";
    # Inherit storePath from caller if needed
  }
