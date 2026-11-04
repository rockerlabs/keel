- `docs/grooming.md` G2 now says a premise about an artifact (a build, a certificate, a binary's version
  string, a deployed config) is checked by reading the artifact itself with a tool before any record about
  it, since a ticket, a registry file and an earlier groom's body-read can agree on one misreading; a
  premise only the operator can confirm is asked in the same sitting, and archived bodies are kept
  verbatim. G9 now keeps the tag namespace a version (`0.N.0`) even on a project that has never tagged,
  not a sprint label, and starts a binary-shipping project's first release by aligning the binary's own
  version string with the plan (dir #563).
