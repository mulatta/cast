# CAST: Content-Addressed Storage Tool

> **⚠️ MANDATORY**: Critical rules are automatically loaded below.
> Additional context files are loaded on-demand based on your task.

## Auto-Loaded Context

The following files are **automatically included** in every conversation:

@.claude/instructions/00-CRITICAL.md

## Context Organization

This project uses a modular instruction system to minimize token usage. Additional files are loaded progressively as needed

### On-Demand Context

Load additional context files **only when needed** for your specific task:

| Your Task | Load File |
|-----------|-----------|
| General questions about CAST | @.claude/instructions/01-project-overview.md |
| Architecture/design questions | @.claude/instructions/02-architecture.md |
| Setup/configuration help | @.claude/instructions/03-configuration.md |
| Implementation status/phases | @.claude/instructions/04-implementation.md |
| Task Master workflow | @.claude/instructions/05-taskmaster-quick.md |

**How to load**: Simply reference the file path with `@` prefix in your thinking or explicitly load it when you determine it's relevant to the user's question.

### Skills (Use via `Skill()` Tool)

Prefer using skills over loading full documentation:

```bash
Skill(jj-workflows)              # Jujutsu version control
Skill(commit-convention)         # Commit message conventions
Skill(flake-parts)               # flake-parts module system
Skill(nix-project-workflows)     # Nix development workflows
```

## Quick Project Info

**CAST** is a Nix-integrated content-addressed storage system for large scientific databases.

**Current Status**: Phase 3 Complete ✅
- Pure configuration pattern (works with `nix build --pure`)
- Transformation pipeline with common builders
- NixOS module for system-wide database management

**Tech Stack**: Nix + Rust + BLAKE3 + SQLite

## Progressive Context Loading Strategy

**DO NOT load all files at once!** Follow this pattern:

1. **Start here**: `00-CRITICAL.md` is auto-loaded (via `@` reference above)
2. **Understand task**: What is the user asking?
3. **Load relevant context**: Use `@` prefix for specific instruction files only when needed
4. **Use skills first**: Try `Skill()` tool before loading instruction files
5. **Respond concisely**: Keep answers actionable

### Using @ References

- `@.claude/instructions/XX-name.md` - Loads file content into context
- Use sparingly to conserve tokens
- Only load when the specific domain knowledge is required

## Version Control: Jujutsu ONLY

**CRITICAL**: This project uses **jujutsu (jj)**, NOT git!

See `instructions/00-CRITICAL.md` for complete rules.

Quick reference:
```bash
# ✅ CORRECT
jj status
jj commit -m "message"
jj describe -m "message"

# ❌ WRONG
git commit -m "message"  # NEVER use git!
```

Use `Skill(jj-workflows)` when unsure about jj commands.

### Commit Policy

**Create commits proactively**:
- ✅ After completing tasks or significant changes
- ✅ Before ending conversation (if changes exist)
- ✅ Use `Skill(commit-convention)` for proper format

See `instructions/00-CRITICAL.md` for detailed commit workflow.

## Development Workflow

```bash
# Enter dev shell
nix develop

# Run checks
nix flake check

# Format code
nix fmt

# Build package
nix build .#cast-cli
```

## Quick Reference

### Documentation Files
- **User Guide**: @README.md
- **Configuration Guide**: @CONFIGURATION.md
- **Implementation Status**: @IMPLEMENTATION_STATUS.md
- **Examples**: See `examples/*/README.md` files

### Key Files by Topic
- **Project Overview**: @.claude/instructions/01-project-overview.md
- **Architecture Details**: @.claude/instructions/02-architecture.md
- **Configuration Help**: @.claude/instructions/03-configuration.md
- **Implementation Status**: @.claude/instructions/04-implementation.md

---

**Remember**:
- Critical rules are auto-loaded
- Load additional context progressively with `@` prefix
- Use `Skill()` tools when possible
- Always use jujutsu (jj) for version control
