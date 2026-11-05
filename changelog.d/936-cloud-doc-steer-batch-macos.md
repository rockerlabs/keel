- `docs/cloud.md` is back in step with the cloud route as it ran (dir #936). Steering a session with a
  non-interactive `claude -p "<steer>" --cloud <session id>` works, so the stale sentence saying it ignores
  `--cloud` is gone. Dispatch now says when to batch several tickets into one session (a backlog-shaped
  mirror passed with `CLOUD_BACKLOG`, one commit per ticket, each ticket keeping its own number and closure,
  and the cost: one bad ticket can hold back the whole PR). Landing names a local macOS step for a project
  whose CI has a macOS leg. `tests/test_cloud_doc.sh` pins all three with one-line needles.
