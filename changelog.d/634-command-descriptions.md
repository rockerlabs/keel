- `/context-dump`, `/init-project` and `/keel-setup` now carry a frontmatter `description:` (and `/init-project` an
  `argument-hint:`), so an adopter's harness lists them with trigger words to route on instead of their bare
  names; `tests/test_command_descriptions.sh` pins that every `commands/*.md` has one (dir #634).
