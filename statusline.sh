#!/usr/bin/env bash
# Claude Code status line
#
#   󰧑 my-project   dev●  Opus 5 high   43%  󰓅 33% 2h47m
#
# Groups are separated by weight and colour rather than drawn rules: a dim glyph
# followed by a bold value, twice the gap between groups. A divider glyph is one
# more mark competing for attention in a line that is only read peripherally.
#
# Values are deliberately unpadded. Padding them to a fixed width put a second
# space between every icon and its number, and a gap inside a pair reads worse
# than the tail of the line moving one column when a value crosses 10% or 100%.
#
# Glyphs are \u escapes, not pasted characters: these codepoints live in the
# Private Use Area and do not survive every copy, paste and editor round trip.
# CC_STATUSLINE_ICONS=0 falls back to text labels.
#
# Speed is a correctness concern, not a nicety. Claude Code re-renders on every
# message and tool call, debounces at 300ms, and *cancels an in-flight script*
# when the next update lands -- so a slow script does not render late, it never
# renders at all and the line sits there stale. Budget is single-digit ms, which
# rules out a subprocess per field: stdin is read by a builtin, all JSON comes
# from one jq call, the branch is parsed out of .git/HEAD rather than asked of
# git, and the worktree-scanning dirty check is cached.

if [[ ${CC_STATUSLINE_ICONS:-1} == 1 ]]; then
  I_GIT=$'\uF418'            # oct-git-branch
  I_CTX_LOW=$'\U000F1632'   # md-database-outline: hollow, room left
  I_CTX_HIGH=$'\U000F01BC'  # md-database: filled. Same height, so no jump.
  # An 8-step pie that fills as the limit is consumed. md-circle-slice is the only
  # escalating family in this font whose members are all the same height (1200
  # units): md-speedometer runs 1044/1142/1044 and md-gauge 1200/1204/1720, so the
  # icon would visibly grow and shrink as the number crossed a threshold.
  CTX_SLICES=($'\U000F0A9E' $'\U000F0A9F' $'\U000F0AA0' $'\U000F0AA1' \
              $'\U000F0AA2' $'\U000F0AA3' $'\U000F0AA4' $'\U000F0AA5')
  I_WEEK=$'\U000F00ED'       # md-calendar
  I_DIRTY=$'●'               # uncommitted changes in the worktree
else
  I_GIT='git'; I_CTX_LOW='ctx'; I_CTX_HIGH='ctx'; CTX_SLICES=(5h 5h 5h 5h 5h 5h 5h 5h)
  I_WEEK='7d'; I_DIRTY='*'
fi

IFS= read -r -d '' input

# The context percentage from stdin is authoritative: Claude Code reports the real
# window, including 1M for extended-context models. Deriving it instead from the
# model id plus a reverse read of the transcript was both slower and wrong -- an
# unrecognised id fell back to 200k and pinned a 36%-full 1M session at 100%.
IFS=$'\t' read -r cwd model effort ctx_pct ctx_in ctx_max five_pct five_reset seven_pct < <(
  jq -r '[
    (.workspace.current_dir // .cwd // ""),
    (.model.display_name // ""),
    (.effort.level // ""),
    (.context_window.used_percentage // ""),
    (.context_window.total_input_tokens // 0),
    (.context_window.context_window_size // 0),
    (.rate_limits.five_hour.used_percentage // ""),
    (.rate_limits.five_hour.resets_at // ""),
    (.rate_limits.seven_day.used_percentage // "")
  ] | @tsv' <<< "$input"
)

bold=$'\033[1m'
teal=$'\033[38;2;122;168;159m'
rose=$'\033[38;2;228;104;118m'
amber=$'\033[38;2;230;195;132m'
red=$'\033[38;2;228;104;118m'
fg=$'\033[38;2;214;217;223m'
dim=$'\033[38;2;104;108;116m'
faint=$'\033[38;2;74;78;86m'
reset=$'\033[0m'

# Colour is spent only once a number deserves attention. A calm session should read
# as calm; colour used to decorate the healthy state has nothing left to say when
# something is actually wrong. Assigns to a global because `x=$(tone …)` forks a
# subshell per call, and a fork is most of this script's budget.
# Thresholds are per metric, because the two numbers mean different things: filling
# the context window is the thing that actually degrades a session, so it escalates
# early, while the five-hour limit is only worth reacting to near the top.
tone() {
  local pct=$1 warn=${2:-50} crit=${3:-80}
  if   (( pct >= crit )); then R_tone=$red
  elif (( pct >= warn )); then R_tone=$amber
  else                         R_tone=$fg
  fi
  local idx=$(( (pct * 8 + 99) / 100 ))       # 1..8, rounded up so 1% is not empty
  (( idx < 1 )) && idx=1
  (( idx > 8 )) && idx=8
  R_gauge=${CTX_SLICES[idx-1]}
}

sep="  "
out="${bold}${teal}${cwd##*/}${reset}"

# --- branch read straight out of .git, because git symbolic-ref costs ~16ms ----
# Walks up like git does: the status line's cwd is often a subdirectory of the
# repo, where .git does not exist, and checking only $cwd drops the segment.
gitdir=''
probe=$cwd
while [[ -n $probe && $probe != / ]]; do
  if [[ -d $probe/.git ]]; then
    gitdir="$probe/.git"; break
  elif [[ -f $probe/.git ]]; then         # worktree or submodule: a gitdir pointer
    read -r _ gitdir < "$probe/.git"
    [[ $gitdir != /* ]] && gitdir="$probe/$gitdir"
    break
  fi
  probe=${probe%/*}
done

if [[ -n $gitdir && -r $gitdir/HEAD ]]; then
  read -r head < "$gitdir/HEAD"
  if [[ $head == ref:* ]]; then branch="${head##*/}"; else branch="${head:0:7}"; fi

  # The dirty check is the one unavoidable worktree scan (~18ms in a large repo),
  # so it is cached for a few seconds. A marker that is a moment stale beats a
  # status line that gets cancelled before it paints.
  now=${EPOCHSECONDS:-$(date +%s)}
  stamp="${TMPDIR:-/tmp}/.ccstatus-${cwd//\//_}"
  cached_at=0 cached=''
  [[ -r $stamp ]] && read -r cached_at cached < "$stamp"
  if (( now - cached_at >= 3 )); then
    if git -C "$cwd" diff --quiet --ignore-submodules 2>/dev/null \
       && git -C "$cwd" diff --cached --quiet --ignore-submodules 2>/dev/null; then
      cached=clean
    else
      cached=dirty
    fi
    printf '%s %s\n' "$now" "$cached" > "$stamp" 2>/dev/null
  fi

  out+="${sep}${dim}${I_GIT}${reset} ${bold}${rose}${branch}${reset}"
  [[ $cached == dirty ]] && out+=" ${amber}${I_DIRTY}${reset}"
fi

# --- model: the lightest thing on the line ------------------------------------
# It changes once a session, so it must not compete with numbers that change
# constantly; "(1M context)" is redundant beside a percentage of that window.
if [[ -n $model ]]; then
  display="${model% (*}"
  [[ -n $effort ]] && display+=" $effort"
  out+="${sep}${faint}${display}${reset}"
fi

# --- context ------------------------------------------------------------------
# used_percentage can be null early in a session; the token counts come from the
# same API response, so fall back to those.
if [[ -z $ctx_pct && $ctx_max =~ ^[0-9]+$ ]] && (( ctx_max > 0 )); then
  ctx_pct=$(( ctx_in * 100 / ctx_max ))
fi
if [[ $ctx_pct =~ ^[0-9] ]]; then
  ctx_int=${ctx_pct%%.*}
  tone "$ctx_int" 25 50
  # The jar fills at the same point the colour first warns, so glyph and colour
  # never disagree about which side of a threshold you are on.
  ctx_icon=$I_CTX_LOW; (( ctx_int >= 25 )) && ctx_icon=$I_CTX_HIGH
  out+="${sep}${R_tone}${ctx_icon}${reset} ${bold}${R_tone}${ctx_int}%${reset}"
fi

# --- five hour limit, with time until it resets --------------------------------
# rate_limits only appears after the first API response of a session, so a freshly
# opened window has none and the segment used to vanish entirely -- which reads as
# "no usage" rather than "not known yet". The window is account-wide and clock-based,
# so the previous session's figure is still meaningful: it is cached and shown faint
# and unbolded until live data replaces it.
limits="${TMPDIR:-/tmp}/.ccstatus-limits"
now=${EPOCHSECONDS:-$(date +%s)}
stale=0
if [[ $five_pct =~ ^[0-9] ]]; then
  printf '%s %s %s\n' "${five_pct%%.*}" "${five_reset:-0}" "${seven_pct%%.*}" > "$limits" 2>/dev/null
elif [[ -r $limits ]]; then
  read -r cached_five cached_reset cached_seven < "$limits"
  # Only trust it while the window it describes has not already rolled over.
  if [[ $cached_reset =~ ^[0-9]+$ ]] && (( cached_reset > now )); then
    five_pct=$cached_five five_reset=$cached_reset stale=1
    [[ -z $seven_pct && $cached_seven =~ ^[0-9]+$ ]] && seven_pct=$cached_seven
  fi
fi

if [[ $five_pct =~ ^[0-9] ]]; then
  five_int=${five_pct%%.*}
  tone "$five_int"
  if (( stale )); then
    out+="${sep}${faint}${R_gauge} ${five_int}%${reset}"
  else
    out+="${sep}${R_tone}${R_gauge}${reset} ${bold}${R_tone}${five_int}%${reset}"
  fi
  if [[ $five_reset =~ ^[0-9]+$ ]]; then
    left=$(( five_reset - now ))
    if (( left > 0 )); then
      if (( left >= 3600 )); then
        printf -v left_txt '%dh%02dm' $(( left / 3600 )) $(( (left % 3600) / 60 ))
      else
        left_txt="$(( left / 60 ))m"
      fi
      out+=" ${faint}${left_txt}${reset}"
    fi
  fi
else
  # Never seen a figure on this machine: hold the slot so the line does not
  # reflow the moment the first response lands.
  tone 0
  out+="${sep}${faint}${R_gauge} --%${reset}"
fi

# --- weekly limit: absent until it is worth knowing ---------------------------
if [[ $seven_pct =~ ^[0-9] ]]; then
  seven_int=${seven_pct%%.*}
  if (( seven_int >= 40 )); then
    tone "$seven_int"
    out+="${sep}${dim}${I_WEEK}${reset} ${bold}${R_tone}${seven_int}%${reset}"
  fi
fi

printf '%s' "$out"
