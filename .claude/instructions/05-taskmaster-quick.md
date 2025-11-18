# Task Master Quick Reference

> **Note**: Only load this file when working with Task Master tasks.
> For general development, this context is not needed.

## Essential Commands

```bash
# Daily workflow
task-master next                              # Get next available task
task-master show <id>                        # View task details
task-master set-status --id=<id> --status=done

# Task management
task-master list                             # Show all tasks
task-master add-task --prompt="..." --research
task-master update-subtask --id=<id> --prompt="notes..."

# Analysis & planning
task-master expand --id=<id> --research --force
task-master analyze-complexity --research
```

## MCP Tools (Auto-Allowed)

All `mcp__taskmaster-ai__*` tools are available without approval:

```
get_tasks, next_task, get_task
set_task_status, update_subtask
expand_task, analyze_project_complexity
```

## Task Structure

### Task IDs
- Main: `1`, `2`, `3`
- Subtasks: `1.1`, `1.2`
- Sub-subtasks: `1.1.1`, `1.1.2`

### Status Values
- `pending` - Ready to work on
- `in-progress` - Currently working
- `done` - Completed
- `deferred` - Postponed
- `cancelled` - No longer needed

## Key Files

```
.taskmaster/
├── tasks/tasks.json      # Main task database (auto-managed)
├── tasks/*.md           # Individual task files (auto-generated)
├── config.json          # AI model config
└── docs/prd.md          # Product requirements (.md recommended)
```

## Workflow Pattern

```bash
# 1. Get next task
task-master next

# 2. Review details
task-master show 1.2

# 3. Log implementation notes during work
task-master update-subtask --id=1.2 --prompt="implemented X, blocked by Y"

# 4. Complete when done
task-master set-status --id=1.2 --status=done
```

## Integration with Jujutsu

Task Master works with jj:

```bash
# Reference tasks in commits
jj commit -m "feat: implement user auth (task 1.2)"

# Create bookmarks for task branches
jj bookmark create task-1.2-auth
```

## Best Practices

1. **Context management**: Use `/clear` between different tasks
2. **Detailed logging**: Use `update-subtask` to log progress
3. **Iterative work**: Update status as you go, don't batch
4. **Parse PRDs**: Use `.md` extension for better editor support

## When NOT to Load

Skip loading this file if:
- Working on general implementation (not task-based)
- Context is already clear from conversation
- Token budget is limited

---

For complete Task Master guide, see `.taskmaster/CLAUDE.md`.
