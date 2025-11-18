# CAST Implementation Roadmap V2

**Version**: 2.0 (Post Pure-Config Design)
**Date**: 2025-11-18
**Status**: Ready for Phase 2 Implementation

## Overview

This roadmap incorporates the finalized pure configuration design using flake-parts options system.

---

## Phase 1: MVP ✅ COMPLETED

### Completed Tasks (All Done)

- ✅ Project structure skeleton (Task 1)
- ✅ Manifest JSON schema (Task 2)
- ✅ Nix library API (Task 3)
  - mkDataset, fetchDatabase, transform, symlinkSubset, manifest utilities
- ✅ Rust CLI basic structure (Task 4)
- ✅ BLAKE3 hashing (Task 5)
- ✅ Local storage backend (Task 6)
- ✅ SQLite metadata database (Task 7)
- ✅ Nix integration and symlink farms (Task 8)
- ✅ Transformation pipeline system (Task 9)
- ✅ Examples and documentation (Task 10)

**Status**: Production-ready MVP completed on 2025-11-18

---

## Phase 2: Pure Configuration & Production Readiness 🔄 IN PROGRESS

### Goal

Implement pure, reproducible configuration using flake-parts options system and prepare for production use.

### Key Decisions

1. **Configuration Method**: flake-parts options system (NOT let-binding or env vars)
2. **Self-reference**: Use `config` argument in perSystem (NOT `getFlake "self"`)
3. **Override Mechanism**: Module system merging
4. **Type Safety**: Full validation via lib.types
5. **Documentation**: Built-in via option descriptions

### Tasks

#### Task 11: CAST Library Restructure for Config (Priority: High)

**Objective**: Update lib to accept config parameter while maintaining simplicity

**Subtasks**:

1. **Update lib/default.nix**
   - Keep current simple API: `mkDataset = config: args:`
   - No changes to `configure` function
   - No awareness of flake-parts required
   - Estimated: 0 LOC change (already correct)

2. **Update lib/mkDataset.nix**
   - Remove hardcoded `~/.cache/cast` default
   - Accept config parameter with `storePath`
   - Improve error messages
   - Priority: explicit param > config.storePath > error
   - Estimated: ~5 LOC change

3. **Update lib/transform.nix**
   - Accept config parameter
   - Use config for any needed settings
   - Estimated: ~3 LOC change

**Success Criteria**:
- No environment variable dependencies
- Clear error messages when storePath missing
- Config parameter well-documented
- All existing tests pass

**Estimated Time**: 1 hour

---

#### Task 12: Database Registry Example with Options (Priority: High)

**Objective**: Create complete example showing flake-parts options pattern

**Subtasks**:

1. **Create examples/database-registry/flake.nix**
   - Define CAST options schema
     ```nix
     options.cast = lib.mkOption {
       type = lib.types.submodule {
         options = {
           storePath = lib.mkOption { type = lib.types.path; };
           preferredDownloader = lib.mkOption {
             type = lib.types.enum [...];
             default = "auto";
           };
         };
       };
     };
     ```
   - Set config values
   - Use in perSystem via `config.cast`
   - Estimated: ~60 LOC

2. **Create example manifests**
   - `manifests/ncbi-nr.json`
   - `manifests/uniprot.json`
   - Include transformation examples
   - Estimated: ~100 LOC JSON

3. **Show transformation builders**
   - Use `castLib.builders.toMMseqs`
   - Chain transformations
   - Document provenance tracking
   - Estimated: ~20 LOC

4. **Add override example**
   - Show how downstream flakes override config
   - Document best practices
   - Estimated: ~30 LOC in comments/docs

**Success Criteria**:
- Example builds with `nix build`
- Options validated at evaluation time
- Override pattern works
- Clear documentation

**Estimated Time**: 2 hours

---

#### Task 13: lib/builders.nix - Transformation Helpers (Priority: Medium)

**Objective**: Provide convenient builders for common bioinformatics transformations

**Subtasks**:

1. **Create lib/builders.nix structure**
   ```nix
   { lib, pkgs, transform }:
   config: {
     toMMseqs = dataset: params: ...;
     toBLAST = dataset: params: ...;
     toDiamond = dataset: ...;
   }
   ```
   - Accept config parameter
   - Export from lib/default.nix
   - Estimated: ~20 LOC

2. **Implement toMMseqs builder**
   - Create MMseqs2 database from FASTA
   - Support createindex
   - Estimated: ~30 LOC

3. **Implement toBLAST builder**
   - Support prot/nucl database types
   - Use makeblastdb
   - Estimated: ~25 LOC

4. **Implement toDiamond builder**
   - Create Diamond database
   - Estimated: ~20 LOC

5. **Add builder tests**
   - Integration test in examples/
   - Verify outputs
   - Estimated: ~40 LOC

**Success Criteria**:
- All builders work with real data
- Provenance tracking correct
- Cached properly by Nix
- Documented with examples

**Estimated Time**: 2 hours

---

#### Task 14: cast-cli Package Export (Priority: High)

**Objective**: Expose cast-cli as a proper Nix package

**Subtasks**:

1. **Add gitignore.nix input to flake.nix**
   ```nix
   inputs.gitignore = {
     url = "github:hercules-ci/gitignore.nix";
     inputs.nixpkgs.follows = "nixpkgs";
   };
   ```
   - Update flake.lock
   - Estimated: ~5 LOC

2. **Add packages.cast-cli in perSystem**
   ```nix
   packages.cast-cli = pkgs.rustPlatform.buildRustPackage {
     pname = "cast-cli";
     src = inputs.gitignore.lib.gitignoreSource ./packages/cast-cli;
     cargoLock.lockFile = ./packages/cast-cli/Cargo.lock;
     nativeBuildInputs = [ pkgs.pkg-config ];
     buildInputs = [ pkgs.sqlite ];
   };
   ```
   - Set as default package
   - Estimated: ~20 LOC

3. **Add package metadata**
   - Description
   - License (determine)
   - mainProgram
   - Estimated: ~5 LOC

4. **Test package builds**
   - `nix build .#cast-cli`
   - Verify binary works
   - Check closure size

**Success Criteria**:
- Package builds successfully
- .git, target/ excluded
- Works on all systems
- Reasonable closure size

**Estimated Time**: 1 hour

---

#### Task 15: NixOS Module for Database Registries (Priority: Medium)

**Objective**: Provide standard NixOS module pattern for database flakes

**Subtasks**:

1. **Create module template in examples/**
   - `examples/database-registry/nixos-module.nix`
   - Reuse CAST options schema
   - Estimated: ~50 LOC

2. **Implement module logic**
   - Enable/disable service
   - Override storePath
   - Install packages system-wide
   - Estimated: ~40 LOC

3. **Export from database flake**
   ```nix
   flake.nixosModules.default = import ./nixos-module.nix {
     inherit self cast;
   };
   ```
   - Estimated: ~5 LOC

4. **Add NixOS configuration example**
   - Show usage in configuration.nix
   - Document best practices
   - Estimated: ~30 LOC in docs

**Success Criteria**:
- Module loads without errors
- Options work correctly
- Override mechanism functions
- System packages installed

**Estimated Time**: 2 hours

---

#### Task 16: Documentation Update (Priority: High)

**Objective**: Update all documentation for pure config design

**Subtasks**:

1. **Update README.md**
   - Remove environment variable references
   - Document flake-parts options pattern
   - Add configuration examples
   - Update architecture diagram
   - Estimated: ~100 LOC changes

2. **Update CLAUDE.md**
   - Document new architecture
   - Configuration philosophy
   - Best practices
   - Phase 2 implementation details
   - Estimated: ~200 LOC additions

3. **Create CONFIGURATION.md**
   - Detailed config guide
   - All options documented
   - Override patterns
   - Troubleshooting
   - Estimated: ~300 LOC

4. **Update API documentation**
   - Document config parameter
   - Update all function signatures
   - Add type information
   - Estimated: ~50 LOC changes

5. **Create migration guide**
   - For any early adopters
   - Environment variable -> options
   - Estimated: ~100 LOC

**Success Criteria**:
- All docs accurate and complete
- Examples work as shown
- Clear migration path
- Troubleshooting section comprehensive

**Estimated Time**: 3 hours

---

#### Task 17: fetchDatabase Redesign (Priority: Low - Future)

**Objective**: Remove /nix/store dependency, use CAST store directly

**Status**: Deferred to Phase 3

**Rationale**: Current implementation works but contradicts CAST philosophy. Redesign requires:
- cast-cli fetch command
- Downloader selection (aria2c/curl/wget)
- CAST store caching
- Manifest generation

**Estimated Time**: 4-6 hours (Phase 3)

---

## Phase 2 Summary

### Total Estimated Time

| Task | Priority | Time |
|------|----------|------|
| Task 11: Lib restructure | High | 1h |
| Task 12: Database example | High | 2h |
| Task 13: Builders | Medium | 2h |
| Task 14: cast-cli package | High | 1h |
| Task 15: NixOS module | Medium | 2h |
| Task 16: Documentation | High | 3h |

**Total**: 11 hours of focused work

### Implementation Order

**Week 1** (High Priority):
1. Task 11: Lib restructure (1h)
2. Task 14: cast-cli package (1h)
3. Task 12: Database example (2h)
4. Task 16: Documentation (3h)

**Week 2** (Medium Priority):
5. Task 13: Builders (2h)
6. Task 15: NixOS module (2h)

---

## Phase 3: Advanced Features (Future)

### Goals

- Garbage collection
- fetchDatabase redesign (CAST store caching)
- Multi-tier storage (SSD/HDD)
- Remote storage backends
- Web UI for dataset browsing

### Estimated Timeline

Q1 2025 or as needed based on user feedback

---

## Success Metrics

### Phase 2 Complete When:

- ✅ Zero environment variables required
- ✅ All config in flake.nix with types
- ✅ Works with `nix build --pure`
- ✅ cast-cli package available
- ✅ Complete database registry example
- ✅ NixOS module pattern established
- ✅ Documentation comprehensive
- ✅ All tests passing

### Quality Gates

- All examples build successfully
- No hardcoded paths
- Type checking catches config errors
- Documentation clear for new users
- Migration path documented

---

## Risk Management

| Risk | Mitigation |
|------|------------|
| flake-parts API changes | Pin to stable version |
| Complexity too high | Extensive examples and docs |
| User confusion | Clear error messages |
| Breaking changes | Semantic versioning, changelog |

---

## Post-Phase 2 Backlog

- [ ] Performance benchmarks
- [ ] fetchDatabase redesign
- [ ] Garbage collection
- [ ] Remote storage backends
- [ ] Web UI
- [ ] CI/CD pipeline
- [ ] Automated testing
- [ ] Release automation

---

**Document Status**: Finalized
**Next Action**: Begin Task 11 (Lib restructure)
**Target Completion**: 2 weeks from start
