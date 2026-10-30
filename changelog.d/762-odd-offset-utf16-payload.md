- `tools/secret-guard/secret-scan.sh` and `tools/public-audit.sh` now decode a UTF-16 or UTF-32 payload that
  starts at an odd byte offset of a binary file (dir #762). Both read the file only from its first byte, so a
  personal name encoded after a prefix of odd length was read as clean; each now reads the file again from its
  second byte as UTF-16, both byte orders (this also decodes a BMP UTF-32 payload at an odd offset), and the
  built-in decoder, used where iconv cannot resume, runs a second time from the second byte. Cost: two more iconv
  passes per blob, a small share of a whole scan; where the built-in decoder runs (musl, or no iconv, with a wide
  personal literal) a blob takes twice as long as before. A non-BMP UTF-32 character at an odd offset stays
  undecoded.
