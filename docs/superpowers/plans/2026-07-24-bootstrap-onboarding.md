# Bootstrap Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one resumable `bootstrap` command that resolves a pinned release, selects one AI client, installs Governance, registers the repository, configures Atlassian, and verifies the result.

**Architecture:** Add a thin orchestrator inside the existing POSIX shell CLI and reuse `cmd_install`, `cmd_register`, `cmd_setup_connectors`, `cmd_doctor`, `detect_client`, and the current transaction boundaries. Resolve `latest` from fresh canonical remote annotated stable tags, but always persist and subsequently use an exact version and commit.

**Tech Stack:** POSIX shell, Git, jq, isolated shell tests using temporary HOME/XDG directories and fake Codex/Claude clients.

## Global Constraints

- `--client codex|claude|cursor` selects exactly one client for the invocation.
- Existing repository lock always wins; bootstrap never silently upgrades it.
- Interactive unregistered bootstrap defaults to latest stable annotated SemVer tag and confirms exact tag/commit.
- Non-interactive unregistered bootstrap requires exact `--version vX.Y.Z`.
- No branch, lightweight tag, prerelease tag, cached tag, or local-only tag may satisfy latest.
- No AI client binary, system package, API token, OAuth URL, OAuth state, or credential is installed or stored by Governance.
- OAuth remains provider-owned and non-interactive mode remains fail-closed.
- Bootstrap never commits, pushes, guesses routing, or configures every installed client.
- Published `v1.0.0` remains unchanged.

---

### Task 1: Bootstrap Release and Client Selection

**Files:**
- Create: `tests/bootstrap.sh`
- Modify: `bin/beroka-governance:40-54`
- Modify: `bin/beroka-governance:640-702`
- Modify: `bin/beroka-governance:1901-1941`
- Modify: `bin/beroka-governance:2353-2377`

**Interfaces:**
- Produces: `remote_release_commit VERSION` setting `REMOTE_RELEASE_COMMIT`;
  `resolve_latest_release` setting `RESOLVED_VERSION` and
  `REMOTE_RELEASE_COMMIT`; `cmd_bootstrap REPO ...`.
- Consumes: canonical `REMOTE_URL`, existing `detect_client`, exact release
  install validation, and the current CLI result codes.

- [ ] **Step 1: Build isolated release/client fixtures and failing tests**

Create `tests/bootstrap.sh` with temporary HOME/XDG/bin/repository directories,
fake Codex and Claude executables, and a local canonical-release rewrite.
Create these remote tags:

```text
v1.1.0       annotated, VERSION=v1.1.0
v1.2.0       annotated, VERSION=v1.2.0
v2.0.0-rc1   annotated prerelease, ignored
v9.0.0       lightweight, ignored
```

Add assertions for:

```sh
# Non-interactive new repo must be exact.
if output=$($CLI bootstrap "$repo" --client codex \
  --non-interactive 2>&1)
then
  fail 'bootstrap accepted an implicit non-interactive latest'
fi
assert_contains "$output" 'Result: RELEASE_RESOLUTION_REQUIRED'

# Interactive one-client detection and latest confirmation.
output=$(printf 'y\ny\n' | script -qec \
  "$CLI bootstrap $repo" /dev/null 2>&1)
assert_contains "$output" 'Detected client: codex'
assert_contains "$output" 'Resolved release: v1.2.0'
assert_contains "$output" 'Selected client: codex'
assert_contains "$output" 'Result: PASS'
grep -F 'VERSION=v1.2.0' "$repo/.beroka-governance.lock" >/dev/null

# Resolver must ignore prerelease and lightweight tags.
assert_not_contains "$output" 'v2.0.0-rc1'
assert_not_contains "$output" 'v9.0.0'
```

Assert that `--api-token`, duplicate `--client`, invalid clients, and
non-interactive omission of `--client` are rejected without echoing a supplied
token value.

- [ ] **Step 2: Run the new test and verify RED**

Run:

```sh
sh tests/bootstrap.sh
```

Expected: usage output because `bootstrap` is not yet a recognized command.

- [ ] **Step 3: Implement portable remote tag resolution**

Add:

```sh
remote_release_commit() {
  rrc_version=$1
  REMOTE_RELEASE_COMMIT=$(
    git ls-remote --tags "$REMOTE_URL" \
      "refs/tags/$rrc_version" "refs/tags/$rrc_version^{}" 2>/dev/null |
      awk -v ref="refs/tags/$rrc_version^{}" '
        $2 == ref { matches++; commit=$1 }
        END {
          if (matches != 1 || commit !~ /^[0-9a-f]{40}$/) exit 42
          print commit
        }
      '
  ) || die RELEASE_RESOLUTION_REQUIRED \
    "Cannot verify annotated release tag: $rrc_version"
}

resolve_latest_release() {
  latest=$(
    git ls-remote --tags "$REMOTE_URL" "refs/tags/v*" 2>/dev/null |
      awk '
        $2 ~ /^refs\/tags\/v[0-9]+\.[0-9]+\.[0-9]+\^\{\}$/ {
          version=$2
          sub(/^refs\/tags\/v/, "", version)
          sub(/\^\{\}$/, "", version)
          split(version, part, ".")
          if (!found ||
              part[1] > major ||
              (part[1] == major && part[2] > minor) ||
              (part[1] == major && part[2] == minor &&
               part[3] > patch)) {
            found=1
            major=part[1]
            minor=part[2]
            patch=part[3]
            commit=$1
          }
        }
        END {
          if (!found || commit !~ /^[0-9a-f]{40}$/) exit 42
          print "v" major "." minor "." patch "\t" commit
        }
      '
  ) || die RELEASE_RESOLUTION_REQUIRED \
    'Cannot resolve the latest stable annotated release'
  RESOLVED_VERSION=${latest%%	*}
  REMOTE_RELEASE_COMMIT=${latest#*	}
}
```

Use only fresh remote output. Do not inspect local tags or branches.

- [ ] **Step 4: Parse bootstrap arguments and select one client**

Add usage:

```text
beroka-governance bootstrap REPO [--client codex|claude|cursor] [--version vX.Y.Z] [--non-interactive]
```

Implement strict option parsing. Determine interactive mode from
`--non-interactive` plus TTY state. If client is omitted, require interactive
mode and call existing `detect_client`; otherwise retain the exact explicit
client. Call `require_client` before install or registration.

For an unregistered repo:

- exact non-interactive version is mandatory;
- interactive missing version calls `resolve_latest_release`;
- exact version calls `remote_release_commit`;
- interactive prints exact version/commit and asks for confirmation.

For an existing lock, call `read_lock`, use its exact version/commit, and reject
a conflicting `--version`.

- [ ] **Step 5: Orchestrate existing commands**

After all prevalidation:

```sh
cmd_install "$bootstrap_version"
[ "$RELEASE_COMMIT" = "$bootstrap_commit" ] ||
  die VERSION_MISMATCH 'Resolved release commit differs from the installed tag'
cmd_register "$bootstrap_repo" --version "$bootstrap_version"
if [ "$bootstrap_non_interactive" -eq 1 ]; then
  cmd_setup_connectors --client "$bootstrap_client" --non-interactive
else
  cmd_setup_connectors --client "$bootstrap_client"
fi
cmd_doctor "$bootstrap_repo"
cmd_doctor "$bootstrap_repo" --client "$bootstrap_client"
```

Print the exact resolved version, selected client, registration review state,
fresh-session instruction, and final `Result: PASS`. Intermediate existing
commands may retain their current PASS output.

- [ ] **Step 6: Run bootstrap tests and verify GREEN**

Run:

```sh
sh tests/bootstrap.sh
```

Expected: `Bootstrap onboarding tests: PASS`.

- [ ] **Step 7: Commit Task 1**

```sh
git add bin/beroka-governance tests/bootstrap.sh
git commit -m "feat: add bootstrap onboarding command"
```

### Task 2: Idempotency, Multi-client Safety, and Documentation

**Files:**
- Modify: `tests/bootstrap.sh`
- Modify: `README.md:14-62`
- Modify: `handbook.md:60-125`
- Modify: `PACKAGE-DESIGN.md:150-225`

**Interfaces:**
- Consumes: `cmd_bootstrap` from Task 1.
- Produces: documented one-command developer onboarding and isolated regression
  coverage for safe reruns and client selection.

- [ ] **Step 1: Add failing rerun and multi-client tests**

Extend `tests/bootstrap.sh` to assert:

```sh
# A registered repo uses its lock and creates no repository diff.
before=$(snapshot_repo "$repo")
output=$($CLI bootstrap "$repo" --client codex --non-interactive)
after=$(snapshot_repo "$repo")
[ "$before" = "$after" ] || fail 'bootstrap changed a registered repository'
assert_contains "$output" 'Version: v1.2.0'

# Conflicting version never upgrades.
if output=$($CLI bootstrap "$repo" --client codex \
  --version v1.1.0 --non-interactive 2>&1)
then
  fail 'bootstrap silently changed a pinned version'
fi
assert_contains "$output" 'Result: VERSION_MISMATCH'

# A second explicit client configures only that client.
: >"$CALLS"
output=$($CLI bootstrap "$repo" --client claude --non-interactive)
assert_contains "$output" 'Selected client: claude'
assert_contains "$(cat "$CALLS")" 'claude mcp'
assert_not_contains "$(cat "$CALLS")" 'codex '
```

Add a multiple-detected interactive test that selects one client and a
no-client test returning `DEPENDENCY_MISSING`. Add a broken remote rewrite test
returning `RELEASE_RESOLUTION_REQUIRED`. Verify neither bootstrap nor tests use
real HOME, XDG, credentials, browser, commit, or push.

- [ ] **Step 2: Run the bootstrap test and verify RED**

Run:

```sh
sh tests/bootstrap.sh
```

Expected: the first unsupported rerun or second-client assertion fails.

- [ ] **Step 3: Make reruns reconcile without repository drift**

Reuse `cmd_register` with the lock version. Its `same_target` checks skip
identical managed files while `prepare_registry_row` refreshes only the
machine-local registry. Do not add a second registration implementation.

Reset connector probe cache before each selected-client bootstrap connector
stage so a second invocation cannot reuse another client's probe. Keep client
selection in one variable from parsing through doctor.

- [ ] **Step 4: Document one-command onboarding**

Replace the four-command developer sequence with:

```bash
beroka-governance bootstrap "$PWD" --client codex
```

Document that:

- maintainers review first-registration files through a PR;
- ordinary developers use the committed lock and do not silently upgrade;
- interactive first registration defaults to latest, but stores exact
  version/commit;
- non-interactive first registration requires exact version;
- client auto-detection always requires confirmation/selection;
- AI client binaries and system packages remain prerequisites;
- auth-required is provider-owned and resumable;
- a fresh agent session is required after registration.

Add documentation assertions to `tests/bootstrap.sh`.

- [ ] **Step 5: Run all tests and static checks**

Run:

```sh
sh -n bin/beroka-governance
sh -n tests/bootstrap.sh
sh tests/bootstrap.sh
sh tests/smoke.sh
sh tests/connectors.sh
```

Run `tests/routing.sh` in an isolated clone without the unpublished local
candidate tag, then run:

```sh
git diff --check
test "$(git rev-parse v1.0.0^{tag})" = \
  1f2db6bd75cf9d9a68d501c351fb2455448e04e1
! rg -n '(ghp_|github_pat_|access_token|refresh_token)' \
  bin tests README.md handbook.md PACKAGE-DESIGN.md
```

Expected: all test scripts print PASS, syntax checks succeed, tag verification
is unchanged, and the credential scan is empty.

- [ ] **Step 6: Commit Task 2**

```sh
git add README.md handbook.md PACKAGE-DESIGN.md tests/bootstrap.sh \
  bin/beroka-governance
git commit -m "docs: simplify developer bootstrap"
```

- [ ] **Step 7: Final branch verification**

Run:

```sh
git status --short --branch
git log --oneline origin/main..HEAD
```

Expected: clean `agent/bootstrap-onboarding` with the design, plan, feature, and
documentation commits; no release tag is created or pushed.
