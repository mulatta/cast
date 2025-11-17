# Create symlink subset
# This will be fully implemented in task 3.5
{
  lib,
  pkgs,
  ...
}: {
  name,
  paths,
}:
# Stub implementation - returns a placeholder derivation
pkgs.stdenv.mkDerivation {
  pname = "cast-symlink-subset-${name}";
  version = "stub";

  phases = ["installPhase"];

  installPhase = ''
    mkdir -p $out
    echo "Stub: Symlink subset ${name}" > $out/README
    echo "Paths: ${toString (lib.attrNames paths)}" >> $out/README
    echo "This is a placeholder. Full implementation in task 3.5." >> $out/README
  '';
}
