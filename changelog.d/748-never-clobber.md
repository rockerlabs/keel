- **`install.sh` and `uninstall.sh` stop clobbering the checkout, an adopter's links and consented edits.**
  A home that is the Keel checkout, or lies inside it, is refused by both with exit 2 before anything is
  created (an uninstall there used to move tracked files out). Whether a link recorded with its target is
  Keel's is now one test, shared by install, uninstall and `doctor.sh`'s dangling-link check: that target
  must lie inside the checkout that wrote the record, so uninstall no longer moves an adopter's link that an
  older manifest recorded; `tools/lib/manifest.sh` is therefore required by `install.sh` too. Answering `y`
  at "Overwrite your copy" or `[u]` at the alias prompt now backs the file up first, as `--force` does.
  Smaller fixes: linked mode no longer advises deleting a `docs/` that is a link into the checkout; a
  `CLAUDE.md` with no rails is reported as carrying no Keel rails block; the hook installers count "hook
  entries"; uninstall names the compatibility links Keel left under `.keel` (dir #748, dir #754).
