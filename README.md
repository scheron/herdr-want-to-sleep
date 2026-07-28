# want-to-sleep

A sleep watch for [herdr](https://herdr.dev). Hand your agents the night's work,
arm it, and go to bed. It waits until herdr reports that none of them is working
any more, then sleeps the Mac and writes down what each one was doing.

```
prefix+shift+s          →  Sleep armed · 3 working · 0 blocked · 1 settled
                           …
                           Every agent has settled — sleep in 2 min.
```

The problem it solves is small and specific: an agent started at midnight might
finish in twenty minutes or in four hours, and you cannot know which. Without
something watching, the choice is to sit and wait, or to leave the machine on
until morning.

## Install

```sh
herdr plugin install scheron/herdr-want-to-sleep
```

Then bind a key in `~/.config/herdr/config.toml` — herdr 0.7 does not bind keys
declared by a plugin:

```toml
[[keys.command]]
key = "prefix+shift+s"
type = "plugin_action"
command = "scheron.want-to-sleep.toggle"
description = "Sleep once every agent has settled"
```

```sh
herdr server reload-config
```

Requires `jq`. macOS only for now — the watch logic is portable, but sleeping
and idle detection are `pmset` and `IOHIDSystem`.

## How it decides

Powering down is easy. Knowing the agents are actually done is not, and this is
where a naive version gets it wrong. Five conditions have to hold at once:

**Nothing is working.** `herdr agent list` reports every agent as `working`,
`idle`, `blocked`, `done`, or `unknown`. This is the signal the plugin exists to
use — an individual agent's own "I finished responding" event cannot tell you
whether it finished or merely stopped to ask a question, and with several agents
running, the first one to go quiet says nothing about the rest.

**It has stayed that way.** Settledness has to hold continuously for the
configured number of minutes. An agent that pauses ten seconds between tool
calls must not read as finished, so a single `working` reading resets the clock
to zero.

**You are away.** `HIDIdleTime` must exceed five minutes, so the machine never
sleeps out from under you while you are sitting at it. The same check runs
during the countdown — touch anything and it cancels.

**Inside the window, if you set one.** An optional `HH:MM-HH:MM` window that
wraps past midnight. Outside it, nothing fires.

**Still armed.** Deleting the state file stops everything within one poll, and
the watch disarms itself after 12 hours so a forgotten arm cannot fire into the
next evening.

## Blocked agents

An agent in `blocked` is waiting on a human. At 3am that answer is not coming,
so by default a blocked agent counts as settled rather than as a reason to keep
the machine awake — and the journal says so loudly, because a blocked agent did
not finish its work:

```markdown
## 2026-07-29 03:34 — sleep

- **done** — Fix the auth redirect loop in the login flow
  - claude · /Users/me/Projects/api
- **blocked** — Migrate the billing tables
  - codex · /Users/me/Projects/billing

> 1 agent(s) were blocked waiting for input. They did not finish.
```

If you would rather stay awake for them, set `blocked = wait`.

## Configuration

`herdr plugin config-dir scheron.want-to-sleep` prints the directory; put a
`config` file there:

```ini
minutes = 20            # how long everything must stay settled
action = sleep          # sleep | shutdown
window =                # e.g. 23:00-09:00, empty means any hour
idle_seconds = 300      # keyboard must be untouched this long
grace_seconds = 120     # cancellable countdown before powering down
blocked = settle        # settle | wait
```

`shutdown` goes through System Events, so it needs no password — but an app
holding an unsaved document can veto it. `sleep` cannot be vetoed, which is why
it is the default.

## From a shell

`herdr/wts.sh` is self-contained and takes the same arguments:

```sh
wts.sh arm                       # use the config defaults
wts.sh arm 45 shutdown           # override for this one night
wts.sh arm 20 sleep 23:00-09:00
wts.sh disarm
wts.sh status
wts.sh journal
```

To arm every night without thinking about it, point a `launchd` calendar job at
`herdr plugin action invoke scheron.want-to-sleep.arm` and give the config a
`window` so a late finish cannot sleep the machine after you sit back down.

## Actions

| Action | Does |
|---|---|
| `scheron.want-to-sleep.toggle` | Arm, or cancel if already armed |
| `scheron.want-to-sleep.arm` | Arm the watch |
| `scheron.want-to-sleep.disarm` | Cancel |
| `scheron.want-to-sleep.status` | Report what the watch currently sees |

## Limitations

- macOS only. Linux needs a different sleep call and a different idle source.
- Agents herdr reports as `unknown` are not counted as working. A pane herdr
  cannot classify will not hold the machine awake.
- The countdown cancels on keyboard input, not on an agent waking back up. If an
  agent starts working during those two minutes, it is interrupted by the sleep.

## License

MIT
