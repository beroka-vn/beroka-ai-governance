# Client-Specific Governance Entrypoints Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make repository registration additive and client-specific so each invocation configures exactly one AI client while every enabled client loads the same pinned governance ruleset.

**Architecture:** Store the canonical enabled-client set in the existing lock as `CLIENTS`. Reuse the existing transaction and marker helpers to create, verify, refresh, and remove only declared entrypoints; keep connector/OAuth state local and unchanged.

**Tech Stack:** POSIX `sh`, Git, existing shell test scripts, temporary HOME/XDG directories, fake clients.

## Global Constraints

- An invocation selects exactly one of `codex`, `claude`, or `cursor`.
- Client selection is additive and idempotent; it never enables every installed client automatically.
- `CLIENTS` is non-empty, duplicate-free, and ordered `codex,claude,cursor`.
- Codex owns `AGENTS.md`, Claude Code owns `CLAUDE.md`, and Cursor owns `.cursor/rules/beroka-governance.mdc`.
- Every entrypoint independently invokes `beroka-governance context "$PWD"` and loads the release pinned by the same lock.
- Existing unrelated `AGENTS.md` and `CLAUDE.md` content must be preserved.
- OAuth state and credentials remain owned by the selected client/OS keyring.
- Governance must never accept, print, log, or store developer API tokens or OAuth credentials.
- Tests use temporary repositories, HOME/XDG directories, fake clients, and no real credentials.
- Do not push or overwrite the public `v1.0.0` tag before both canonical pilots pass.

---

### Task 1: Implement the client-aware repository contract

**Files:**
- Modify: `bin/beroka-governance:25-40, 762-875, 880-1170, 2445-2472, 2533-2557`
- Modify: `templates/agent-entrypoints/CLAUDE.md`
- Modify: `templates/agent-entrypoints/team-dev-ai-workflow.mdc`
- Modify: `tests/smoke.sh:100-598`

**Interfaces:**
- Consumes: existing transaction helpers, marker helpers, `release_for_version`, and the three entrypoint templates.
- Produces: `LOCK_CLIENTS`, `client_list_contains LIST CLIENT`, `canonical_clients LIST CLIENT`, `stage_client_entrypoint REPO RELEASE CLIENT`, and a client-aware `verify_entrypoints`.

- [ ] **Step 1: Add failing isolated registration tests**

Add fresh Codex, Claude, and Cursor consumers near the start of the registration
section in `tests/smoke.sh`:

```sh
codex_repo=$TMP_ROOT/codex-consumer
new_repo "$codex_repo"
git -C "$codex_repo" remote add origin \
  https://github.com/beroka-vn/codex-consumer.git
$CLI register "$codex_repo" --version v1.0.0 --client codex
assert_contains "$(cat "$codex_repo/.beroka-governance.lock")" \
  'CLIENTS=codex'
[ -f "$codex_repo/AGENTS.md" ] ||
  fail 'Codex registration omitted AGENTS.md'
[ ! -e "$codex_repo/CLAUDE.md" ] ||
  fail 'Codex registration created CLAUDE.md'
[ ! -e "$codex_repo/.cursor" ] ||
  fail 'Codex registration created .cursor'

claude_repo=$TMP_ROOT/claude-consumer
new_repo "$claude_repo"
git -C "$claude_repo" remote add origin \
  https://github.com/beroka-vn/claude-consumer.git
$CLI register "$claude_repo" --version v1.0.0 --client claude
assert_contains "$(cat "$claude_repo/.beroka-governance.lock")" \
  'CLIENTS=claude'
[ -f "$claude_repo/CLAUDE.md" ] ||
  fail 'Claude registration omitted CLAUDE.md'
[ ! -e "$claude_repo/AGENTS.md" ] ||
  fail 'Claude registration created AGENTS.md'
[ ! -e "$claude_repo/.cursor" ] ||
  fail 'Claude registration created .cursor'

cursor_repo=$TMP_ROOT/cursor-consumer
new_repo "$cursor_repo"
git -C "$cursor_repo" remote add origin \
  https://github.com/beroka-vn/cursor-consumer.git
$CLI register "$cursor_repo" --version v1.0.0 --client cursor
assert_contains "$(cat "$cursor_repo/.beroka-governance.lock")" \
  'CLIENTS=cursor'
[ -f "$cursor_repo/.cursor/rules/beroka-governance.mdc" ] ||
  fail 'Cursor registration omitted its rule'
[ ! -e "$cursor_repo/AGENTS.md" ] ||
  fail 'Cursor registration created AGENTS.md'
[ ! -e "$cursor_repo/CLAUDE.md" ] ||
  fail 'Cursor registration created CLAUDE.md'
```

Add additive/idempotent assertions:

```sh
codex_hash=$(git -C "$codex_repo" hash-object AGENTS.md)
$CLI register "$codex_repo" --version v1.0.0 --client claude
assert_contains "$(cat "$codex_repo/.beroka-governance.lock")" \
  'CLIENTS=codex,claude'
[ "$codex_hash" = "$(git -C "$codex_repo" hash-object AGENTS.md)" ] ||
  fail 'adding Claude rewrote the Codex entrypoint'
[ ! -e "$codex_repo/.cursor" ] ||
  fail 'adding Claude created .cursor'

before_repeat=$(git -C "$codex_repo" hash-object \
  AGENTS.md CLAUDE.md .beroka-governance.lock)
$CLI register "$codex_repo" --version v1.0.0 --client claude
after_repeat=$(git -C "$codex_repo" hash-object \
  AGENTS.md CLAUDE.md .beroka-governance.lock)
[ "$before_repeat" = "$after_repeat" ] ||
  fail 'repeated client registration changed repository state'
```

Add malformed lock and stale-entrypoint cases:

```sh
cp "$codex_repo/.beroka-governance.lock" "$TMP_ROOT/codex.lock"
sed 's/^CLIENTS=.*/CLIENTS=cursor,codex/' "$TMP_ROOT/codex.lock" \
  >"$codex_repo/.beroka-governance.lock"
if output=$($CLI doctor "$codex_repo" 2>&1); then
  fail 'Doctor accepted non-canonical CLIENTS'
fi
assert_contains "$output" 'Result: GOVERNANCE_NOT_READY'
cp "$TMP_ROOT/codex.lock" "$codex_repo/.beroka-governance.lock"

sed 's/^CLIENTS=.*/CLIENTS=codex,codex/' "$TMP_ROOT/codex.lock" \
  >"$codex_repo/.beroka-governance.lock"
if output=$($CLI doctor "$codex_repo" 2>&1); then
  fail 'Doctor accepted duplicate CLIENTS'
fi
assert_contains "$output" 'Result: GOVERNANCE_NOT_READY'
cp "$TMP_ROOT/codex.lock" "$codex_repo/.beroka-governance.lock"

mkdir -p "$claude_repo/.cursor/rules"
cp "$source_repo/templates/agent-entrypoints/team-dev-ai-workflow.mdc" \
  "$claude_repo/.cursor/rules/beroka-governance.mdc"
if output=$($CLI doctor "$claude_repo" 2>&1); then
  fail 'Doctor accepted an undeclared Cursor entrypoint'
fi
assert_contains "$output" 'Result: ENTRYPOINT_DRIFT'
```

- [ ] **Step 2: Run the new tests and verify RED**

Run:

```bash
sh tests/smoke.sh
```

Expected: FAIL at the first `register ... --client codex` call because the
current command grammar does not accept `--client`.

- [ ] **Step 3: Add canonical client-state helpers and lock parsing**

In `bin/beroka-governance`, initialize `LOCK_CLIENTS` with the other lock
globals and add:

```sh
client_list_contains() {
  clc_list=$1 clc_client=$2
  case ",$clc_list," in
    *",$clc_client,"*) return 0 ;;
    *) return 1 ;;
  esac
}

validate_clients() {
  case "$1" in
    codex|claude|cursor|codex,claude|codex,cursor|claude,cursor|codex,claude,cursor) ;;
    *) die GOVERNANCE_NOT_READY 'Invalid CLIENTS' ;;
  esac
}

canonical_clients() {
  cc_current=$1 cc_selected=$2 cc_result=
  for cc_client in codex claude cursor; do
    if client_list_contains "$cc_current" "$cc_client" ||
      [ "$cc_selected" = "$cc_client" ]
    then
      if [ -n "$cc_result" ]; then
        cc_result=$cc_result,$cc_client
      else
        cc_result=$cc_client
      fi
    fi
  done
  validate_clients "$cc_result"
  printf '%s\n' "$cc_result"
}
```

Extend `read_lock` with one allowlisted `CLIENTS` key, one duplicate guard, and
`validate_clients "$LOCK_CLIENTS"`. Change `write_lock_file` to accept a fifth
argument and emit:

```sh
printf '%s\n' \
  "SOURCE=$SOURCE_SLUG" \
  "REPOSITORY=$repository" \
  "VERSION=$version" \
  "COMMIT=$commit" \
  "CLIENTS=$clients" >"$destination" ||
  die GOVERNANCE_NOT_READY 'Cannot stage governance lock'
```

Do not infer a missing `CLIENTS`; unpublished candidate locks must fail closed.

- [ ] **Step 4: Make each entrypoint independent**

Replace `templates/agent-entrypoints/CLAUDE.md` with the same managed routing
block used by `templates/agent-entrypoints/AGENTS.md`.

Remove the `Follow @AGENTS.md.` sentence from the Cursor template so its body is:

```text
Run `beroka-governance context "$PWD"` before governed work. Continue only when
it returns `Result: PASS`; then use `beroka-governance show` to load only the
relevant document or template.
```

Delete `write_claude_entrypoint`; both marker-based files use the existing
`write_entrypoint`.

- [ ] **Step 5: Stage and verify only declared clients**

Add a shared staging helper:

```sh
stage_client_entrypoint() {
  sce_repo=$1 sce_release=$2 sce_client=$3
  case "$sce_client" in
    codex)
      sce_template=$sce_release/templates/agent-entrypoints/AGENTS.md
      assert_valid_template "$sce_template"
      write_entrypoint "$sce_repo/AGENTS.md" "$sce_template" \
        "$TX_DIR/work/agents"
      tx_stage_write AGENTS.md "$TX_DIR/work/agents"
      ;;
    claude)
      sce_template=$sce_release/templates/agent-entrypoints/CLAUDE.md
      assert_valid_template "$sce_template"
      write_entrypoint "$sce_repo/CLAUDE.md" "$sce_template" \
        "$TX_DIR/work/claude"
      tx_stage_write CLAUDE.md "$TX_DIR/work/claude"
      ;;
    cursor)
      sce_template=$sce_release/templates/agent-entrypoints/team-dev-ai-workflow.mdc
      [ -f "$sce_template" ] ||
        die ENTRYPOINT_DRIFT "Missing Cursor rule in $sce_release"
      tx_stage_write .cursor/rules/beroka-governance.mdc "$sce_template"
      ;;
    *) usage >&2; exit 2 ;;
  esac
}

stage_client_entrypoints() {
  sces_repo=$1 sces_release=$2 sces_clients=$3
  for sces_client in codex claude cursor; do
    client_list_contains "$sces_clients" "$sces_client" ||
      continue
    stage_client_entrypoint "$sces_repo" "$sces_release" "$sces_client"
  done
}
```

Rewrite `verify_entrypoints` so it:

1. validates exact managed blocks only for declared Codex/Claude clients;
2. validates the exact Cursor file only when Cursor is declared;
3. returns `ENTRYPOINT_DRIFT` when either marker occurs in an undeclared
   `AGENTS.md` or `CLAUDE.md`; and
4. returns `ENTRYPOINT_DRIFT` when the dedicated Cursor rule exists but Cursor
   is undeclared.

Use this exact membership pattern for all three clients:

```sh
if client_list_contains "$LOCK_CLIENTS" codex; then
  [ -f "$entrypoints_repo/AGENTS.md" ] ||
    die ENTRYPOINT_DRIFT 'Missing AGENTS.md'
  if ! extract_managed_block "$entrypoints_repo/AGENTS.md" \
    "$entrypoints_dir/agents" ||
    ! cmp -s "$entrypoints_dir/agents" "$agents_template"
  then
    rm -rf "$entrypoints_dir" || :
    die ENTRYPOINT_DRIFT 'AGENTS.md managed block differs from the release'
  fi
elif grep -Fq "$START_MARKER" "$entrypoints_repo/AGENTS.md" 2>/dev/null ||
  grep -Fq "$END_MARKER" "$entrypoints_repo/AGENTS.md" 2>/dev/null
then
  rm -rf "$entrypoints_dir" || :
  die ENTRYPOINT_DRIFT 'Undeclared AGENTS.md managed block'
fi
```

- [ ] **Step 6: Make register, repin, and unregister client-aware**

Change direct registration syntax to:

```text
beroka-governance register REPO --version VERSION --client codex|claude|cursor [--dry-run]
```

Parse `requested`, `--version`, version, `--client`, client, and optional
`--dry-run`. Validate the client with `client_executable "$client" >/dev/null`;
this validates the name without checking whether the client is installed.

For a new registration:

```sh
resolve_canonical_remote "$REPO"
repository=$(normalize_github_url "$CANONICAL_REMOTE_URL") ||
  die REMOTE_MISMATCH 'Canonical remote is not a supported GitHub repository'
clients=$client
preflight_undeclared_entrypoints "$REPO" "$clients"
release_for_version "$version"
```

For an existing registration:

```sh
verify_registration "$REPO"
[ "$version" = "$LOCK_VERSION" ] ||
  die VERSION_MISMATCH \
    "Repository is pinned to $LOCK_VERSION; use update to change it"
repository=$LOCK_REPOSITORY
clients=$(canonical_clients "$LOCK_CLIENTS" "$client")
```

Stage the lock with `clients`, then call only:

```sh
stage_client_entrypoint "$REPO" "$RELEASE_DIR" "$client"
```

In `cmd_repin`, preserve `clients=$LOCK_CLIENTS`, write it to the new lock, and
call:

```sh
stage_client_entrypoints "$REPO" "$RELEASE_DIR" "$clients"
```

In `cmd_unregister`, strip the Codex and Claude managed blocks only when their
clients are declared, delete the dedicated Cursor file only when Cursor is
declared, then remove the lock. Keep the current unmanaged-content preservation
and transaction behavior.

Update all `tests/smoke.sh` registration calls with an explicit client chosen
for the path under test:

- `codex` for AGENTS, marker, dirty AGENTS, registry, and generic lifecycle
  cases;
- `cursor` for ignored Cursor and Cursor symlink cases; and
- add `claude` and `cursor` explicitly to the main lifecycle repository before
  assertions that intentionally cover all three files.

- [ ] **Step 7: Gate connector-aware Doctor by repository client state**

Immediately after `verify_registration "$requested"` in `cmd_doctor`, before
dependency or connector checks, add:

```sh
if [ -n "$doctor_client" ] &&
  ! client_list_contains "$LOCK_CLIENTS" "$doctor_client"
then
  die CLIENT_SETUP_REQUIRED \
    "Remediation: beroka-governance bootstrap $REPO --client $doctor_client"
fi
```

Add a smoke assertion using a Codex-only repository:

```sh
if output=$($CLI doctor "$codex_repo" --client cursor 2>&1); then
  fail 'Doctor accepted an unregistered client'
fi
assert_contains "$output" 'Result: CLIENT_SETUP_REQUIRED'
assert_contains "$output" \
  "Remediation: beroka-governance bootstrap $codex_repo --client cursor"
```

- [ ] **Step 8: Run the repository lifecycle suite and verify GREEN**

Run:

```bash
sh tests/smoke.sh
```

Expected final lines:

```text
PASS: safe removal and drift detection
```

- [ ] **Step 9: Commit the repository contract**

```bash
git add bin/beroka-governance \
  templates/agent-entrypoints/CLAUDE.md \
  templates/agent-entrypoints/team-dev-ai-workflow.mdc \
  tests/smoke.sh
git commit -m "feat: register selected agent entrypoints"
```

---

### Task 2: Carry the selected-client contract through bootstrap and isolated suites

**Files:**
- Modify: `bin/beroka-governance:858-872`
- Modify: `tests/bootstrap.sh:166-285`
- Modify: `tests/connectors.sh:508-602`
- Modify: `tests/routing.sh:311-328`

**Interfaces:**
- Consumes: Task 1 `cmd_register ... --client CLIENT`, `LOCK_CLIENTS`, and client-aware Doctor.
- Produces: idempotent bootstrap for enabled clients and additive bootstrap for new clients.

- [ ] **Step 1: Add failing bootstrap assertions**

After first Codex bootstrap in `tests/bootstrap.sh`, assert:

```sh
grep -Fx 'CLIENTS=codex' "$repo/.beroka-governance.lock" >/dev/null ||
  fail 'bootstrap did not record the selected client'
[ -f "$repo/AGENTS.md" ] ||
  fail 'Codex bootstrap omitted AGENTS.md'
[ ! -e "$repo/CLAUDE.md" ] ||
  fail 'Codex bootstrap created CLAUDE.md'
[ ! -e "$repo/.cursor" ] ||
  fail 'Codex bootstrap created .cursor'
```

After bootstrapping Claude into the same repository, assert:

```sh
assert_contains "$output" 'Repository changes: REVIEW_REQUIRED'
grep -Fx 'CLIENTS=codex,claude' \
  "$repo/.beroka-governance.lock" >/dev/null ||
  fail 'second bootstrap did not add Claude'
[ -f "$repo/CLAUDE.md" ] ||
  fail 'second bootstrap omitted CLAUDE.md'
[ ! -e "$repo/.cursor" ] ||
  fail 'second bootstrap created Cursor files'
```

Repeat Claude bootstrap, compare `snapshot_repo` before/after, and require
`Repository changes: NONE`.

- [ ] **Step 2: Run bootstrap tests and verify RED**

Run:

```bash
sh tests/bootstrap.sh
```

Expected: FAIL because `cmd_bootstrap` still calls `cmd_register` without
`--client`.

- [ ] **Step 3: Pass the selected client through bootstrap**

Change the bootstrap registration call to:

```sh
cmd_register "$bs_repo" --version "$bs_version" --client "$bs_client"
```

Keep connector setup and Doctor checks scoped to `bs_client`. Healthy local
authentication continues through the existing early PASS path and must not
invoke OAuth.

- [ ] **Step 4: Update connector and routing fixtures**

In `tests/connectors.sh`, construct the Doctor consumer as Codex-only:

```sh
cp "$RELEASE_SOURCE/templates/agent-entrypoints/AGENTS.md" \
  "$CONSUMER/AGENTS.md"
printf '%s\n' \
  'SOURCE=beroka-vn/beroka-ai-governance' \
  'REPOSITORY=beroka-vn/consumer' \
  "VERSION=$RELEASE_VERSION" \
  "COMMIT=$RELEASE_COMMIT" \
  'CLIENTS=codex' \
  >"$CONSUMER/.beroka-governance.lock"
```

Do not create `CLAUDE.md` or `.cursor` for that fixture. Retain the existing
assertion that healthy Codex auth does not call `codex mcp login atlassian`.

In `tests/routing.sh`, register Codex explicitly:

```sh
$CLI register "$consumer" --version v1.1.0 --client codex
```

Copy and commit only:

```sh
cp "$consumer/.beroka-governance.lock" "$remote_work/.beroka-governance.lock"
cp "$consumer/AGENTS.md" "$remote_work/AGENTS.md"
git -C "$remote_work" add .beroka-governance.lock AGENTS.md
```

Add an explicit client to every remaining direct register call. The initial
`tests/smoke.sh` consumer already contains all three entrypoints, so give it
`CLIENTS=codex,claude,cursor`. The `tests/connectors.sh` consumer contains only
`AGENTS.md`, so give it `CLIENTS=codex`. `tests/routing.sh` obtains its lock from
the Codex registration command instead of hand-writing it.

- [ ] **Step 5: Run all isolated suites**

Run:

```bash
sh tests/smoke.sh
sh tests/connectors.sh
sh tests/bootstrap.sh
```

Expected:

```text
PASS: safe removal and drift detection
Connector selection tests: PASS
Bootstrap onboarding tests: PASS
```

Then run the routing suite in a clean isolated clone, as required by its own
test contract:

```bash
routing_clone=$(mktemp -d "${TMPDIR:-/tmp}/beroka-routing.XXXXXX")
git clone -q --no-local . "$routing_clone/repo"
git -C "$routing_clone/repo" checkout -q HEAD
sh "$routing_clone/repo/tests/routing.sh"
```

Expected:

```text
Routing and operation preflight tests: PASS
```

- [ ] **Step 6: Commit bootstrap and fixture integration**

```bash
git add bin/beroka-governance \
  tests/bootstrap.sh tests/connectors.sh tests/routing.sh
git commit -m "test: cover additive client bootstrap"
```

---

### Task 3: Update operator documentation and validate the real rollout

**Files:**
- Modify: `README.md:27-86`
- Modify: `handbook.md:174-195`
- Modify: `PACKAGE-DESIGN.md:92-145, 369-404`

**Interfaces:**
- Consumes: completed CLI behavior and passing isolated suites.
- Produces: exact developer commands and release gates for Codex, Claude Code, and Cursor.

- [ ] **Step 1: Add failing documentation checks**

Append to the documentation assertions in `tests/connectors.sh`:

```sh
grep -F 'CLIENTS=codex,claude' "$ROOT/PACKAGE-DESIGN.md" >/dev/null ||
  fail 'package design does not document additive clients'
grep -F 'register "$repo" --version "$release" --client codex' \
  "$ROOT/handbook.md" >/dev/null ||
  fail 'handbook register command does not select a client'
grep -F 'bootstrap "$repo" --client claude' "$ROOT/README.md" >/dev/null ||
  fail 'README does not document adding another client'
```

- [ ] **Step 2: Run the documentation assertion and verify RED**

Run:

```bash
sh tests/connectors.sh
```

Expected: FAIL with the first missing client-specific documentation message.

- [ ] **Step 3: Update the public contract**

In `PACKAGE-DESIGN.md`, replace the unconditional four-entrypoint contract with
the client table from the approved spec and this lock example:

```text
SOURCE=beroka-vn/beroka-ai-governance
REPOSITORY=beroka-vn/example-backend
VERSION=v1.0.0
COMMIT=0123456789abcdef0123456789abcdef01234567
CLIENTS=codex,claude
```

State that all entrypoints independently load the same central release,
unlisted managed entrypoints are drift, and a missing `CLIENTS` is invalid
before the first public release.

In `handbook.md`, change direct registration to:

```bash
beroka-governance register "$repo" \
  --version "$release" \
  --client codex
git -C "$repo" diff -- .beroka-governance.lock AGENTS.md
```

Document that adding Claude is explicit:

```bash
beroka-governance bootstrap "$repo" --client claude
git -C "$repo" diff -- .beroka-governance.lock CLAUDE.md
```

In `README.md`, explain that setup is additive, existing client entrypoints are
not rewritten, and local OAuth may still be required on another developer
machine. Include:

```bash
beroka-governance bootstrap "$repo" --client claude
```

- [ ] **Step 4: Run complete verification**

Run:

```bash
git diff --check
sh tests/smoke.sh
sh tests/connectors.sh
sh tests/bootstrap.sh
```

Run routing from a clean clone:

```bash
routing_clone=$(mktemp -d "${TMPDIR:-/tmp}/beroka-routing-final.XXXXXX")
git clone -q --no-local . "$routing_clone/repo"
git -C "$routing_clone/repo" checkout -q HEAD
sh "$routing_clone/repo/tests/routing.sh"
```

All four suites must exit `0`.

- [ ] **Step 5: Commit the documentation**

```bash
git add README.md handbook.md PACKAGE-DESIGN.md tests/connectors.sh
git commit -m "docs: explain additive agent setup"
```

- [ ] **Step 6: Push and open the Governance PR**

Use `github:yeet` to verify scope, push
`agent/client-specific-entrypoints`, and open a draft PR against `main`.

The PR must contain only:

- the approved spec and implementation plan;
- `bin/beroka-governance`;
- the two changed client templates;
- isolated tests; and
- the three public documentation files.

Do not create or reopen a Frontend `.cursor` PR.

- [ ] **Step 7: Run canonical post-merge pilots before tagging**

After the Governance PR is reviewed and merged, resolve the exact new
`origin/main` commit. Recreate only the local candidate `v1.0.0` annotated tag
at that commit; do not push it yet.

Use fresh canonical HTTPS clones of Backend and Frontend plus isolated
HOME/XDG/bin directories. For each repository run:

```bash
beroka-governance bootstrap "$pilot_repo" \
  --client codex \
  --version v1.0.0 \
  --non-interactive
```

If local Atlassian auth is absent, `ATLASSIAN_AUTH_REQUIRED` with
`codex mcp login atlassian` is the expected connector result. Then verify the
repository artifacts directly:

```bash
grep -Fx 'CLIENTS=codex' "$pilot_repo/.beroka-governance.lock"
test -f "$pilot_repo/AGENTS.md"
test ! -e "$pilot_repo/CLAUDE.md"
test ! -e "$pilot_repo/.cursor"
beroka-governance doctor "$pilot_repo"
```

`doctor` must return `PASS` for both repositories. Frontend must remain free of
`.cursor`. Only after both pilots pass may the annotated `v1.0.0` tag and GitHub
Release be pushed.
