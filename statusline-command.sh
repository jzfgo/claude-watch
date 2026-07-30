#!/bin/sh
input=$(cat)

# --- icons ---
# Written as \NNN octal UTF-8 escapes, never as literal glyphs: most of these live
# in the Private Use Area (U+E000-U+F8FF) and get silently stripped by editors,
# linters and anything that sanitises unknown codepoints. Octal (not \xHH) because
# only octal is POSIX: dash — /bin/sh on Debian and Ubuntu — prints "\xe2\xa7\x97"
# literally, so hex escapes would show as raw text on the platforms we support.
ICON_ZMX=$(printf '\342\247\227')          # U+29D7  matches [env_var.ZMX_SESSION] in starship.toml
ICON_GIT=$(printf '\363\260\212\242')      # U+F02A2 nf-md-git
ICON_SVN=$(printf '\356\242\265')          # U+E8B5  nf-dev-subversion
# Nerd Fonts ships logos for git and subversion only — there is no mercurial,
# fossil, jujutsu or bazaar glyph in the set, so those share a generic marker.
ICON_SCM=$(printf '\363\260\263\217')      # U+F0CCF nf-md-source_repository
ICON_FOLDER=$(printf '\363\260\211\213')   # U+F024B nf-md-folder
ICON_WORKTREE=$(printf '\363\260\231\205') # U+F0645 nf-md-file_tree
ICON_BRANCH=$(printf '\356\202\240')       # U+E0A0  matches [git_branch].symbol in starship.toml

# --- platform icon + hostname ---
os_type=$(uname -s 2>/dev/null)
case "$os_type" in
  Darwin)  platform_icon=$(printf '\357\205\271') ;;   # U+F179 nf-fa-apple
  Linux)
    if [ -f "/system/build.prop" ] || [ -n "$ANDROID_ROOT" ]; then
      platform_icon=$(printf '\357\205\273')            # U+F17B nf-fa-android
    else
      platform_icon=$(printf '\357\205\274')            # U+F17C nf-fa-linux
    fi
    ;;
  MINGW*|MSYS*|CYGWIN*) platform_icon=$(printf '\357\205\272') ;;  # U+F17A nf-fa-windows
  *)                     platform_icon=$(printf '\357\204\211') ;;  # U+F109 nf-fa-laptop
esac
host_name=$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo "unknown")

# --- zmx session (only when zmx is installed *and* we are inside a session) ---
zmx_session=""
if command -v zmx > /dev/null 2>&1 && [ -n "$ZMX_SESSION" ]; then
  zmx_session="$ZMX_SESSION"
fi

# --- model ---
model=$(echo "$input" | jq -r '.model.display_name // ""')

# --- leading segment: the repo, or a plain directory when outside one ---
# Name and icon start as the plain-directory case; whichever SCM block matches
# below swaps in the project name and that SCM's glyph. Keeping the folder glyph
# here is what lets it mean "subdirectory" in the trailing segment.
dir=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
dir_name=$(basename "$dir")
dir_icon="$ICON_FOLDER"
subdir=""

# --- git branch + worktree name ---
branch=""
worktree_name=""
if git -C "$dir" rev-parse --git-dir > /dev/null 2>&1; then
  dir_icon="$ICON_GIT"

  # Path from the worktree root to the cwd, with a trailing slash and empty at the
  # root — so "are we in a subdirectory" needs no path arithmetic, and git has
  # already resolved symlinks that a manual prefix strip would trip over.
  prefix=$(git -C "$dir" rev-parse --show-prefix 2>/dev/null)
  [ -n "$prefix" ] && subdir=$(basename "$prefix")

  branch=$(git -C "$dir" symbolic-ref --short HEAD 2>/dev/null || git -C "$dir" rev-parse --short HEAD 2>/dev/null)

  # Resolve the canonical path of the current worktree dir
  current_worktree=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)

  if [ -n "$current_worktree" ]; then
    # Find the main worktree path (always listed first by git worktree list)
    # sub() rather than $2 so a repo path containing spaces is not truncated
    main_worktree=$(git -C "$dir" worktree list --porcelain 2>/dev/null | awk '/^worktree / { sub(/^worktree /, ""); print; exit }')

    if [ -n "$main_worktree" ]; then
      main_basename=$(basename "$main_worktree")
      current_basename=$(basename "$current_worktree")

      # The folder segment names the *project*, never the cwd. Inside a worktree
      # the cwd basename is the worktree name, which would duplicate the next
      # segment and hide which repo we are actually in.
      dir_name="$main_basename"

      if [ "$current_worktree" = "$main_worktree" ]; then
        # We are on the main worktree — name it "main"
        worktree_name="main"
      else
        # Strip the main repo basename prefix and the leading dot/separator
        # e.g. "carroquesi.feat-list-route" → "feat-list-route"
        # Inner quotes keep glob characters in the repo name literal
        suffix="${current_basename#"${main_basename}."}"
        if [ "$suffix" != "$current_basename" ]; then
          worktree_name="$suffix"
        else
          worktree_name="$current_basename"
        fi
      fi
    fi
  fi
else
  # --- other SCMs: walk up for a marker directory, innermost wins ---
  # Detection is a filesystem test rather than a call to each tool, so it costs one
  # stat per level and works even when the SCM itself is not installed. Only the
  # repo name and subdirectory are derived here; branch and worktree stay git-only.
  probe="$dir"
  scm=""
  # "." terminates too: dirname "." is "." forever, so a relative cwd would spin here.
  while [ -n "$probe" ] && [ "$probe" != "/" ] && [ "$probe" != "." ] && [ -z "$scm" ]; do
    if [ -d "$probe/.hg" ]; then
      scm="hg"
    elif [ -d "$probe/.svn" ]; then
      scm="svn"
    elif [ -d "$probe/.jj" ]; then
      scm="jj"
    elif [ -e "$probe/.fslckout" ] || [ -e "$probe/_FOSSIL_" ]; then
      scm="fossil"
    elif [ -d "$probe/.bzr" ]; then
      scm="bzr"
    else
      probe=$(dirname "$probe")
    fi
  done

  if [ -n "$scm" ]; then
    dir_name=$(basename "$probe")
    case "$scm" in
      svn) dir_icon="$ICON_SVN" ;;
      *) dir_icon="$ICON_SCM" ;;
    esac
    # Same trailing-segment rule as git, minus git's symlink normalisation: empty
    # when the cwd *is* the repo root, otherwise the innermost component.
    rel="${dir#"$probe"}"
    [ -n "$rel" ] && [ "$rel" != "$dir" ] && subdir=$(basename "$rel")
  fi
fi

# --- usage stats (5h / 7d) from cache ---
CACHE_FILE="/tmp/.claude_usage_cache"
five_h=""
seven_d=""
five_h_reset=""
seven_d_reset=""

if [ -f "$CACHE_FILE" ]; then
  five_h=$(sed -n '1p' "$CACHE_FILE")
  seven_d=$(sed -n '2p' "$CACHE_FILE")
  five_h_reset=$(sed -n '3p' "$CACHE_FILE")
  seven_d_reset=$(sed -n '4p' "$CACHE_FILE")
else
  bash ~/.claude/fetch-usage.sh > /dev/null 2>&1 &
fi

# --- compute_delta: given a raw ISO timestamp, returns human-readable time until reset ---
compute_delta() {
  raw="$1"
  # macOS/BSD date needs an exact format string, so strip fractional seconds and
  # the UTC offset first and parse the remainder as UTC.
  clean=$(echo "$raw" | sed 's/\.[0-9]*//' | sed 's/[+-][0-9][0-9]:[0-9][0-9]$//' | sed 's/Z$//')
  reset_epoch=$(TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$clean" "+%s" 2>/dev/null)
  if [ -z "$reset_epoch" ] && date --version > /dev/null 2>&1; then
    # GNU/Linux date: parses full ISO-8601 natively, so feed it the *raw* string
    # and let it honour the embedded "+00:00" offset instead of guessing a zone.
    # Gated on --version, which only GNU date has: on BSD, -d does not parse a
    # date at all, it *sets the kernel DST value*. Harmless as a normal user
    # because it fails, but as root a malformed timestamp would change system
    # state, so never reach that flag on a platform where it means something else.
    reset_epoch=$(date -d "$raw" "+%s" 2>/dev/null)
  fi
  if [ -z "$reset_epoch" ]; then return; fi
  now_epoch=$(date -u "+%s")
  diff=$(( reset_epoch - now_epoch ))
  if [ "$diff" -le 0 ]; then echo "now"; return; fi
  days=$(( diff / 86400 ))
  hours=$(( (diff % 86400) / 3600 ))
  minutes=$(( (diff % 3600) / 60 ))
  if [ "$days" -gt 0 ]; then
    echo "${days}d ${hours}h"
  elif [ "$hours" -gt 0 ]; then
    echo "${hours}h ${minutes}m"
  else
    echo "${minutes}m"
  fi
}

# --- context window ---
used=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
ctx_str=""
ctx_tokens_str=""
if [ -n "$used" ]; then
  used_int=$(printf "%.0f" "$used")
  ctx_str="${used_int}%"
  ctx_used=$(echo "$input" | jq -r '(.context_window.current_usage.cache_read_input_tokens + .context_window.current_usage.cache_creation_input_tokens + .context_window.current_usage.input_tokens + .context_window.current_usage.output_tokens) // empty' 2>/dev/null)
  ctx_total=$(echo "$input" | jq -r '.context_window.context_window_size // empty' 2>/dev/null)
  if [ -n "$ctx_used" ] && [ -n "$ctx_total" ]; then
    ctx_used_k=$(( ctx_used / 1000 ))
    ctx_total_k=$(( ctx_total / 1000 ))
    ctx_tokens_str="${ctx_used_k}k/${ctx_total_k}k"
  fi
fi

# --- assemble output ---
SEP="\033[90m • \033[0m"
BAR="\033[90m | \033[0m"

# line 1:  host [• zmx]  |  repo [• worktree] [• branch] [• subdir]
# Segments run outermost to innermost, and every optional one sits at the tail, so
# the leading "repo • worktree" keeps the same shape and the line only grows right.
printf "%s " "$platform_icon"
printf "\033[38;2;156;162;175m%s\033[0m" "$host_name"
if [ -n "$zmx_session" ]; then
  printf "%b" "$SEP"
  printf "\033[38;2;232;121;249m%s %s\033[0m" "$ICON_ZMX" "$zmx_session"
fi
if [ -n "$dir_name" ]; then
  printf "%b" "$BAR"
  printf "\033[1m\033[38;2;76;208;222m%s %s\033[22m\033[0m" "$dir_icon" "$dir_name"
fi
if [ -n "$worktree_name" ]; then
  printf "%b" "$SEP"
  printf "\033[1m\033[38;2;255;185;0m%s %s\033[22m\033[0m" "$ICON_WORKTREE" "$worktree_name"
fi
if [ -n "$branch" ] && [ "$branch" != "$worktree_name" ]; then
  printf "%b" "$SEP"
  printf "\033[1m\033[38;2;192;103;222m%s %s\033[22m\033[0m" "$ICON_BRANCH" "$branch"
fi
if [ -n "$subdir" ]; then
  printf "%b" "$SEP"
  printf "\033[1m\033[38;2;76;208;222m%s %s\033[22m\033[0m" "$ICON_FOLDER" "$subdir"
fi

# line 2: model | usage (5h • 7d) | ctx
# Every segment is optional, so track whether anything has been emitted yet
# instead of hardcoding separators — otherwise a missing cache or model leaves
# a dangling " | " at the start of the line.
printf "\n"
line2_empty=1
usage_started=0

if [ -n "$model" ]; then
  printf "\033[38;5;208m\033[1m%s\033[22m\033[0m" "$model"
  line2_empty=0
fi
if [ -n "$five_h" ]; then
  [ "$line2_empty" -eq 0 ] && printf "%b" "$BAR"
  printf "\033[38;2;156;162;175m5h %s%%\033[0m" "$five_h"
  if [ -n "$five_h_reset" ]; then
    delta=$(compute_delta "$five_h_reset")
    [ -n "$delta" ] && printf " \033[2m\033[38;2;156;162;175m(%s)\033[0m" "$delta"
  fi
  line2_empty=0
  usage_started=1
fi
if [ -n "$seven_d" ]; then
  if [ "$usage_started" -eq 1 ]; then
    printf "%b" "$SEP"
  elif [ "$line2_empty" -eq 0 ]; then
    printf "%b" "$BAR"
  fi
  printf "\033[38;2;156;162;175m7d %s%%\033[0m" "$seven_d"
  if [ -n "$seven_d_reset" ]; then
    delta=$(compute_delta "$seven_d_reset")
    [ -n "$delta" ] && printf " \033[2m\033[38;2;156;162;175m(%s)\033[0m" "$delta"
  fi
  line2_empty=0
fi
if [ -n "$ctx_str" ]; then
  [ "$line2_empty" -eq 0 ] && printf "%b" "$BAR"
  printf "\033[38;2;156;162;175mctx %s\033[0m" "$ctx_str"
  [ -n "$ctx_tokens_str" ] && printf " \033[2m\033[38;2;156;162;175m(%s)\033[0m" "$ctx_tokens_str"
  line2_empty=0
fi
