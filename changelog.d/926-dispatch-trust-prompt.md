- Cloud `--dispatch` no longer hangs when the CLI stops on its folder-trust prompt (dir #926). The tool watches
  the CLI's output, stops it on "Is this a project you created or one you trust?" and exits 5 with the remedy
  (run `claude` once in the main checkout, answer "Yes, I trust this folder", dispatch again); it never answers
  the prompt. The CLI call is also bounded by `CLOUD_DISPATCH_TIMEOUT` seconds (default 300): a hang on any other
  prompt exits 5 with the captured output. The row goes back to `built` either way. `script` now flushes its
  typescript on every write (`-f` on Linux, `-F` on macOS) so the output is readable while the CLI runs. [`docs/cloud.md`](/docs/cloud.md) names the one-time
  trust step.
