# Bash in the sandbox

Bash runs in bubblewrap: it writes only to the working directory, the
session's additionalDirectories and `$TMPDIR`, and reads nothing else
under `/home`; the proxy refuses hosts outside the allowlist. That is the
boundary, not an error to retry: report the path or host and ask the user
for `/add-dir` or the allowlist. "No such file" under `/home` may mean
hidden, not absent: let the user check with `!`.

git and gh leave the sandbox (for signing and credentials) only as one plain
command per call that starts with `git` or `gh`. `git -C`, `--git-dir`,
`--work-tree`, an env prefix, pipe, redirect, heredoc, `%(…)` format string,
or `$(…)` or a backtick even when quoted, sandboxes the call or prompts.
Instead, `cd /abs/path` in its own call first, and pass messages from a file
(`-F`, gh `--body-file`) or, when plain and short, `-m`. A subagent's `cd`
does not persist: there `git -C` still reads, and it hands commits outside its
cwd back to the caller. A `git config` write works only as such a plain call:
sandboxed it fails with EBUSY, the config files being read-only mounts.

Commit messages: every line at most 72 columns, subject included, except a
URL, trailer or quoted output, which stay whole. git does not wrap `-m`, so
each `-m` is one such line; anything longer goes in a file for `-F`. Don't
hard-wrap gh bodies: GitHub renders their newlines as line breaks.

On a permission denial, report the exact command and rule name, then split it
or switch tools; never reword and retry.

# Plan first

The user's own `?` (not in quotes, code or pasted output) gets an answer
or suggestion, never edits, even "Can we fix…?" or a trailing "ok?"; it
neither gives nor withdraws a yes. In a mixed message, plan the
imperatives.

Before a task's first edit or external write, show a short plan (what,
where, why, commit/push) and wait for a yes, except for `$TMPDIR`
scratch or an ordered small fix already discussed. A yes covers the
plan, what it needs to work, and destructive steps it names. Mention
anything else; don't start it. Subagents inherit the plan.

# Ask first

Unless the user asked for exactly that, ask before destroying anything
that isn't wholly yours from this session and can't be restored from a
commit, the remote or a rebuild (the reflog doesn't count): uncommitted
changes, untracked or ignored files, unpushed commits, remote history
(`push --force`, deleting a remote branch).

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
- If a bare clone has no fetch refspec (no `origin/<branch>`), set
  `remote.origin.fetch` to `+refs/heads/*:refs/remotes/origin/*`, then
  `git fetch origin`.
