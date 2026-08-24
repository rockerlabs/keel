#!/usr/bin/env bash
. "$(dirname "$0")/lib.sh"

home="$SANDBOX/claude"
engine="$SANDBOX/keel/engine"
kb="$SANDBOX/.keel/kb"

export KEEL_HOME="$home"
export KEEL_ENGINE="$engine"
export HOME="$SANDBOX"

mkdir -p "$home"
echo "old claude" > "$home/CLAUDE.md"
echo "old instance" > "$home/INSTANCE.md"

echo "y" | "$REPO_ROOT/tools/kb-unify.sh"
check_status "kb-unify runs successfully" 0 $?

check_file "FRAMEWORK-personal.md created" "$kb/FRAMEWORK-personal.md"
check_link "CLAUDE.md is a symlink" "$home/CLAUDE.md"
check_file "KEEL.md router created" "$kb/KEEL.md"

summary
