---
name: Commit Message Convention
description: Guide for writing consistent, informative commit messages following Conventional Commits specification. Use when creating commits or describing changes. Helps maintain clear project history and enables automated changelog generation.
allowed-tools: Bash(jj describe:*), Bash(jj commit:*)
---

# Commit Message Convention

## Format

```
<type>[optional scope][!]: <description>

[optional body]

[optional footer(s)]
```

**Breaking change indicator**: Add `!` after type/scope for breaking changes.

## Commit Types

### Primary Types

| Type | Purpose | When to Use |
|------|---------|-------------|
| `feat` | New feature | Adding new functionality, user-facing features |
| `fix` | Bug fix | Fixing bugs, correcting errors |
| `docs` | Documentation | README, comments, docs changes (no code changes) |
| `style` | Code style | Formatting, missing semicolons (no logic changes) |
| `refactor` | Code refactoring | Restructuring code without changing behavior |
| `perf` | Performance | Performance improvements |
| `test` | Tests | Adding or fixing tests |
| `build` | Build system | Changes to build process, dependencies |
| `ci` | CI/CD | CI configuration, workflow changes |
| `chore` | Maintenance | Other changes that don't modify src/test files |

### Additional Types

| Type | Purpose | When to Use |
|------|---------|-------------|
| `revert` | Revert commit | Reverting a previous commit |
| `wip` | Work in progress | Incomplete work (avoid in main branch) |

## Scope

**Optional** but recommended for clarity. Indicates which part of codebase is affected.

### Common Scopes for This Project

- `lib` - Nix library functions (mkDataset, transform, etc.)
- `cli` - Rust CLI tool (cast-cli)
- `modules` - NixOS modules
- `examples` - Example projects
- `docs` - Documentation files
- `ci` - CI/CD workflows
- `deps` - Dependencies
- `flake` - Flake configuration
- `tests` - Test infrastructure

### Scope Examples

```
feat(lib): add extractArchive transformation builder
fix(cli): correct BLAKE3 hash validation
docs(examples): update transformation pipeline guide
refactor(modules): simplify NixOS module options
```

## Breaking Changes

Use `!` after type/scope to indicate breaking changes:

```
feat!: change configure API to require explicit storePath
feat(lib)!: remove deprecated mkDataset parameter
refactor!: restructure library exports
```

**Body MUST include `BREAKING CHANGE:` footer**:

```
feat!: change configure API

BREAKING CHANGE: storePath is now required in configure call.
Migration: cast.lib.configure {} → cast.lib.configure {storePath = "...";}
```

## Header Message (Description)

**Rules**:
- Use **imperative mood**: "add" not "adds" or "added"
- **No capitalization**: Start with lowercase
- **No period** at the end
- **Max 72 characters** (enforced by jj describe)
- Be **specific and concise**

**Good Examples**:
```
feat: add NixOS module for system-wide database management
fix: correct symlink generation for nested directories
docs: update CONFIGURATION.md with flake-parts examples
refactor: extract manifest validation into separate module
test: add integration tests for transformation pipeline
```

**Bad Examples**:
```
feat: Add new feature          # Capitalized, vague
fix: Fixed bugs.               # Past tense, period, vague
docs: updated docs             # Past tense, vague
refactor: Changes              # Vague, not imperative
```

## Detail Message (Body)

**When to include**:
- Complex changes requiring explanation
- Breaking changes (required)
- Non-obvious rationale
- Related issues or context

**Format**:
- Separated from header by **blank line**
- Use **present tense** for consistency
- Explain **what** and **why**, not how (code shows how)
- Wrap at **72 characters** per line
- Can include multiple paragraphs

**Structure**:
1. **Context**: Why is this change needed?
2. **Solution**: What does this commit do?
3. **Impact**: What are the effects? (if non-obvious)

**Example**:
```
feat(lib): add transformation builder for MMseqs2 format

MMseqs2 is commonly used in bioinformatics workflows for fast
sequence searching. Users were manually writing transformation
builders for this common use case.

This adds toMMseqs builder that:
- Converts FASTA to MMseqs2 database format
- Optionally creates index for faster searches
- Handles multi-file FASTA inputs

Simplifies database registry definitions by eliminating
repetitive transformation code.
```

## Footers

Optional metadata at the end of commit message.

### Common Footers

```
BREAKING CHANGE: description of breaking change
Fixes: #123
Closes: #456
Related: #789
Co-authored-by: Name <email@example.com>
Reviewed-by: Name <email@example.com>
```

### This Project's Footers

For Task Master integration:
```
Task: 1.2
Subtask: 1.2.3
```

For AI-generated commits:
```
🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

## Complete Examples

### Simple Feature
```
feat(lib): add extractArchive transformation builder

Provides unified interface for extracting tar.gz, zip, and other
common archive formats. Auto-detects format from file extension
or allows manual specification via format parameter.
```

### Bug Fix
```
fix(cli): handle missing manifest.json gracefully

Previously, cast-cli would panic if manifest.json was missing.
Now returns user-friendly error message with troubleshooting steps.

Fixes: #42
```

### Breaking Change
```
feat!: migrate to flake-parts flakeModules pattern

Replace manual configure function with flake-parts module system
for better composability and type safety.

BREAKING CHANGE: Configuration now happens via perSystem module
instead of explicit configure call.

Migration guide:
  Before: let castLib = cast.lib.configure {storePath = "..."};
  After: perSystem = {castLib, ...}: {cast.storePath = "...";}

See CONFIGURATION.md for complete migration instructions.

Task: 2.1
```

### Documentation
```
docs: reorganize CLAUDE.md into modular instructions

Split monolithic CLAUDE.md into:
- .claude/CLAUDE.md (entry point)
- .claude/instructions/00-CRITICAL.md (jj rules)
- .claude/instructions/01-project-overview.md
- .claude/instructions/02-architecture.md
- .claude/instructions/03-configuration.md
- .claude/instructions/04-implementation.md
- .claude/instructions/05-taskmaster-quick.md

Enables progressive context loading and reduces token usage.
Enforces jujutsu-only workflow via explicit rules.
```

### Refactoring
```
refactor(lib): extract common transformation logic

Move shared builder logic (hash calculation, manifest generation,
symlink creation) into internal buildTransformation function.

Reduces code duplication across toMMseqs, toBLAST, and toDiamond
builders. No user-facing changes.
```

### Chore
```
chore(deps): update nixpkgs to 25.05

Updates flake.lock with latest nixpkgs stable release.
Includes Rust 1.83 and improved nix-command performance.
```

## Jujutsu-Specific Tips

### Using `jj describe`

```bash
# Interactive editor (recommended for multi-line)
jj describe

# Single-line message
jj describe -m "feat: add new feature"

# Multi-line with heredoc
jj describe -m "$(cat <<'EOF'
feat(lib): add transformation pipeline

Enables chaining multiple transformations with automatic
dependency tracking and caching.
EOF
)"
```

### Editing Existing Commits

```bash
# Edit any commit's message
jj edit <change-id>
jj describe -m "new message"
jj new  # Return to tip
```

### Stack-Based Commits

Each commit in a stack should:
- Be **atomic** (single logical change)
- Have **clear message** following conventions
- Be **independently reviewable**

```bash
# Good stack example:
# 1. feat(lib): add manifest validation types
# 2. feat(lib): implement manifest validator
# 3. test: add manifest validation tests
# 4. docs: document manifest validation
```

## Anti-Patterns to Avoid

❌ **Too vague**:
```
fix: bug fixes
feat: improvements
docs: update
```

❌ **Multiple changes**:
```
feat: add feature X, fix bug Y, update docs
```
*Split into separate commits!*

❌ **Wrong type**:
```
feat: fix typo in README        # Should be: docs
fix: add new configuration      # Should be: feat
```

❌ **Not imperative**:
```
feat: adding new feature        # Should be: add
fix: fixed the bug              # Should be: fix
docs: updated documentation     # Should be: update
```

## Tools & Automation

### Validation

While this project doesn't enforce commit conventions mechanically, following them helps with:
- **Code review**: Easier to understand changes
- **Changelog generation**: Automated release notes
- **Git history search**: Finding specific types of changes
- **Bisecting**: Clearer when bugs were introduced

### Future Integration

Consider adding:
- Pre-commit hooks via `jj` config
- Automated changelog via `git-cliff` or similar
- Release automation based on conventional commits

## References

- **Conventional Commits**: https://www.conventionalcommits.org/
- **Angular Convention**: https://github.com/angular/angular/blob/main/CONTRIBUTING.md#commit
- **Semantic Versioning**: https://semver.org/

---

**When in doubt**: Use the imperative mood, be specific, explain why.
Good commit messages are a gift to your future self and collaborators!
