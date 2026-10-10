- **`secret-scan.sh` allow decisions read the right field, and `--tracked` reads every tracked file.** A hit is now
  a record whose label and content are kept apart: the inline `secret-scan:allow` marker and every ERE allowlist
  entry match the matched line only, so a file named `notes-secret-scan:allow.txt`, or `README.md:x.txt` under
  `path:README.md`, no longer exempts its own key, and a `path:` glob never exempts a commit or tag message
  (dir #741). Under `--range`, a `path:` glob exempts a blob only when every path the push introduces it at is
  exempt: the same key added at `fixtures/key.txt` and `src/real.txt` — in one commit, on two merged branches, or
  by an evil merge — is reported under the path that is not exempt (dir #742).
  A tracked file `--tracked` could not read from the working tree used to be skipped — an unreadable one with a
  WARN, a deleted one silently — and the run reported clean; it now scans that file's index copy, with one WARN
  line naming why, and so does an absent sparse-checkout (skip-worktree) entry, counted in one summary line. It
  exits 2 only when git cannot read the index copy (dir #746). A tracked file replaced by a symlink is read from
  its index copy too, and a mid-merge (unmerged) file from its working file (or symlink) and each of its stages'
  index copies, a hit they share printed once and one WARN naming the path; an unreadable working file of an
  unmerged path exits 2. Hit lines print in the same form as before. Upgrading: an ERE
  allowlist entry now matches the line's content only; use `path:` for a path.
