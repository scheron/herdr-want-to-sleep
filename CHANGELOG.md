# Changelog

## 0.2.0

- **Sidebar.** A split pane with the live watch state, every agent herdr can
  see, and a legend for the rules being applied. `a` start, `c` stop, `-`/`+`
  the quiet needed, `q` stop and close, `x` close and keep watching.
- `toggle`, `open` and `close` now drive the sidebar; `arm`, `disarm` and
  `status` still drive the watch headlessly.
- Default quiet lowered from 20 to 15 minutes.
- `shutdown` is no longer reachable from the UI — config only. As a one-key
  toggle beside the others it invited mistakes.
- Notifications are mirrored to macOS Notification Center. `herdr notification
  show` exits 0 even when `[ui.toast] delivery = "off"`, so the previous
  fallback never fired and the warning before sleeping was silent.
- Scripts export a PATH before using `jq`; herdr runs plugin commands with a
  minimal one.

## 0.1.0

Initial release.

- Arm/disarm/status actions, plus a startup hook that re-attaches the watcher
  after a herdr server restart.
- Sleeps once no agent has been `working` for a configurable number of
  continuous minutes, the keyboard has been idle, and an optional time window
  allows it.
- Journals every agent's final state, calling out the blocked ones.
