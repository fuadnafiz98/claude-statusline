# claude-statusline

A status line for [Claude Code](https://claude.com/claude-code): directory, branch,
model, context window, and rate limits. One file, no dependencies beyond `jq`, and it
renders in about 12 ms.

```
my-project   dev  Opus 5 high  󰆼 36%  󰪠 28% 2h34m
```

## Previews

Colour and glyph escalate together, so a glance is enough.

```
calm                my-project   dev  Opus 5 high  󱘲 12%  󰪟 22% 2h34m
context warning     my-project   dev  Opus 5 high  󰆼 34%  󰪟 22% 2h34m
context critical    my-project   dev  Opus 5 high  󰆼 63%  󰪟 22% 2h34m
limit running out   my-project   dev  Opus 5 high  󰆼 63%  󰪤 87% 2h34m
weekly limit shown  my-project   dev  Opus 5 high  󰆼 63%  󰪤 87% 2h34m  󰃭 55%
uncommitted changes my-project   main ●  Opus 5 high  󱘲 12%  󰪟 22% 2h34m
limits not known yet  my-project   main  Opus 5 high  󱘲 12%  󰪞 --%
```

Without a Nerd Font (`CC_STATUSLINE_ICONS=0`):

```
my-project  git main *  Opus 5 high  ctx 12%  5h 22% 2h34m
```

## Install

```sh
git clone https://github.com/fuadnafiz98/claude-statusline
cd claude-statusline
./install.sh
```

The installer symlinks `statusline.sh` into `~/.claude/`, points `settings.json` at it
with `refreshInterval: 1`, backs up anything it replaces, and prints a sample render.
Because it is a symlink, edits in the checkout take effect immediately.

To do it by hand, add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash /path/to/claude-statusline/statusline.sh",
    "refreshInterval": 1
  }
}
```

`refreshInterval` keeps the reset countdown moving while the session is idle. One
second is the documented minimum.

## What it shows

| Segment | |
| --- | --- |
| directory | basename of the session's working directory |
| ` branch` | found by walking up for `.git`, so subdirectories of a monorepo still show it |
| `●` | uncommitted changes in the worktree |
| model | dimmest tier: it changes once a session, so it should not compete with numbers that change constantly |
| `󰆼 nn%` | context window used. The jar is hollow below 25%, filled above |
| `󰪠 nn% 2h34m` | five-hour limit and time until it resets. An eight-step pie fills as it is consumed |
| `󰃭 nn%` | weekly limit, shown only past 40% |

### Colour

Thresholds are per metric. Filling the context window is what degrades a session, so
it escalates early; the rate limits only matter near the top.

| | neutral | amber | red |
| --- | --- | --- | --- |
| context | below 25% | 25–49% | 50% and up |
| five-hour, weekly | below 50% | 50–79% | 80% and up |

Nothing is coloured until it deserves attention, so a calm session reads as calm.

## Configuration

| Variable | Effect |
| --- | --- |
| `CC_STATUSLINE_ICONS=0` | text labels instead of Nerd Font glyphs |

Colours, thresholds and glyphs are named values in the first 60 lines of
`statusline.sh`. It is one file and meant to be edited.

## Requirements

- `bash` 4 or newer — macOS ships 3.2, so `brew install bash`
- `jq`
- a Nerd Font, unless you set `CC_STATUSLINE_ICONS=0`

## Design notes

**The context percentage comes from Claude Code, not from guesswork.** Scripts that map
a model id to a window size and read token counts out of the transcript get this wrong
as soon as a new model ships: an unrecognised id falls back to 200k, so a 1M-window
session at 338k reports 169%, clamped to 100%. Claude Code already provides
`context_window.used_percentage` and `context_window_size` on stdin.

**Speed is correctness, not polish.** Claude Code cancels an in-flight status line when
the next update arrives, so a slow script does not paint late — during active tool use
it often does not paint at all, and the line sits stale. This one reads stdin with a
builtin, makes a single `jq` call, parses the branch out of `.git/HEAD` instead of
spawning `git`, and caches the one unavoidable worktree scan. ~12 ms against ~125 ms
for the same information gathered the obvious way.

**Rate limits survive a fresh window.** `rate_limits` only appears after the first API
response of a session, so a new window has none. Hiding the segment then reads as "no
usage" rather than "not known yet", so the last figure is cached and shown faint until
live data replaces it — and only while the window it describes has not already reset.

**Glyphs are chosen by measured size.** In a `Mono` build every glyph is squeezed into
one cell, and families are drawn to different optical sizes. `md-speedometer` runs
1044/1142/1044 units and `md-gauge` 1200/1204/1720, so an icon built from either would
grow and shrink as a value crossed a threshold. The ramp uses `md-circle-slice`, whose
eight members are all 1200. Everything on the line sits between 1200 and 1402 with no
state-dependent size change.

**Glyphs are written as escapes.** `$''` rather than a pasted character: these
codepoints live in the Private Use Area and a paste can arrive as a zero-length string,
leaving an icon variable silently empty.

## License

MIT
