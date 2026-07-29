# User-Scope Governance Installation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install, upgrade, and run Beroka governance entirely from user-owned state while leaving every application repository unchanged.

**Architecture:** Add a verified active-release record and user-level client enrollment, move routing into a central release catalog keyed by canonical GitHub slug, and make context, Doctor, and preflight read that catalog. Delete repository registration and entrypoint mutation paths; retain legacy files only as ignored diagnostics.

**Tech Stack:** POSIX shell, Git, GitHub CLI, jq, client-native MCP/OAuth commands, temporary HOME/XDG Git fixtures.

## Global Constraints

- Keep the application repository byte-for-byte unchanged during bootstrap, upgrade, connector setup, Doctor, and context loading.
- Do not create, modify, or delete `.beroka-governance.lock`, `AGENTS.md`, `CLAUDE.md`, `.cursor/`, the index, a branch, a commit, a push, an Issue, or a pull request in an application repository.
- `--client codex|claude|cursor` selects exactly one client per invocation.
- Codex and Claude managed blocks preserve all user content outside the Beroka markers.
- Cursor Individual uses one user-confirmed User Rule; never edit Cursor's undocumented internal settings database.
- Repository identity and routing come only from the verified central release catalog and canonical GitHub origin.
- Unknown repositories are standalone with `NO_DEPENDENCY_DECLARED`, `explicit-only`, and `ROUTING_REQUIRED`.
- OAuth credentials remain owned by the selected client and OS keyring.
- Never accept, print, log, or store a developer API token.
- Non-interactive authentication failure returns `ATLASSIAN_AUTH_REQUIRED` with the selected client's exact remediation.
- Bootstrap and upgrade perform no GitHub write operation and never open a repository pull request.
- Legacy repository governance files are `PRESENT_IGNORED`; they never become effective version or routing state.
- Do not create a release tag or GitHub Release while implementing this plan.

---

### Task 1: Verified Active Release State

**Files:**
- Modify: `bin/beroka-governance:5-17`
- Modify: `bin/beroka-governance:454-790`
- Modify: `tests/smoke.sh`

**Interfaces:**
- Consumes: existing `prepare_release VERSION`, `validate_release_checkout DIR VERSION`, and user-file transaction helpers.
- Produces: `ACTIVE_RELEASE=$CONFIG_ROOT/active-release`, `write_active_release FILE VERSION COMMIT`, and `load_active_release`.

- [ ] **Step 1: Add failing active-release tests**

Add an isolated install case to `tests/smoke.sh`:

```sh
active_file=$XDG_CONFIG_HOME/beroka-ai-governance/active-release
$CLI install v1.0.0 >/dev/null
[ "$(cat "$active_file")" = "$(printf '%s\n%s' \
  'VERSION=v1.0.0' "COMMIT=$v1_0_commit")" ] ||
  fail 'install omitted the verified active release'

printf '%s\n' 'VERSION=v1.0.0' \
  'COMMIT=0000000000000000000000000000000000000000' >"$active_file"
if output=$($CLI install v1.0.0 2>&1); then
  fail 'install accepted a forged active release commit'
fi
assert_contains "$output" 'Result: VERSION_MISMATCH'
```

Update the fixture to retain `v1_0_commit` from its annotated tag. Add a
failure-injection assertion that a failed CLI activation restores the previous
`active-release` file.

- [ ] **Step 2: Run the focused test and confirm RED**

Run:

```bash
sh tests/smoke.sh
```

Expected: FAIL because install does not create `active-release` and context
still depends on a repository lock.

- [ ] **Step 3: Implement the active-release record**

Add:

```sh
ACTIVE_RELEASE=$CONFIG_ROOT/active-release

write_active_release() {
  war_file=$1 war_version=$2 war_commit=$3
  printf '%s\n' \
    "VERSION=$war_version" \
    "COMMIT=$war_commit" >"$war_file" ||
    die GOVERNANCE_NOT_READY 'Cannot stage active release'
}

load_active_release() {
  assert_safe_user_path "$ACTIVE_RELEASE" 'active release'
  [ -f "$ACTIVE_RELEASE" ] ||
    die GOVERNANCE_NOT_READY 'No active governance release is installed'
  ar_values=$(awk -F= '
    $1 == "VERSION" && $2 ~ /^v[0-9]+\.[0-9]+\.[0-9]+$/ && !version++ {
      value=$2
    }
    $1 == "COMMIT" && $2 ~ /^[0-9a-f]{40}$/ && !commit++ {
      hash=$2
    }
    END {
      if (NR != 2 || version != 1 || commit != 1) exit 1
      print value "\t" hash
    }
  ' "$ACTIVE_RELEASE") ||
    die VERSION_MISMATCH 'Invalid active release record'
  ACTIVE_VERSION=${ar_values%%	*}
  ACTIVE_COMMIT=${ar_values#*	}
  release_for_version "$ACTIVE_VERSION"
  [ "$RELEASE_COMMIT" = "$ACTIVE_COMMIT" ] ||
    die VERSION_MISMATCH 'Active release commit does not match installed tag'
}
```

Extend `cmd_install`'s existing transaction:

```sh
write_active_release "$TX_DIR/work/active-release" \
  "$ci_version" "$RELEASE_COMMIT"
tx_snapshot_user_file "$ACTIVE_RELEASE" active-release
apply_user_file "$TX_DIR/work/active-release" "$ACTIVE_RELEASE" active-release
```

When `$ACTIVE_RELEASE` already exists, call `load_active_release` before
preparing another install. Restore the snapshot from `tx_abort` when
installation fails. Do not infer the active version from the copied CLI or
from an application repository.

- [ ] **Step 4: Run focused and regression tests**

Run:

```bash
sh tests/smoke.sh
sh tests/release.sh
```

Expected: both PASS, including rollback of the active-release record.

- [ ] **Step 5: Commit**

```bash
git add bin/beroka-governance tests/smoke.sh
git commit -m "refactor: track active governance release in user state"
```

---

### Task 2: User-Level Client Enrollment and Instructions

**Files:**
- Modify: `templates/agent-entrypoints/AGENTS.md`
- Modify: `templates/agent-entrypoints/CLAUDE.md`
- Delete: `templates/agent-entrypoints/team-dev-ai-workflow.mdc`
- Create: `templates/agent-entrypoints/CURSOR-USER-RULE.txt`
- Modify: `bin/beroka-governance:421-590`
- Modify: `bin/beroka-governance:779-925`
- Modify: `bin/beroka-governance:975-1162`
- Replace repository-mutation assertions in: `tests/bootstrap.sh`

**Interfaces:**
- Consumes: `load_active_release`, existing managed markers, `strip_managed_block`, `extract_managed_block`, `apply_user_file`, and `canonical_clients`.
- Produces: `CLIENTS_FILE=$CONFIG_ROOT/clients`, `CURSOR_ACK_FILE=$CONFIG_ROOT/cursor-user-rule.sha256`, `load_enabled_clients`, `enable_client CLIENT`, `active_instruction_file CLIENT`, `install_client_instruction CLIENT INTERACTIVE`, and user-scope `cmd_bootstrap`.

- [ ] **Step 1: Replace bootstrap tests with user-scope RED cases**

Keep the existing fake clients and release fixtures, but replace repository
lock/entrypoint assertions with:

```sh
repo_before=$(snapshot_repo "$repo")
printf '%s\n' '# Personal Codex instruction' >"$HOME/.codex/AGENTS.md"

output=$($CLI bootstrap "$repo" --client codex \
  --version v1.1.0 --non-interactive)

[ "$repo_before" = "$(snapshot_repo "$repo")" ] ||
  fail 'bootstrap changed the application repository'
assert_contains "$(cat "$HOME/.codex/AGENTS.md")" \
  '# Personal Codex instruction'
assert_contains "$(cat "$HOME/.codex/AGENTS.md")" \
  '<!-- BEROKA-GOVERNANCE:START -->'
[ "$(cat "$XDG_CONFIG_HOME/beroka-ai-governance/clients")" = codex ] ||
  fail 'bootstrap omitted Codex enrollment'
assert_not_contains "$output" 'Repository pull request:'
```

Add cases for:

```sh
printf '%s\n' '# Active override' >"$HOME/.codex/AGENTS.override.md"
printf '%s\n' '# Personal Claude instruction' >"$HOME/.claude/CLAUDE.md"
```

Verify Codex updates the active override, Claude preserves personal content,
reruns are byte-identical, adding Claude produces `codex,claude`, and neither
changes the repository.

For Cursor non-interactive first setup:

```sh
if output=$($CLI bootstrap "$repo" --client cursor \
  --version v1.1.0 --non-interactive 2>&1)
then
  fail 'Cursor bootstrap accepted a missing User Rule acknowledgement'
fi
assert_contains "$output" 'Result: CURSOR_USER_RULE_REQUIRED'
assert_contains "$output" \
  'Remediation: beroka-governance bootstrap --client cursor'
[ ! -e "$HOME/.cursor" ] ||
  fail 'Cursor bootstrap edited undocumented Cursor state'
```

- [ ] **Step 2: Run bootstrap tests and confirm RED**

Run:

```bash
sh tests/bootstrap.sh
```

Expected: FAIL because bootstrap still writes repository locks and entrypoints.

- [ ] **Step 3: Make the three instruction templates user-scoped**

Use this shared managed body for Codex and Claude:

```markdown
<!-- BEROKA-GOVERNANCE:START -->
## Beroka AI Governance

This workstation uses verified Beroka governance. In a Git repository, before
Jira, GitHub, Confluence, planning, or implementation work, run:

```bash
beroka-governance context "$PWD"
```

After context compaction, session resume, or a new chat, rerun context before
the next governed action. Run a fresh operation-specific preflight immediately
before every external write. Never rely on governance details preserved only
in conversation history.

Repository instructions may narrow governance but must not broaden authority
or bypass a central stop condition.
<!-- BEROKA-GOVERNANCE:END -->
```

`CURSOR-USER-RULE.txt` contains the same instructions without managed markers
or MDC frontmatter. Remove `team-dev-ai-workflow.mdc` from release validation.

- [ ] **Step 4: Implement user-owned enrollment and managed writes**

Add:

```sh
CLIENTS_FILE=$CONFIG_ROOT/clients
CURSOR_ACK_FILE=$CONFIG_ROOT/cursor-user-rule.sha256

active_instruction_file() {
  case "$1" in
    codex)
      codex_home=${CODEX_HOME:-$HOME/.codex}
      if [ -s "$codex_home/AGENTS.override.md" ]; then
        printf '%s\n' "$codex_home/AGENTS.override.md"
      else
        printf '%s\n' "$codex_home/AGENTS.md"
      fi
      ;;
    claude) printf '%s\n' "$HOME/.claude/CLAUDE.md" ;;
    cursor) return 1 ;;
  esac
}

load_enabled_clients() {
  ENABLED_CLIENTS=
  [ ! -e "$CLIENTS_FILE" ] || {
    [ -f "$CLIENTS_FILE" ] && [ ! -L "$CLIENTS_FILE" ] ||
      die GOVERNANCE_NOT_READY 'Unsafe client enrollment'
    ENABLED_CLIENTS=$(sed -n '1p' "$CLIENTS_FILE")
    validate_clients "$ENABLED_CLIENTS"
    [ "$(wc -l <"$CLIENTS_FILE" | tr -d ' ')" -eq 1 ] ||
      die GOVERNANCE_NOT_READY 'Invalid client enrollment'
  }
}
```

`enable_client` uses `canonical_clients`, stages `$CLIENTS_FILE`, and writes it
atomically with existing user-file helpers. `install_client_instruction`
validates markers, merges the active template into the active user file, and
preserves all content outside the managed block.

For Cursor, calculate:

```sh
cursor_rule_hash=$(git hash-object --no-filters \
  "$RELEASE_DIR/templates/agent-entrypoints/CURSOR-USER-RULE.txt")
```

Interactive setup prints the file, asks
`User Rule added in Cursor Settings > Rules? [y/N]`, and stores only that hash
after confirmation. Non-interactive setup without the matching hash returns
`CURSOR_USER_RULE_REQUIRED`. Report `Instruction: USER_CONFIRMED`, never
`VERIFIED`.

- [ ] **Step 5: Make bootstrap user-scoped**

Retain explicit client and version parsing, but make the repository argument
optional for this task:

```text
beroka-governance bootstrap [REPO] --client codex|claude|cursor \
  [--version vX.Y.Z] [--upgrade] [--non-interactive]
```

The body becomes:

```sh
cmd_install "$bs_version"
load_active_release
install_client_instruction "$bs_client" "$bs_interactive"
enable_client "$bs_client"
cmd_setup_connectors --client "$bs_client" $bs_non_interactive_flag
```

Remove `managed_repo_snapshot`, `cmd_register`, lock updates, and
`Repository pull request` output from bootstrap. Do not remove legacy public
commands yet; Task 4 retires them.

- [ ] **Step 6: Run focused tests**

Run:

```bash
sh tests/bootstrap.sh
sh tests/connectors.sh
```

Expected: PASS. Repositories remain identical and connector behavior stays
client-specific.

- [ ] **Step 7: Commit**

```bash
git add bin/beroka-governance \
  templates/agent-entrypoints tests/bootstrap.sh tests/connectors.sh
git commit -m "feat: install governance instructions in user scope"
```

---

### Task 3: Central Repository Catalog and Canonical Origin

**Files:**
- Create: `runtime/repositories/cuongngo1801-beroka/Maket_Data_Lakehouse.conf`
- Modify: `bin/beroka-governance:13-420`
- Modify: `bin/beroka-governance:600-675`
- Replace baseline-routing fixtures in: `tests/routing.sh`

**Interfaces:**
- Consumes: `load_active_release`, `canonical_repo`, `parse_routing FILE SLUG`, `normalize_github_url`, profiles, integrations, and capability gates.
- Produces: `REPOSITORY_SLUG`, `CATALOG_RECORD`, `resolve_repository_context PATH`, `catalog_record_for_slug SLUG`, and catalog-derived `ROUTING_STATE`.

- [ ] **Step 1: Add central-catalog RED tests**

Replace remote default-branch routing setup in `tests/routing.sh` with a release
catalog fixture:

```sh
catalog=$RELEASE_SOURCE/runtime/repositories/beroka-vn
mkdir -p "$catalog"
cat >"$catalog/routing-consumer.conf" <<'EOF'
SCHEMA_VERSION=1
PROFILE=standalone
JIRA_PROJECT_KEY=APP
CONFLUENCE_SPACE_KEY=APP
CONFLUENCE_ROOT_CONTENT_ID=123456
CONFLUENCE_ROOT_CONTENT_TYPE=page
INTEGRATION_PROFILE=none
CROSS_REPO_POLICY=explicit-only
EOF
```

For a cataloged repository, assert:

```sh
assert_contains "$($CLI context "$consumer")" 'Routing: ROUTING_ACTIVE'
assert_contains "$($CLI context "$consumer")" 'Routing source: central catalog'
```

For an unknown repository:

```sh
unknown_output=$($CLI context "$unknown_repo")
assert_contains "$unknown_output" 'Routing: ROUTING_REQUIRED'
assert_contains "$unknown_output" \
  'Dependency state: NO_DEPENDENCY_DECLARED'
assert_contains "$unknown_output" \
  'Cross-repository policy: explicit-only'
```

Add a fake `ssh` whose `ssh -G github.com-work` prints
`hostname github.com`; verify
`git@github.com-work:cuongngo1801-beroka/Beroka_Frontend.git` normalizes to the
GitHub slug. A host resolving anywhere else returns `REMOTE_MISMATCH`.

- [ ] **Step 2: Run routing tests and confirm RED**

Run:

```bash
sh tests/routing.sh
```

Expected: FAIL because context still fetches `.beroka-governance.conf` from the
application repository default branch.

- [ ] **Step 3: Add the first production catalog record**

Create the exact reviewed MDL record:

```text
SCHEMA_VERSION=1
PROFILE=standalone
JIRA_PROJECT_KEY=MDL
CONFLUENCE_SPACE_KEY=MDL
CONFLUENCE_ROOT_CONTENT_ID=72417572
CONFLUENCE_ROOT_CONTENT_TYPE=page
INTEGRATION_PROFILE=none
CROSS_REPO_POLICY=explicit-only
```

Do not add Backend, Frontend, or governance routing without exact reviewed
Jira and Confluence targets.

- [ ] **Step 4: Implement catalog lookup**

Add:

```sh
catalog_record_for_slug() {
  crs_slug=$1
  printf '%s\n' "$crs_slug" |
    grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' || return 1
  CATALOG_RECORD=$RELEASE_DIR/runtime/repositories/$crs_slug.conf
  case "$CATALOG_RECORD" in
    "$RELEASE_DIR/runtime/repositories/"*) ;;
    *) return 1 ;;
  esac
}

resolve_repository_context() {
  REPO=$(canonical_repo "$1")
  resolve_canonical_remote "$REPO"
  REPOSITORY_SLUG=$(normalize_github_url "$CANONICAL_REMOTE_URL") ||
    die REMOTE_MISMATCH 'Canonical remote is not GitHub'
  catalog_record_for_slug "$REPOSITORY_SLUG" ||
    die REMOTE_MISMATCH 'Invalid canonical repository slug'
  if [ -f "$CATALOG_RECORD" ]; then
    parse_routing "$CATALOG_RECORD" "$REPOSITORY_SLUG" ||
      die ROUTING_INVALID
    ROUTING_STATE=ROUTING_ACTIVE
  else
    clear_routing_values
    ROUTE_PROFILE=standalone
    ROUTE_INTEGRATION_PROFILE=none
    ROUTE_CROSS_REPO_POLICY=explicit-only
    DEPENDENCY_STATE=NO_DEPENDENCY_DECLARED
    ROUTING_STATE=ROUTING_REQUIRED
  fi
}
```

Delete default-branch routing fetch, temporary bare repository, local routing
comparison, and `ROUTING_CHANGE_PENDING` production paths. Keep
`ROUTING_CHANGE_PENDING` only in historical documentation if explicitly
labelled legacy.

Extend SSH URL normalization only when local `ssh -G HOST` resolves
`hostname github.com`; never accept an alias based on its name.

Change `parse_routing` to require the canonical slug as its second argument.
Use that slug, not the removed `LOCK_REPOSITORY`, when validating an
integration-profile allowlist.

- [ ] **Step 5: Validate catalog files as release content**

During release validation, walk only regular files under
`runtime/repositories/*/*.conf`, reject symlinks, validate each path segment,
parse every record with `parse_routing FILE SLUG`, and require the
path-derived slug to be unique. Reuse `parse_routing`; do not add a second
schema parser.

- [ ] **Step 6: Run routing and release tests**

Run:

```bash
sh tests/routing.sh
sh tests/release.sh
```

Expected: PASS without any remote routing fetch.

- [ ] **Step 7: Commit**

```bash
git add bin/beroka-governance runtime/repositories tests/routing.sh tests/release.sh
git commit -m "feat: resolve repository routing from central catalog"
```

---

### Task 4: Context, Doctor, Preflight, and Retired Repository Commands

**Files:**
- Modify: `bin/beroka-governance:20-55`
- Delete obsolete repository transaction code from: `bin/beroka-governance:421-590`
- Delete lock/entrypoint registration code from: `bin/beroka-governance:779-1362`
- Modify: `bin/beroka-governance:3202-3530`
- Replace registration lifecycle assertions in: `tests/smoke.sh`
- Modify: `tests/connectors.sh`
- Modify: `tests/routing.sh`

**Interfaces:**
- Consumes: `load_active_release`, `load_enabled_clients`, `resolve_repository_context`, connector health, capability inventory, and GitHub preflight.
- Produces: `legacy_repository_state REPO`, `require_enrolled_client CLIENT`, user-scope `cmd_doctor`, catalog-based `cmd_context`, catalog-based `cmd_preflight`, and `retired_command NAME`.

- [ ] **Step 1: Add command and legacy RED tests**

Create repositories covering clean, modified, untracked, deleted, detached,
behind, and feature-branch states. Record:

```sh
snapshot_repo_complete() {
  src_repo=$1
  {
    git -C "$src_repo" rev-parse HEAD
    git -C "$src_repo" symbolic-ref -q HEAD || printf '%s\n' DETACHED
    git -C "$src_repo" status --porcelain=v1 --untracked-files=all
    git -C "$src_repo" ls-files -s
    git -C "$src_repo" diff --binary
    git -C "$src_repo" diff --cached --binary
    find "$src_repo" -path "$src_repo/.git" -prune -o -type f -print |
      sort |
      while IFS= read -r file; do
        sha256sum "$file"
      done
  }
}
```

Run `doctor`, `context`, `preflight --operation github-write`, and
`setup-connectors` where applicable; assert the snapshot is identical.

Add legacy files with arbitrary old versions and managed blocks. Assert:

```sh
assert_contains "$($CLI doctor "$legacy_repo")" \
  'Legacy repository metadata: PRESENT_IGNORED'
assert_not_contains "$($CLI doctor "$legacy_repo")" 'VERSION_MISMATCH'
```

For each retired command:

```sh
for command in register update rollback unregister; do
  before=$(snapshot_repo_complete "$legacy_repo")
  if output=$($CLI "$command" "$legacy_repo" 2>&1); then
    fail "$command remained active"
  fi
  assert_contains "$output" 'Result: COMMAND_RETIRED'
  [ "$before" = "$(snapshot_repo_complete "$legacy_repo")" ] ||
    fail "$command changed the repository"
done
```

- [ ] **Step 2: Run smoke, connector, and routing tests and confirm RED**

Run:

```bash
sh tests/smoke.sh
sh tests/connectors.sh
sh tests/routing.sh
```

Expected: FAIL because verification still requires repository locks and enabled
clients from those locks.

- [ ] **Step 3: Switch governed commands to active user state**

At the start of `doctor`, `context`, `show`, and `preflight`:

```sh
load_active_release
resolve_repository_context "$requested"
```

When a client is supplied:

```sh
load_enabled_clients
client_list_contains "$ENABLED_CLIENTS" "$client" ||
  die CLIENT_INSTRUCTION_REQUIRED \
    "Remediation: beroka-governance bootstrap --client $client"
```

`context` prints:

```text
Repository: beroka-vn/routing-consumer
Version: v1.1.0
Commit: 1111111111111111111111111111111111111111
Routing source: central catalog
```

For an unknown repository it renders general plus standalone policy and exits
successfully with routing-dependent writes blocked.

`preflight github-write` does not require routing or Atlassian. Jira,
Confluence, folder, and board operations require `ROUTING_ACTIVE` before
connector and capability checks.

- [ ] **Step 4: Report legacy state without reading it**

Implement:

```sh
legacy_repository_state() {
  lrs_repo=$1
  for lrs_path in \
    .beroka-governance.lock \
    AGENTS.md CLAUDE.md \
    .cursor/rules/beroka-governance.mdc
  do
    [ -e "$lrs_repo/$lrs_path" ] || continue
    printf '%s\n' PRESENT_IGNORED
    return
  done
  printf '%s\n' ABSENT
}
```

Do not parse, compare, validate, rewrite, or delete these files. Doctor prints
the returned state separately from active release and routing health.

- [ ] **Step 5: Retire mutating repository commands and delete dead code**

Keep their names in dispatch for a stable error:

```sh
retired_command() {
  die COMMAND_RETIRED \
    'Repository registration is central; bootstrap and upgrade never modify application repositories'
}
```

Delete `REGISTRY`, lock parsing, repository entrypoint verification/staging,
repository transaction manifests, repin, unregister, and their rollback-only
helpers when no remaining caller exists. Before deleting each helper, confirm
with:

```bash
rg -n 'read_lock|verify_registration|stage_client_entrypoint|cmd_register|cmd_repin|cmd_unregister|tx_stage_write|tx_stage_delete' \
  bin/beroka-governance tests
```

Change dispatch to:

```sh
register|update|rollback|unregister)
  retired_command "$command"
  ;;
```

so every legacy invocation returns `COMMAND_RETIRED` before parsing old
arguments or inspecting a repository.

`uninstall` removes only user-owned CLI, release data, enrollment, managed
global Codex/Claude blocks, and Cursor acknowledgement. It never scans
application repositories.

Add an uninstall test that starts with personal Codex and Claude text plus
managed blocks, runs `uninstall --force`, verifies personal text remains, and
verifies the application repository snapshot is unchanged.

- [ ] **Step 6: Run focused and full command tests**

Run:

```bash
sh tests/smoke.sh
sh tests/connectors.sh
sh tests/routing.sh
```

Expected: PASS; repository snapshots remain identical.

- [ ] **Step 7: Commit**

```bash
git add bin/beroka-governance tests/smoke.sh tests/connectors.sh tests/routing.sh
git commit -m "refactor: remove application repository governance state"
```

---

### Task 5: Repository-Independent Verified Launcher

**Files:**
- Modify: `release/bootstrap.sh.in:19-196`
- Modify: `tests/launcher.sh`
- Modify: `tests/bootstrap.sh`

**Interfaces:**
- Consumes: embedded `RELEASE_VERSION`, embedded `RELEASE_COMMIT`, exact
  annotated tag verification, and user-scope `bootstrap`.
- Produces: launcher invocation
  `beroka-governance bootstrap --client CLIENT --version VERSION [--upgrade] [--non-interactive]`.

- [ ] **Step 1: Add launcher RED tests**

Change the outside-Git test to:

```sh
: >"$calls"
output=$(cd "$TEST_ROOT" &&
  sh "$asset" --client codex --non-interactive)
assert_contains "$output" 'LAUNCHER_NON_INTERACTIVE=PASS'
grep -Fx \
  '--client codex --version v9.9.9 --non-interactive' \
  "$calls" >/dev/null ||
  fail 'launcher passed an application repository to bootstrap'
```

For clean, dirty, detached, and ambiguous-remote repositories, assert the same
successful CLI arguments and unchanged complete repository snapshots. Remove
expectations for `REPOSITORY_REQUIRED` and `REMOTE_MISMATCH` during
installation.

- [ ] **Step 2: Run launcher tests and confirm RED**

Run:

```bash
sh tests/launcher.sh
```

Expected: FAIL because the launcher still resolves and passes the current Git
root.

- [ ] **Step 3: Remove application repository discovery from the launcher**

Delete Git-root and canonical-remote resolution from `release/bootstrap.sh.in`.
After tag verification, invoke:

```sh
set -- bootstrap \
  --client "$client" \
  --version "$RELEASE_VERSION"
[ "$upgrade" -eq 0 ] || set -- "$@" --upgrade
[ "$non_interactive" -eq 0 ] || set -- "$@" --non-interactive
```

Retain interactive `/dev/tty`, `jq` handling, exact tag type, peeled commit,
checked-out commit, and fail-closed dependency behavior.

- [ ] **Step 4: Run launcher and bootstrap tests**

Run:

```bash
sh tests/launcher.sh
sh tests/bootstrap.sh
```

Expected: PASS from both Git and non-Git directories.

- [ ] **Step 5: Commit**

```bash
git add release/bootstrap.sh.in tests/launcher.sh tests/bootstrap.sh
git commit -m "refactor: make release launcher repository independent"
```

---

### Task 6: Documentation and Release Contract

**Files:**
- Modify: `README.md`
- Modify: `handbook.md`
- Modify: `PACKAGE-DESIGN.md`
- Modify: `governance.md`
- Modify: `workflow.md`
- Modify: `tests/documentation-architecture.sh`
- Modify: `tests/release.sh`

**Interfaces:**
- Consumes: final public bootstrap command and all result codes from Tasks 1–5.
- Produces: one install command, one upgrade command, Cursor one-time setup
  guidance, central catalog maintenance guidance, and executable documentation
  assertions.

- [ ] **Step 1: Add documentation RED assertions**

In `tests/release.sh`, assert that Quick start and Upgrade contain the exact
launchers but no repository mutation language:

```sh
for forbidden in \
  '.beroka-governance.lock' \
  'Repository pull request: REQUIRED' \
  'git add AGENTS.md' \
  'git commit' \
  'git push'
do
  if first_code_block_after_heading README.md '## Quick start' |
    grep -F "$forbidden" >/dev/null
  then
    fail "Quick start contains repository mutation: $forbidden"
  fi
done
```

Add full-document assertions that active guidance does not tell developers to
pin governance in an application repository. Historical specs and plans are
excluded from this check.

Add required phrases:

```text
Application repository changes: NONE
Legacy repository metadata: PRESENT_IGNORED
Cursor Settings > Rules
Central repository catalog
```

- [ ] **Step 2: Run documentation tests and confirm RED**

Run:

```bash
sh tests/documentation-architecture.sh
sh tests/release.sh
```

Expected: FAIL on current lock, entrypoint, and application PR instructions.

- [ ] **Step 3: Rewrite active operator documentation**

Keep the compact authenticated private-release command. Document:

```text
Install:
  bootstrap.sh --client codex

Upgrade:
  bootstrap.sh --client codex --upgrade

Application repository changes: NONE
```

Explain that changing `codex` to `claude` or `cursor` enrolls exactly that
client, and existing healthy client setup is preserved. Cursor Individual has
a one-time User Rule confirmation.

Remove active instructions to diff, add, commit, push, or open a governance
version PR in an application repository. State that central catalog changes
belong to an explicitly authorized governance-repository task.

Document migration honestly: tracked legacy files stay until a repository
owner explicitly requests cleanup, but the new CLI ignores them.

- [ ] **Step 4: Align governance and workflow rules**

Replace repository-pin language with active user release plus central catalog.
Keep the distinction:

```text
CLI hard-enforces installation, release integrity, catalog routing, connector,
authentication, and operation preflight.

Agent instructions govern workflow behavior unless CI, hooks, branch
protection, or platform policy provides hard enforcement.
```

- [ ] **Step 5: Run documentation and release tests**

Run:

```bash
sh tests/documentation-architecture.sh
sh tests/release.sh
git diff --check
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add README.md handbook.md PACKAGE-DESIGN.md governance.md workflow.md \
  tests/documentation-architecture.sh tests/release.sh
git commit -m "docs: document repository-clean governance setup"
```

---

### Task 7: Full Regression and Isolated Pilot

**Files:**
- Modify only if a regression is found: files already listed in Tasks 1–6
- Record no credentials or generated pilot artifacts in the repository

**Interfaces:**
- Consumes: completed Tasks 1–6.
- Produces: release-readiness evidence only; no tag, GitHub Release, Jira,
  Confluence, Issue, branch push, or pull request.

- [ ] **Step 1: Run shell syntax and all seven suites**

Run:

```bash
sh -n bin/beroka-governance release/bootstrap.sh.in tests/*.sh
for test_script in \
  tests/smoke.sh \
  tests/bootstrap.sh \
  tests/connectors.sh \
  tests/routing.sh \
  tests/documentation-architecture.sh \
  tests/launcher.sh \
  tests/release.sh
do
  sh "$test_script"
done
```

Expected: syntax PASS and seven suites PASS.

- [ ] **Step 2: Render a local unpublished candidate**

Use the current reviewed branch commit without creating a tag:

```bash
candidate_commit=$(git rev-parse HEAD)
candidate_root=$(mktemp -d \
  "${TMPDIR:-/tmp}/beroka-user-scope-candidate.XXXXXX")
sed \
  -e 's/@RELEASE_VERSION@/v9.9.9/g' \
  -e "s/@RELEASE_COMMIT@/$candidate_commit/g" \
  release/bootstrap.sh.in >"$candidate_root/bootstrap.sh"
sh -n "$candidate_root/bootstrap.sh"
```

For the pilot, create a temporary annotated `v9.9.9` only inside a temporary
clone of the governance source. Do not create or move a tag in the real
repository.

Configure only the temporary pilot HOME to use that clone:

```bash
HOME="$pilot_home" git config --global \
  url."file://$candidate_source".insteadOf \
  https://github.com/beroka-vn/beroka-ai-governance.git
```

- [ ] **Step 3: Pilot clean and dirty application repositories**

Create temporary clones representing:

1. a clean repository;
2. a repository with modified tracked source;
3. untracked source and legacy `.beroka-governance.lock`;
4. deleted tracked `AGENTS.md`;
5. detached HEAD; and
6. a branch behind its remote.

For every fixture:

```bash
before=$(snapshot_repo_complete "$pilot_repo")
(
  cd "$pilot_repo"
  HOME="$pilot_home" \
  XDG_DATA_HOME="$pilot_data" \
  XDG_CONFIG_HOME="$pilot_config" \
  XDG_CACHE_HOME="$pilot_cache" \
  BEROKA_GOV_BIN_DIR="$pilot_bin" \
    sh "$candidate_root/bootstrap.sh" \
      --client codex --non-interactive
)
after=$(snapshot_repo_complete "$pilot_repo")
[ "$before" = "$after" ]
```

With no real Atlassian credentials, the expected terminal result is
`ATLASSIAN_AUTH_REQUIRED` and remediation
`codex mcp login atlassian`. Installation, active-release state, client
enrollment, and the Codex global managed block must remain installed.

- [ ] **Step 4: Pilot Cursor fail-closed behavior**

With temporary HOME/XDG and a fake Cursor binary:

```bash
sh "$candidate_root/bootstrap.sh" \
  --client cursor --non-interactive
```

Expected:

```text
Result: CURSOR_USER_RULE_REQUIRED
Remediation: beroka-governance bootstrap --client cursor
```

No Cursor database or application repository file exists afterward.

- [ ] **Step 5: Verify final branch scope**

Run:

```bash
git diff --check origin/main...HEAD
git status --short --branch
git log --oneline --decorate origin/main..HEAD
git diff --stat origin/main...HEAD
```

Expected: only reviewed governance source, tests, templates, catalog, and
active documentation are changed. Root controller `AGENTS.md` and
`.beroka-governance.lock` remain untracked and absent from the diff.

If a regression is found, return to the task that owns that behavior, add its
failing test there, make the minimal fix, rerun that task, and then repeat this
full gate. Do not create an evidence-only commit.
