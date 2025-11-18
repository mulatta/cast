# CRITICAL Rules - MUST FOLLOW

> **⚠️ HIGHEST PRIORITY**: These rules override ALL other instructions.
> Read this FIRST before any other context.

## 🔴 Version Control: Jujutsu ONLY

### MANDATORY: Use Jujutsu (jj), NOT Git

This project **EXCLUSIVELY** uses **Jujutsu (jj)** for version control.

**NEVER use `git` commands** unless explicitly instructed otherwise.

### Allowed jj Commands

```bash
# Status & inspection (auto-allowed)
jj status
jj log
jj show
jj diff
jj evolog / obslog / op log / op show

# File operations (auto-allowed)
jj file list
jj file show

# Basic editing (auto-allowed)
jj commit / new / describe
jj squash / unsquash / split / move
jj edit / next / prev
jj rebase / resolve / restore / abandon
jj undo / op undo / op restore

# Bookmarks (ask first)
jj bookmark list            # auto-allowed
jj bookmark create/delete   # requires approval
```

### Forbidden Operations

```bash
# NEVER use these without explicit user permission:
jj git push / fetch         # denied by settings
jj bookmark push/track      # denied by settings
```

### When to Use Git (Rare Exceptions)

Git commands are **ONLY** allowed for:
1. **Read-only operations** where jj equivalent doesn't exist
2. **Interoperability** tasks explicitly requested by user
3. **GitHub CLI** (`gh`) operations that internally use git

Example allowed cases:
```bash
gh pr create               # OK - GitHub CLI tool
git remote -v              # OK if user asks about remotes
jj git export              # OK - jj's own git interop
```

### Skills Integration

When user mentions version control, commits, or changes:

1. **FIRST**: Check if `jj-workflows` skill applies
2. **THEN**: Use jj commands, never git
3. **REFERENCE**: Jujutsu documentation when uncertain

```bash
# Load skills when needed
Skill(jj-workflows)           # Jujutsu workflows and commands
Skill(commit-convention)      # Commit message format and conventions
```

**Use commit-convention skill when**:
- Writing commit messages
- User asks about commit format
- Describing changes with `jj describe`

## 🎯 Token Management

### Documentation Access Strategy

1. **Minimize context loading**: Only load relevant instruction files
2. **Use skills**: Prefer `Skill()` tool over loading full docs
3. **Progressive disclosure**: Start with overview, drill down as needed
4. **Use @ references**: Load files with `@` prefix only when needed

### Using @ File References

**Auto-loaded** (already in context):
```
@.claude/instructions/00-CRITICAL.md  → This file (MANDATORY)
```

**Load on-demand** using @ prefix:
```
@.claude/instructions/01-project-overview.md   → General questions
@.claude/instructions/02-architecture.md       → Design/implementation
@.claude/instructions/03-configuration.md      → Setup/config
@.claude/instructions/04-implementation.md     → Status/phases
@.claude/instructions/05-taskmaster-quick.md   → Task management
```

**Skills** (use `Skill()` tool):
```
Skill(jj-workflows)           → Jujutsu commands
Skill(commit-convention)      → Commit format
Skill(flake-parts)            → flake-parts patterns
Skill(nix-project-workflows)  → Nix development
```

### DO NOT Load Unnecessarily

- ❌ Don't load all files at conversation start
- ❌ Don't re-read files already in context
- ❌ Don't use @ for files you can find with grep/search
- ✅ Load on-demand based on user query
- ✅ Use `Skill()` for skills, `@` for instruction files
- ✅ Use grep/search to find specific info first

## 🔧 Task Master Integration

### Quick Commands

```bash
# Most common workflow
task-master next                     # Get next task
task-master show <id>               # View task details
task-master set-status --id=<id> --status=done

# Use skills for complex operations
Skill(taskmaster-quick)             # Load detailed guide only when needed
```

### MCP Tools

All `mcp__taskmaster-ai__*` tools are auto-allowed. Use them freely.

## 🏗️ Project-Specific Rules

### Nix Development

1. **flake-parts pattern**: Use `Skill(flake-parts)` for module questions
2. **Pure builds**: All configurations must work with `nix build --pure`
3. **Testing**: Use `nix flake check` before committing

### Rust Development

1. **Format before commit**: `cargo fmt`
2. **Lint**: `cargo clippy`
3. **Tests**: `cargo test`

### Commit Workflow

#### When to Create Commits

**IMPORTANT**: Create commits proactively at the end of each work session.

**Auto-commit triggers**:
1. ✅ **After completing a task or subtask**
2. ✅ **After significant code changes** (>50 lines or new feature)
3. ✅ **Before ending a conversation** (if changes exist)
4. ✅ **After user requests changes** (implement → commit)
5. ❌ **NOT for trivial changes** (<10 lines, formatting only)

**Workflow**:
```bash
# 1. Check for changes
jj status

# 2. If changes exist, create commit
jj describe -m "$(cat <<'EOF'
<type>[scope]: <description>

[optional body following commit-convention]

🤖 Generated with Claude Code

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

#### Commit Message Requirements

**ALWAYS**:
- Use `Skill(commit-convention)` for proper format
- Follow Conventional Commits (type, scope, description)
- Include AI footer (🤖 Generated with Claude Code)
- Use imperative mood ("add" not "added")
- Keep header under 72 characters

**Example commit at session end**:
```bash
jj describe -m "$(cat <<'EOF'
feat(lib): add extractArchive transformation builder

Provides unified interface for extracting tar.gz, zip, and other
archive formats. Auto-detects format from file extension or
allows manual specification.

Simplifies common database preprocessing workflows.

🤖 Generated with Claude Code

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

#### Safety Checks Before Commit

**MUST check**:
1. **Nix projects**: Run `nix flake check` (if flake.nix changed)
2. **Rust projects**: Run `cargo fmt` and `cargo clippy`
3. **Format check**: Run `nix fmt` (if Nix files changed)
4. **No secrets**: Verify no API keys, passwords in changes

**If checks fail**: Fix issues before committing.

#### Jujutsu vs Git Commands

```bash
# ✅ CORRECT: Using jj
jj describe -m "feat: add new feature"
jj status
jj diff

# ❌ WRONG: Using git
git commit -m "..."                  # NEVER DO THIS
git add .                            # NEVER DO THIS
```

#### Multi-Commit Sessions

For complex work spanning multiple logical changes:

```bash
# After first feature
jj describe -m "feat(lib): add feature A"

# Create new change for next feature
jj new

# After second feature
jj describe -m "feat(lib): add feature B"

# Stack multiple commits for related work
```

**Prefer atomic commits**: One logical change per commit.

## 📝 Communication Style

- **Concise**: Keep responses short and actionable
- **No emojis**: Unless explicitly requested
- **Technical accuracy**: Over emotional validation
- **Markdown**: Use proper formatting for code/commands

---

**Remember**: When in doubt about version control, **ASK** rather than assume git!

Use `Skill(jj-workflows)` for comprehensive jujutsu guidance.
