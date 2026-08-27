# Modular Governance CLI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the monolithic CLI source with domain-oriented POSIX shell modules and a deterministic build while preserving every public behavior.

**Architecture:** Source lives in seven ordered `src/*.sh` modules. A small POSIX build script concatenates and syntax-checks those modules into the committed, self-contained `bin/beroka-governance` release artifact; bootstrap and runtime consumers remain unchanged.

**Tech Stack:** POSIX `sh`, Git, existing shell test harness, GitHub Actions on Ubuntu and macOS.

**Spec:** `docs/superpowers/specs/2026-08-27-modular-governance-cli-design.md`

## Global Constraints

- Preserve all commands, arguments, exit statuses, result codes, and output.
- Preserve the verified, immutable release and user-scoped installation model.
- Preserve `release/bootstrap.sh.in` as a small, independent release launcher.
- Continue to support POSIX `sh` on Linux and macOS.
- Add no runtime dependency.
- Keep the generated CLI committed so release packaging remains unchanged.
- Keep security and destructive-action boundaries at least as strict as today.
- Do not implement offboarding, repository deletion, AI usage collection, telemetry storage, or a plugin framework.

---

## File Map

- Create `src/00-runtime.sh`: interpreter header, global state, errors, path safety, and shared low-level helpers.
- Create `src/10-repository.sh`: canonical repository discovery, catalog parsing, routing, role scope, and legacy-state inspection.
- Create `src/20-release.sh`: release validation, transactions, install/upgrade/uninstall, client enrollment, and instruction installation.
- Create `src/30-clients.sh`: GitHub and Atlassian client adapters, connector probing, OAuth, capabilities, and authentication preflight.
- Create `src/40-governance.sh`: handoff validation, Confluence routing, context, preflight, doctor, setup, and document display.
- Create `src/50-cursor-hooks.sh`: Cursor request parsing, workspace classification, receipts, template validation, and hook commands.
- Create `src/90-main.sh`: usage text, retired-command handling, command dispatch, and `main "$@"`.
- Create `scripts/build-cli.sh`: deterministic, atomic builder with default and `--check` modes.
- Create `tests/build.sh`: executable behavioral tests for artifact freshness, determinism, syntax rejection, and atomic replacement.
- Modify `bin/beroka-governance`: replace hand-maintained source with the generated artifact.
- Modify `PACKAGE-DESIGN.md`: document the source/build/release contract and add the build test to the release gate.
- Modify `tests/release.sh`: enforce the documented build contract and executable build test.

### Module Interfaces

- `00-runtime.sh` produces the existing global variables plus `die`, `pass_result`, `cleanup_personal_stage`, and `assert_safe_user_path`.
- `10-repository.sh` consumes runtime errors/state and produces `canonical_repo`, `resolve_repository_context`, `repository_is_governed`, `require_role_scope`, and routing state.
- `20-release.sh` consumes runtime/path helpers and repository validation; it produces `load_active_release`, `cmd_install`, `cmd_bootstrap`, `cmd_uninstall`, and client-enrollment state.
- `30-clients.sh` consumes active-release and role state; it produces client detection, connector health, OAuth boundaries, capability resolution, and `github_preflight`.
- `40-governance.sh` consumes repository, release, and client interfaces; it produces the existing context, preflight, doctor, setup, Confluence, and show commands.
- `50-cursor-hooks.sh` consumes the existing context/preflight interfaces; it produces `cmd_cursor_hook`.
- `90-main.sh` consumes all command functions and is the only module that invokes `main "$@"`.

---

### Task 1: Build the CLI from domain modules

**Files:**
- Create: `tests/build.sh`
- Create: `src/00-runtime.sh`
- Create: `src/10-repository.sh`
- Create: `src/20-release.sh`
- Create: `src/30-clients.sh`
- Create: `src/40-governance.sh`
- Create: `src/50-cursor-hooks.sh`
- Create: `src/90-main.sh`
- Create: `scripts/build-cli.sh`
- Modify: `bin/beroka-governance`

**Interfaces:**
- Consumes: the current `bin/beroka-governance` behavior.
- Produces: the seven module interfaces in the File Map, `scripts/build-cli.sh [--check]`, one generated executable, and an executable test automatically discovered by CI.

- [ ] **Step 1: Create the behavioral build test**

Write `tests/build.sh` with this structure:

```sh
#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/beroka-governance-build-test.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

fail() {
  printf '%s\n' "FAIL: $*" >&2
  exit 1
}

[ -x "$ROOT/scripts/build-cli.sh" ] ||
  fail 'build script is not executable'
"$ROOT/scripts/build-cli.sh" --check ||
  fail 'committed CLI is stale'

mkdir -p "$TMP_ROOT/repo"
cp -R "$ROOT/src" "$ROOT/scripts" "$ROOT/bin" "$TMP_ROOT/repo/"
builder=$TMP_ROOT/repo/scripts/build-cli.sh
artifact=$TMP_ROOT/repo/bin/beroka-governance

"$builder"
first_checksum=$(cksum "$artifact")
"$builder"
[ "$first_checksum" = "$(cksum "$artifact")" ] ||
  fail 'two builds produced different artifacts'
"$builder" --check || fail 'fresh artifact failed --check'

printf '%s\n' '# stale source mutation' >>"$TMP_ROOT/repo/src/00-runtime.sh"
if "$builder" --check >/dev/null 2>&1; then
  fail '--check accepted a stale artifact'
fi
"$builder"
"$builder" --check || fail 'rebuilt artifact failed --check'

good_checksum=$(cksum "$artifact")
printf '%s\n' 'if then' >>"$TMP_ROOT/repo/src/50-cursor-hooks.sh"
if "$builder" >/dev/null 2>&1; then
  fail 'builder accepted malformed shell'
fi
[ "$good_checksum" = "$(cksum "$artifact")" ] ||
  fail 'failed build replaced the last valid artifact'

printf '%s\n' 'Modular CLI build tests: PASS'
```

This test exercises the real builder and a disposable copy. It does not inspect
private builder functions or modify the working tree.

- [ ] **Step 2: Make the test executable**

Run:

```bash
chmod 755 tests/build.sh
```

- [ ] **Step 3: Run the test and verify RED**

Run:

```bash
sh tests/build.sh
```

Expected: exit 1 with `FAIL: build script is not executable`.

- [ ] **Step 4: Create the seven source modules by moving existing code unchanged**

Move complete function bodies, adjacent function-specific comments, and no
other behavior. Use these exact ownership groups:

```text
00-runtime.sh
  lines 1-50 global header/state
  cleanup_personal_stage, die, pass_result, assert_safe_user_path

10-repository.sh
  canonical_repo
  normalize_github_url through parse_routing
  read_github_role through require_role_scope
  legacy_repository_state

20-release.sh
  assert_install_paths
  assert_valid_template through cmd_uninstall

30-clients.sh
  client_executable through github_preflight

40-governance.sh
  require_trusted_confluence_body_gate
  handoff_body_is_safe through validate_handoff_body
  require_confluence_route through cmd_show

50-cursor-hooks.sh
  cursor_require_jq through cmd_cursor_hook

90-main.sh
  usage
  retired_command
  main
  main "$@"
```

`00-runtime.sh` is the only source file with `#!/bin/sh` and `set -eu`.
`90-main.sh` is the only source file with a top-level command invocation.
Function names and bodies remain byte-for-byte unchanged during the move.
Ensure every module ends with one newline.

- [ ] **Step 5: Add the deterministic builder**

Create executable `scripts/build-cli.sh`:

```sh
#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
OUTPUT=$ROOT/bin/beroka-governance
MODULES='
src/00-runtime.sh
src/10-repository.sh
src/20-release.sh
src/30-clients.sh
src/40-governance.sh
src/50-cursor-hooks.sh
src/90-main.sh
'

case "${1:-}" in
  '') mode=write ;;
  --check) mode=check ;;
  *)
    printf '%s\n' 'Usage: scripts/build-cli.sh [--check]' >&2
    exit 2
    ;;
esac
[ "$#" -le 1 ] || {
  printf '%s\n' 'Usage: scripts/build-cli.sh [--check]' >&2
  exit 2
}

temporary=$(mktemp "$ROOT/bin/.beroka-governance.XXXXXX")
trap 'rm -f "$temporary"' EXIT HUP INT TERM
: >"$temporary"
first=1
for relative in $MODULES; do
  module=$ROOT/$relative
  [ -f "$module" ] || {
    printf '%s\n' "Missing CLI module: $relative" >&2
    exit 1
  }
  if [ "$first" -eq 0 ]; then printf '\n' >>"$temporary"; fi
  first=0
  cat "$module" >>"$temporary"
done

sh -n "$temporary"
chmod 755 "$temporary"
if [ "$mode" = check ]; then
  if ! cmp -s "$temporary" "$OUTPUT"; then
    printf '%s\n' 'Generated CLI is stale. Run: scripts/build-cli.sh' >&2
    exit 1
  fi
  exit 0
fi
mv "$temporary" "$OUTPUT"
trap - EXIT HUP INT TERM
```

Run:

```bash
chmod 755 scripts/build-cli.sh
scripts/build-cli.sh
```

- [ ] **Step 6: Verify the generated script has one entrypoint and valid syntax**

Run:

```bash
sh -n src/*.sh scripts/build-cli.sh bin/beroka-governance
test "$(rg -n '^main "\$@"$' bin/beroka-governance | wc -l)" -eq 1
scripts/build-cli.sh --check
```

Expected: all commands exit 0 with no output.

- [ ] **Step 7: Run the focused build test and verify GREEN**

Run:

```bash
sh tests/build.sh
```

Expected: `Modular CLI build tests: PASS`.

- [ ] **Step 8: Run the existing smoke and routing suites**

```bash
sh tests/smoke.sh
sh tests/routing.sh
```

Expected:

```text
PASS: user-scoped governance commands
PASS: routing state
```

- [ ] **Step 9: Review the extraction for accidental behavior edits**

Run:

```bash
git diff --check
git diff --stat
git status --short
```

Expected: only the seven modules, builder, generated artifact, and Task 1 test
are part of this extraction. No bootstrap, runtime policy, template, or catalog
file changes.

- [ ] **Step 10: Commit the modular source and builder**

```bash
git add src scripts/build-cli.sh bin/beroka-governance tests/build.sh
git commit -m "refactor: build governance CLI from domain modules"
```

---

### Task 2: Document and enforce the generated-artifact release contract

**Files:**
- Modify: `PACKAGE-DESIGN.md`
- Modify: `tests/release.sh`
- Test: `tests/build.sh`
- Test: `tests/release.sh`

**Interfaces:**
- Consumes: Task 1's `scripts/build-cli.sh --check` and committed generated artifact.
- Produces: release documentation and regression assertions that make the build contract visible to maintainers.

- [ ] **Step 1: Add failing release assertions**

Near the existing release-gate assertions in `tests/release.sh`, add:

```sh
[ -x "$ROOT/scripts/build-cli.sh" ] ||
  fail 'modular CLI builder is not executable'
[ -x "$ROOT/tests/build.sh" ] ||
  fail 'modular CLI build test is not executable'
require_text PACKAGE-DESIGN.md 'Source modules are concatenated in a fixed order'
require_text PACKAGE-DESIGN.md 'scripts/build-cli.sh --check'
require_text PACKAGE-DESIGN.md 'sh tests/build.sh'
```

- [ ] **Step 2: Run the release test and verify RED**

Run:

```bash
sh tests/release.sh
```

Expected: failure because `PACKAGE-DESIGN.md` does not yet contain the
modular build contract.

- [ ] **Step 3: Document the source and release contract**

Add a `### Modular CLI source` subsection immediately before
`### Release launcher` in `PACKAGE-DESIGN.md`:

```markdown
### Modular CLI source

The maintained CLI source is split by domain under `src/`. Source modules are
concatenated in a fixed order by `scripts/build-cli.sh` into the committed,
self-contained `bin/beroka-governance` artifact. Runtime installation and
release verification continue to consume that single artifact and do not
source files from the working tree.

Run `scripts/build-cli.sh` after changing a module. CI runs
`scripts/build-cli.sh --check` through `sh tests/build.sh` and rejects a
stale, nondeterministic, or syntactically invalid generated artifact.
```

Add `sh tests/build.sh` to the existing release-gate command block before the
other behavioral suites.

- [ ] **Step 4: Run focused documentation and release tests**

```bash
sh tests/build.sh
sh tests/release.sh
sh tests/documentation-architecture.sh
```

Expected:

```text
Modular CLI build tests: PASS
First public release readiness: PASS
Documentation architecture tests: PASS
```

- [ ] **Step 5: Commit the release contract**

```bash
git add PACKAGE-DESIGN.md tests/release.sh
git commit -m "docs: define modular CLI release contract"
```

---

### Task 3: Run the complete foundation verification

**Files:**
- Verify only; no planned source changes.

**Interfaces:**
- Consumes: Tasks 1-2.
- Produces: fresh evidence that the modular source preserves the complete governance behavior.

- [ ] **Step 1: Verify syntax and artifact freshness**

```bash
sh -n src/*.sh scripts/build-cli.sh bin/beroka-governance release/bootstrap.sh.in tests/*.sh
scripts/build-cli.sh --check
git diff --check origin/main...HEAD
```

Expected: all commands exit 0 with no output.

- [ ] **Step 2: Run every test suite exactly as CI does**

```bash
set -eu
for test_file in tests/*.sh; do
  echo "=== $test_file ==="
  sh "$test_file"
done
```

Expected: every test exits 0, including:

```text
Modular CLI build tests: PASS
Bootstrap onboarding tests: PASS
Connector selection tests: PASS
PASS: Cursor hook runtime
Documentation architecture tests: PASS
One-command launcher tests: PASS
First public release readiness: PASS
PASS: routing state
PASS: user-scoped governance commands
```

- [ ] **Step 3: Verify worktree and commit structure**

```bash
git status --short --branch
git log --oneline origin/main..HEAD
```

Expected: clean worktree and three focused commits: the existing design commit,
the modular extraction commit, and the release-contract documentation commit.

- [ ] **Step 4: Stop before external writes**

Do not push or create a pull request until the user selects an integration
option. A fresh `github-write` governance preflight is required immediately
before each later push, PR creation, review reply, or other GitHub write.
