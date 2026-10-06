# Test stage (before build), the production test gate, and test suites

Status: draft 2026-10-06 (added on request during the first round). Mockups: `mockups/web-tests.html` (8 states) and the test badges in `mockups/web-environment.html` state 1. Copy: `copy/tests.md`.

Reading this as: a gate the owner meets on every deploy and rarely thinks about until it blocks; exact, calm, high restraint. When it blocks, the next step must be obvious.

## 1. Job story

When I deploy, I want the project's tests to run on the exact commit before anything is built or uploaded, so a broken release never reaches production; and when I must ship anyway, I want that to be a deliberate, recorded choice.

HMW make the gate strict for production without making a flaky test an outage?

## 2. What podship needs (proposal, not existing behavior)

podship has no test stage today (`ops/deploy.dart` starts with the export, the Flutter web builds and `pre_deploy` hooks). Proposed:

- `podship.yaml`: `tests:` a list of suites: `name`, `command`, `dir` (relative to the project root), `timeout` (minutes), `environments` (names, or `all`). Example: `{name: server, command: dart test --reporter json, dir: cazafacturas_server, timeout: 10, environments: [all]}`.
- The deploy plan gets one step per suite, **after "Export main (a0dc2b0)" and before "Build Flutter web: app"**, titled "Run tests: server". They run on the console host, in the exported commit (like `pre_deploy`).
- Counts (passed, failed, skipped) and failing tests with their output come from a JSON reporter when the command is `dart test` or `flutter test` (`--reporter json` or `--file-reporter json:<file>`). Other commands report only pass or fail by exit code; the UI then says "Counts not available (exit code only)".
- The release records its result in `.podship/release.json`: `tests: {status: passed | failed | skipped | none, suites: [{name, passed, failed, skipped, duration}], ran_on: <env>, skipped_by, skip_reason}`.
- Flags: `deploy --skip-tests --reason "<text>"`; for production also `--confirm <project>/<env>`.

## 3. The gate

| Target | Tests passed | Tests failed | Tests skipped | No suites configured |
|---|---|---|---|---|
| Non-production deploy | continues | **blocked** before build; nothing uploaded | allowed with a reason (tier 1) | continues, badge "No tests" |
| Production deploy | continues | **blocked** | allowed with a reason **and** typed `cazafacturas/production` (tier 2) | continues, badge "No tests" (owner may require suites: open question) |
| Promote to production | allowed if the release's tests **passed** in the staging deploy (or a previous deploy of that release) | refused; the dialog shows the failing suites | allowed only through the same tier-2 override, recorded on the release | allowed, badge "No tests" |

A blocked deploy never touches the server: the operation ends "Blocked by tests" and the environment keeps its current release.

## 4. Screens and states

| State | Frame |
|---|---|
| Test stage running inside the deploy's step list: a "Tests" group with one row per suite (passed, failed, skipped counts as they arrive; running suite with elapsed time); the right pane shows the suite list with expandable failures | web-tests 1 |
| Deploy blocked by failing tests: outcome banner "Blocked by tests. 2 tests failed in server. Nothing was built or uploaded; production still runs 20261005-221844-9c41e07." Failing tests expanded with file, line and output. Next steps panel: "Fix the tests and deploy again", "Run the tests again" (for a flaky test), "Deploy without tests…" | web-tests 2 |
| Skip tests on staging: dialog, reason required (min 10 characters), consequence "The release is marked Tests skipped and can't be promoted to production without the same override." | web-tests 3 |
| Skip tests on production: tier 2: reason + typed `cazafacturas/production` | web-tests 4 |
| Promote dialog with the release's test status: "Tests passed on staging, 6 Oct 10:58: server 412 passed, server-integration 38 passed, app 96 passed, 2 skipped" | web-tests 5 |
| Promote refused: the staging release's tests failed or were skipped; the reason and the two ways forward (deploy a fixed commit to staging; or the tier-2 override) | web-tests 6 |
| Project settings, Tests: suites table (name, command, directory, timeout, environments, last result) | web-tests 7 |
| Edit a suite: dialog with validation error on the command (empty) and timeout (out of range) | web-tests 8 |
| Timeline badges: each release row shows `TestBadge`: "Tests passed", "Tests failed" (only on failed deploys), "Tests skipped" (with reason on hover and in the row detail), "No tests" | web-environment 1 |

## 5. Layout

- Operation view: the test suites appear as a "Tests" group at the top of the step list; selecting a suite shows its results in the right pane in place of the log (tabs "Results" and "Output").
- Compact: suites as rows; a failing test opens full screen with its output; skipping tests on production is not offered on the phone (desktop only; the sheet says why).
- Project settings live at `/projects/<p>/settings/tests` (a project-level page reached from the project row in the sidebar, "Project settings").

## 6. Components

`TestSuiteList` (new), `TestBadge` (new), `StepList` (Tests group), `ConfirmDialog` tier 1/2, `TypedConfirmField`, `PsTextField` (reason, multiline), `DataTable`, `PsCheckbox` (environments).

## 7. Validation

- Skip reason: required, 10 to 280 characters; on submit: "Write why you're skipping the tests (at least 10 characters). It's saved with the release."
- Suite name: `^[a-z0-9-]+$`, unique in the project; on blur.
- Command: required; on blur.
- Directory: must exist in the repository at the default ref; checked on blur: "cazafacturas_srver doesn't exist in main."
- Timeout: 1 to 120 minutes; on blur.
- Environments: at least one; on submit.

## 8. Accessibility

- Suite rows: "server, 410 passed, 2 failed, 0 skipped, 1 minute 52 seconds". Counts are words and numbers, never color only.
- Failing tests are a disclosure list (`NakedDisclosure`), expanded state announced; the output is selectable mono text.
- The blocked banner is a live region (assertive is not used; polite).

## 9. Acceptance criteria

- A deploy whose tests fail ends before "Prepare caza-vps:…"; the environment's current release is unchanged; the banner names it.
- Production rejects a promote of a release whose tests did not pass unless the tier-2 override is completed; the override's reason and person appear on the release and in history.
- Every release row shows a test badge; "Tests skipped" always has its reason available.
- Suites without a JSON reporter show "Counts not available" rather than invented numbers.

## 10. Open questions

- Should production require at least one suite (no "No tests" releases)? (owner)
- Where are suites edited: in `podship.yaml` (committed, proposed) with the console writing the change and showing the diff to commit, or in the console only? Proposed: `podship.yaml` stays the source of truth; the settings page edits it in the console host's checkout and shows "podship.yaml changed. Commit it with your next change." (owner)
- The typed string for skipping on production is `cazafacturas/production` (the same rule as every tier-2 action), which contains the environment name; if a bare `production` is preferred, it must change for every tier-2 action at once. (owner)
- Run tests on the server instead of the console host (architecture parity)? Not proposed: tests run where the build exports the commit. (podship)
