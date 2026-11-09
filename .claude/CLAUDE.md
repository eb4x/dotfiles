# Bash in the sandbox

Bash runs in bubblewrap and sees only the working directory, the session's
additionalDirectories and `/tmp/claude-1000`; the proxy refuses hosts outside
the allowlist. That is the boundary, not an error to retry: report the path or
host and ask the user for `/add-dir` or the allowlist. "No such file" under
`/home` may mean hidden, not absent: let the user check with `!`.

git and gh leave the sandbox (for signing and credentials) only as one plain
command per call that starts with `git` or `gh`. `git -C`, `--git-dir`,
`--work-tree`, an env prefix, pipe, redirect, heredoc, `%(…)` format string,
or `$(…)` or a backtick even when quoted, sandboxes the call or prompts.
Instead, `cd /abs/path` in its own call first, and pass messages from a file
(`-F`, gh `--body-file`) or, when plain, with several `-m`. A subagent's `cd`
does not persist: there `git -C` still reads, and it hands commits outside its
cwd back to the caller. `git config` writes fail: use
`git remote add`/`set-url`/`set-branches` or `git branch -u` where they fit,
else hand the write to the user.

On a permission denial, report the exact command and rule name, then split it
or switch tools; never reword and retry.

# Bare repos with worktrees

Many of my repos are bare, with worktrees beneath (`<repo>/master/`,
`<repo>/<branch>/`). When a session starts at the bare root:

- Agent/tooling files (`CLAUDE.md`, `.claude/`, notes, scratch files) go in the
  bare root, never in a worktree. Use absolute paths for them: the working
  directory can be switched into a worktree mid-session.
- Source edits, builds, tests and `git` for a branch run in its worktree. A
  `CLAUDE.md` committed in the repo counts as source: change it only for what
  belongs in the repo.
- To add a worktree, `cd` to the bare root, then give a relative path:
  `git worktree add <branch> <branch>` (`-b <branch> <branch>` if new).
