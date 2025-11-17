# Create a dataset derivation from manifest
# This will be fully implemented in task 8
{
  lib,
  pkgs,
  ...
}: {
  name,
  version,
  manifest,
  storePath ? null,
}:
# Stub implementation - returns a placeholder derivation
pkgs.stdenv.mkDerivation {
  pname = "cast-dataset-${name}";
  inherit version;

  phases = ["installPhase"];

  installPhase = ''
    mkdir -p $out
    echo "Stub: Dataset ${name} v${version}" > $out/README
    echo "This is a placeholder. Full implementation in task 8." >> $out/README
  '';

  passthru = {
    inherit manifest storePath;
    castDatasetName = lib.toUpper (lib.replaceStrings ["-"] ["_"] name);
  };
}
