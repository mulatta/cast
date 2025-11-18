# Final Design: flake-parts Options System

**Version**: 3.0 (Final)
**Date**: 2025-11-18
**Status**: ✅ Ready for Implementation

## Key Discovery from flake-parts Skill

### Module Options System (lines 286-296)

flake-parts provides a **proper module system** with options:

```nix
options.perSystem = flake-parts-lib.mkPerSystemOption {
  options.myFeature = lib.mkOption {
    type = lib.types.package;
    description = "My custom feature";
  };
};
```

### Available Arguments

**Top-level** (line 64-72):
- `config` - Top-level configuration (can access custom options!)
- `options` - Top-level options
- `withSystem` - Access per-system config

**perSystem** (line 74-82):
- `config` - Current perSystem configuration
- `self'` - System-specific outputs from self
- `inputs'` - System-specific outputs from all inputs

## Why Let-binding is Insufficient

### Problem with Let-binding

```nix
# ❌ Let-binding limitations
flake-parts.lib.mkFlake { inherit inputs; }
let
  castConfig = { storePath = "/data/cast"; };
in {
  perSystem = { ... }:
    # castConfig is hardcoded, no override mechanism
    let castLib = cast.lib.configure castConfig;
```

**Issues**:
1. 🔴 **No parameterization**: Can't override in consuming flakes
2. 🔴 **No type checking**: No validation of config values
3. 🔴 **No defaults**: Must specify everything
4. 🔴 **No merging**: Can't compose multiple configs
5. 🔴 **No documentation**: Options are implicit

### Solution: flake-parts Options

```nix
# ✅ Proper module options
{
  options = {
    cast = lib.mkOption {
      type = lib.types.submodule {
        options = {
          storePath = lib.mkOption {
            type = lib.types.path;
            description = "CAST storage root directory";
          };
          preferredDownloader = lib.mkOption {
            type = lib.types.enum [ "aria2c" "curl" "wget" "auto" ];
            default = "auto";
            description = "Preferred download tool";
          };
        };
      };
    };
  };

  config = {
    perSystem = { config, ... }:
      let castLib = cast.lib.configure config.cast;
      in { ... };
  };
}
```

**Benefits**:
1. ✅ **Type checking**: Validates storePath is a path
2. ✅ **Defaults**: `preferredDownloader = "auto"`
3. ✅ **Documentation**: Descriptions built-in
4. ✅ **Merging**: Multiple modules can set options
5. ✅ **Override**: Downstream can override via module system

## Recommended Architecture

### Database Flake Pattern

```nix
# ============================================
# Database registry flake (CAST consumer)
# ============================================
{
  description = "Lab database registry";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    cast.url = "github:user/cast";
  };

  outputs = inputs @ { flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" ];

      # ════════════════════════════════════════
      # CAST Configuration via Options
      # ════════════════════════════════════════
      options = {
        cast = inputs.nixpkgs.lib.mkOption {
          type = inputs.nixpkgs.lib.types.submodule {
            options = {
              storePath = inputs.nixpkgs.lib.mkOption {
                type = inputs.nixpkgs.lib.types.path;
                description = "CAST storage root directory";
                example = "/data/lab-databases";
              };

              preferredDownloader = inputs.nixpkgs.lib.mkOption {
                type = inputs.nixpkgs.lib.types.enum [ "aria2c" "curl" "wget" "auto" ];
                default = "auto";
                description = "Preferred download tool for fetchDatabase";
              };
            };
          };
          description = "CAST configuration for this database registry";
        };
      };

      # ════════════════════════════════════════
      # Set Configuration Values
      # ════════════════════════════════════════
      config = {
        cast = {
          storePath = "/data/lab-databases";
          preferredDownloader = "aria2c";
        };

        # ════════════════════════════════════════
        # Use Configuration in perSystem
        # ════════════════════════════════════════
        perSystem = { config, pkgs, system, ... }:
        let
          # ✅ Access config.cast from module system
          castLib = inputs.cast.lib.configure config.cast;
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

            # Use builders
            ncbi-mmseqs = castLib.builders.toMMseqs config.packages.ncbi-nr;
          };
        };

        # ════════════════════════════════════════
        # Export for NixOS Module
        # ════════════════════════════════════════
        flake.nixosModules.default = { config, lib, pkgs, ... }:
          let
            cfg = config.services.databases;
          in {
            options.services.databases = {
              enable = lib.mkEnableOption "lab databases";

              # ✅ Reuse cast options schema
              cast = inputs.nixpkgs.lib.mkOption {
                type = inputs.nixpkgs.lib.types.submodule {
                  options = {
                    storePath = lib.mkOption {
                      type = lib.types.path;
                      default = "/var/lib/cast";
                      description = "CAST storage path";
                    };
                  };
                };
              };
            };

            config = lib.mkIf cfg.enable {
              # Use overridden config
              environment.systemPackages =
                let castLib = inputs.cast.lib.configure cfg.cast;
                in lib.attrValues {
                  ncbi = castLib.mkDataset {
                    name = "ncbi-nr";
                    manifest = ./manifests/ncbi-nr.json;
                  };
                };
            };
          };
      };
    };
}
```

### Consumer Override Pattern

```nix
# ============================================
# Consuming flake with override
# ============================================
{
  inputs.databases.url = "github:lab/databases";

  outputs = { databases, nixpkgs, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      # ✅ Override databases config via module system
      imports = [
        databases.flakeModules.override or {}
      ];

      config.databases.cast.storePath = "/scratch/my-cast";

      perSystem = { ... }: {
        # Uses overridden config automatically
      };
    };
}
```

## CAST Library Design (Unchanged)

```nix
# ============================================
# cast/lib/default.nix
# ============================================
{ lib, pkgs }:
{
  # Simple config-accepting functions
  mkDataset = config: args:
    import ./mkDataset.nix { inherit lib pkgs config; } args;

  transform = config: args:
    import ./transform.nix { inherit lib pkgs config; } args;

  builders = config:
    import ./builders.nix { inherit lib pkgs; } config;

  # Convenience wrapper
  configure = config: {
    inherit config;
    mkDataset = mkDataset config;
    transform = transform config;
    builders = builders config;
  };
}
```

**Note**: CAST lib stays simple - it just accepts a config object.

## Comparison: Let-binding vs Options

| Feature | Let-binding | flake-parts Options |
|---------|-------------|---------------------|
| **Parameterization** | ❌ Hardcoded | ✅ Module system |
| **Type checking** | ❌ None | ✅ Full validation |
| **Default values** | ❌ Manual | ✅ Built-in |
| **Documentation** | ❌ Implicit | ✅ Descriptions |
| **Override** | ❌ Must edit | ✅ Module merge |
| **Composition** | ❌ Difficult | ✅ Natural |
| **Discoverability** | ❌ Hidden | ✅ `nix flake show` |
| **Complexity** | ✅ Simple | ⚠️ More code |

**Verdict**: Options system is significantly better for library-like flakes.

## Implementation Checklist

### Phase 2A: Database Flake Template

- [ ] Create options schema for CAST config
  - [ ] `cast.storePath` (path, required)
  - [ ] `cast.preferredDownloader` (enum, default "auto")

- [ ] Set default config in `config.cast`

- [ ] Use `config.cast` in perSystem
  - [ ] `castLib = cast.lib.configure config.cast`

- [ ] Export nixosModule with same options

### Phase 2B: CAST Library (No changes)

- [ ] Keep current `configure` function
- [ ] Accept plain config object
- [ ] No awareness of flake-parts

### Phase 2C: Examples

- [ ] `examples/database-registry/` with options
- [ ] Show override pattern
- [ ] NixOS integration example

### Phase 2D: Documentation

- [ ] Document options schema
- [ ] Show override examples
- [ ] Best practices guide

## Advanced: Reusable Options Module

For better reusability, CAST could export an options module:

```nix
# cast/flake.nix
{
  flake.flakeModules.cast-options = { lib, ... }: {
    options.cast = lib.mkOption {
      type = lib.types.submodule {
        options = {
          storePath = lib.mkOption {
            type = lib.types.path;
            description = "CAST storage root";
          };
          # ... other options
        };
      };
    };
  };
}

# Database flake
{
  imports = [ inputs.cast.flakeModules.cast-options ];

  config.cast.storePath = "/data/cast";
}
```

**Status**: Future enhancement (Phase 3)

## Benefits Summary

### For Database Maintainers

- ✅ **Type safety**: Invalid configs caught early
- ✅ **Documentation**: Options are self-documenting
- ✅ **Defaults**: Don't specify everything
- ✅ **Validation**: Enum for downloader, path validation

### For Consumers

- ✅ **Override**: Clean module system override
- ✅ **Discovery**: `nix flake show` lists options
- ✅ **Composition**: Multiple overrides merge
- ✅ **Type hints**: Editor support (with nix LSP)

### For NixOS Integration

- ✅ **Standard pattern**: Same as NixOS modules
- ✅ **Reusable schema**: Same options everywhere
- ✅ **Natural integration**: No impedance mismatch

## Migration from Earlier Design

**Before** (let-binding):
```nix
let castConfig = { storePath = "/data/cast"; };
```

**After** (options):
```nix
options.cast = lib.mkOption { ... };
config.cast = { storePath = "/data/cast"; };
```

**Effort**: Minimal - just wrap config in options/config structure

## Complexity Assessment

| Aspect | Before (let) | After (options) | Change |
|--------|--------------|-----------------|--------|
| **LOC in flake** | ~5 lines | ~25 lines | +20 |
| **Type safety** | None | Full | ++ |
| **Override** | Hard | Easy | ++ |
| **Documentation** | None | Built-in | ++ |
| **Learning curve** | Low | Medium | + |

**Assessment**: Higher upfront complexity, but much better long-term.

## Final Recommendation

✅ **Use flake-parts options system**

**Reasons**:
1. Proper parameterization (overcomes let-binding limitation)
2. Type checking and validation
3. Natural override mechanism
4. Self-documenting
5. Standard NixOS pattern
6. Better for library-like flakes

**Cost**: ~20 more lines of boilerplate
**Benefit**: Complete, production-ready configuration system

---

**Next Steps**: Implement database-registry example with options

**Status**: Design finalized, ready for implementation
