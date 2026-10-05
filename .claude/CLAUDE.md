# Bare repos with worktrees

Many of my repos are bare, with worktrees beneath (`<repo>/master/`, `<repo>/<branch>/`). When a session starts at the bare root:

- Agent/tooling files (`CLAUDE.md`, `.claude/`, notes, scratch files) go in the bare root, never in a worktree. Use absolute paths for them: the working directory can be switched into a worktree mid-session.
- Source edits, builds, tests and `git` for a branch run in its worktree. A `CLAUDE.md` committed in the repo counts as source: change it only for what belongs in the repo.
