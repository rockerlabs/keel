- **Grooming and release-close corrections from the 0.18.0 groom.** `docs/release-management.md` R8's checked writer
  now holds a deletion to its exact expected byte count, and `docs/grooming.md` G4 now says every backlog write in the
  hygiene sweep goes through that writer, after a copy taken before the first write: that groom's first in-place edit
  emptied the backlog, and a copy taken seconds earlier restored it. It is labelled a compensation; its remover is
  dir #193. G5 briefly floored the release audit's price at the smallest of the last three measured audits instead of
  scaling it linearly by tickets, which had under-read the 0.17.0 audit by about a third; dir #872 replaced that
  floor in this same release with a price from the previous audit's measured parts, so it is not in the release.
  The G4 rule is mirrored into [`/groom`](/commands/groom.md). `docs/release-management.md` R9 now requires every
  `known-issue-in-changelog` disposition in the audit's staged files to reach the CHANGELOG section before the GO SHA,
  or to be demoted with a written reason: 0.17.0's one staged known issue went to a ticket Log and was disclosed
  nowhere.
