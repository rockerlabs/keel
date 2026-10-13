- **Grooming: priced options read as a gauge, and offered tickets are checked live first.** Two rules from
  the 0.17.0 re-cut. A window-point figure on its own was read as the gauge's end, not its change, so
  G5 in [`docs/grooming.md`](/docs/grooming.md) now has each priced option state where the weekly gauge
  stands now and where the option leaves it, plus the date the window ends. The lane rule holds back body
  reads until the operator says yes; it no longer holds back the cheap live premise check. G1 now runs that
  check on every ticket before it is named in a priced option. That re-cut had offered one parked ticket a
  later change had already fixed.
