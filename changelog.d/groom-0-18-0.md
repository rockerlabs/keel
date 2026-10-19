- **Grooming and release-close corrections from the 0.18.0 groom.** `docs/grooming.md` G4 now says every backlog
  write in the hygiene sweep goes through the checked writer `docs/release-management.md` R8 requires, with a deletion
  written at its exact expected byte count: that groom's first in-place edit emptied the backlog, and a copy taken
  seconds earlier restored it. It is labelled a compensation, removed by dir #193. G5 now prices the release audit no
  lower than the smallest of the last three measured audits instead of scaling it linearly by tickets, which had
  under-read the 0.17.0 audit by about a third; dir #872 is its remover. Both rules are mirrored into
  [`/groom`](/commands/groom.md). `docs/release-management.md` R9 now requires every `known-issue-in-changelog`
  disposition of the audit's staged files to reach the CHANGELOG section before the GO SHA, or to be demoted with a
  written reason: 0.17.0's one staged known issue went to a ticket Log and was disclosed nowhere.
