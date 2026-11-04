- The pre-PR gate's suite no longer asserts the absence of the phrase "re-run install.sh" in four stale-copy deny
  messages (dir #330). That phrase never occurs in those messages, which say "re-running install.sh", so the four
  absence checks could not fail even if a message were rewritten to call a bare install re-run a reliable refresh.
  Each site now pins, on one physical line, the positive claim and its stated reason: a re-run is not a reliable
  refresh, it offers only from a terminal and defaults to no. Rewriting the claim to its opposite, or flipping the
  reason, turns every site red. Test-only; no tool changed.
