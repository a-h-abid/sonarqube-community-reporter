#!/usr/bin/env bash
# shellcheck shell=bash
# ==============================================================================
# helpers.bash — Shared helpers for all bats test files
#
# Load in each .bats file with:
#   load 'helpers'
# ==============================================================================

# ---------------------------------------------------------------------------
# counter_file_new
#   Creates a temporary file seeded with "0" and prints its path.
#   Intended for tracking call counts across mock function invocations.
#
#   Usage:
#     export MY_CTR
#     MY_CTR=$(counter_file_new)
# ---------------------------------------------------------------------------
counter_file_new() {
  local f
  f=$(mktemp)
  echo "0" >"$f"
  echo "$f"
}

# ---------------------------------------------------------------------------
# counter_file_increment <path>
#   Atomically increments the counter stored in the file and prints
#   the new value.  Intended for use inside exported mock functions.
#
#   Usage (inside a mock):
#     n=$(counter_file_increment "$MY_CTR")
# ---------------------------------------------------------------------------
counter_file_increment() {
  local f="$1"
  local n
  n=$(cat "$f")
  n=$((n + 1))
  echo "$n" >"$f"
  echo "$n"
}
