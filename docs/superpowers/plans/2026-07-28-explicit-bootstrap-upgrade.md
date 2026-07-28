# Explicit Bootstrap Upgrade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provide one compact install command and the same command plus
`--upgrade` for safe same-major release upgrades without uninstalling.

**Architecture:** The downloaded release launcher verifies its embedded
annotated tag and commit, handles the one post-download dependency (`jq`), and
passes explicit decisions to the verified package CLI. Package bootstrap owns
the upgrade transaction so it can snapshot managed repository state before the
lock changes and report the correct PR requirement afterward.

**Tech Stack:** POSIX shell, Git, GitHub CLI, existing shell test harness

## Global Constraints

- Never silently upgrade; `--upgrade` is mandatory for a pin change.
- Never downgrade through `update`; use `rollback`.
- Preserve enabled clients, managed entrypoints, registration identity, and
  client/OS-owned OAuth state.
- Never accept, print, log, or store a developer API token.
- `gh` and the selected AI client remain workstation prerequisites because the
  private release cannot be downloaded without them.
- Interactive bootstrap may offer to install `jq`; non-interactive bootstrap
  must fail closed with `DEPENDENCY_MISSING`.
- Do not move, replace, delete, or push the unpublished local `v1.0.2` tag.
- Never stage root `AGENTS.md` or `.beroka-governance.lock`.

---

### Task 1: Transactional CLI bootstrap upgrade

**Files:**
- Modify: `tests/bootstrap.sh`
- Modify: `tests/smoke.sh`
- Modify: `bin/beroka-governance`

**Interfaces:**
- Consumes: existing `cmd_repin update`, `managed_repo_snapshot`, and
  `cmd_bootstrap`
- Produces: `semver_not_older CURRENT TARGET` and CLI
  `bootstrap ... --upgrade`

- [ ] **Step 1: Add failing CLI tests**

Add bootstrap parser coverage before the first successful registration:

```sh
if output=$($CLI bootstrap "$repo" --client codex \
  --version v1.1.0 --upgrade --upgrade --non-interactive 2>&1)
then
  fail 'bootstrap accepted duplicate upgrade selection'
fi
assert_contains "$output" 'Usage:'

if output=$($CLI bootstrap "$repo" --client codex \
  --version v1.1.0 --upgrade --non-interactive 2>&1)
then
  fail 'bootstrap upgrade accepted an unregistered repository'
fi
assert_contains "$output" 'Result: GOVERNANCE_NOT_READY'
```

After the existing v1.1.0 registration is committed, add:

```sh
upgrade_output=$($CLI bootstrap "$repo" --client codex \
  --version v1.2.0 --upgrade --non-interactive)
assert_contains "$upgrade_output" 'Version: v1.2.0'
assert_contains "$upgrade_output" 'Repository pull request: REQUIRED'
assert_contains "$(cat "$repo/.beroka-governance.lock")" 'VERSION=v1.2.0'

same_version_output=$($CLI bootstrap "$repo" --client codex \
  --version v1.2.0 --upgrade --non-interactive)
assert_contains "$same_version_output" \
  'Repository pull request: NOT_REQUIRED'
```

In `tests/smoke.sh`, after a repository is pinned to `v1.1.0`, add:

```sh
if downgrade_output=$($CLI update "$repin_dry_repo" \
  --to v1.0.0 2>&1)
then
  fail 'update accepted an older target'
fi
assert_contains "$downgrade_output" 'Result: VERSION_MISMATCH'
assert_contains "$downgrade_output" 'use rollback'
```

- [ ] **Step 2: Run tests to verify RED**

Run:

```bash
sh tests/bootstrap.sh
sh tests/smoke.sh
```

Expected: bootstrap rejects `--upgrade` as usage, and direct `update` accepts
the older target.

- [ ] **Step 3: Add the minimum forward-version comparator**

Add before `cmd_repin`:

```sh
semver_not_older() {
  awk -v current="${1#v}" -v target="${2#v}" '
    function canonical(component) {
      sub(/^0+/, "", component)
      return component == "" ? "0" : component
    }
    BEGIN {
      split(current, c, ".")
      split(target, t, ".")
      for (i = 1; i <= 3; i++) {
        c[i] = canonical(c[i])
        t[i] = canonical(t[i])
        if (length(t[i]) != length(c[i]))
          exit length(t[i]) > length(c[i]) ? 0 : 1
        if (t[i] != c[i])
          exit ("x" t[i]) > ("x" c[i]) ? 0 : 1
      }
      exit 0
    }
  '
}
```

After the existing same-major check in `cmd_repin`, add:

```sh
if [ "$mode" = update ]; then
  semver_not_older "$LOCK_VERSION" "$version" ||
    die VERSION_MISMATCH \
      'Update target is older than the current version; use rollback'
fi
```

- [ ] **Step 4: Implement `cmd_bootstrap --upgrade`**

Extend bootstrap state and parsing:

```sh
bs_client= bs_version= bs_non_interactive=0 bs_upgrade=0
```

```sh
--upgrade)
  [ "$bs_upgrade" -eq 0 ] || { usage >&2; exit 2; }
  bs_upgrade=1
  shift
  ;;
```

Resolve the repository before client dependency validation, reject
`--upgrade` when no lock exists, and snapshot before any repin:

```sh
bs_repo=$(canonical_repo "$bs_requested")
assert_safe_managed_paths "$bs_repo"
[ "$bs_upgrade" -eq 0 ] || [ -f "$bs_repo/.beroka-governance.lock" ] ||
  die GOVERNANCE_NOT_READY \
    'Bootstrap --upgrade requires an existing registration'
bs_before=$(managed_repo_snapshot "$bs_repo")
```

Inside the existing-lock branch, replace the mismatched-version guard with:

```sh
if [ -n "$bs_version" ] && [ "$bs_version" != "$LOCK_VERSION" ]; then
  [ "$bs_upgrade" -eq 1 ] ||
    die VERSION_MISMATCH \
      "Repository is pinned to $LOCK_VERSION; use --upgrade to change it"
  SUPPRESS_PASS_RESULT=1
  cmd_repin update "$bs_repo" --to "$bs_version"
  read_lock "$bs_repo"
  resolve_canonical_remote "$bs_repo" "$LOCK_REPOSITORY"
fi
```

Remove the later duplicate `bs_before=` assignment. Leave the existing
install, additive registration, final snapshot, repository-review summary,
connector setup, and Doctor flow unchanged.

Update CLI usage text to include `[--upgrade]`.

- [ ] **Step 5: Run focused tests to verify GREEN**

Run:

```bash
sh tests/bootstrap.sh
sh tests/smoke.sh
```

Expected: both print PASS and upgrade output reports a repository PR only when
tracked managed state changed.

- [ ] **Step 6: Commit Task 1**

```bash
git add bin/beroka-governance tests/bootstrap.sh tests/smoke.sh
git commit -m "feat(bootstrap): add explicit in-place upgrade"
```

---

### Task 2: Verified release launcher flag and dependency setup

**Files:**
- Modify: `tests/launcher.sh`
- Modify: `release/bootstrap.sh.in`

**Interfaces:**
- Consumes: CLI `bootstrap ... --upgrade` from Task 1
- Produces: release asset
  `bootstrap.sh --client CLIENT [--upgrade] [--non-interactive]`

- [ ] **Step 1: Add failing launcher tests**

Add parser coverage:

```sh
if output=$(cd "$target_repo" &&
  sh "$asset" --client codex --upgrade --upgrade 2>&1)
then
  fail 'launcher accepted duplicate upgrade selection'
fi
assert_contains "$output" 'Usage:'
```

Add explicit propagation coverage:

```sh
: >"$calls"
output=$(cd "$target_repo" &&
  sh "$asset" --client codex --upgrade --non-interactive)
assert_contains "$output" 'LAUNCHER_NON_INTERACTIVE=PASS'
grep -F -- \
  "bootstrap $target_repo --client codex --version v9.9.9 --upgrade --non-interactive" \
  "$calls" >/dev/null ||
  fail 'launcher omitted explicit upgrade selection'
```

Add an isolated missing-`jq` fixture with a fake `apt-get` that installs a fake
`jq`. Assert interactive confirmation calls `apt-get update` and
`apt-get install -y jq`. Run the same asset with `--non-interactive` and assert:

```text
Result: DEPENDENCY_MISSING
Remediation: install jq
```

- [ ] **Step 2: Run launcher tests to verify RED**

Run:

```bash
sh tests/launcher.sh
```

Expected: the launcher rejects `--upgrade`, omits it from the verified CLI
call, and fails instead of offering to install missing `jq`.

- [ ] **Step 3: Parse and forward `--upgrade`**

Change launcher usage to:

```sh
"Usage: $PROGRAM --client codex|claude|cursor [--upgrade] [--non-interactive]"
```

Initialize and parse:

```sh
upgrade=0
```

```sh
--upgrade)
  [ "$upgrade" -eq 0 ] || { usage >&2; exit 2; }
  upgrade=1
  shift
  ;;
```

Build bootstrap arguments without `eval`:

```sh
set -- bootstrap "$repo" \
  --client "$client" \
  --version "$RELEASE_VERSION"
[ "$upgrade" -eq 0 ] || set -- "$@" --upgrade
[ "$non_interactive" -eq 0 ] || set -- "$@" --non-interactive
```

Invoke `sh "$cli" "$@"`, using `</dev/tty` only in interactive mode.

- [ ] **Step 4: Move the `jq` prompt behind release verification**

After tag and checked-out commit verification, return immediately when `jq`
already exists. In non-interactive mode fail closed:

```sh
command -v jq >/dev/null 2>&1 || {
  [ "$non_interactive" -eq 0 ] ||
    die DEPENDENCY_MISSING 'Remediation: install jq'
}
```

For interactive mode, require `/dev/tty`, select the first available package
manager from `apt-get`, `dnf`, or `brew`, ask:

```text
Missing dependency: jq. Install with PACKAGE_MANAGER (may request sudo)? [y/N]
```

On confirmation run only:

```sh
apt-get update
apt-get install -y jq
```

or:

```sh
dnf install -y jq
```

or:

```sh
brew install jq
```

Use the current process when root, otherwise `sudo` for `apt-get`/`dnf`.
Decline, missing package manager, missing `sudo`, install failure, or a missing
post-install `jq` all return:

```text
Result: DEPENDENCY_MISSING
Remediation: install jq
```

- [ ] **Step 5: Run launcher tests to verify GREEN**

Run:

```bash
sh tests/launcher.sh
```

Expected: `One-command launcher tests: PASS`.

- [ ] **Step 6: Commit Task 2**

```bash
git add release/bootstrap.sh.in tests/launcher.sh
git commit -m "feat(launcher): support verified release upgrades"
```

---

### Task 3: Compact install and upgrade documentation

**Files:**
- Modify: `tests/release.sh`
- Modify: `README.md`
- Modify: `handbook.md`
- Modify: `PACKAGE-DESIGN.md`

**Interfaces:**
- Consumes: launcher contract from Task 2
- Produces: identical active install and upgrade commands across team docs

- [ ] **Step 1: Replace release-document assertions first**

Define the exact install command:

```sh
interactive_launcher=$(cat <<'EOF'
bash -e -o pipefail -c '
  gh auth status --hostname github.com >/dev/null 2>&1 ||
    gh auth login --hostname github.com --web
  gh auth setup-git --hostname github.com
  gh release download \
    --repo beroka-vn/beroka-ai-governance \
    --pattern bootstrap.sh \
    --output - |
    sh -s -- --client codex
'
EOF
)
```

Define `upgrade_launcher` identically with `--upgrade`, and retain a
non-interactive launcher that requires healthy GitHub authentication and passes
`--non-interactive` without starting browser OAuth.

Update behavior fixtures so fake `gh release download` writes the test script
to stdout. Require `bash -e -o pipefail`, remove the old package-manager block
tests from README, require the new upgrade block, and keep failure coverage
proving a failed download never appears successful.

- [ ] **Step 2: Run release tests to verify RED**

Run:

```bash
sh tests/release.sh
```

Expected: exact launcher assertions fail because active documentation still
contains the long installer.

- [ ] **Step 3: Replace active documentation**

In all three documents:

- Make the first active command the exact compact install block.
- Add the exact compact upgrade block immediately after explaining that an
  existing registration never upgrades without `--upgrade`.
- State that `gh` and the selected AI client are one-time workstation
  prerequisites.
- State that healthy GitHub auth is reused and browser OAuth runs only when
  missing.
- State that interactive verified bootstrap offers to install `jq`, while
  automation installs nothing and fails closed.
- Remove the duplicated `dependency_error`, `run_as_root`, package-manager, and
  temporary-file shell bodies from active documentation.
- Preserve token/OAuth ownership, additive client setup, PR-review, routing,
  connector, and automation rules.

- [ ] **Step 4: Run documentation tests to verify GREEN**

Run:

```bash
sh tests/release.sh
sh tests/bootstrap.sh
sh tests/connectors.sh
sh tests/routing.sh
```

Expected: all four suites pass.

- [ ] **Step 5: Commit Task 3**

```bash
git add README.md handbook.md PACKAGE-DESIGN.md tests/release.sh
git commit -m "docs(onboarding): simplify install and upgrade commands"
```

---

### Task 4: Full regression and MDL upgrade pilot

**Files:**
- Verify only; do not modify MDL tracked files outside its isolated pilot
  worktree

**Interfaces:**
- Consumes: completed Tasks 1–3
- Produces: release-readiness evidence; no tag or GitHub Release

- [ ] **Step 1: Run the full shell suite**

Run:

```bash
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
git diff --check origin/main...HEAD
```

Expected: seven suites pass and diff check is clean.

- [ ] **Step 2: Render an unpublished candidate asset**

Render `release/bootstrap.sh.in` with `RELEASE_VERSION=v1.0.2` and the current
review commit into a temporary file. Do not alter or push any tag.

- [ ] **Step 3: Repeat the MDL public-style upgrade pilot**

Use the existing isolated MDL pilot or a fresh detached worktree at
`origin/main`, temporary HOME/XDG/bin directories, and the rendered candidate
asset. Run:

```bash
sh "$candidate_asset" --client codex --upgrade --non-interactive
```

Verify:

- the repository moves from the v1.0.1 lock to the candidate v1.0.2 commit;
- output includes `Repository pull request: REQUIRED`;
- enabled clients are preserved;
- Codex connector/auth remains client-owned;
- `doctor --client codex` passes;
- `preflight --client codex --operation jira-write --non-interactive` passes;
- the normal MDL checkout remains unchanged;
- no Jira, Confluence, GitHub Issue, PR, tag, or Release is created.

- [ ] **Step 4: Record final branch evidence**

Run:

```bash
git status --short --branch
git log --oneline --decorate origin/main..HEAD
git diff --stat origin/main...HEAD
```

Expected: only the reviewed feature commits are ahead; root `AGENTS.md` and
`.beroka-governance.lock` remain untracked and absent from the diff.
