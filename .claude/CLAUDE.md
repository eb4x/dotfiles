# Bash in the sandbox

Bash runs in bubblewrap and sees only the working directory, the session's
additionalDirectories and `/tmp/claude-1000`. A path outside those does not
exist to it, and a host outside the sandbox allowlist is refused by the proxy:
both are the boundary, not errors to retry; report the path or host and ask the
user for `/add-dir` or the allowlist. git and gh run outside the sandbox, under
the static fence: for those two, one plain command per call, absolute paths, no
pipes, no `%(…)` format strings. On any denial, quote it verbatim with the rule
name; never retry a variant.

# Bare repos with worktrees

Many of my repos are bare, with worktrees beneath (`<repo>/master/`,
`<repo>/<branch>/`). When a session starts at the bare root:

- Agent/tooling files (`CLAUDE.md`, `.claude/`, notes, scratch files) go in the
  bare root, never in a worktree. Use absolute paths for them: the working
  directory can be switched into a worktree mid-session.
- Source edits, builds, tests and `git` for a branch run in its worktree. A
  `CLAUDE.md` committed in the repo counts as source: change it only for what
  belongs in the repo.
