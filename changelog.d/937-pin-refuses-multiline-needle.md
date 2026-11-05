- `pin` and `pin_exact` in `tests/lib.sh` now fail a needle that holds a newline (dir #937). `grep -F` reads each
  line of its pattern as an alternative, so such a pin passed when either half was present and bound nothing;
  the failure names the rule and says to cut the needle to one physical line. A new
  `tests/test_lib_pin_needle.sh` covers both helpers. No existing pin carried a multi-line needle, so no test
  or doc needed rewriting.
