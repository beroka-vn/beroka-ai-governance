# Codex Delayed Reauthentication Classification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent a first empty OAuth-labeled Codex inventory from masking delayed Atlassian reauthentication evidence.

**Architecture:** Reuse the existing app-server probe and auth classifiers. Require a second valid empty response before treating an empty `oAuth` inventory as complete, while allowing any accumulated auth evidence to terminate the probe immediately.

**Tech Stack:** POSIX shell, Codex app-server JSON-RPC, existing shell integration tests

## Global Constraints

- Do not infer authentication failure solely from an empty inventory.
- Do not add Codex-version-specific log parsing.
- Do not persist or parse producer OAuth output.
- Keep Doctor, hooks, and explicit non-interactive commands non-interactive.
- Do not change `VERSION`, tags, releases, README cleanup, or client enrollment.

---

### Task 1: Protect delayed authentication classification

**Files:**
- Modify: `tests/routing.sh`
- Modify: `bin/beroka-governance`

**Interfaces:**
- Consumes: `codex_probe_complete FILE`, `codex_probe_response_count FILE`, `codex_reauthentication_required`, `connector_health`, and the existing fake Codex health-state protocol.
- Produces: a bounded Codex probe that accepts an empty `oAuth` inventory only after two valid status responses without authentication evidence.

- [ ] **Step 1: Add a failing delayed-reauth fixture**

Add a fake Codex state whose first `mcpServerStatus/list` request emits:

```json
{"id":1,"result":{"data":[{"name":"atlassian","tools":{},"authStatus":"oAuth"}]}}
```

On its second request, emit the existing exact structured reauthentication notification followed by the same empty record. Track the request count in the test configuration directory.

- [ ] **Step 2: Add non-interactive and interactive assertions**

The non-interactive assertion must observe:

```text
Result: ATLASSIAN_AUTH_REQUIRED
```

and reject `CONNECTOR_CAPABILITY_REQUIRED` and any login invocation. The interactive assertion must use `run_pty`, invoke `codex mcp login atlassian` exactly once, and finish with `Result: PASS` after the fake login changes health to `healthy-all`.

- [ ] **Step 3: Run the routing suite and verify RED**

Run:

```bash
sh tests/routing.sh
```

Expected: FAIL because the first empty response currently completes the probe and returns `CONNECTOR_CAPABILITY_REQUIRED`.

- [ ] **Step 4: Implement the minimum probe confirmation rule**

Change the shared Codex probe completion path so a valid `oAuth` record with no tool names is incomplete while fewer than two valid status responses have been observed. Preserve immediate completion for auth evidence, non-empty inventories, `notLoggedIn`, terminal errors, malformed records, and the existing deadline.

- [ ] **Step 5: Run targeted GREEN verification**

Run:

```bash
sh tests/routing.sh
sh tests/connectors.sh
```

Expected: both suites print their PASS markers with exit code 0.

- [ ] **Step 6: Commit the regression fix**

```bash
git add bin/beroka-governance tests/routing.sh
git commit -m "fix: await delayed Codex reauth evidence"
```

### Task 2: Verify and publish the fix branch

**Files:**
- Verify: all tracked source and test files

**Interfaces:**
- Consumes: the complete repository test suite and GitHub Actions matrix.
- Produces: a pull request linked to issue #67 with green Ubuntu and macOS checks.

- [ ] **Step 1: Run syntax and the full local suite**

```bash
set -eu
sh -n bin/beroka-governance tests/pty.shlib tests/*.sh
for f in tests/*.sh; do sh "$f"; done
git diff --check
```

Expected: every suite prints its PASS marker and all commands exit 0.

- [ ] **Step 2: Push and open the pull request**

Push `fix/issue-67-atlassian-reauth` and open a PR against `main` whose body summarizes the root cause, safety boundary, verification, and includes `Closes #67`.

- [ ] **Step 3: Watch both CI jobs to completion**

Require `test (ubuntu-latest)` and `test (macos-latest)` to conclude `SUCCESS`. If either fails, inspect the job log and return to the targeted red-green cycle before pushing a correction.

- [ ] **Step 4: Stop before merge or release**

Report the reviewed commit and PR URL. Do not merge, bump `VERSION`, tag, or publish `v1.0.12`.
