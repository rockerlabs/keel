- `bootstrap.sh`'s exit cleanup is now best-effort: a failing `rm -rf` of its temp directory (macOS can
  report "Directory not empty" under concurrent runs) no longer replaces the script's exit status, so a
  fully successful install no longer reports failure, and a failed one still exits non-zero (dir #394).
