- `examples/tour.sh` and `docs/demo/record-demo.sh` now `unset KEEL_INSTANCE`, so an ambient project registry is no
  longer appended with a row naming the tour's deleted sandbox (dir #800). README's record-demo line no longer claims
  it "touches nothing": the default mode writes `docs/demo.gif` into the checkout.
