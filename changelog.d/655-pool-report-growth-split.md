- `tools/self/pool-report.sh --record` now stores the pool's id set and the files a reading covered, not only its size.
  The next run prints "new since the last reading" and "returned from a slate" (an id present now, absent from the last
  reading and older than it), the growth trigger counts its latest step net of returned tickets, and no growth is read
  across a change of coverage. Older history rows without the new fields keep the size-only reading. This replaces the
  hand-split of the growth that `docs/grooming.md` G4 asked every groom to do, now a pointer (dir #655).
