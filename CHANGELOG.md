# Changelog

## 0.1.0

Initial release.

- Arm/disarm/toggle/status actions, plus a startup hook that re-attaches the
  watcher after a herdr server restart.
- Sleeps once no agent has been `working` for a configurable number of
  continuous minutes, the keyboard has been idle, and an optional time window
  allows it.
- Journals every agent's final state, calling out the blocked ones.
