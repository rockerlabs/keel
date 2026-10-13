- **Keel's own maintenance: a finding accumulator, `tools/self/accumulate.sh`.** A recurring defect class used to be
  noticed only when a person connected two tickets, and the hand-kept `[n×]` counters rarely moved. The tool keeps a
  class registry and an append-only sighting log in a data directory the caller names, counts the distinct
  independent sources of each class inside a window (60 days and a threshold of 2 unless the class says otherwise),
  and lists the classes that are due. One felt danger is due at once. A class that was promoted to a ticket counts
  recurrence only from the ticket's closure date, and a class quiet for its whole window retires. It reads a backlog
  to find out whether a promoted class's ticket has closed, through the closure vocabulary in
  `tools/lib/backlog-blocks.sh`. It never files or edits a ticket, and its day arithmetic is awk, not `date`.
  `tests/test_accumulate.sh` covers it and `tests/mutants/accumulate.tsv` lists 34 single-clause edits that suite must
  turn red. The command observers of dir #838 and the guard register of dir #842 are its first consumers.
