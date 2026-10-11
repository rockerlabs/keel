- **`install.sh`'s Verify now says when the always-on rails will not load, and the remedies it and `doctor.sh`
  advise keep the home's own mode.** A link or non-regular file the run declined is reported as "not provably
  Keel's" instead of "yours": with the manifest lost, a link Keel made itself lands there too. The "rails will
  NOT load" warning now also fires, in linked mode, when `CLAUDE.md` imports `keel/CORE.md` but that file does
  not resolve, and, in either mode, when the context file is not a regular file; the run still exits 0, and an
  embedded rails block is kept while it is the only copy that loads. Verify's re-run advice carries `--link`
  (and `--no-git`) for a linked home, and `doctor.sh`'s remedies take the flags from the home's install
  manifest (or, without one, from its layout), so following a dangling-link remedy no longer turns a copy-mode
  home into a linked one or advises `--codex` for a Claude slot. The one exception is the advice for a
  `CLAUDE.md` importing a `keel/CORE.md` that does not resolve: it still names `--link`, now after removing
  whatever blocks that file (dir #789 decides what such an import means). A named pipe at `CLAUDE.md` no
  longer hangs `install.sh --link`: it is declined with one line. Under `--no-hooks`, Verify says when a
  conditional `[includeIf]` include would refuse a run without the flag. The one-line bootstrap's summary lists
  `/go`'s handoff note among the things that need a kept checkout (dir #751, dir #752, dir #743, dir #691).
