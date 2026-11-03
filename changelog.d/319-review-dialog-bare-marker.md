- Step 5(a)'s review reminder dialog is now traced the way step 4's skip dialog is, and the marker changes
  shape (dir #319). The question must END with the bare literal `KEEL-REVIEW-DIALOG` (no `level=` suffix) and
  the event must carry a non-empty answer; the hook reads `tool_response.answers` instead of greping the raw
  event JSON, and writes a level-less `dialog:review` trace line. The two dialog legs now share one
  answer-keyed read. A mid-sentence mention, an unanswered dialog, two questions both ending with the
  marker and the old level-suffixed shape trace nothing, and the level near-misses (`high2`, `high-ish`)
  are structurally impossible on this leg. The gate's `agent:*` unlock now requires `dialog:review` at HEAD,
  and its `review-dialog-missing` deny carries the stale-copy hand-copy remedy. **Behaviour change:** an
  adopter whose COPIED `commands/polish-guide.md` still composes the old level-suffixed marker traces
  nothing under the new leg, so in an ARMED repo, on the agent-fallback path only, `gh pr create` denies
  `review-dialog-missing` until they copy the shipped polish files over their own. UNARMED repos are
  unaffected. Residual, narrowed rather than closed: an agent that ends an UNRELATED question with the bare
  marker mints the trace once the operator answers it; the marker is operator-visible, which bounds it
  (no answer-value rule can, since the agent composes the option labels too).
