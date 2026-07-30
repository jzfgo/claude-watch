# claude-watch

![claude-watch statusline](screenshot.png)

## Installation

**1. Copy the scripts**

```sh
cp fetch-usage.sh ~/.claude/fetch-usage.sh
cp statusline-command.sh ~/.claude/statusline-command.sh
chmod +x ~/.claude/fetch-usage.sh ~/.claude/statusline-command.sh
```

**2. Merge `settings.json` into `~/.claude/settings.json`**

Add the `statusLine` and `hooks` blocks from `settings.json` into your existing `~/.claude/settings.json`. If you don't have one yet, copy it directly:

```sh
cp settings.json ~/.claude/settings.json
```

**3. Trigger an initial fetch (optional)**

```sh
bash ~/.claude/fetch-usage.sh
```

The usage cache will otherwise populate automatically on the next tool call or Claude response.

## How it works

- **`statusline-command.sh`** — reads the JSON piped by Claude Code and renders two lines. Line 1: platform icon + hostname, the current `zmx` session (only when zmx is installed and `$ZMX_SESSION` is set), then repo, worktree, branch and subdirectory, each with its own Nerd Font glyph. Segments run outermost to innermost, and the optional ones sit at the tail so the leading `repo • worktree` keeps a stable shape:

  - **repo** — the main checkout's name, so it does not change as you move between worktrees or into subdirectories. Its glyph follows the SCM: git, subversion, or a generic marker for mercurial, jujutsu, fossil and bazaar, which have no logo in Nerd Fonts. Outside a repo the segment falls back to a plain folder glyph and the current directory's name.
  - **worktree** — `main` for the main checkout, otherwise the worktree's directory name. Git only.
  - **branch** — shown only when it differs from the worktree name, so the same word never appears twice. Falls back to the short commit hash on a detached HEAD. Git only.
  - **subdirectory** — the innermost component of the path below the repo root, omitted at the root. Only the last component, so deep paths do not stretch the line.

  Line 2: model, usage stats and context window. Every segment is optional and separators collapse when one is missing.
- **`fetch-usage.sh`** — reads the OAuth token from `~/.claude/.credentials.json`, caches it in `/tmp/.claude_token_cache` for 15 minutes, hits the `/oauth/usage` endpoint (3s timeout), and writes results to `/tmp/.claude_usage_cache`. On failure the stale cache is preserved.
- **`settings.json`** — wires up the statusline command and triggers `fetch-usage.sh` in the background on `PreToolUse` and `Stop` hooks.

## Dependencies

- `jq`
- `curl`
- `git` (optional, for branch/worktree display)
- `zmx` (optional, for session name display)
- [Nerd Fonts](https://www.nerdfonts.com/) (for the platform, repo, worktree, branch and folder icons)

Other SCMs are detected by their marker directory (`.hg`, `.svn`, `.jj`, `.fslckout`, `.bzr`), so nothing needs to be installed for the repo segment to appear.

Works on macOS and Linux — the reset countdowns detect BSD vs GNU `date` at runtime.
