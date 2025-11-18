# CAST Architecture Discussion: Pure Configuration Strategy

## Context

Discussion date: 2025-11-18
Status: Planning Phase
Goal: Design pure, reproducible configuration mechanism for CAST library

## Problem Statement

### Current Issues

1. **Environment Variable Impurity**
   - `CAST_STORE` environment variable breaks reproducibility
   - `nix build --pure` fails with empty env vars
   - Different machines produce different results

2. **Hardcoded Defaults**
   - `~/.cache/cast` hardcoded in mkDataset.nix (line 30-33)
   - Not portable across systems
   - Makes cloning/mirroring difficult

3. **External Config Files**
   - `~/.config/cast/config.nix` not tracked in version control
   - Difficult to reproduce builds
   - Not suitable for flake-based workflows

4. **Database Fetch Anti-pattern**
   - Current `fetchDatabase.nix` uses `/nix/store` (line 19-188)
   - Contradicts CAST's core philosophy
   - Should use CAST store, not Nix store

## Proposed Solution: Non-canonical Flake Outputs

### Core Concept

Use non-canonical flake outputs to store CAST configuration directly in user's flake:

```nix
# User's database flake
{
  inputs.cast.url = "github:user/cast";

  outputs = { self, cast, ... }: {
    # Non-canonical output: CAST config
    cast = {
      storePath = "/data/cast-store";
      preferredDownloader = "aria2c";
    };

    # Use config
    packages.x86_64-linux.ncbi = cast.lib.mkDataset {
      name = "ncbi-nr";
      manifest = ./ncbi.json;
      # storePath auto-injected from self.cast
    };
  };
}
```

### Benefits

- ✅ **Completely Pure**: No environment variables
- ✅ **Version Controlled**: Config in flake.nix
- ✅ **Reproducible**: Same flake = same result
- ✅ **Portable**: Easy to clone/mirror
- ✅ **NixOS Integration**: Natural consumption

## Technical Challenges Analyzed

### Challenge 1: Self-reference

**Problem**: How to reference `self.cast` during evaluation?

**Solution A: Pass flake to lib**
```nix
cast.lib.mkDataset self { name = "ncbi"; ... }
```

**Solution B: withFlakeConfig helper**
```nix
let lib = cast.lib.withFlakeConfig self;
in lib.mkDataset { name = "ncbi"; ... }
```

**Decision**: Both work due to Nix's lazy evaluation. Prefer B for cleaner syntax.

### Challenge 2: Override Mechanism

**Problem**: Downstream users want different storePath

**Solution: Parameterized factory**
```nix
# Database flake exports
{
  outputs = { self, cast, ... }: {
    cast = { storePath = "/data/default"; };

    packages.x86_64-linux = self.mkPackages self.cast;

    # Factory for overrides
    mkPackages = config: {
      ncbi = cast.lib.mkDataset config { ... };
    };
  };
}

# Consumer overrides
{
  packages.x86_64-linux = databases.mkPackages {
    storePath = "/custom/path";
  };
}
```

**Status**: ✅ Solved

### Challenge 3: Multi-flake Scenario

**Question**: Multiple database flakes with different storePaths?

**Answer**: Not a problem - each flake is independent
- `databases-ncbi` uses its own `cast.storePath`
- `databases-uniprot` uses its own `cast.storePath`
- Symlinks point to correct locations
- Can share store if needed via `mkPackages` override

**Status**: ✅ No issue

### Challenge 4: NixOS Module Integration

**Solution**: Export nixosModule with options
```nix
# Database flake
{
  nixosModules.default = { config, lib, ... }: {
    options.services.databases = {
      storePath = lib.mkOption {
        default = self.cast.storePath;
      };
    };

    config = {
      environment.systemPackages = self.mkPackages {
        storePath = config.services.databases.storePath;
      };
    };
  };
}
```

**Status**: ✅ Solved

## Flake-parts Integration

### Current Usage

CAST already uses flake-parts (flake.nix:3-242):
- `perSystem` for system-specific outputs
- `flake` for flake-level outputs
- Modular structure

### Potential Improvements

**flake-parts features that help**:

1. **Self-reference in perSystem**
   ```nix
   perSystem = { self', ... }: {
     # self' provides access to current system's outputs
   };
   ```

2. **Flake-level outputs**
   ```nix
   flake = {
     # Directly accessible outputs
     lib = ...;
   };
   ```

3. **Module system**
   - Compose configuration
   - Override mechanism built-in

### Question for Investigation

Does flake-parts provide better patterns for:
- Accessing non-canonical outputs?
- Self-referential configuration?
- Config composition?

**Action**: Review flake-parts documentation for config patterns

## Implementation Plan

### Phase 2: Pure Configuration (Next)

1. **CAST lib restructure**
   ```nix
   # lib/default.nix
   {
     mkDataset = config: args: ...;
     transform = config: args: ...;
     withFlakeConfig = flake: { ... };
   }
   ```

2. **Example database flake**
   - `examples/database-registry/`
   - Demonstrate non-canonical output pattern
   - Show `mkPackages` factory

3. **Documentation**
   - Best practices guide
   - Override patterns
   - NixOS integration examples

### Phase 3: Advanced Features

1. **lib/builders.nix**
   - `toMMseqs`, `toBLAST`, `toDiamond`
   - Accept config parameter

2. **fetchDatabase redesign**
   - Remove `/nix/store` usage
   - Use CAST store directly
   - Implement in `cast-cli fetch`

3. **NixOS module template**
   - Standard module for database flakes
   - Reusable across projects

## Open Questions

1. **flake-parts patterns**: Are there better ways to handle config with flake-parts?
2. **Complexity assessment**: Does this add too much abstraction?
3. **Escape hatches**: Can users still use explicit parameters?

## Design Principles

1. **Purity First**: No impure operations at build time
2. **Explicit Configuration**: No hidden defaults
3. **Progressive Disclosure**: Simple use cases should be simple
4. **Escape Hatches**: Always allow explicit overrides
5. **Minimal Abstraction**: Only add complexity when needed

## Next Steps

1. Save this discussion to project docs
2. Investigate flake-parts config patterns
3. Update implementation plan
4. Assess remaining complexity
5. Implement if no blocking issues found

---

**Document Version**: 1.0
**Last Updated**: 2025-11-18
**Status**: Planning - Awaiting flake-parts investigation
