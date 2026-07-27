# Non-Interactive First Release Cutover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the non-interactive launcher the only team onboarding command, publish and verify `v1.0.1`, then remove the unused GitHub Release and tag `v1.0.0`.

**Architecture:** Active documentation and release tests define one deterministic team deployment path while the CLI retains explicit interactive OAuth capability. Publication is an atomic cutover: a reviewed follow-up merge becomes the new annotated `v1.0.1`, three isolated pilots and one public clean-machine simulation must pass, and only then are the exact old `v1.0.0` Release and tag deleted.

**Tech Stack:** POSIX shell, Git, GitHub CLI, GitHub Releases, existing shell test suites.

## Global Constraints

- Keep `VERSION=v1.0.1`; do not reuse `v1.0.0` for a different commit.
- The only active team Quick Start is the exact `curl | sh` pipeline ending in `--client codex --non-interactive`.
- Retain interactive CLI capability for explicit OAuth login and recovery.
- Historical specifications, plans, and Git commits remain unchanged for traceability.
- One invocation selects exactly one of `codex`, `claude`, or `cursor`.
- Non-interactive mode never opens a browser or `/dev/tty`.
- Missing or invalid Codex OAuth returns exactly one final `Result: ATLASSIAN_AUTH_REQUIRED` plus `Remediation: codex mcp login atlassian`.
- OAuth state and credentials remain owned by the selected client or OS keyring.
- Never request, print, log, or store a developer API token.
- Do not rewrite Git history and do not force-push any branch or tag.
- Do not delete `v1.0.0` until the public `v1.0.1` launcher passes its clean-machine simulation.
- If publication or public simulation fails, stop before deleting `v1.0.0`.
- Never stage or commit `.beroka-governance.lock` or root `AGENTS.md` from the controller worktree.

---

### Task 1: Make Active Onboarding Non-Interactive

**Files:**
- Modify: `README.md`
- Modify: `handbook.md`
- Modify: `PACKAGE-DESIGN.md`
- Modify: `tests/release.sh`
- Modify: `tests/routing.sh`

**Interfaces:**
- Consumes: the verified `bootstrap.sh` launcher and existing non-interactive bootstrap behavior.
- Produces: one active team command, current `v1.0.1` examples, and release-test assertions used by later publication gates.

- [ ] **Step 1: Add failing release-documentation assertions**

In `tests/release.sh`, remove the two assertions that require
`` `v1.0.0` is the first public stable release ``. Replace the launcher
assertion section with:

```sh
noninteractive_launcher='curl -fsSL \
  https://github.com/beroka-vn/beroka-ai-governance/releases/latest/download/bootstrap.sh |
  sh -s -- --client codex --non-interactive'
[ "$(first_code_block_after_heading README.md '## Quick start')" = \
  "$noninteractive_launcher" ] ||
  fail 'README Quick start does not begin with the exact non-interactive launcher'
require_code_block README.md "$noninteractive_launcher"
require_code_block handbook.md "$noninteractive_launcher"
require_code_block PACKAGE-DESIGN.md "$noninteractive_launcher"

for file in README.md handbook.md PACKAGE-DESIGN.md; do
  if grep -Eq '^[[:space:]]*sh -s -- --client codex[[:space:]]*$' \
    "$ROOT/$file"; then
    fail "interactive launcher remains in active onboarding: $file"
  fi
done

reject_text README.md '`v1.0.0` is the first public stable release'
reject_text handbook.md '`v1.0.0` là first public stable release'
reject_text PACKAGE-DESIGN.md \
  '`v1.0.0` is the first public stable release'
```

Keep the existing exact `VERSION=v1.0.1`, launcher-template, trust-boundary,
token, Backend/Frontend, and connector-state assertions.

In `tests/routing.sh`, replace:

```sh
grep -F '`v1.0.0` is the first public stable release' \
  "$ROOT/PACKAGE-DESIGN.md" >/dev/null ||
  fix_wave_fail 'package design does not define the first stable release'
```

with:

```sh
grep -F 'VERSION=v1.0.1' "$ROOT/PACKAGE-DESIGN.md" >/dev/null ||
  fix_wave_fail 'package design does not select v1.0.1'
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```sh
sh tests/release.sh
sh tests/routing.sh
```

Expected: `tests/release.sh` fails because the first README command is still
interactive and active docs still identify `v1.0.0` as the first stable
release. `tests/routing.sh` fails because `PACKAGE-DESIGN.md` does not yet
contain the current lock example.

- [ ] **Step 3: Update `README.md`**

Replace the Quick Start introduction and its two launcher blocks with:

````markdown
## Quick start

From the Git root of the repository to register, install the latest stable
release and set up one explicit client with:

```bash
curl -fsSL \
  https://github.com/beroka-vn/beroka-ai-governance/releases/latest/download/bootstrap.sh |
  sh -s -- --client codex --non-interactive
```

Replace `codex` with `claude` or `cursor`. The client flag is mandatory.
Run setup once for one client on each execution environment, then repeat it
for every additional client there. All enabled clients load the same pinned
governance release. Changing a model inside the same client needs no setup.

The command never opens a browser. When client-owned OAuth is missing or
invalid, installation and repository registration remain in place and the
command returns the exact remediation. Complete that client OAuth flow, then
rerun the same command. Governance never accepts or stores a developer API
token.
````

Keep the launcher tag/commit verification paragraph. Change the later Claude
bootstrap example to:

```sh
beroka-governance bootstrap "$(git rev-parse --show-toplevel)" \
  --client claude \
  --non-interactive
```

- [ ] **Step 4: Update `handbook.md`**

Under `Điều kiện trước khi cài`, replace the `v1.0.0` bullet with:

```markdown
- Dùng một annotated SemVer tag đã được review và publish. Release hiện hành
  cho team là `v1.0.1`; mọi tag được publish từ cutover này là immutable.
```

Under `Bootstrap và install`, keep only this launcher block:

```bash
curl -fsSL \
  https://github.com/beroka-vn/beroka-ai-governance/releases/latest/download/bootstrap.sh |
  sh -s -- --client codex --non-interactive
```

Follow it with:

```markdown
Command không mở browser. Nếu OAuth thiếu hoặc invalid, installation và
registration vẫn được giữ nguyên, command trả
`ATLASSIAN_AUTH_REQUIRED` cùng remediation của selected client. Hoàn tất OAuth
do client sở hữu rồi chạy lại đúng command trên.
```

Replace the release-gate introduction with:

```markdown
`v1.0.1` là release chính thức đầu tiên cho team. Trước mọi push tag,
coordinator phải nhận:
```

Keep the generic candidate checks and the rule forbidding force/overwrite.
Remove the three paragraphs that call `v1.0.0` published or immutable. Do not
edit historical files under `docs/superpowers/`.

- [ ] **Step 5: Update `PACKAGE-DESIGN.md`**

Make these exact active-example replacements:

```text
releases/v1.0.0/                  -> releases/v1.0.1/
VERSION=v1.0.0                    -> VERSION=v1.0.1
install v1.0.0                    -> install v1.0.1
--version v1.0.0                 -> --version v1.0.1
--to v1.0.0                      -> --to v1.0.1
```

Replace the release-policy introduction with:

```markdown
Each release is an immutable annotated SemVer tag. `v1.0.1` is the first
supported team release.
```

Change the Bootstrap lifecycle example to:

```bash
beroka-governance bootstrap /path/to/repo \
  --client codex \
  --non-interactive
```

Replace the `Release launcher` command and introduction with:

````markdown
Each stable release publishes `bootstrap.sh` as a GitHub Release asset. From a
repository Git root, the supported team deployment command is:

```bash
curl -fsSL \
  https://github.com/beroka-vn/beroka-ai-governance/releases/latest/download/bootstrap.sh |
  sh -s -- --client codex --non-interactive
```
````

Retain the later sections explaining that interactive OAuth remains supported
when explicitly invoked and that non-interactive mode never opens a browser.

- [ ] **Step 6: Run focused tests and verify GREEN**

Run:

```sh
git diff --check
sh tests/release.sh
sh tests/routing.sh
sh tests/bootstrap.sh
sh tests/connectors.sh
```

Expected markers:

```text
First public release readiness: PASS
PASS: routing state
Bootstrap onboarding tests: PASS
Connector selection tests: PASS
```

- [ ] **Step 7: Commit Task 1**

Run:

```sh
git add README.md handbook.md PACKAGE-DESIGN.md tests/release.sh tests/routing.sh
git commit -m "docs: make team bootstrap non-interactive"
```

Expected: the commit contains only the five listed files.

---

### Task 2: Verify and Merge the Follow-Up PR

**Files:**
- Verify only.
- Do not modify `v1.0.0` or the unpushed local `v1.0.1` candidate tag.

**Interfaces:**
- Consumes: Task 1 active documentation and tests.
- Produces: a reviewed merge commit that becomes the only valid release
  candidate.

- [ ] **Step 1: Run the complete local suite**

Run:

```sh
git diff --check
sh -n bin/beroka-governance
sh -n release/bootstrap.sh.in
sh -n tests/smoke.sh
sh -n tests/connectors.sh
sh -n tests/bootstrap.sh
sh -n tests/launcher.sh
sh -n tests/routing.sh
sh -n tests/release.sh
sh tests/smoke.sh
sh tests/connectors.sh
sh tests/bootstrap.sh
sh tests/launcher.sh
sh tests/routing.sh
sh tests/release.sh
sh tests/documentation-architecture.sh
```

Expected: every command exits `0`; suite output contains no unexpected
`RED`, `FAIL`, or `GOVERNANCE_NOT_READY`.

- [ ] **Step 2: Review branch scope**

Run:

```sh
git status --short
git diff --stat origin/main...HEAD
git diff --name-only origin/main...HEAD
git tag --list v1.0.1 --format='%(objecttype) %(objectname)'
```

Expected: tracked changes are limited to the approved spec, plan, five Task 1
files, and their commits. The only untracked controller files are
`.beroka-governance.lock` and `AGENTS.md`. The local `v1.0.1` tag still points
to the pre-follow-up merge and has not been pushed.

- [ ] **Step 3: Push the branch and open a draft PR**

Run:

```sh
git push -u origin agent/noninteractive-first-release
gh pr create \
  --repo beroka-vn/beroka-ai-governance \
  --draft \
  --base main \
  --head agent/noninteractive-first-release \
  --title "Make team bootstrap non-interactive" \
  --body "Makes the verified non-interactive launcher the only active team onboarding command, keeps interactive OAuth capability, and prepares the reviewed v1.0.1 cutover. Historical plans remain unchanged."
```

Expected: GitHub returns the draft PR URL.

- [ ] **Step 4: Stop at the human merge gate**

Do not merge the PR. Do not delete any release/tag and do not publish
`v1.0.1`. After the user reports the PR merged, run:

```sh
git fetch origin main
followup_merge=$(git rev-parse origin/main)
git merge-base --is-ancestor HEAD "$followup_merge"
git show "$followup_merge:VERSION"
```

Expected: feature HEAD is an ancestor of the merge commit and VERSION is
`v1.0.1`.

---

### Task 3: Rebuild and Pilot the Exact V1.0.1 Candidate

**Files:**
- Generate outside the repository: a new temporary `bootstrap.sh`.
- Generate outside the repository: isolated Backend, Frontend, and Governance
  clones and HOME/XDG/CODEX_HOME.

**Interfaces:**
- Consumes: the exact follow-up merge commit from Task 2.
- Produces: a new local annotated `v1.0.1` and three isolated pilot results.

- [ ] **Step 1: Remove only the stale unpushed local candidate**

Run:

```sh
old_candidate_commit=a3ce417b6143867feef6d063178f91085fec6ca2
[ -z "$(git ls-remote --tags origin \
  refs/tags/v1.0.1 'refs/tags/v1.0.1^{}')" ]
[ "$(git rev-parse 'refs/tags/v1.0.1^{commit}')" = \
  "$old_candidate_commit" ]
git tag -d v1.0.1
```

Expected: only the local candidate tag created before the follow-up PR is
deleted. The remote has no `v1.0.1`.

- [ ] **Step 2: Create the exact new local tag and asset**

Run:

```sh
release=v1.0.1
release_commit=$(git rev-parse origin/main)
git tag -a "$release" "$release_commit" \
  -m "Beroka AI governance package v1.0.1 candidate"
asset_root=$(mktemp -d \
  "${TMPDIR:-/tmp}/beroka-v1.0.1-asset.XXXXXX")
asset=$asset_root/bootstrap.sh
git show "$release_commit:release/bootstrap.sh.in" |
  sed \
    -e "s/@RELEASE_VERSION@/$release/g" \
    -e "s/@RELEASE_COMMIT@/$release_commit/g" >"$asset"
chmod 755 "$asset"
sh -n "$asset"
if grep -F '@RELEASE_' "$asset" >/dev/null; then
  printf '%s\n' 'STOP: unresolved release placeholder' >&2
  exit 1
fi
[ "$(git cat-file -t refs/tags/v1.0.1)" = tag ]
[ "$(git rev-parse 'refs/tags/v1.0.1^{commit}')" = "$release_commit" ]
```

Expected: the local tag and embedded asset commit both equal the follow-up
merge commit.

- [ ] **Step 3: Create isolated pilot repositories and environment**

Run:

```sh
pilot_root=$(mktemp -d \
  "${TMPDIR:-/tmp}/beroka-v1.0.1-pilot.XXXXXX")
git clone --depth 1 \
  https://github.com/hungnx77/Beroka_Backend.git \
  "$pilot_root/backend"
git clone --depth 1 \
  https://github.com/cuongngo1801-beroka/Beroka_Frontend.git \
  "$pilot_root/frontend"
git clone --depth 1 \
  https://github.com/beroka-vn/beroka-ai-governance.git \
  "$pilot_root/governance"

export HOME=$pilot_root/home
export XDG_DATA_HOME=$pilot_root/data
export XDG_CONFIG_HOME=$pilot_root/config
export BEROKA_GOV_BIN_DIR=$pilot_root/bin
export CODEX_HOME=$pilot_root/codex
export PATH=$BEROKA_GOV_BIN_DIR:$PATH
mkdir -p \
  "$HOME" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" \
  "$BEROKA_GOV_BIN_DIR" "$CODEX_HOME"

canonical_url=https://github.com/beroka-vn/beroka-ai-governance.git
common_git=$(cd "$(git rev-parse --git-common-dir)" && pwd -P)
rewrite_url=${common_git%/.git}
git config --global \
  url."file://$rewrite_url".insteadOf \
  "$canonical_url"
```

Expected: GitHub target remotes remain canonical while governance release
clones are redirected to the exact local candidate inside the isolated HOME.

- [ ] **Step 4: Run all three non-interactive pilots**

Define:

```sh
pilot_one() {
  po_repo=$1
  set +e
  po_output=$(cd "$po_repo" &&
    sh "$asset" --client codex --non-interactive 2>&1)
  po_status=$?
  set -e
  if [ "$po_status" -eq 0 ]; then
    printf '%s\n' "$po_output" | grep -F 'Result: PASS' >/dev/null
  else
    printf '%s\n' "$po_output" |
      grep -F 'Result: ATLASSIAN_AUTH_REQUIRED' >/dev/null
    printf '%s\n' "$po_output" |
      grep -F 'Remediation: codex mcp login atlassian' >/dev/null
  fi
  [ "$(printf '%s\n' "$po_output" | grep -c '^Result: ')" -eq 1 ]
  grep -Fx 'VERSION=v1.0.1' \
    "$po_repo/.beroka-governance.lock" >/dev/null
  grep -Fx "COMMIT=$release_commit" \
    "$po_repo/.beroka-governance.lock" >/dev/null
  grep -Fx 'CLIENTS=codex' \
    "$po_repo/.beroka-governance.lock" >/dev/null
  test -f "$po_repo/AGENTS.md"
  test ! -e "$po_repo/CLAUDE.md"
  test ! -e "$po_repo/.cursor"
  beroka-governance doctor "$po_repo" |
    grep -F 'Result: PASS' >/dev/null
  [ "$(git -C "$po_repo" status --short)" = \
    "?? .beroka-governance.lock
?? AGENTS.md" ]
}

pilot_one "$pilot_root/backend"
pilot_one "$pilot_root/frontend"
pilot_one "$pilot_root/governance"
```

Expected: all pilots preserve registration and return either one `PASS` or one
exact fail-closed Atlassian result. No browser opens and no real credential is
used.

---

### Task 4: Publish V1.0.1 and Remove the Unused V1.0.0

**Files:**
- External GitHub state only after every gate passes.
- Do not change repository history.

**Interfaces:**
- Consumes: the Task 3 annotated tag, verified asset, release commit, and pilot
  evidence.
- Produces: stable latest `v1.0.1`, a passing public launcher simulation, and
  absence of the old `v1.0.0` Release and tag.

- [ ] **Step 1: Verify exact pre-publication state**

Run:

```sh
gh auth status
release_commit=$(git rev-parse 'refs/tags/v1.0.1^{commit}')
asset_root=$(mktemp -d \
  "${TMPDIR:-/tmp}/beroka-v1.0.1-publish.XXXXXX")
asset=$asset_root/bootstrap.sh
git show refs/tags/v1.0.1:release/bootstrap.sh.in |
  sed \
    -e 's/@RELEASE_VERSION@/v1.0.1/g' \
    -e "s/@RELEASE_COMMIT@/$release_commit/g" >"$asset"
chmod 755 "$asset"
sh -n "$asset"
grep -F "RELEASE_COMMIT='$release_commit'" "$asset" >/dev/null
[ -z "$(git ls-remote --tags origin \
  refs/tags/v1.0.1 'refs/tags/v1.0.1^{}')" ]
if gh release view v1.0.1 \
  --repo beroka-vn/beroka-ai-governance >/dev/null 2>&1; then
  printf '%s\n' 'STOP: v1.0.1 release already exists' >&2
  exit 1
fi

old_tag_object=$(git ls-remote --tags origin refs/tags/v1.0.0 |
  awk '{print $1}')
old_tag_commit=$(git ls-remote --tags origin 'refs/tags/v1.0.0^{}' |
  awk '{print $1}')
[ "$old_tag_object" = a9a50cadaa74c537187eaa5602e0da7b60eecb6f ]
[ "$old_tag_commit" = 268a6ecc0443a844211ca23ab0b0e07a2daa2ca2 ]
gh release view v1.0.0 \
  --repo beroka-vn/beroka-ai-governance \
  --json tagName,name,isDraft,isPrerelease,publishedAt,url
```

Expected: `v1.0.1` is absent; exact known `v1.0.0` Release and annotated tag
are still present.

- [ ] **Step 2: Push and publish V1.0.1 without force**

Run:

```sh
git push origin refs/tags/v1.0.1:refs/tags/v1.0.1
gh release create v1.0.1 \
  --repo beroka-vn/beroka-ai-governance \
  --verify-tag \
  --latest \
  --title "Beroka AI Governance v1.0.1" \
  --notes "Verified non-interactive team onboarding with response-driven connector health and resumable client-owned OAuth." \
  "$asset#bootstrap.sh"
```

Expected: the tag push succeeds without force and GitHub returns the new
Release URL.

- [ ] **Step 3: Verify the public Release asset**

Run:

```sh
curl -fsSL \
  https://github.com/beroka-vn/beroka-ai-governance/releases/latest/download/bootstrap.sh |
  grep -F "RELEASE_COMMIT='$release_commit'"
gh release view v1.0.1 \
  --repo beroka-vn/beroka-ai-governance \
  --json url,tagName,name,isDraft,isPrerelease,publishedAt
```

Expected: `v1.0.1` is stable, non-draft, non-prerelease, and the public asset
contains the exact follow-up merge commit.

- [ ] **Step 4: Run the public clean-machine simulation**

Run in a new shell context:

```sh
public_root=$(mktemp -d \
  "${TMPDIR:-/tmp}/beroka-v1.0.1-public.XXXXXX")
git clone --depth 1 \
  https://github.com/beroka-vn/beroka-ai-governance.git \
  "$public_root/governance"
export HOME=$public_root/home
export XDG_DATA_HOME=$public_root/data
export XDG_CONFIG_HOME=$public_root/config
export BEROKA_GOV_BIN_DIR=$public_root/bin
export CODEX_HOME=$public_root/codex
export PATH=$BEROKA_GOV_BIN_DIR:$PATH
mkdir -p \
  "$HOME" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" \
  "$BEROKA_GOV_BIN_DIR" "$CODEX_HOME"

set +e
public_output=$(cd "$public_root/governance" &&
  curl -fsSL \
    https://github.com/beroka-vn/beroka-ai-governance/releases/latest/download/bootstrap.sh |
  sh -s -- --client codex --non-interactive 2>&1)
public_status=$?
set -e
if [ "$public_status" -eq 0 ]; then
  printf '%s\n' "$public_output" | grep -F 'Result: PASS' >/dev/null
else
  printf '%s\n' "$public_output" |
    grep -F 'Result: ATLASSIAN_AUTH_REQUIRED' >/dev/null
  printf '%s\n' "$public_output" |
    grep -F 'Remediation: codex mcp login atlassian' >/dev/null
fi
[ "$(printf '%s\n' "$public_output" | grep -c '^Result: ')" -eq 1 ]
grep -Fx 'VERSION=v1.0.1' \
  "$public_root/governance/.beroka-governance.lock" >/dev/null
grep -Fx "COMMIT=$release_commit" \
  "$public_root/governance/.beroka-governance.lock" >/dev/null
beroka-governance doctor "$public_root/governance" |
  grep -F 'Result: PASS' >/dev/null
[ "$(git -C "$public_root/governance" status --short)" = \
  "?? .beroka-governance.lock
?? AGENTS.md" ]
```

Expected: no timing-related `GOVERNANCE_NOT_READY`; only one valid final
result, the exact lock, base Doctor PASS, and exactly two repository additions.

- [ ] **Step 5: Delete the exact old Release and remote tag**

Only after Step 4 passes, run:

```sh
[ "$(git ls-remote --tags origin refs/tags/v1.0.0 |
  awk '{print $1}')" = a9a50cadaa74c537187eaa5602e0da7b60eecb6f ]
[ "$(git ls-remote --tags origin 'refs/tags/v1.0.0^{}' |
  awk '{print $1}')" = 268a6ecc0443a844211ca23ab0b0e07a2daa2ca2 ]

gh release delete v1.0.0 \
  --repo beroka-vn/beroka-ai-governance \
  --yes
git push origin :refs/tags/v1.0.0

[ "$(git rev-parse 'refs/tags/v1.0.0^{commit}')" = \
  268a6ecc0443a844211ca23ab0b0e07a2daa2ca2 ]
git tag -d v1.0.0
```

Expected: only the exact known `v1.0.0` Release, remote tag, and local tag are
deleted. No force flag is used.

- [ ] **Step 6: Verify final public state**

Run:

```sh
if gh release view v1.0.0 \
  --repo beroka-vn/beroka-ai-governance >/dev/null 2>&1; then
  printf '%s\n' 'FAIL: v1.0.0 Release still exists' >&2
  exit 1
fi
[ -z "$(git ls-remote --tags origin \
  refs/tags/v1.0.0 'refs/tags/v1.0.0^{}')" ]
[ "$(git ls-remote --tags origin 'refs/tags/v1.0.1^{}' |
  awk '{print $1}')" = "$release_commit" ]
gh release view v1.0.1 \
  --repo beroka-vn/beroka-ai-governance \
  --json url,tagName,name,isDraft,isPrerelease,publishedAt
curl -fsSL \
  https://github.com/beroka-vn/beroka-ai-governance/releases/latest/download/bootstrap.sh |
  grep -F "RELEASE_COMMIT='$release_commit'"
```

Expected: `v1.0.0` is absent; `v1.0.1` is the only supported stable Release,
remains latest, and serves the verified asset.
