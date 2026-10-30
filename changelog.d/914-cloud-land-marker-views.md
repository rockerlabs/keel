- `tools/cloud-land.sh`'s added-marker check (dir #914) now greps the scanner's decoded views, not only the raw
  bytes. A marker split by an invalid byte, or written in UTF-16 or UTF-32, passed the grep and landed; every later
  scan without `SECRET_SCAN_NO_INLINE_ALLOW=1` (pre-commit, pre-push, CI) would then have honoured it. Each patch and
  commit-message spool is now read as it is, NUL-stripped, and with its invalid UTF-8 dropped by `iconv -c` (every
  byte >= 0x80 dropped instead where iconv is missing or cannot resume after an invalid byte, which can only refuse
  more); a hit names the view it came from.
