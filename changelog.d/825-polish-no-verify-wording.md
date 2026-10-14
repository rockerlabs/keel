- The `/polish` preamble no longer reads as an instruction to push with `--no-verify`: it now says the
  pre-PR gate denies `git push --no-verify`, so the pre-push secret scan always runs. A test in
  `tests/test_polish_command.sh` pins that no shipped command tells the agent to use the flag (dir #825).
