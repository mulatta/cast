# Implementation Plan: Pure Configuration with flake-parts

## Executive Summary

**Objective**: Implement pure, reproducible CAST configuration using flake-parts patterns
**Status**: Design Complete - Ready for Implementation
**Complexity Assessment**: ✅ Low - Leverages existing flake-parts infrastructure

## Key Insight: flake-parts Solves Self-reference

CAST already uses flake-parts. We can leverage its module system to eliminate all identified issues:

```nix
# Database flake using flake-parts
{
  outputs = inputs @ { flake-parts, cast, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];

      # ✅ Flake-level config (non-canonical output)
      flake.cast = {
        storePath = "/data/cast-store";
        preferredDownloader = "aria2c";
      };

      # ✅ perSystem can access flake.cast via getFlake
      perSystem = { config, lib, pkgs, getFlake, ... }:
      let
        # Access flake-level config
        castConfig = (getFlake "self").cast;
        castLib = cast.lib.configure castConfig;
      in {
        packages = {
          ncbi = castLib.mkDataset {
            name = "ncbi-nr";
            manifest = ./ncbi.json;
          };
        };
      };

      # ✅ Export factory for overrides
      flake.mkPackages = config: system:
        let pkgs = import inputs.nixpkgs { inherit system; };
            castLib = cast.lib.configure config;
        in {
          ncbi = castLib.mkDataset {
            name = "ncbi-nr";
            manifest = ./ncbi.json;
          };
        };
    };
}
```

**Result**:
- ✅ No self-reference issues (flake-parts handles it)
- ✅ Pure configuration (no env vars)
- ✅ Override mechanism built-in
- ✅ No additional complexity

## Technical Design

### 1. CAST Library Structure

```nix
# ============================================
# cast/lib/default.nix
# ============================================
{ lib, pkgs }:
rec {
  # Core: Config-accepting functions
  mkDataset = config: args:
    import ./mkDataset.nix { inherit lib pkgs config; } args;

  transform = config: args:
    import ./transform.nix { inherit lib pkgs config; } args;

  builders = config:
    import ./builders.nix { inherit lib pkgs; inherit (self) transform; } config;

  # Convenience: Configure once, use many
  configure = config: {
    inherit config;
    mkDataset = mkDataset config;
    transform = transform config;
    builders = builders config;
  };

  # Helper: Extract config from flake
  withFlake = flake:
    configure (flake.cast or (throw ''
      No CAST configuration found in flake.
      Add to your flake.nix:
        flake.cast = { storePath = "/data/cast"; };
    ''));
}
```

### 2. mkDataset Implementation

```nix
# ============================================
# lib/mkDataset.nix
# ============================================
{ lib, pkgs, config }:
{ name, version, manifest, storePath ? null }:
let
  # Priority: explicit param > config > error
  effectiveStorePath =
    if storePath != null then storePath
    else if config ? storePath && config.storePath != null then config.storePath
    else throw ''
      CAST storePath not configured.

      In your flake.nix:
        flake.cast = { storePath = "/data/cast-store"; };

      Or pass explicit parameter:
        mkDataset { storePath = "/data/cast"; ... }
    '';

  manifestData =
    if builtins.isPath manifest || builtins.isString manifest
    then builtins.fromJSON (builtins.readFile manifest)
    else manifest;

in pkgs.stdenv.mkDerivation {
  pname = "cast-dataset-${name}";
  inherit version;

  dontUnpack = true;
  dontBuild = true;

  manifestJson = builtins.toJSON manifestData;

  installPhase = ''
    mkdir -p $out/data

    # Create symlinks to CAST store
    ${pkgs.jq}/bin/jq -r '.contents[] | "\(.path)\t\(.hash)"' <<< "$manifestJson" | \
    while IFS=$'\t' read -r path hash; do
      dir=$(dirname "$path")
      [ "$dir" != "." ] && mkdir -p "$out/data/$dir"

      # Convert hash to CAS path
      stripped=$(echo "$hash" | sed 's/^blake3://')
      prefix2=$(echo "$stripped" | cut -c1-2)
      prefix4=$(echo "$stripped" | cut -c3-4)
      cas_path="${effectiveStorePath}/store/$prefix2/$prefix4/$stripped"

      ln -s "$cas_path" "$out/data/$path"
    done

    echo "$manifestJson" | ${pkgs.jq}/bin/jq '.' > $out/manifest.json
  '';

  passthru = {
    inherit manifest manifestData;
    castStorePath = effectiveStorePath;
    castConfig = config;
  };
}
```

### 3. Database Flake Pattern (flake-parts)

```nix
# ============================================
# examples/database-registry/flake.nix
# ============================================
{
  description = "Lab database registry with CAST";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    cast.url = "github:user/cast";
  };

  outputs = inputs @ { flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" ];

      # ============================================
      # CAST Configuration (flake-level)
      # ============================================
      flake.cast = {
        storePath = "/data/lab-databases";
        preferredDownloader = "aria2c";
      };

      # ============================================
      # System-specific packages
      # ============================================
      perSystem = { config, lib, pkgs, system, getFlake, ... }:
      let
        # Get flake-level config
        self = getFlake "self";
        castLib = inputs.cast.lib.configure self.cast;
      in {
        packages = {
          ncbi-nr = castLib.mkDataset {
            name = "ncbi-nr";
            version = "2024-01";
            manifest = ./manifests/ncbi-nr.json;
          };

          uniprot = castLib.mkDataset {
            name = "uniprot";
            version = "2024.01";
            manifest = ./manifests/uniprot.json;
          };

          # With transformation
          ncbi-mmseqs = castLib.builders.toMMseqs self.packages.${system}.ncbi-nr;
        };
      };

      # ============================================
      # Factory for config override
      # ============================================
      flake.mkPackages = config: system:
        let
          pkgs = import inputs.nixpkgs { inherit system; };
          castLib = inputs.cast.lib.configure config;
        in {
          ncbi-nr = castLib.mkDataset {
            name = "ncbi-nr";
            version = "2024-01";
            manifest = ./manifests/ncbi-nr.json;
          };

          uniprot = castLib.mkDataset {
            name = "uniprot";
            version = "2024.01";
            manifest = ./manifests/uniprot.json;
          };
        };

      # ============================================
      # NixOS Module
      # ============================================
      flake.nixosModules.default = { config, lib, pkgs, ... }:
        let
          cfg = config.services.databases;
          self = getFlake "self";
        in {
          options.services.databases = {
            enable = lib.mkEnableOption "lab databases";

            storePath = lib.mkOption {
              type = lib.types.path;
              default = self.cast.storePath;
              description = "CAST storage path";
            };
          };

          config = lib.mkIf cfg.enable {
            environment.systemPackages =
              lib.attrValues (self.mkPackages {
                storePath = cfg.storePath;
              } pkgs.system);
          };
        };
    };
}
```

### 4. Consumer Usage Patterns

```nix
# ============================================
# Pattern 1: Use default config
# ============================================
{
  inputs.databases.url = "github:lab/databases";

  outputs = { databases, ... }: {
    packages.x86_64-linux.analysis = pkgs.mkShell {
      buildInputs = [
        databases.packages.x86_64-linux.ncbi-nr
      ];
    };
  };
}

# ============================================
# Pattern 2: Override config
# ============================================
{
  inputs.databases.url = "github:lab/databases";

  outputs = { databases, nixpkgs, ... }: {
    packages.x86_64-linux.analysis =
      let pkgs = nixpkgs.legacyPackages.x86_64-linux;
      in pkgs.mkShell {
        buildInputs = lib.attrValues (
          databases.mkPackages {
            storePath = "/scratch/my-cast";
          } "x86_64-linux"
        );
      };
  };
}

# ============================================
# Pattern 3: NixOS integration
# ============================================
{
  inputs.databases.url = "github:lab/databases";

  outputs = { databases, nixpkgs, ... }: {
    nixosConfigurations.server = nixpkgs.lib.nixosSystem {
      modules = [
        databases.nixosModules.default
        {
          services.databases = {
            enable = true;
            storePath = "/mnt/nvme/cast-store";
          };
        }
      ];
    };
  };
}
```

## Complexity Assessment

### Added Complexity: ✅ MINIMAL

| Component | Before | After | Change |
|-----------|--------|-------|--------|
| **lib/default.nix** | Basic exports | +configure, +withFlake | +10 lines |
| **lib/mkDataset.nix** | Uses env var | Uses config param | Same logic |
| **User flake** | Set CAST_STORE | Add flake.cast = {...} | Cleaner |
| **Total LOC** | ~200 | ~220 | +10% |

**Assessment**: Very low complexity increase for major benefits.

### Benefits Gained: ✅ SIGNIFICANT

- ✅ Complete purity (no env vars)
- ✅ Version controlled config
- ✅ Reproducible builds
- ✅ Easy cloning/mirroring
- ✅ Natural NixOS integration
- ✅ No circular reference issues
- ✅ Leverages existing flake-parts

## Remaining Issues: ✅ NONE IDENTIFIED

### Issue 1: Self-reference
**Status**: ✅ Solved by flake-parts
- `getFlake "self"` provides access to flake outputs
- No circular dependency issues

### Issue 2: Evaluation Order
**Status**: ✅ Not a problem
- Lazy evaluation handles it
- flake-parts manages evaluation order

### Issue 3: Override Mechanism
**Status**: ✅ Solved with mkPackages
- Factory function accepts custom config
- Composable and flexible

### Issue 4: Multi-flake Scenario
**Status**: ✅ No problem
- Each flake independent
- Can share via override if needed

### Issue 5: NixOS Integration
**Status**: ✅ Natural pattern
- Module options system
- Easy override mechanism

## Implementation Checklist

### Phase 2A: Core Library (Priority 1)

- [ ] Update `lib/default.nix`
  - [ ] Add `configure` function
  - [ ] Add `withFlake` helper
  - [ ] Update all exports to accept config

- [ ] Update `lib/mkDataset.nix`
  - [ ] Accept `config` parameter
  - [ ] Remove hardcoded `~/.cache/cast`
  - [ ] Add clear error messages
  - [ ] Keep explicit parameter override

- [ ] Update `lib/transform.nix`
  - [ ] Accept `config` parameter
  - [ ] Use config for defaults

- [ ] Add `lib/builders.nix`
  - [ ] `toMMseqs`
  - [ ] `toBLAST`
  - [ ] `toDiamond`
  - [ ] All accept config

### Phase 2B: Examples & Documentation (Priority 2)

- [ ] Create `examples/database-registry/`
  - [ ] Full flake-parts example
  - [ ] Multiple databases
  - [ ] Show mkPackages pattern
  - [ ] NixOS module

- [ ] Update `README.md`
  - [ ] Pure configuration guide
  - [ ] flake-parts patterns
  - [ ] Override examples
  - [ ] NixOS integration

- [ ] Update `CLAUDE.md`
  - [ ] Document new architecture
  - [ ] Configuration philosophy
  - [ ] Best practices

### Phase 2C: cast-cli Package (Priority 3)

- [ ] Add gitignore.nix input
- [ ] Export cast-cli package
- [ ] Use gitignoreSource for src

### Phase 2D: fetchDatabase Redesign (Future)

- [ ] Design cast-cli fetch command
- [ ] Implement downloader selection
- [ ] Remove /nix/store usage
- [ ] Use CAST store directly

## Testing Strategy

### Unit Tests
- [ ] Config resolution priority
- [ ] Error messages for missing config
- [ ] Override mechanism

### Integration Tests
- [ ] Database flake with flake-parts
- [ ] mkPackages override
- [ ] NixOS module

### Example Projects
- [ ] Simple database registry
- [ ] Multi-database consumer
- [ ] NixOS configuration

## Migration Path

### For Existing Users (if any)

**Before** (impure):
```bash
CAST_STORE=/data/cast nix build --impure .#ncbi
```

**After** (pure):
```nix
flake.cast = { storePath = "/data/cast"; };
# nix build .#ncbi (no --impure needed)
```

**Backward compatibility**: Not required (pre-release)

## Success Criteria

- ✅ Zero environment variables required
- ✅ All config in flake.nix
- ✅ Works with `nix build --pure`
- ✅ Easy override mechanism
- ✅ NixOS integration works
- ✅ Examples build successfully
- ✅ Documentation clear and complete

## Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| flake-parts API change | Low | Medium | Use stable version |
| User confusion | Medium | Low | Good docs & examples |
| Performance regression | Very Low | Low | Same code paths |
| Breaking changes | N/A | N/A | Pre-release |

**Overall Risk**: ✅ Very Low

## Timeline Estimate

- **Phase 2A (Core)**: 2-3 hours
- **Phase 2B (Docs)**: 1-2 hours
- **Phase 2C (cast-cli)**: 1 hour
- **Total**: 4-6 hours

## Conclusion

**Recommendation**: ✅ **PROCEED WITH IMPLEMENTATION**

- Design is sound
- Complexity is minimal
- All issues resolved
- Benefits are significant
- No blocking problems identified

The flake-parts integration makes this solution elegant and simple. The non-canonical `flake.cast` output is the perfect pattern for this use case.

---

**Document Version**: 1.0
**Last Updated**: 2025-11-18
**Status**: Ready for Implementation
**Approved**: Pending review
