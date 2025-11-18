# Create symlink subset
# Creates a selective symlink farm from multiple datasets or paths
{
  lib,
  pkgs,
  ...
}: {
  name,
  paths,
  version ? "1.0",
}: let
  # Normalize paths to a consistent format
  # paths can be:
  # - List of datasets (with .data attribute)
  # - List of { name, path } attrsets
  # - List of plain paths
  normalizedPaths =
    if builtins.isList paths
    then
      map (item:
        if builtins.isAttrs item && item ? name && item ? path
        then item
        else if builtins.isAttrs item && item ? data
        then {
          name = item.pname or item.name or "dataset";
          path = "${item}/data";
        }
        else {
          name = baseNameOf (toString item);
          path = toString item;
        })
      paths
    else throw "paths must be a list";
in
  pkgs.stdenv.mkDerivation {
    pname = "cast-symlink-subset-${name}";
    inherit version;

    dontUnpack = true;
    dontBuild = true;

    nativeBuildInputs = with pkgs; [
      b3sum
      jq
      coreutils
      findutils
    ];

    # Pass path information to build phase
    pathsJson = builtins.toJSON normalizedPaths;

    installPhase = ''
      runHook preInstall

      mkdir -p $out/data

      # Create symlinks for each path
      echo "$pathsJson" | ${pkgs.jq}/bin/jq -r '.[] | "\(.name)\t\(.path)"' | while IFS=$'\t' read -r item_name item_path; do
        echo "Processing $item_name from $item_path"

        if [ -d "$item_path" ]; then
          # Create subdirectory for this item
          mkdir -p "$out/data/$item_name"

          # Create symlinks for all files in the source
          find "$item_path" -type f -o -type l | while read -r file; do
            relpath=$(realpath --relative-to="$item_path" "$file" 2>/dev/null || echo "$(basename "$file")")
            target_dir=$(dirname "$out/data/$item_name/$relpath")

            # Create parent directories
            mkdir -p "$target_dir"

            # Create symlink
            ln -sf "$file" "$out/data/$item_name/$relpath"
          done
        else
          echo "Warning: Path not found or not a directory: $item_path"
        fi
      done

      # Generate file inventory
      echo "Generating file inventory..."
      find "$out/data" -type l | while read -r link; do
        relpath=$(realpath --relative-to="$out/data" "$link")
        target=$(readlink "$link")

        # Calculate hash of target (if it exists and is a regular file)
        if [ -f "$target" ]; then
          size=$(stat -c%s "$target")
          filehash=$(b3sum "$target" | cut -d' ' -f1)
          executable=$(if [ -x "$target" ]; then echo "true"; else echo "false"; fi)

          jq -n \
            --arg path "$relpath" \
            --arg hash "blake3:$filehash" \
            --arg size "$size" \
            --argjson exec "$executable" \
            '{path: $path, hash: $hash, size: ($size | tonumber), executable: $exec}'
        fi
      done | jq -s '.' > "$out/contents.json"

      # Generate manifest
      jq -n \
        --arg schema "1.0" \
        --arg name "${name}" \
        --arg version "${version}" \
        --arg desc "Symlink subset: ${name}" \
        --slurpfile contents "$out/contents.json" \
        '{
          schema_version: $schema,
          dataset: {
            name: $name,
            version: $version,
            description: $desc
          },
          source: {
            url: "subset://${name}",
            download_date: "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
            server_mtime: "unknown",
            archive_hash: "blake3:subset"
          },
          contents: $contents[0],
          transformations: []
        }' > "$out/manifest.json"

      echo "Symlink subset created: $(jq '.contents | length' "$out/contents.json") files"

      runHook postInstall
    '';

    passthru = {
      inherit name paths version;
      manifestPath = "$out/manifest.json";
      inherit normalizedPaths;
    };

    meta = with lib; {
      description = "CAST symlink subset: ${name}";
      platforms = platforms.all;
    };
  }
