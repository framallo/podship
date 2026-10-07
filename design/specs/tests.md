# Spec · Test stage, production test gate, test suites

Status: draft 2026-10-06, added on request during the first round. Key: TST. Copy: [tests](../copy/tests.md). Mockups: `mockups/web-tests.html` (8 states), test badges in `mockups/web-environment.html` state 1.
Read: a gate the owner meets on every deploy and rarely thinks about until it blocks. Exact, calm, high restraint. When it blocks, the next step is obvious.

## Purpose

Tests run on the exact commit before build or upload, so a broken release never reaches production. Shipping anyway is deliberate and recorded.

HMW: strict for production, without making a flaky test an outage.

## Entry and exit

| Way | From or to | Condition |
|---|---|---|
| Entry | The deploy step list ("Tests" group), the promote dialog, the release timeline badge | |
| Entry | `/projects/<p>/settings/tests`, from the project row in the sidebar, "Project settings" | Suites |
| Exit | The deploy continues, or ends "Blocked by tests" | Gate result (TST-9) |

## States

| State | What shows | Trigger | Frame |
|---|---|---|---|
| Running | "Tests" group in the step list, one row per suite with counts as they arrive. Running suite shows elapsed time. Right pane: suite list, expandable failures. | Deploy with suites | web-tests 1 |
| Blocked | Banner `tests.blocked`. Failing tests expanded with file, line, output. Next steps: `tests.next.fix`, `tests.next.rerun`, `tests.next.skip`. | A suite fails | web-tests 2 |
| Skip on staging | Dialog, reason required, consequence `skip.dialog.staging` | `tests.next.skip` on non-production | web-tests 3 |
| Skip on production | Tier 2: reason plus typed `cazafacturas/production` | `tests.next.skip` on production | web-tests 4 |
| Promote, passed | `promote.tests.passed` ("server 412 passed, server-integration 38 passed, app 96 passed, 2 skipped") | Promote | web-tests 5 |
| Promote refused | `promote.tests.refused` with `promote.tests.ways`: deploy a fixed commit to staging, or the tier-2 override | Staging tests failed or skipped | web-tests 6 |
| Suites | Table: name, command, directory, timeout, environments, last result | Project settings, Tests | web-tests 7 |
| Edit suite | Dialog with errors on command (empty) and timeout (out of range) | Edit | web-tests 8 |
| Badges | `TestBadge` per release row: `badge.passed`, `badge.failed` (failed deploys only), `badge.skipped` (reason on hover and in row detail), `badge.none` | Timeline | web-environment 1 |

## Rules

| ID | Kind | Rule | Ref |
|---|---|---|---|
| TST-1 | server | Proposal, not existing behavior. Today `ops/deploy.dart` starts with the export, the Flutter web builds and `pre_deploy` hooks. | |
| TST-2 | server | `podship.yaml` `tests:` lists suites: `name`, `command`, `dir` (relative to project root), `timeout` (minutes), `environments` (names, or `all`). | |
| TST-3 | server | Example: `{name: server, command: dart test --reporter json, dir: cazafacturas_server, timeout: 10, environments: [all]}`. | |
| TST-4 | server | One plan step per suite, "Run tests: server", after "Export main (a0dc2b0)", before "Build Flutter web: app". | |
| TST-5 | server | Suites run on the console host, in the exported commit, like `pre_deploy`. | |
| TST-6 | server | Counts and failing tests with output come from a JSON reporter for `dart test` or `flutter test` (`--reporter json` or `--file-reporter json:<file>`). | |
| TST-7 | server | Other commands report pass or fail by exit code only. The UI shows `tests.noCounts`, never invented numbers. | |
| TST-8 | server | The release records `tests: {status: passed or failed or skipped or none, suites: [{name, passed, failed, skipped, duration}], ran_on, skipped_by, skip_reason}` in `.podship/release.json`. | |
| TST-9 | server | Flags: `deploy --skip-tests --reason "<text>"`. Production also needs `--confirm <project>/<env>`. | |
| TST-10 | flow | Gate, non-production deploy: passed continues. Failed blocks before build, nothing uploaded. Skipped needs a reason (tier 1). No suites continues with "No tests". | |
| TST-11 | flow | Gate, production deploy: passed continues. Failed blocks. Skipped needs a reason and typed `cazafacturas/production` (tier 2). No suites continues with "No tests". | Open question 1 |
| TST-12 | flow | Gate, promote to production: allowed if the release's tests passed on staging or in an earlier deploy. | |
| TST-13 | flow | Promote with failed tests: refused, the dialog shows the failing suites. Skipped: only through the tier-2 override, recorded on the release. No suites: allowed, "No tests". | |
| TST-14 | flow | A blocked deploy never touches the server. The operation ends "Blocked by tests". The environment keeps its release. | |
| TST-15 | layout | Operation view: "Tests" group at the top of the step list. A selected suite shows results in the right pane, tabs "Results" and "Output". | |
| TST-16 | layout | Compact: suites as rows. A failing test opens full screen with its output. | |
| TST-17 | platform | Skipping tests on production is desktop only. The phone sheet says why. | |
| TST-18 | ui | Components: `TestSuiteList` (new), `TestBadge` (new), `StepList` (Tests group), `ConfirmDialog` tier 1/2, `TypedConfirmField`. | |
| TST-19 | ui | Components also: `PsTextField` (reason, multiline), `DataTable`, `PsCheckbox` (environments). | |
| TST-20 | validation | Skip reason: required, 10 to 280 characters, on submit. Error: `skip.dialog.reasonError`. | |
| TST-21 | validation | Suite name: `^[a-z0-9-]+$`, unique in the project, on blur. | |
| TST-22 | validation | Command: required, on blur. | |
| TST-23 | validation | Directory: exists in the repository at the default ref, on blur (`suites.dir.error`: "cazafacturas_srver doesn't exist in main."). | |
| TST-24 | validation | Timeout: 1 to 120 minutes, on blur. Environments: at least one, on submit. | |
| TST-25 | test | A deploy whose tests fail ends before "Prepare caza-vps:…". The current release is unchanged and the banner names it. | |
| TST-26 | test | Production rejects a promote of a release without passed tests unless the tier-2 override completes. | |
| TST-27 | test | The override's reason and person appear on the release and in history. | |
| TST-28 | test | Every release row shows a test badge. "Tests skipped" always has its reason available. | |

## Copy keys

`tests.*`, `skip.dialog.*`, `promote.tests.*`, `badge.*`, `suites.*` in the copy table.

## Accessibility and platform

| ID | Rule |
|---|---|
| TST-29 | Suite row label: "server, 410 passed, 2 failed, 0 skipped, 1 minute 52 seconds". Counts are words and numbers, never color only. |
| TST-30 | Failing tests are a disclosure list (`NakedDisclosure`). The expanded state is announced. Output is selectable mono text. |
| TST-31 | The blocked banner is a polite live region, not assertive. |

## Open questions

| # | Question | Owner | Date |
|---|---|---|---|
| 1 | Should production require at least one suite (no "No tests" releases)? | owner | 2026-10-06 |
| 2 | Where are suites edited? Proposed: `podship.yaml` stays the source of truth. The settings page edits it in the console host's checkout and shows `suites.saved`. Alternative: console only. | owner | 2026-10-06 |
| 3 | Skipping on production types `cazafacturas/production`, like every tier-2 action. A bare `production` would change every tier-2 action at once. | owner | 2026-10-06 |
| 4 | Run tests on the server instead of the console host (architecture parity)? Not proposed: tests run where the build exports the commit. | podship | 2026-10-06 |
