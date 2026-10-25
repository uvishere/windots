# herdr

Adapted from [Tolsee's herdr setup](https://github.com/Tolsee/dotfiles/tree/main/herdr) for
Windows, PowerShell and JIRA. `Setup.ps1` links `config.toml` to
`%APPDATA%\herdr\config.toml`; the scripts run from this folder, so the repo must live at
`~\pageup\windots`. After editing the config, `prefix+r` reloads it.

## Task loop

One ticket, one worktree workspace, one Claude. `prefix` is Ctrl+B.

| Key | Action |
| --- | --- |
| `prefix+t` | Start a task from a JIRA link, key or branch name (suggested from the clipboard). A bare key asks for a short description and branches `feat/PE-123-description` from origin's default branch; a ticket that already has a worktree reopens it. Claude starts with `/ticket PE-123`. |
| `prefix+o` | Links for the focused task: ticket, PR, changed files, checks, each failing check, the branch (compare view before a PR). Enter opens, ctrl-y copies. |

Every task needs a JIRA key. Settings, read from the environment herdr was started with:

- `HERDR_TASK_PROJECT_ROOTS`: semicolon-separated folders whose child repositories the project
  picker offers (default `~\pageup`).
- `HERDR_TASK_JIRA_SITE`: JIRA site for links built from a bare key (default PageUp's).

## Moving around

| Key | Action |
| --- | --- |
| `prefix+a` / `prefix+shift+a` | Next / previous agent |
| `prefix+alt+1..9` | Focus agent by sidebar index |
| `prefix+shift+o` | Open the latest notification target |
| `prefix+;` | Last pane |
| `prefix+(` / `prefix+)` | Previous / next workspace |
| `prefix+g` | Search across workspaces, tabs and panes |
| `prefix+w` | Pick a workspace |
| `prefix+shift+g` / `prefix+alt+x` | New / remove worktree |
| `prefix+v` or `prefix+%` / `prefix+minus` or `prefix+"` | Split vertically / horizontally |
| `prefix+r` / `prefix+shift+r` | Reload config / resize mode (swapped from herdr's defaults) |
| `prefix+shift+q` | Close workspace (herdr's default is `prefix+shift+d`) |
| `prefix+?` | Show the active keymap |

## Status bar

`herdr-status.ps1` fills the right of the tab bar every 20 seconds: agents waiting for you
across the session, then the focused branch's PR (open, draft, merged or closed), its review
decision and CI rollup, in Nerd Font Octicons. It needs `gh` logged in.

## Not ported yet

From Tolsee's setup: review (`prefix+y`), ship (`prefix+u`), the PR picker (`prefix+m`), the
project sessionizer (`prefix+f`), pruning merged worktrees (`prefix+alt+t`), the
worktree-cleanup and link-handler plugins, and `check-keymap`.
