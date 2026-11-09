# Bash in the sandbox

Bash runs in bubblewrap and sees only the working directory, the session's
additionalDirectories and `/tmp/claude-1000`. A path outside those does not
exist to it, and a host outside the sandbox allowlist is refused by the proxy:
both are the boundary, not errors to retry; report the path or host and ask the
user for `/add-dir` or the allowlist. "No such file" under `/home` outside those
directories may mean hidden rather than absent, and Bash cannot tell which: say
so and let the user check with `!`. git and gh leave the sandbox only when a
call starts with `git` or `gh`, with no `-C`, `--git-dir` or `--work-tree`
before the subcommand: those keep git sandboxed, where commit signing fails.
Any `git config` write and `git worktree add` with an absolute path stay
sandboxed too (the config write fails); use `git remote add`/`set-url`/
`set-branches`, `git branch -u`, a path relative to the cwd, or hand the write
to the user. Leave off env prefixes (`VAR=x git …` prompts); `git --no-pager`
is fine. To work in a repo, `cd /abs/path` in its own call first. One command
per call: no pipes, redirects, `$(…)` or heredocs (commit messages via several
`-m` or `-F file`), no `%(…)` format strings. On any denial, report the exact
command and rule name, then split it or switch tools; never reword and retry.

# Bare repos with worktrees

Many of my repos are bare, with worktrees beneath (`<repo>/master/`,
`<repo>/<branch>/`). When a session starts at the bare root:

- Agent/tooling files (`CLAUDE.md`, `.claude/`, notes, scratch files) go in the
  bare root, never in a worktree. Use absolute paths for them: the working
  directory can be switched into a worktree mid-session.
- Source edits, builds, tests and `git` for a branch run in its worktree. A
  `CLAUDE.md` committed in the repo counts as source: change it only for what
  belongs in the repo.
