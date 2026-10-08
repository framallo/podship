#!/usr/bin/env bash
# Runs every unit test file as a script and prints one line per file.
cd "$(dirname "$0")/.."
fail=0
for f in test/*_test.dart; do
  out=$(dart run "$f" 2>&1 | tr '\r' '\n' | sed 's/\x1b\[[0-9;]*m//g' | grep -E "(All tests passed|Some tests failed)" | tail -1)
  echo "$f: ${out:-NO RESULT}"
  [[ "$out" == *"All tests passed"* ]] || fail=1
done
exit $fail
