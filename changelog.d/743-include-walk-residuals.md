- **`tools/install-secret-guard.sh`'s conditional-include walk and machine-wide reads close their residuals.** dir #743:
  a dangling symlink into a directory that cannot be searched is no longer skipped as missing (the walk was incomplete
  there but read as clean — an edge fail-open); a bare `path = ~` (git's `$HOME`, a directory git then fails to read)
  and any `~user/` or `%(prefix)/` include are expanded by git itself (one `git config --type=path --default` call)
  instead of by the walk's own rules; a file reached again under a second, independent condition is reported under
  both, with the includes nested in it; the "git config failed on …" line for a path git never read now says
  "cannot tell whether … exists". A command-scope `core.hooksPath` (`git -c`) is no longer taken for the machine-wide one, so it is never recorded as the
  displaced global nor written into `~/.gitconfig` by `--uninstall`; a git config git cannot read is refused instead of
  read as "unset"; and a `core.hooksPath` one global config file sets twice is refused up front, in words, instead of git
  exiting 5 after the hooks were placed (one value in each of two files is fine). `--where` prints `read-error=1` for an unreadable config.
