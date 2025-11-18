# Task Master AI - Integration

> **Note**: As of Task Master v2.7.0+, Claude Code automatically loads `.claude/CLAUDE.md`.
>
> **Quick reference** for Task Master commands is available at:
> `.claude/instructions/05-taskmaster-quick.md`

## Quick Commands

```bash
# Daily workflow
task-master next                              # Get next task
task-master show <id>                        # View details
task-master set-status --id=<id> --status=done

# Task management
task-master list                             # Show all tasks
task-master update-subtask --id=<id> --prompt="notes..."
```

## File Locations

- **Tasks**: `.taskmaster/tasks/tasks.json` (auto-managed)
- **Config**: `.taskmaster/config.json` (use `task-master models`)
- **PRD**: `.taskmaster/docs/prd.md` (`.md` extension recommended)

## Integration

All `mcp__taskmaster-ai__*` tools are auto-allowed via `.claude/settings.json`.

For complete Task Master documentation, load:
- `.claude/instructions/05-taskmaster-quick.md` (when working on tasks)

---

**This file is kept minimal to reduce token usage.**
**Comprehensive instructions are in `.claude/` directory.**
