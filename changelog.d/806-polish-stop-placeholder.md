- The `/polish` compaction stop's paste-ready line and its `<call>` sentence no longer carry the literal `--no-test` inside
  the flags placeholder (now `<the flags this run had, if any>`); step 3 acts on that token in the arguments, so a copied
  placeholder could skip the test run. `tests/test_polish_command.sh` pins both lines and asserts neither holds `--no-test`
  (dir #806).
