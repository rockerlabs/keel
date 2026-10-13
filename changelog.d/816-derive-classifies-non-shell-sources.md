- `tools/delta-audit/derive.sh` (dir #816, absorbing dir #484 and the classifier half of dir #552)
  no longer classes every non-shell source as `prose`: Swift, Python, Go, Rust, JS/TS and other
  compiled/source files class `code`, so they read with the seams before prose; `.yml`/`.yaml`, `.json`,
  `.toml`, `.plist`, `.xcconfig` and `requirements.txt` class a new `config` read with code; `test/`,
  `Tests/`, `spec/`, `*Tests.swift` and `*_test.*` class `test`. A file no list names still falls to
  `prose`, now with one stderr note naming it. The lists are the `DELTA_CODE_EXTENSIONS`,
  `DELTA_CONFIG_EXTENSIONS` and `DELTA_PROSE_EXTENSIONS` knobs; the executable-bit fallback stays for
  extensionless CLIs but no longer overrides a known prose extension.
