# macOS CI Portability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make PR #66's shell suite terminate and pass on Ubuntu and macOS without GNU-only utilities.

**Architecture:** Put the PTY behavior in one sourced test helper. Use Python's standard-library PTY primitives with a select loop that forwards piped input, sends terminal EOF once the pipe closes, and watches the direct child with `waitpid` so inherited slave descriptors cannot hang the driver. Use `shasum -a 256` and POSIX `find -perm` for the remaining portable test/runtime operations.

**Tech Stack:** POSIX shell, Python 3 standard library, GitHub Actions.

## Global Constraints

- Interactive tests must continue to use a real pseudo-terminal.
- Product prompts, release verification, and governance routing must not change.
- Add no package installation step or dependency.
- Keep existing shell tests as the verification harness.

---

### Task 1: Shared PTY lifecycle

**Files:**
- Create: `tests/pty.shlib`
- Modify: `tests/bootstrap.sh`
- Modify: `tests/connectors.sh`
- Modify: `tests/launcher.sh`
- Modify: `tests/routing.sh`

**Interfaces:**
- Produces: `run_pty COMMAND`, a sourced shell function that forwards stdin through a real PTY, sends one terminal EOF byte after piped stdin closes, streams output, and returns the child's exit code.

- [ ] **Step 1: Verify the existing regression is red**

Run: `timeout 15s sh tests/bootstrap.sh`

Expected: exit 124 while an invalid interactive role waits for more terminal input.

- [ ] **Step 2: Add the minimal shared implementation**

Create `tests/pty.shlib` with:

```sh
run_pty() {
  /usr/bin/python3 -c '
import os, pty, select, sys

pid, master = pty.fork()
if pid == 0:
    os.execv("/bin/sh", ["/bin/sh", "-c", sys.argv[1]])

os.set_blocking(master, False)
stdin_open = True
pending_input = b""
status = None

while status is None:
    readers = [master]
    if stdin_open and not pending_input:
        readers.append(sys.stdin.fileno())
    writers = [master] if pending_input else []
    ready_read, ready_write, _ = select.select(readers, writers, [], 0.1)

    if sys.stdin.fileno() in ready_read:
        data = os.read(sys.stdin.fileno(), 1024)
        if data:
            pending_input = data
        else:
            pending_input = b"\x04"
            stdin_open = False

    if master in ready_write:
        pending_input = pending_input[os.write(master, pending_input):]

    if master in ready_read:
        try:
            data = os.read(master, 1024)
        except OSError:
            data = b""
        if data:
            os.write(sys.stdout.fileno(), data)

    waited, child_status = os.waitpid(pid, os.WNOHANG)
    if waited:
        status = child_status

while True:
    try:
        data = os.read(master, 1024)
    except (BlockingIOError, OSError):
        break
    if not data:
        break
    os.write(sys.stdout.fileno(), data)

sys.exit(os.waitstatus_to_exitcode(status))
' "$1"
}
```

Source it with `. "$ROOT/tests/pty.shlib"` in the four callers and delete their copied `run_pty` functions.

- [ ] **Step 3: Verify EOF and exit-status behavior is green**

Run: `sh tests/bootstrap.sh`

Expected: `Bootstrap onboarding tests: PASS` without hanging; invalid-role cases still return nonzero.

Run: `sh tests/connectors.sh && sh tests/launcher.sh && sh tests/routing.sh`

Expected: all three existing suites pass.

### Task 2: Native command portability and CI containment

**Files:**
- Modify: `bin/beroka-governance`
- Modify: `tests/bootstrap.sh`
- Modify: `tests/cursor-hooks.sh`
- Modify: `tests/smoke.sh`
- Modify: `.github/workflows/tests.yml`

**Interfaces:**
- Consumes: native `shasum -a 256` available on both GitHub runner images.
- Produces: identical 64-character lowercase SHA-256 values and a 15-minute matrix-job timeout.

- [ ] **Step 1: Replace GNU-only operations**

Replace each `sha256sum` invocation with `shasum -a 256`. Replace `/usr/bin/stat -c '%a'` in the staged-file permission check with an exact POSIX `find PATH -prune -perm 0600 -print` check.

Preserve NUL-ended personal instruction bytes during managed-block removal by copying the raw prefix with Perl rather than printing binary data through BSD awk.

Confirm JSON-RPC response ID `1` with `jq` so BSD awk cannot mistake escaped `"id":1` text inside a notification value for a top-level response ID.

- [ ] **Step 2: Add the CI timeout**

Add `timeout-minutes: 15` to the matrix job beside `runs-on`.

- [ ] **Step 3: Verify the complete suite**

Run:

```sh
set -eu
for f in tests/*.sh; do
  echo "=== $f ==="
  sh "$f"
done
```

Expected: every test script reports PASS and the loop exits 0.

- [ ] **Step 4: Review and publish**

Run `git diff --check`, inspect the full diff against the design and unresolved PR thread, commit, push `ci/macos-test-matrix`, and wait for both PR #66 matrix jobs to finish successfully before resolving or replying to the thread.
