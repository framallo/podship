#!/usr/bin/env bash
# Runs the integration test against PODSHIP_IT_HOST and prints a short log.
#   PODSHIP_IT_HOST=user@host PODSHIP_IT_HOME=/path tool/it.sh
set -uo pipefail
cd "$(dirname "$0")/.."
dart run test/integration/flow_test.dart > /tmp/podship-it.log 2>&1
code=$?
grep -aE '^(\$ podship|▶|✓|✗|!|\[[0-9]+s\]|  Expected|    Actual|  [A-Za-z].*Exception|healthy|no healthy)' /tmp/podship-it.log | tail -150
echo "exit $code"
exit $code
