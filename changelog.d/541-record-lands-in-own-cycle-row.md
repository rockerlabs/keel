- `docs/release-management.md` R7 and `docs/grooming.md` G0/G4(c) gain a lookup rule for records addressed to one
  cycle (dir #541): the release manager finds the row it completes by its version token or run number, never by the
  nearest empty slot, and a per-cycle record lands under that cycle's own header. The groom's G0 now checks that the
  previous release's opened row carries no `_` placeholder and that the previous audit run's harvest sits under its own
  dated header.
