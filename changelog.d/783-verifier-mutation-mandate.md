- **Delta audit: the verifier runs a mutation sweep by default, one range per pass, and files pin gaps as one
  ticket.** In [`docs/delta-audit.md`](/docs/delta-audit.md), the S-final verifier now mutates the qualifying
  rules (a filter, threshold, guard or exclusion rule, `/polish`'s own trigger) in its range without a brief
  asking for it. Each verifier pass sweeps the commits no earlier pass swept, recorded as a `Mutation sweep:`
  line in the verdict record, so a fix round's rules are swept by the pass that verifies them and no commit is
  swept twice; a survivor reaches GO only through the §8 disposition any finding gets, never through a rule of
  its own. A reading leg that claims a test cannot fail now writes a `Mutation candidate:` line unless it ran
  the mutant itself, and the verifier runs one mutant per candidate. One run's pin gaps are staged as ONE
  ticket, not one per rule: the 0.16.0 audit filed three for this one class (dir #783).
