# GitHub Team Role Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route canonical `beroka-vn` Backend and Frontend repositories while enforcing a GitHub Team-verified FE, BE, or Full-stack user role before governed external writes.

**Architecture:** Reuse the exact file-backed repository catalog and existing `gh`/`jq` dependencies. Store one validated role in user scope, apply it locally when rendering Backend/Frontend contexts, and re-query exact `beroka-vn` Team membership after a preflight passes repository and operation routing.

**Tech Stack:** POSIX shell, Git, GitHub CLI, jq, Markdown, existing shell test suite

## Global Constraints

- Match only exact `beroka-vn/frontend` and `beroka-vn/backend` GitHub Teams.
- Store exactly `FE`, `BE`, or `FULL_STACK`; never default to Full-stack.
- Keep `context` offline by reading the stored role; revalidate membership
  after preflight routing passes and before connector login or an external
  write.
- Return `GITHUB_ROLE_REQUIRED`, `GITHUB_ROLE_SELECTION_REQUIRED`, `GITHUB_ROLE_UNAVAILABLE`, or `ROLE_SCOPE_DENIED` without broadening existing authority.
- Add no service, daemon, wildcard routing, self-declaration path, or dependency.
- Keep `cuongngo1801-beroka/Beroka_Backend` and `cuongngo1801-beroka/Beroka_Frontend` only for the `v1.0.4` transition.
- Active documentation uses only `beroka-vn` URLs; historical plans remain unchanged.
- Do not combine Issue #30 or Issue #31 with Issue #29.
- Resolve GitHub's current default branch for PR and release operations; never
  use a branch name as repository identity.
- Do not merge, tag, or release without explicit human confirmation of the exact reviewed pull request and commit.

---

### Task 1: Canonical catalog and local role scope

**Files:**
- Create: `runtime/repositories/beroka-vn/Beroka_Backend.conf`
- Create: `runtime/repositories/beroka-vn/Beroka_Frontend.conf`
- Modify: `runtime/integrations/beroka-be-fe.repositories`
- Modify: `bin/beroka-governance:14-24,197-227,815-827,1248`
- Test: `tests/routing.sh:659-768`

**Interfaces:**
- Consumes: `resolve_repository_context REPO`, parsed `ROUTE_PROFILE`, and the existing safe user-file checks.
- Produces: `GITHUB_ROLE_FILE`, `load_github_role`, and `require_role_scope`; canonical and deprecated-alias contexts share the same profile routing.

- [ ] **Step 1: Write canonical and local-scope regression tests**

Create Backend and Frontend fixtures with canonical remotes and manually seed
the user role file:

```sh
role_file=$XDG_CONFIG_HOME/beroka-ai-governance/github-role
printf '%s\n' FE >"$role_file"

if output=$($CLI context "$canonical_backend" 2>&1); then
  fail 'FE role loaded Backend routing'
fi
assert_contains "$output" 'Result: ROLE_SCOPE_DENIED'
assert_not_contains "$output" 'Jira project: BB'

frontend_output=$($CLI context "$canonical_frontend")
assert_contains "$frontend_output" \
  'Repository: beroka-vn/Beroka_Frontend'
assert_contains "$frontend_output" 'Routing: ROUTING_ACTIVE'

printf '%s\n' FULL_STACK >"$role_file"
assert_contains "$($CLI context "$canonical_backend")" 'Jira project: BB'
assert_contains "$($CLI context "$canonical_frontend")" 'Jira project: BF'
```

Keep the existing `cuongngo1801-beroka` fixtures and assert that both still
resolve under `FULL_STACK`.

- [ ] **Step 2: Run the focused test to verify RED**

Run:

```bash
sh tests/routing.sh
```

Expected: FAIL because the canonical records and `ROLE_SCOPE_DENIED` gate do
not exist.

- [ ] **Step 3: Add the two canonical catalog records**

Copy the existing Backend and Frontend routing values into:

```text
runtime/repositories/beroka-vn/Beroka_Backend.conf
runtime/repositories/beroka-vn/Beroka_Frontend.conf
```

Set the integration inventory to these four exact rows:

```text
beroka-vn/Beroka_Backend	backend
beroka-vn/Beroka_Frontend	frontend
cuongngo1801-beroka/Beroka_Backend	backend
cuongngo1801-beroka/Beroka_Frontend	frontend
```

- [ ] **Step 4: Implement the minimum local role gate**

Add:

```sh
GITHUB_ROLE_FILE=$CONFIG_ROOT/github-role
GITHUB_ROLE=

load_github_role() {
  assert_client_files
  [ -f "$GITHUB_ROLE_FILE" ] && [ ! -L "$GITHUB_ROLE_FILE" ] ||
    die GITHUB_ROLE_REQUIRED \
      'Remediation: rerun beroka-governance bootstrap with an enrolled client'
  GITHUB_ROLE=$(sed -n '1p' "$GITHUB_ROLE_FILE")
  [ "$(wc -l <"$GITHUB_ROLE_FILE" | tr -d ' ')" -eq 1 ] ||
    die GITHUB_ROLE_REQUIRED
  case "$GITHUB_ROLE" in FE|BE|FULL_STACK) ;; *)
    die GITHUB_ROLE_REQUIRED
  esac
}

require_role_scope() {
  case "$ROUTE_PROFILE" in
    backend)
      load_github_role
      case "$GITHUB_ROLE" in BE|FULL_STACK) ;; *)
        die ROLE_SCOPE_DENIED 'GitHub role cannot govern Backend routing'
      esac
      ;;
    frontend)
      load_github_role
      case "$GITHUB_ROLE" in FE|FULL_STACK) ;; *)
        die ROLE_SCOPE_DENIED 'GitHub role cannot govern Frontend routing'
      esac
      ;;
  esac
}
```

Call `require_role_scope` after catalog parsing and before any routed context
is printed. Extend `assert_client_files` to validate `GITHUB_ROLE_FILE`, and
remove the file in `cmd_uninstall`.

- [ ] **Step 5: Run the focused test to verify GREEN**

Run:

```bash
sh tests/routing.sh
```

Expected: `PASS: routing state`.

- [ ] **Step 6: Commit Task 1**

```bash
git add bin/beroka-governance runtime tests/routing.sh
git commit -m "feat: enforce local BE FE role scope"
```

### Task 2: Verified GitHub Team selection and preflight revalidation

**Files:**
- Modify: `bin/beroka-governance:1087-1190,1281-1335,2961-3020,3088-3139`
- Modify: `tests/bootstrap.sh:81-180,500-548`
- Modify: `tests/routing.sh:595-620,784-885`
- Modify: `tests/smoke.sh`

**Interfaces:**
- Consumes: `GITHUB_ROLE_FILE`, `load_github_role`, `require_role_scope`, `github_auth_health`, `apply_user_file`, and the bootstrap interactive flag.
- Produces: `github_team_memberships`, `configure_github_role`, and `verify_github_role`; preflight verifies membership before connector/OAuth activity.

- [ ] **Step 1: Extend fake `gh` with exact Team fixtures**

Make the fake support `api --help` and `/user/teams`:

```sh
'api --help') exit 0 ;;
'api --paginate /user/teams')
  case "$(sed -n '1p' "$XDG_CONFIG_HOME/fake-github-teams")" in
    frontend)
      printf '%s\n' '[{"slug":"frontend","organization":{"login":"beroka-vn"}}]'
      ;;
    backend)
      printf '%s\n' '[{"slug":"backend","organization":{"login":"beroka-vn"}}]'
      ;;
    both)
      printf '%s\n' '[{"slug":"frontend","organization":{"login":"beroka-vn"}},{"slug":"backend","organization":{"login":"beroka-vn"}}]'
      ;;
    neither) printf '%s\n' '[]' ;;
    *) exit 1 ;;
  esac
  ;;
```

Record calls in `$CALLS` so tests can prove membership happens before any
`mcp` or Atlassian OAuth command.

- [ ] **Step 2: Write failing bootstrap selection tests**

Exercise the real bootstrap command:

```sh
printf '%s\n' healthy >"$XDG_CONFIG_HOME/fake-github-health"
printf '%s\n' frontend >"$XDG_CONFIG_HOME/fake-github-teams"
$CLI bootstrap "$repo" --client codex \
  --version v1.1.0 --non-interactive
[ "$(cat "$role_file")" = FE ] ||
  fail 'Frontend-only membership did not select FE'

printf '%s\n' both >"$XDG_CONFIG_HOME/fake-github-teams"
rm -f "$role_file"
if output=$($CLI bootstrap "$repo" --client codex \
  --version v1.1.0 --non-interactive 2>&1)
then
  fail 'dual membership defaulted a role'
fi
assert_contains "$output" 'Result: GITHUB_ROLE_SELECTION_REQUIRED'

printf '%s\n' neither >"$XDG_CONFIG_HOME/fake-github-teams"
if output=$($CLI bootstrap "$repo" --client codex \
  --version v1.1.0 --non-interactive 2>&1)
then
  fail 'bootstrap accepted no eligible Team'
fi
assert_contains "$output" 'Result: GITHUB_ROLE_REQUIRED'
```

Also assert Backend-only selects `BE`, an existing eligible dual-membership
choice is reused, malformed role state fails, and uninstall removes the role
file.

- [ ] **Step 3: Write failing preflight revalidation tests**

Seed `FE`, then change Team fixtures and assert:

```sh
printf '%s\n' FE >"$role_file"
printf '%s\n' frontend >"$XDG_CONFIG_HOME/fake-github-teams"
assert_contains "$($CLI preflight "$canonical_frontend" --client codex \
  --operation github-write --non-interactive)" 'Result: PASS'

printf '%s\n' backend >"$XDG_CONFIG_HOME/fake-github-teams"
if output=$($CLI preflight "$canonical_frontend" --client codex \
  --operation github-write --non-interactive 2>&1)
then
  fail 'preflight accepted stale FE eligibility'
fi
assert_contains "$output" 'Result: GITHUB_ROLE_REQUIRED'
assert_not_contains "$(cat "$CALLS")" 'mcp '
```

Cover `FULL_STACK` requiring both Teams and API failure returning
`GITHUB_ROLE_UNAVAILABLE`.

- [ ] **Step 4: Run tests to verify RED**

Run:

```bash
sh tests/bootstrap.sh
sh tests/routing.sh
```

Expected: FAIL because bootstrap does not create the role and preflight does
not call the Team API.

- [ ] **Step 5: Implement exact membership parsing**

Use one real API call and literal output flags:

```sh
github_team_memberships() {
  GITHUB_FRONTEND_MEMBER=0
  GITHUB_BACKEND_MEMBER=0
  gtm_output=$(gh api --paginate /user/teams 2>/dev/null) ||
    die GITHUB_ROLE_UNAVAILABLE \
      'Cannot verify beroka-vn GitHub Team membership'
  gtm_memberships=$(printf '%s\n' "$gtm_output" | jq -e -s -r '
    [ .[][] |
      select(.organization.login == "beroka-vn") |
      select(.slug == "frontend" or .slug == "backend") |
      .slug
    ] | unique | .[]
  ') || die GITHUB_ROLE_UNAVAILABLE \
    'Invalid GitHub Team membership response'
  case "$gtm_memberships" in
    frontend) GITHUB_FRONTEND_MEMBER=1 ;;
    backend) GITHUB_BACKEND_MEMBER=1 ;;
    'backend
frontend'|'frontend
backend') GITHUB_FRONTEND_MEMBER=1; GITHUB_BACKEND_MEMBER=1 ;;
    '') ;;
    *) die GITHUB_ROLE_UNAVAILABLE 'Invalid GitHub Team membership response' ;;
  esac
}
```

Require `gh api --help` in `require_github_client`.

- [ ] **Step 6: Implement selection, persistence, and verification**

`configure_github_role CLIENT INTERACTIVE` verifies GitHub auth, calls
`github_team_memberships`, automatically chooses a single Team, reuses an
eligible dual-Team stored role, or prompts exactly once in an interactive
terminal. Write the selected value through `apply_user_file`.

`verify_github_role CLIENT` verifies auth and membership, loads the stored
role, and accepts only:

```sh
FE) [ "$GITHUB_FRONTEND_MEMBER" -eq 1 ] ;;
BE) [ "$GITHUB_BACKEND_MEMBER" -eq 1 ] ;;
FULL_STACK)
  [ "$GITHUB_FRONTEND_MEMBER" -eq 1 ] &&
    [ "$GITHUB_BACKEND_MEMBER" -eq 1 ]
  ;;
```

Call `configure_github_role` after `cmd_setup_connectors` in bootstrap. Call
`verify_github_role` after client-instruction verification and before both
GitHub and Atlassian preflight paths.

- [ ] **Step 7: Run focused tests to verify GREEN**

Run:

```bash
sh tests/bootstrap.sh
sh tests/routing.sh
sh tests/smoke.sh
```

Expected: all three scripts exit `0`.

- [ ] **Step 8: Commit Task 2**

```bash
git add bin/beroka-governance tests/bootstrap.sh tests/routing.sh tests/smoke.sh
git commit -m "feat: verify GitHub Team roles"
```

### Task 3: Canonical active documentation

**Files:**
- Modify: `tests/documentation-architecture.sh`
- Modify: `README.md`
- Modify: `handbook.md`
- Modify: `governance.md`
- Modify: `workflow.md`
- Modify: `runtime/rules/general.md`
- Modify: `runtime/profiles/backend.md`
- Modify: `runtime/profiles/frontend.md`
- Modify: `templates/ai-agent-assignment.md`

**Interfaces:**
- Consumes: the implemented role lifecycle and exact result codes.
- Produces: current developer and agent instructions that use only canonical organization URLs and explain role gates.

- [ ] **Step 1: Write failing documentation assertions**

Add:

```sh
for active_file in \
  README.md handbook.md governance.md workflow.md \
  runtime/rules/general.md runtime/profiles/backend.md \
  runtime/profiles/frontend.md templates/ai-agent-assignment.md
do
  reject_text "$active_file" 'cuongngo1801-beroka/Beroka_Backend'
  reject_text "$active_file" 'cuongngo1801-beroka/Beroka_Frontend'
done

require_text handbook.md 'GITHUB_ROLE_REQUIRED'
require_text runtime/rules/general.md 'ROLE_SCOPE_DENIED'
require_text governance.md 'GitHub Team membership'
```

- [ ] **Step 2: Run documentation tests to verify RED**

Run:

```bash
sh tests/documentation-architecture.sh
```

Expected: FAIL on old personal-account URLs and missing role policy.

- [ ] **Step 3: Update only active documentation**

Replace active Backend and Frontend links with:

```text
https://github.com/beroka-vn/Beroka_Backend
https://github.com/beroka-vn/Beroka_Frontend
```

Document automatic single-Team role selection, the explicit dual-Team choice,
offline context, preflight revalidation, and the exact fail-closed result
codes. Do not edit historical `docs/superpowers/specs` or
`docs/superpowers/plans`.

- [ ] **Step 4: Run documentation and routing tests**

Run:

```bash
sh tests/documentation-architecture.sh
sh tests/routing.sh
```

Expected: both scripts exit `0`.

- [ ] **Step 5: Commit Task 3**

```bash
git add README.md handbook.md governance.md workflow.md runtime templates \
  tests/documentation-architecture.sh
git commit -m "docs: route active guidance through beroka-vn"
```

### Task 4: Prepare and verify v1.0.4

**Files:**
- Modify: `VERSION`
- Modify: `PACKAGE-DESIGN.md`
- Modify: `README.md`
- Modify: `handbook.md`
- Modify: `tests/release.sh`

**Interfaces:**
- Consumes: canonical catalog, role enforcement, active documentation, and both transition alias records.
- Produces: a reviewable `v1.0.4` source state whose next version bump forces alias removal.

- [ ] **Step 1: Write failing release assertions**

Require `VERSION=v1.0.4`, the supported bootstrap command to target `v1.0.4`,
and exactly four integration inventory rows. Add the version-aware transition
gate:

```sh
version=$(sed -n '1p' "$ROOT/VERSION")
case "$version" in
  v1.0.4)
    require_text runtime/integrations/beroka-be-fe.repositories \
      'cuongngo1801-beroka/Beroka_Backend'
    require_text runtime/integrations/beroka-be-fe.repositories \
      'cuongngo1801-beroka/Beroka_Frontend'
    ;;
  *)
    reject_text runtime/integrations/beroka-be-fe.repositories \
      'cuongngo1801-beroka/Beroka_Backend'
    reject_text runtime/integrations/beroka-be-fe.repositories \
      'cuongngo1801-beroka/Beroka_Frontend'
    ;;
esac
```

- [ ] **Step 2: Run release tests to verify RED**

Run:

```bash
sh tests/release.sh
```

Expected: FAIL because source metadata still selects `v1.0.3`.

- [ ] **Step 3: Update release metadata**

Set `VERSION` to `v1.0.4`. Update current supported-release and bootstrap
examples in `README.md`, `handbook.md`, and `PACKAGE-DESIGN.md`. Add a compact
release note covering canonical organization routing, Team role enforcement,
and one-release deprecated aliases.

- [ ] **Step 4: Run the complete verification suite**

Run:

```bash
sh -n bin/beroka-governance release/bootstrap.sh.in
for test_script in tests/*.sh; do sh "$test_script"; done
git diff --check origin/main...HEAD
```

Expected: every command exits `0`.

- [ ] **Step 5: Commit Task 4**

```bash
git add VERSION PACKAGE-DESIGN.md README.md handbook.md tests/release.sh
git commit -m "chore(release): prepare v1.0.4"
```

### Task 5: Publish for review and release

**Files:**
- Update: GitHub Issue `#29`
- Create: pull request from `agent/issue-29-github-team-roles`
- Create after reviewed-commit approval: annotated tag and GitHub Release `v1.0.4`

**Interfaces:**
- Consumes: the four verified implementation commits and full-suite evidence.
- Produces: one traceable Issue #29 PR and, after exact human approval, immutable release `v1.0.4`.

- [ ] **Step 1: Run fresh GitHub preflight before the issue comment**

```bash
beroka-governance preflight "$PWD" \
  --client codex --operation github-write --non-interactive
```

Expected: `Result: PASS`.

- [ ] **Step 2: Comment on Issue #29**

Record:

```text
v1.0.3 evidence: catalog contains the transferred personal-account slugs and canonical beroka-vn clones return ROUTING_REQUIRED.
Implementation branch: agent/issue-29-github-team-roles
Design: docs/superpowers/specs/2026-07-30-github-team-role-routing-design.md
Plan: docs/superpowers/plans/2026-07-30-github-team-role-routing.md
```

Add the final test evidence and PR link after creation; do not create a second
issue.

- [ ] **Step 3: Run fresh preflight and push the branch**

```bash
beroka-governance preflight "$PWD" \
  --client codex --operation github-write --non-interactive
git push -u origin agent/issue-29-github-team-roles
```

- [ ] **Step 4: Resolve the default branch and open a draft PR**

Read `defaultBranchRef.name` from GitHub immediately before PR creation. Create
a draft PR targeting that exact branch with `Fixes #29`, the role matrix,
alias window, full verification evidence, and explicit unverified release
gates.

- [ ] **Step 5: Read back and review**

Verify issue owner/state, PR base/head/draft state, exact head commit, changed
files, and checks. Address review feedback and rerun the complete suite.

- [ ] **Step 6: Request exact merge/release confirmation**

Report the exact PR number and reviewed head commit. Do not merge, tag, or
publish until the user confirms both exact values.

- [ ] **Step 7: Merge and publish only the approved commit**

After fresh GitHub preflights, merge the approved PR, fetch the exact
merge commit from the freshly resolved GitHub default branch, run the release
readiness checks, create annotated tag `v1.0.4`, push that tag, and create the
GitHub Release with the verified `bootstrap.sh` asset. Read back the tag
target, release URL, asset digest, and non-draft/non-prerelease state.
