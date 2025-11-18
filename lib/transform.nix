# Transform dataset
# Executes transformation on source dataset and generates new manifest with provenance
{
  lib,
  pkgs,
  ...
}: {
  name,
  src,
  builder,
  params ? {},
}: let
  # Read source manifest if src is a CAST dataset
  sourceManifest =
    src.manifestData or (
      if src ? manifest && (builtins.isPath src.manifest || builtins.isString src.manifest)
      then builtins.fromJSON (builtins.readFile src.manifest)
      else null
    );

  # Extract source hash for provenance tracking
  sourceHash =
    if sourceManifest != null
    then
      if sourceManifest ? source && sourceManifest.source ? archive_hash
      then sourceManifest.source.archive_hash
      else "blake3:unknown"
    else "blake3:unknown";

  # Determine transformation version from source
  version =
    if sourceManifest != null
    then sourceManifest.dataset.version
    else "transformed";

  # Execute the transformation
  transformedData = pkgs.stdenv.mkDerivation {
    pname = "cast-transform-${name}";
    inherit version;

    inherit src;

    nativeBuildInputs = with pkgs; [
      b3sum
      jq
      coreutils
      findutils
    ];

    # Environment variables for transformation
    CAST_TRANSFORM_NAME = name;
    CAST_TRANSFORM_PARAMS = builtins.toJSON params;

    # Store builder script for use in buildPhase
    builderScript =
      if builtins.isPath builder || builtins.isString builder
      then builder
      else pkgs.writeScript "transform-${name}.sh" builder;

    phases = ["unpackPhase" "buildPhase" "installPhase"];

    # Unpack source if it's an archive
    unpackPhase = ''
      runHook preUnpack

      # If src is a CAST dataset with data/, use it directly
      if [ -d "$src/data" ]; then
        echo "Using CAST dataset from $src/data"
        export SOURCE_DATA="$src/data"
        # Don't change directory for CAST datasets
      elif [ -f "$src" ]; then
        echo "Unpacking source archive"
        unpackFile "$src"
        cd "$(find . -mindepth 1 -maxdepth 1 -type d | head -n1)" || true
        export SOURCE_DATA="$PWD"
      else
        echo "Using source directory: $src"
        export SOURCE_DATA="$src"
      fi

      runHook postUnpack
    '';

    buildPhase = ''
      runHook preBuild

      # Set CAST_OUTPUT for builder to use
      export CAST_OUTPUT="$out/data"

      echo "Running transformation: ${name}"
      echo "CAST_OUTPUT: $CAST_OUTPUT"
      echo "SOURCE_DATA: $SOURCE_DATA"

      # Create output directory
      mkdir -p "$CAST_OUTPUT"

      # Execute the transformation builder
      # Builder should write outputs to $CAST_OUTPUT
      if [ -f "$builderScript" ]; then
        chmod +x "$builderScript"
        "$builderScript"
      else
        eval "$builderScript"
      fi

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      # Verify CAST_OUTPUT has files
      if [ ! -d "$CAST_OUTPUT" ] || [ -z "$(ls -A "$CAST_OUTPUT")" ]; then
        echo "Error: Transformation produced no output in $CAST_OUTPUT"
        exit 1
      fi

      # Generate file inventory with BLAKE3 hashes
      echo "Generating file inventory..."
      find "$CAST_OUTPUT" \( -type f -o -type l \) | while read -r file; do
        relpath=$(realpath --relative-to="$CAST_OUTPUT" "$file")
        size=$(stat -c%s "$file")
        filehash=$(b3sum "$file" | cut -d' ' -f1)

        # Check if file is executable
        if [ -x "$file" ]; then
          exec_flag="true"
        else
          exec_flag="false"
        fi

        jq -n \
          --arg path "$relpath" \
          --arg hash "blake3:$filehash" \
          --arg size "$size" \
          --arg exec "$exec_flag" \
          '{path: $path, hash: $hash, size: ($size | tonumber), executable: ($exec == "true")}'
      done | jq -s '.' > "$out/contents.json"

      # Generate transformation provenance
      jq -n \
        --arg type "${name}" \
        --arg from "${sourceHash}" \
        --argjson params "$CAST_TRANSFORM_PARAMS" \
        '{type: $type, from: $from, params: $params}' \
        > "$out/transformation.json"

      # Build transformations array (preserve existing + add new)
      # Read source manifest at build time to support chained transformations
      if [ -f "$src/manifest.json" ]; then
        echo "Preserving transformation chain from source manifest"
        # Source has manifest, extend its transformations
        # Append new transformation to the array
        jq --slurpfile new_transform "$out/transformation.json" \
           '.transformations += $new_transform' \
           < "$src/manifest.json" | \
        jq '.transformations' > "$out/transformations.json"
      else
        echo "Starting new transformation chain"
        # No source manifest, start fresh
        jq -s '.' "$out/transformation.json" > "$out/transformations.json"
      fi

      # Generate complete manifest
      jq -n \
        --arg schema "1.0" \
        --arg name "${name}" \
        --arg version "${version}" \
        --arg desc "Transformed dataset: ${name}" \
        --slurpfile contents "$out/contents.json" \
        --slurpfile transformations "$out/transformations.json" \
        '{
          schema_version: $schema,
          dataset: {
            name: $name,
            version: $version,
            description: $desc
          },
          source: {
            url: "transformed://${name}",
            download_date: "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
            server_mtime: "unknown",
            archive_hash: "blake3:transformed"
          },
          contents: $contents[0],
          transformations: $transformations[0]
        }' > "$out/manifest.json"

      echo "Transformation complete: $(jq '.contents | length' "$out/contents.json") files generated"

      runHook postInstall
    '';

    passthru = {
      inherit name src params;
      transformationType = name;
      inherit sourceHash;
      manifestPath = "$out/manifest.json";
      manifest = "$out/manifest.json";
      manifestData = sourceManifest;
    };
  };
in
  # Return the transformed dataset directly
  transformedData
