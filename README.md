# want-to-sleep

<p align="center">
  <a href="#install">install</a> · <a href="#the-sidebar">sidebar</a> · <a href="#how-it-decides">how it decides</a> · <a href="#blocked-agents">blocked agents</a> · <a href="#configuration">config</a> · <a href="#limitations">limitations</a>
</p>

A sleep watch for [herdr](https://herdr.dev). Hand your agents the night's work,
start the watch, and go to bed. It waits until none of them is working any more,
sleeps the Mac, and writes down what each one was doing.

An agent started at midnight might finish in twenty minutes or in four hours,
and you cannot know which. Without something watching, the choice is to sit and
wait, or to leave the machine on until morning.

## Install

```sh
herdr plugin install scheron/herdr-want-to-sleep
```

Bind a key in `~/.config/herdr/config.toml` — herdr 0.7 does not bind keys
declared by a plugin — then `herdr server reload-config`:

```toml
[[keys.command]]
key = "prefix+shift+s"
type = "plugin_action"
command = "scheron.want-to-sleep.toggle"
description = "want-to-sleep sidebar"
```

Needs `jq`. macOS only: sleeping and idle detection are `pmset` and
`IOHIDSystem`.

## The sidebar

The key toggles a split pane with the live watch state, every agent herdr can
see, and the rules it is applying.

| Key | Does |
|---|---|
| `a` | Start watching |
| `c` | Stop watching, leave the pane open |
| `-` `+` | Quiet needed before sleeping, in 5 min steps |
| `q` | Stop watching and close the pane |
| `x` | Close the pane, **keep watching** |

The watcher is a detached process, so `x` is the normal way out: close the pane,
reclaim the space, go to bed. Only `q` and `c` stop it.

## How it decides

Powering down is easy; knowing the agents are done is not. Four things have to
hold at once.

**Nothing is working.** `herdr agent list` reports each agent as `working`,
`idle`, `blocked`, `done` or `unknown`. This is the signal the plugin exists to
use — an agent's own "finished responding" event cannot tell you whether it
finished or merely stopped to ask a question, and with several agents running,
the first to go quiet says nothing about the rest.

**It has stayed that way.** The quiet must hold unbroken for the configured
minutes. An agent pausing ten seconds between tool calls must not read as
finished, so a single `working` reading resets the timer to zero.

**You are away.** `HIDIdleTime` must exceed five minutes, so the machine never
sleeps out from under you. The same check runs during the two-minute countdown —
touch anything and it cancels.

**Inside the window, if you set one.** An optional `HH:MM-HH:MM` that wraps past
midnight.

The watch also disarms itself after 12 hours, so a forgotten start cannot fire
into the next evening.

## Blocked agents

A `blocked` agent is waiting on a human. At 3am that answer is not coming, so by
default it counts as quiet rather than as a reason to keep the machine awake —
and the journal says so, because a blocked agent did not finish its work:

```markdown
## 2026-07-29 03:34 — sleep

- **done** — Fix the auth redirect loop in the login flow
  - claude · /Users/me/Projects/api
- **blocked** — Migrate the billing tables
  - codex · /Users/me/Projects/billing

> 1 agent(s) were blocked waiting for input. They did not finish.
```

Set `blocked = wait` to stay awake for them instead.

## Configuration

`herdr plugin config-dir scheron.want-to-sleep` prints the directory; put a
`config` file there.

| Key | Default | Means |
|---|---|---|
| `minutes` | `15` | How long the quiet must hold |
| `action` | `sleep` | `sleep` or `shutdown` |
| `window` | *(empty)* | e.g. `23:00-09:00`, empty means any hour |
| `idle_seconds` | `300` | Keyboard untouched this long |
| `grace_seconds` | `120` | Cancellable countdown |
| `blocked` | `settle` | `settle` or `wait` |
| `placement` | `split` | `split`, `tab`, `overlay`, `zoomed` |
| `direction` | `right` | Split side |

`shutdown` is deliberately not reachable from the sidebar: it is rarer and
riskier than sleep, and a one-key toggle beside the others invited mistakes. It
goes through System Events, so it needs no password — but an app holding an
unsaved document can veto it. Sleep cannot be vetoed.

## From a shell

`herdr/wts.sh` is self-contained and shares the plugin's state, so the CLI and
the sidebar always agree:

```sh
wts.sh arm 20 sleep 23:00-09:00
wts.sh disarm
wts.sh status
wts.sh journal
```

To start it every night, point a `launchd` calendar job at
`herdr plugin action invoke scheron.want-to-sleep.arm`, and set a `window` so a
late finish cannot sleep the machine after you sit back down.

## Actions

`toggle`, `open` and `close` drive the sidebar; `arm`, `disarm` and `status`
drive the watch headlessly, each reporting through a notification.

## Limitations

- macOS only. Linux needs a different sleep call and idle source.
- Agents herdr reports as `unknown` are not counted as working, so a pane it
  cannot classify will not hold the machine awake.
- The countdown cancels on keyboard input, not on an agent waking back up. An
  agent that starts working during those two minutes is interrupted.
- With `[ui.toast] delivery = "off"` herdr suppresses its own toasts, so
  notifications are mirrored to macOS Notification Center — otherwise the
  warning before sleeping would be silent.

## License

MIT
