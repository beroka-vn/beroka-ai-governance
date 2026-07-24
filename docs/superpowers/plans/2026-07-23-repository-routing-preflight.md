# Repository Routing and Connector Preflight Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add trusted repository routing, profile-scoped runtime behavior, and operation-scoped Atlassian preflight without letting pending routing authorize external writes.

**Architecture:** Keep the existing single POSIX shell CLI and add focused routing helpers beside the current registration and connector helpers. Resolve the registered repository's remote default branch into a temporary bare repository, compare only `.beroka-governance.conf`, and render centrally shipped runtime packs. A new `preflight` command composes trusted routing, the existing explicitly selected client health flow, and a small tri-state capability resolver.

**Tech Stack:** POSIX `sh`, Git CLI, `awk`/`sed`/`grep`/`cmp`, Markdown runtime packs, isolated shell smoke tests.

## Global Constraints

- `.beroka-governance.conf` is strict allowlisted `KEY=VALUE`; never `source` or `eval` it.
- Do not fetch, write refs, add objects, alter the index, or change Git configuration in the application repository.
- Fresh online routing verification is required only before routing-dependent external writes.
- Base `doctor REPO` remains connector-independent and offline-safe.
- `context REPO` remains usable for source-only work when routing cannot be verified.
- `--client codex|claude|cursor` selects exactly one client for every preflight.
- Non-interactive authentication failure returns `ATLASSIAN_AUTH_REQUIRED` with the exact selected-client remediation command and never opens a browser.
- OAuth credentials remain owned by the selected client and OS keyring.
- Never accept, print, log, or store a developer API token.
- Capability states are exactly `SUPPORTED`, `UNSUPPORTED`, and `UNKNOWN`.
- `UNKNOWN` and `UNSUPPORTED` block only the requested operation with `CONNECTOR_CAPABILITY_REQUIRED`.
- `page` is the safe Confluence V1 default; `folder` never falls back to a space root.
- Preserve all existing Git tags and never change or overwrite `v1.0.0`.
- Add no dependency beyond the commands already required by the project.

## File Map

| File | Responsibility |
| --- | --- |
| `bin/beroka-governance` | Canonical remote resolution, trusted routing state, strict config parsing, context rendering, preflight, and capability checks. |
| `runtime/routing-schema` | Feature marker; value `1` enables the new routing runtime without invalidating older pinned releases. |
| `runtime/rules/general.md` | Mandatory principles loaded for every verified registered repository. |
| `runtime/profiles/standalone.md` | Standalone repository boundaries. |
| `runtime/profiles/backend.md` | Backend-only boundaries that do not imply a counterpart. |
| `runtime/profiles/frontend.md` | Frontend-only boundaries that do not imply a counterpart. |
| `runtime/integrations/beroka-be-fe.md` | Reviewed BE–FE cross-repository behavior. |
| `runtime/integrations/beroka-be-fe.repositories` | Exact canonical repositories allowed to select the BE–FE integration. |
| `runtime/compatibility/atlassian.tsv` | Reviewed exact connector compatibility records; V1 ships with schema comments and no unverified production claims. |
| `runtime/entrypoint.md` | Session instructions for interpreting core and routing status. |
| `tests/routing.sh` | Isolated routing, baseline, profile, capability, and preflight tests. |
| `tests/smoke.sh` | Release-fixture validation for the new required runtime artifacts. |
| `README.md` | User-facing bootstrap, context, and preflight example. |
| `handbook.md` | Vietnamese onboarding, routing lifecycle, result remediation, and capability policy. |

---

### Task 1: Trusted remote baseline and routing state

**Files:**
- Create: `tests/routing.sh`
- Modify: `bin/beroka-governance:20-45`
- Modify: `bin/beroka-governance:120-150`
- Modify: `bin/beroka-governance:560-575`
- Modify: `bin/beroka-governance:1067-1070`

**Interfaces:**
- Consumes: validated `REPO`, `LOCK_REPOSITORY`, and `RELEASE_DIR` from `verify_registration`.
- Produces: `resolve_canonical_remote REPO EXPECTED_SLUG`; globals `CANONICAL_REMOTE_NAME`, `CANONICAL_REMOTE_URL`.
- Produces: `resolve_routing REPO`; globals `ROUTING_STATE`, `ROUTING_BASELINE_PRESENT`, `ROUTING_BASELINE_COMMIT`, `ROUTING_BASELINE_FILE`.
- Produces: stable states `ROUTING_REQUIRED`, `ROUTING_CHANGE_PENDING`, `ROUTING_ACTIVE`, and `ROUTING_VERIFICATION_REQUIRED`.

- [ ] **Step 1: Create the isolated routing test harness**

Create `tests/routing.sh` with temporary HOME/XDG paths, a fake GitHub URL
rewritten to a local bare remote, a non-`main` default branch, and assertions
that snapshot the application repository:

```sh
#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
CLI=$ROOT/bin/beroka-governance
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/beroka-routing-test.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT HUP INT TERM

export HOME=$TEST_ROOT/home
export XDG_CONFIG_HOME=$TEST_ROOT/config
export XDG_DATA_HOME=$TEST_ROOT/data
export BEROKA_GOV_BIN_DIR=$TEST_ROOT/bin
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$BEROKA_GOV_BIN_DIR"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  case "$1" in
    *"$2"*) ;;
    *) fail "expected [$2] in [$1]" ;;
  esac
}

new_repo() {
  nr_path=$1
  mkdir -p "$nr_path"
  git -C "$nr_path" init -q
  git -C "$nr_path" config user.name test-user
  git -C "$nr_path" config user.email test@example.invalid
}

snapshot_repo() {
  sr_repo=$1
  {
    git -C "$sr_repo" for-each-ref --format='%(refname) %(objectname)'
    git -C "$sr_repo" count-objects -v
    git -C "$sr_repo" config --local --list
    git -C "$sr_repo" status --porcelain=v1 --untracked-files=all
    git -C "$sr_repo" ls-files -s
  }
}

remote_work=$TEST_ROOT/remote-work
remote_bare=$TEST_ROOT/remote.git
new_repo "$remote_work"
git -C "$remote_work" switch -qc trunk
printf '%s\n' '# application' >"$remote_work/README.md"
git -C "$remote_work" add README.md
git -C "$remote_work" commit -qm 'test: initialize application'
git clone -q --bare "$remote_work" "$remote_bare"
git -C "$remote_bare" symbolic-ref HEAD refs/heads/trunk

git config --global \
  url."file://$remote_bare".insteadOf \
  https://github.com/beroka-vn/routing-consumer.git
```

Create the installed governance release and registered consumer with:

```sh
source_repo=$TEST_ROOT/governance-source
new_repo "$source_repo"
mkdir -p "$source_repo/bin" "$source_repo/templates"
cp "$ROOT/VERSION" "$source_repo/VERSION"
cp "$CLI" "$source_repo/bin/beroka-governance"
chmod 755 "$source_repo/bin/beroka-governance"
cp -R "$ROOT/runtime" "$source_repo/runtime"
cp "$ROOT/governance.md" "$ROOT/handbook.md" "$ROOT/workflow.md" "$source_repo/"
cp -R "$ROOT/templates/." "$source_repo/templates/"
git -C "$source_repo" add .
git -C "$source_repo" commit -qm 'test: create governance release'
git -C "$source_repo" tag -a v1.0.0 -m v1.0.0

git config --global \
  url."file://$source_repo".insteadOf \
  https://github.com/beroka-vn/beroka-ai-governance.git
release_dir=$XDG_DATA_HOME/beroka-ai-governance/releases/v1.0.0
mkdir -p "$(dirname -- "$release_dir")"
git clone -q --depth 1 --branch v1.0.0 \
  https://github.com/beroka-vn/beroka-ai-governance.git "$release_dir"

consumer=$TEST_ROOT/consumer
new_repo "$consumer"
git -C "$consumer" remote add upstream \
  https://github.com/beroka-vn/routing-consumer.git
git -C "$consumer" fetch -q upstream trunk
git -C "$consumer" switch -qc trunk FETCH_HEAD
$CLI register "$consumer" --version v1.0.0
git -C "$consumer" add .
git -C "$consumer" commit -qm 'test: register governance'
```

Then assert:

```sh
before=$(snapshot_repo "$consumer")
output=$($CLI context "$consumer")
after=$(snapshot_repo "$consumer")

[ "$before" = "$after" ] ||
  fail 'context changed application repository state'
assert_contains "$output" 'Routing: ROUTING_REQUIRED'

printf '%s\n' \
  'SCHEMA_VERSION=1' \
  'PROFILE=standalone' \
  'JIRA_PROJECT_KEY=APP' \
  'CONFLUENCE_SPACE_KEY=APP' \
  'CONFLUENCE_ROOT_CONTENT_ID=123456' \
  'CONFLUENCE_ROOT_CONTENT_TYPE=page' \
  'INTEGRATION_PROFILE=none' \
  'CROSS_REPO_POLICY=explicit-only' \
  >"$consumer/.beroka-governance.conf"

output=$($CLI context "$consumer")
assert_contains "$output" 'Routing: ROUTING_CHANGE_PENDING'
```

Commit and push the routing file to `trunk`, fetch nothing into the consumer,
and assert `ROUTING_ACTIVE`. Modify the working tree, stage a different value,
and commit another different value on a task branch in three separate cases;
each must return `ROUTING_CHANGE_PENDING`. Finally make the remote temporarily
unreachable without changing the application remote:

```sh
mv "$remote_bare" "$TEST_ROOT/remote.offline"
doctor_output=$($CLI doctor "$consumer")
assert_contains "$doctor_output" 'Result: PASS'
context_output=$($CLI context "$consumer")
assert_contains "$context_output" 'Routing: ROUTING_VERIFICATION_REQUIRED'
assert_contains "$context_output" 'External routing-dependent writes: BLOCKED'
mv "$TEST_ROOT/remote.offline" "$remote_bare"
```

This proves base Doctor is offline-safe while Context degrades only the
routing-dependent scope.

- [ ] **Step 2: Run the routing test and verify it fails**

Run:

```bash
sh tests/routing.sh
```

Expected: FAIL because `context` does not print a routing state and
`verify_registration` requires a remote named `origin`.

- [ ] **Step 3: Replace fixed-origin lookup with canonical remote resolution**

Replace `normalize_origin` with a URL normalizer and a resolver. Registration
continues to prefer a valid `origin`; verification may use any single remote
whose normalized slug equals the lock:

```sh
normalize_github_url() {
  ngu_url=$1
  case "$ngu_url" in
    https://github.com/*) ngu_slug=${ngu_url#https://github.com/} ;;
    git@github.com:*) ngu_slug=${ngu_url#git@github.com:} ;;
    ssh://git@github.com/*) ngu_slug=${ngu_url#ssh://git@github.com/} ;;
    *) return 1 ;;
  esac
  while [ "${ngu_slug%/}" != "$ngu_slug" ]; do ngu_slug=${ngu_slug%/}; done
  ngu_slug=${ngu_slug%.git}
  printf '%s\n' "$ngu_slug" |
    grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' || return 1
  printf '%s\n' "$ngu_slug"
}

resolve_canonical_remote() {
  rcr_repo=$1 rcr_expected=${2:-}
  CANONICAL_REMOTE_NAME= CANONICAL_REMOTE_URL=
  rcr_matches=0
  for rcr_name in $(git -C "$rcr_repo" remote); do
    rcr_url=$(git -C "$rcr_repo" remote get-url "$rcr_name" 2>/dev/null) ||
      continue
    rcr_slug=$(normalize_github_url "$rcr_url") || continue
    if [ -n "$rcr_expected" ]; then
      [ "$rcr_slug" = "$rcr_expected" ] || continue
    elif [ "$rcr_name" != origin ]; then
      continue
    fi
    rcr_matches=$((rcr_matches + 1))
    CANONICAL_REMOTE_NAME=$rcr_name
    CANONICAL_REMOTE_URL=$rcr_url
  done
  if [ -z "$rcr_expected" ] && [ "$rcr_matches" -eq 0 ]; then
    for rcr_name in $(git -C "$rcr_repo" remote); do
      rcr_url=$(git -C "$rcr_repo" remote get-url "$rcr_name" 2>/dev/null) ||
        continue
      normalize_github_url "$rcr_url" >/dev/null 2>&1 || continue
      rcr_matches=$((rcr_matches + 1))
      CANONICAL_REMOTE_NAME=$rcr_name
      CANONICAL_REMOTE_URL=$rcr_url
    done
  fi
  [ "$rcr_matches" -eq 1 ] ||
    die REMOTE_MISMATCH 'Cannot resolve exactly one canonical GitHub remote'
}
```

In `cmd_register`, call `resolve_canonical_remote "$REPO"` and derive
`repository` with:

```sh
repository=$(normalize_github_url "$CANONICAL_REMOTE_URL") ||
  die REMOTE_MISMATCH 'Canonical remote is not a supported GitHub repository'
```

In `verify_registration`, call:

```sh
resolve_canonical_remote "$REPO" "$LOCK_REPOSITORY"
```

Remove the fixed-origin comparison.

- [ ] **Step 4: Implement temporary-bare baseline resolution and blob-only comparison**

Add routing globals beside the transaction globals:

```sh
ROUTING_FILE=.beroka-governance.conf
ROUTING_STATE= ROUTING_BASELINE_PRESENT=0 ROUTING_BASELINE_COMMIT=
ROUTING_BASELINE_FILE= ROUTING_TEMP_DIR=
```

Add:

```sh
routing_cleanup() {
  rc_temp=$ROUTING_TEMP_DIR
  ROUTING_TEMP_DIR=
  [ -z "$rc_temp" ] || rm -rf "$rc_temp"
  trap - EXIT HUP INT TERM
}

fetch_routing_baseline() {
  ROUTING_BASELINE_PRESENT=0 ROUTING_BASELINE_COMMIT= ROUTING_BASELINE_FILE=
  rfb_advertised=$(
    git ls-remote --symref "$CANONICAL_REMOTE_URL" HEAD 2>/dev/null
  ) || return 1
  rfb_ref=$(printf '%s\n' "$rfb_advertised" |
    awk '$1 == "ref:" && $3 == "HEAD" { print $2; exit }')
  rfb_commit=$(printf '%s\n' "$rfb_advertised" |
    awk '$2 == "HEAD" && $1 ~ /^[0-9a-f]{40}$/ { print $1; exit }')
  case "$rfb_ref:$rfb_commit" in
    refs/heads/*:[0-9a-f][0-9a-f]*) ;;
    *) return 1 ;;
  esac

  ROUTING_TEMP_DIR=$(
    mktemp -d "${TMPDIR:-/tmp}/beroka-routing-fetch.XXXXXX"
  ) || return 1
  trap 'routing_cleanup' EXIT
  trap 'routing_cleanup; exit 1' HUP INT TERM
  git -C "$ROUTING_TEMP_DIR" init -q --bare || {
    routing_cleanup
    return 1
  }
  git -C "$ROUTING_TEMP_DIR" fetch -q --depth 1 \
    "$CANONICAL_REMOTE_URL" "$rfb_ref" || {
    routing_cleanup
    return 1
  }
  ROUTING_BASELINE_COMMIT=$(
    git -C "$ROUTING_TEMP_DIR" rev-parse FETCH_HEAD 2>/dev/null
  ) || {
    routing_cleanup
    return 1
  }
  [ "$ROUTING_BASELINE_COMMIT" = "$rfb_commit" ] || {
    routing_cleanup
    return 1
  }

  ROUTING_BASELINE_FILE=$ROUTING_TEMP_DIR/baseline.conf
  if git -C "$ROUTING_TEMP_DIR" cat-file -e \
    "$ROUTING_BASELINE_COMMIT:$ROUTING_FILE" 2>/dev/null
  then
    rfb_mode=$(git -C "$ROUTING_TEMP_DIR" ls-tree \
      "$ROUTING_BASELINE_COMMIT" -- "$ROUTING_FILE" |
      awk '{ print $1; exit }')
    case "$rfb_mode" in
      100644|100755) ;;
      *) routing_cleanup; return 2 ;;
    esac
    git -C "$ROUTING_TEMP_DIR" show \
      "$ROUTING_BASELINE_COMMIT:$ROUTING_FILE" \
      >"$ROUTING_BASELINE_FILE" || {
      routing_cleanup
      return 1
    }
    ROUTING_BASELINE_PRESENT=1
  else
    : >"$ROUTING_BASELINE_FILE"
  fi
}

local_routing_present() {
  git -C "$REPO" cat-file -e "HEAD:$ROUTING_FILE" 2>/dev/null ||
    git -C "$REPO" ls-files --error-unmatch "$ROUTING_FILE" >/dev/null 2>&1 ||
    [ -e "$REPO/$ROUTING_FILE" ] || [ -L "$REPO/$ROUTING_FILE" ]
}

local_routing_matches_baseline() {
  [ ! -L "$REPO/$ROUTING_FILE" ] && [ -f "$REPO/$ROUTING_FILE" ] || return 1
  lrm_baseline=$(
    git -C "$ROUTING_TEMP_DIR" ls-tree \
      "$ROUTING_BASELINE_COMMIT" -- "$ROUTING_FILE"
  )
  lrm_head=$(git -C "$REPO" ls-tree HEAD -- "$ROUTING_FILE")
  lrm_index=$(git -C "$REPO" ls-files -s -- "$ROUTING_FILE")
  [ -n "$lrm_baseline" ] && [ -n "$lrm_head" ] && [ -n "$lrm_index" ] ||
    return 1
  lrm_mode=$(printf '%s\n' "$lrm_baseline" | awk '{ print $1 }')
  lrm_blob=$(printf '%s\n' "$lrm_baseline" | awk '{ print $3 }')
  [ "$(printf '%s\n' "$lrm_head" | awk '{ print $1, $3 }')" = "$lrm_mode $lrm_blob" ] ||
    return 1
  [ "$(printf '%s\n' "$lrm_index" | awk '{ print $1, $2 }')" = "$lrm_mode $lrm_blob" ] ||
    return 1
  git -C "$REPO" diff --quiet -- "$ROUTING_FILE"
}

resolve_routing() {
  ROUTING_STATE=
  rr_fetch=0
  fetch_routing_baseline || rr_fetch=$?
  case "$rr_fetch" in
    0) ;;
    2) ROUTING_STATE=ROUTING_INVALID; return 0 ;;
    *) ROUTING_STATE=ROUTING_VERIFICATION_REQUIRED; return 0 ;;
  esac
  if [ "$ROUTING_BASELINE_PRESENT" -eq 0 ]; then
    if local_routing_present; then
      ROUTING_STATE=ROUTING_CHANGE_PENDING
    else
      ROUTING_STATE=ROUTING_REQUIRED
    fi
  elif local_routing_matches_baseline; then
    ROUTING_STATE=ROUTING_ACTIVE
  else
    ROUTING_STATE=ROUTING_CHANGE_PENDING
  fi
}
```

Ensure `die` calls `routing_cleanup` when `ROUTING_TEMP_DIR` is non-empty so a
dependency, connector, authentication, or capability failure cannot leak the
temporary bare repository. `routing_cleanup` must only remove the exact
`mktemp` directory held in that global.

- [ ] **Step 5: Render routing state from Context without making it fatal**

Change `cmd_context` to preserve core context and add state:

```sh
cmd_context() {
  verify_registration "$1"
  cat "$RELEASE_DIR/runtime/entrypoint.md" ||
    die GOVERNANCE_NOT_READY 'Cannot read runtime entrypoint'
  resolve_routing
  printf '%s\n' \
    "Routing: $ROUTING_STATE" \
    "Routing baseline commit: ${ROUTING_BASELINE_COMMIT:-UNVERIFIED}"
  case "$ROUTING_STATE" in
    ROUTING_ACTIVE) printf '%s\n' 'External routing-dependent writes: PREFLIGHT_REQUIRED' ;;
    *) printf '%s\n' 'External routing-dependent writes: BLOCKED' ;;
  esac
  routing_cleanup
}
```

- [ ] **Step 6: Run focused and existing tests**

Run:

```bash
sh -n bin/beroka-governance
sh tests/routing.sh
sh tests/smoke.sh
```

Expected: all three commands exit 0 and print their PASS summaries. Confirm
`git status --short` shows only the intended Task 1 files.

- [ ] **Step 7: Commit the trusted routing state**

```bash
git add bin/beroka-governance tests/routing.sh
git commit -m "feat: verify trusted repository routing"
```

---

### Task 2: Strict routing schema and profile-scoped runtime

**Files:**
- Create: `runtime/rules/general.md`
- Create: `runtime/routing-schema`
- Create: `runtime/profiles/standalone.md`
- Create: `runtime/profiles/backend.md`
- Create: `runtime/profiles/frontend.md`
- Create: `runtime/integrations/beroka-be-fe.md`
- Create: `runtime/integrations/beroka-be-fe.repositories`
- Modify: `runtime/entrypoint.md`
- Modify: `bin/beroka-governance:315-350`
- Modify: `bin/beroka-governance:1067-1078`
- Modify: `tests/routing.sh`
- Modify: `tests/smoke.sh:20-75`

**Interfaces:**
- Consumes: `ROUTING_BASELINE_FILE`, `ROUTING_BASELINE_PRESENT`, and `ROUTING_STATE` from Task 1.
- Produces: `parse_routing FILE`; globals `ROUTE_PROFILE`, `ROUTE_JIRA_PROJECT_KEY`, `ROUTE_JIRA_BOARD_ID`, `ROUTE_CONFLUENCE_SPACE_KEY`, `ROUTE_CONFLUENCE_ROOT_CONTENT_ID`, `ROUTE_CONFLUENCE_ROOT_CONTENT_TYPE`, `ROUTE_INTEGRATION_PROFILE`, `ROUTE_CROSS_REPO_POLICY`, and `DEPENDENCY_STATE`.
- Produces: `render_routing_context`, which emits only general rules, the selected profile, and the selected integration pack.

- [ ] **Step 1: Add failing schema and profile tests**

Extend `tests/routing.sh` with a helper that replaces and pushes the remote
baseline, resets the consumer to the same commit, and then runs Context:

```sh
publish_routing() {
  pr_content=$1
  printf '%s\n' "$pr_content" >"$remote_work/.beroka-governance.conf"
  git -C "$remote_work" add .beroka-governance.conf
  git -C "$remote_work" commit -qm 'test: publish routing'
  git -C "$remote_work" push -q "file://$remote_bare" trunk
  git -C "$consumer" fetch -q "file://$remote_bare" trunk
  git -C "$consumer" reset -q --hard FETCH_HEAD
}
```

Add exact assertions:

```sh
standalone_config='SCHEMA_VERSION=1
PROFILE=standalone
JIRA_PROJECT_KEY=APP
CONFLUENCE_SPACE_KEY=APP
CONFLUENCE_ROOT_CONTENT_ID=123456
CONFLUENCE_ROOT_CONTENT_TYPE=page
INTEGRATION_PROFILE=none
CROSS_REPO_POLICY=explicit-only'
publish_routing "$standalone_config"
output=$($CLI context "$consumer")
assert_contains "$output" 'Profile: standalone'
assert_contains "$output" 'Dependency state: NO_DEPENDENCY_DECLARED'
assert_contains "$output" '# Standalone Repository'
case "$output" in
  *'# Backend–Frontend Integration'*) fail 'standalone loaded BE-FE integration' ;;
esac

invalid_config='SCHEMA_VERSION=1
PROFILE=standalone
PROFILE=backend
INTEGRATION_PROFILE=none
CROSS_REPO_POLICY=explicit-only'
publish_routing "$invalid_config"
output=$($CLI context "$consumer")
assert_contains "$output" 'Routing: ROUTING_INVALID'
```

Cover an unknown key, a symlink candidate, unsupported schema, invalid board
ID, `standalone + beroka-be-fe`, `none + profile-controlled`, and a valid
Backend config narrowed to `explicit-only`.

- [ ] **Step 2: Run the test and verify it fails**

Run:

```bash
sh tests/routing.sh
```

Expected: FAIL because Context does not parse routing or load runtime packs.

- [ ] **Step 3: Add mandatory general runtime principles**

Create `runtime/routing-schema`:

```text
1
```

Create `runtime/rules/general.md`:

```markdown
# General Repository Governance

- Work only in the registered repository, issue, branch, and file scope.
- Read existing linked records before asking for information or creating work.
- Do not guess a Jira project, Confluence location, repository, dependency,
  counterpart, parent, assignee, permission, or integration mapping.
- One issue has one primary owner, branch, and pull request.
- Repository-local rules and task instructions may narrow this authority but
  may not broaden it or bypass a stop condition.
- Current-repository source, branch, commit, push, Issue, and pull-request work
  does not require Atlassian OAuth.
- Every routing-dependent external write requires a fresh successful
  `beroka-governance preflight`.
- AI may not approve or merge without explicit human confirmation for the exact
  pull request and reviewed commit.
- Report failed or unverified checks as blocked for their dependent scope;
  never report them as PASS.
```

- [ ] **Step 4: Add the three repository profiles**

Create `runtime/profiles/standalone.md`:

```markdown
# Standalone Repository

- GitHub work belongs only to the current registered repository.
- Jira writes belong only to the configured project.
- Confluence writes belong only to the configured space and root content.
- Do not discover a counterpart, create an Integration Hub link, or write to
  another repository, Jira project, or Confluence root automatically.
- Report a possible dependency as a candidate and wait for an exact target and
  developer confirmation.
```

Create `runtime/profiles/backend.md`:

```markdown
# Backend Repository

- The repository owns its machine-readable API, schema, and event contracts.
- Jira and Confluence writes remain inside the configured routing unless an
  active integration profile authorizes an exact counterpart.
- Backend classification alone does not declare a Frontend dependency.
```

Create `runtime/profiles/frontend.md`:

```markdown
# Frontend Repository

- The repository consumes exact published contract artifacts and versions.
- Jira and Confluence writes remain inside the configured routing unless an
  active integration profile authorizes an exact counterpart.
- Frontend classification alone does not declare a Backend dependency.
```

- [ ] **Step 5: Add the reviewed BE–FE integration pack**

Create `runtime/integrations/beroka-be-fe.md`:

```markdown
# Backend–Frontend Integration

- BB and BF use separate project-local Jira items and exact verified links.
- A shared capability uses one verified mapping and one owning Integration Hub.
- Backend publishes the canonical contract artifact; Frontend consumes its
  exact version and does not reconstruct it from issue descriptions.
- Similar names produce candidates only and never authorize links or writes.
- Counterpart and handoff discovery requires exact Jira, Hub, or contract
  evidence plus developer confirmation where the mapping is not unique.
- Cross-repository writes require `CROSS_REPO_POLICY=profile-controlled`.
- `explicit-only` narrows this pack and disables automatic counterpart use.
```

Create `runtime/integrations/beroka-be-fe.repositories` with the exact
currently documented Backend pilot repository:

```text
# canonical repository slug<TAB>profile
hungnx77/Beroka_Backend	backend
```

Do not add a Frontend repository until its exact canonical repository has been
reviewed. In the tagged routing test fixture, append the exact fake mapping
before committing the release:

```sh
printf 'beroka-vn/routing-consumer\tbackend\n' \
  >>"$source_repo/runtime/integrations/beroka-be-fe.repositories"
```

- [ ] **Step 6: Validate the runtime packs without invalidating older releases**

Keep the existing required-file loop unchanged for backward compatibility.
After it, add:

```sh
if [ -e "$vrc_checkout/runtime/routing-schema" ]; then
  assert_release_file "$vrc_checkout" runtime/routing-schema
  [ "$(sed -n '1p' "$vrc_checkout/runtime/routing-schema")" = 1 ] ||
    die VERSION_MISMATCH 'Unsupported routing schema in installed release'
  for vrc_routing_file in \
    runtime/rules/general.md \
    runtime/profiles/standalone.md runtime/profiles/backend.md \
    runtime/profiles/frontend.md runtime/integrations/beroka-be-fe.md \
    runtime/integrations/beroka-be-fe.repositories
  do
    assert_release_file "$vrc_checkout" "$vrc_routing_file"
  done
fi
```

Update both release-fixture builders in `tests/smoke.sh` and
`tests/routing.sh` to copy the complete current `runtime/` tree:

```sh
rm -rf "$source_repo/runtime"
cp -R "$ROOT/runtime" "$source_repo/runtime"
```

Add one legacy release fixture containing `runtime/entrypoint.md` but no
`runtime/routing-schema`. Its base Doctor and Context must continue to pass.
`preflight` against that pinned release must return `GOVERNANCE_NOT_READY` with
an update-release remediation and must not inspect a connector.

- [ ] **Step 7: Implement the strict routing parser**

Add parser globals and a parser that never executes input:

```sh
clear_routing_values() {
  ROUTE_SCHEMA_VERSION= ROUTE_PROFILE= ROUTE_JIRA_PROJECT_KEY=
  ROUTE_JIRA_BOARD_ID= ROUTE_CONFLUENCE_SPACE_KEY=
  ROUTE_CONFLUENCE_ROOT_CONTENT_ID=
  ROUTE_CONFLUENCE_ROOT_CONTENT_TYPE=
  ROUTE_INTEGRATION_PROFILE= ROUTE_CROSS_REPO_POLICY=
  DEPENDENCY_STATE=
}

parse_routing() {
  pr_file=$1
  clear_routing_values
  [ ! -L "$pr_file" ] && [ -f "$pr_file" ] || return 1
  pr_parsed=$(
    awk -F= '
      /^[[:space:]]*$/ { next }
      index($0, "=") == 0 { exit 42 }
      {
        key=$1
        value=substr($0, length(key) + 2)
        if (key !~ /^[A-Z][A-Z0-9_]*$/ || value == "" || seen[key]++) exit 42
        if (key != "SCHEMA_VERSION" &&
            key != "PROFILE" &&
            key != "JIRA_PROJECT_KEY" &&
            key != "JIRA_BOARD_ID" &&
            key != "CONFLUENCE_SPACE_KEY" &&
            key != "CONFLUENCE_ROOT_CONTENT_ID" &&
            key != "CONFLUENCE_ROOT_CONTENT_TYPE" &&
            key != "INTEGRATION_PROFILE" &&
            key != "CROSS_REPO_POLICY") exit 42
        print key "\t" value
      }
    ' "$pr_file"
  ) || return 1
  while IFS="$(printf '\t')" read -r pr_key pr_value; do
    case "$pr_key" in
      SCHEMA_VERSION) ROUTE_SCHEMA_VERSION=$pr_value ;;
      PROFILE) ROUTE_PROFILE=$pr_value ;;
      JIRA_PROJECT_KEY) ROUTE_JIRA_PROJECT_KEY=$pr_value ;;
      JIRA_BOARD_ID) ROUTE_JIRA_BOARD_ID=$pr_value ;;
      CONFLUENCE_SPACE_KEY) ROUTE_CONFLUENCE_SPACE_KEY=$pr_value ;;
      CONFLUENCE_ROOT_CONTENT_ID) ROUTE_CONFLUENCE_ROOT_CONTENT_ID=$pr_value ;;
      CONFLUENCE_ROOT_CONTENT_TYPE) ROUTE_CONFLUENCE_ROOT_CONTENT_TYPE=$pr_value ;;
      INTEGRATION_PROFILE) ROUTE_INTEGRATION_PROFILE=$pr_value ;;
      CROSS_REPO_POLICY) ROUTE_CROSS_REPO_POLICY=$pr_value ;;
    esac
  done <<EOF
$pr_parsed
EOF

  [ "$ROUTE_SCHEMA_VERSION" = 1 ] || return 1
  case "$ROUTE_PROFILE" in standalone|backend|frontend) ;; *) return 1 ;; esac
  case "$ROUTE_INTEGRATION_PROFILE" in none|beroka-be-fe) ;; *) return 1 ;; esac
  case "$ROUTE_CROSS_REPO_POLICY" in explicit-only|profile-controlled) ;; *) return 1 ;; esac
  [ -z "$ROUTE_JIRA_PROJECT_KEY" ] ||
    printf '%s\n' "$ROUTE_JIRA_PROJECT_KEY" |
      grep -Eq '^[A-Z][A-Z0-9_]*$' || return 1
  [ -z "$ROUTE_JIRA_BOARD_ID" ] ||
    printf '%s\n' "$ROUTE_JIRA_BOARD_ID" |
      grep -Eq '^[1-9][0-9]*$' || return 1
  [ -z "$ROUTE_CONFLUENCE_SPACE_KEY" ] ||
    printf '%s\n' "$ROUTE_CONFLUENCE_SPACE_KEY" |
      grep -Eq '^[A-Za-z0-9._~-]+$' || return 1
  [ -z "$ROUTE_CONFLUENCE_ROOT_CONTENT_ID" ] ||
    printf '%s\n' "$ROUTE_CONFLUENCE_ROOT_CONTENT_ID" |
      grep -Eq '^[1-9][0-9]*$' || return 1
  case "$ROUTE_CONFLUENCE_ROOT_CONTENT_TYPE" in ''|page|folder) ;; *) return 1 ;; esac

  [ "$ROUTE_INTEGRATION_PROFILE" != none ] ||
    [ "$ROUTE_CROSS_REPO_POLICY" = explicit-only ] || return 1
  [ "$ROUTE_PROFILE" != standalone ] ||
    [ "$ROUTE_INTEGRATION_PROFILE:$ROUTE_CROSS_REPO_POLICY" = none:explicit-only ] ||
    return 1
  [ "$ROUTE_INTEGRATION_PROFILE" != beroka-be-fe ] ||
    [ "$ROUTE_PROFILE" = backend ] || [ "$ROUTE_PROFILE" = frontend ] ||
    return 1
  if [ "$ROUTE_INTEGRATION_PROFILE" = beroka-be-fe ]; then
    awk -F '\t' \
      -v repository="$LOCK_REPOSITORY" \
      -v profile="$ROUTE_PROFILE" '
        $0 !~ /^#/ && $1 == repository && $2 == profile { found=1 }
        END { exit !found }
      ' "$RELEASE_DIR/runtime/integrations/beroka-be-fe.repositories" ||
      return 1
  fi

  if [ "$ROUTE_INTEGRATION_PROFILE" = none ]; then
    DEPENDENCY_STATE=NO_DEPENDENCY_DECLARED
  else
    DEPENDENCY_STATE=MAPPING_VERIFICATION_REQUIRED
  fi
}
```

After `resolve_routing`, parse a present baseline. Invalid baseline mode or
content sets `ROUTING_STATE=ROUTING_INVALID`. Validate a local pending candidate
in a subshell so it cannot replace parsed baseline globals:

```sh
if [ "$ROUTING_STATE" = ROUTING_CHANGE_PENDING ] &&
   [ -e "$REPO/$ROUTING_FILE" ]
then
  if (parse_routing "$REPO/$ROUTING_FILE"); then
    printf '%s\n' 'Local routing validation: PASS'
  else
    printf '%s\n' 'Local routing validation: INVALID'
  fi
fi
```

The lifecycle state remains `ROUTING_CHANGE_PENDING` in both cases.

- [ ] **Step 8: Render only the effective runtime packs**

Add:

```sh
render_routing_context() {
  cat "$RELEASE_DIR/runtime/rules/general.md" ||
    die GOVERNANCE_NOT_READY 'Cannot read general runtime rules'
  [ "$ROUTING_BASELINE_PRESENT" -eq 1 ] || return 0
  case "$ROUTING_STATE" in
    ROUTING_ACTIVE|ROUTING_CHANGE_PENDING) ;;
    *) return 0 ;;
  esac
  printf '%s\n' \
    "Profile: $ROUTE_PROFILE" \
    "Dependency state: $DEPENDENCY_STATE" \
    "Jira project: ${ROUTE_JIRA_PROJECT_KEY:-ROUTING_REQUIRED}" \
    "Jira board: ${ROUTE_JIRA_BOARD_ID:-NOT_DECLARED}" \
    "Confluence space: ${ROUTE_CONFLUENCE_SPACE_KEY:-ROUTING_REQUIRED}" \
    "Confluence root content: ${ROUTE_CONFLUENCE_ROOT_CONTENT_ID:-ROUTING_REQUIRED}" \
    "Confluence root type: ${ROUTE_CONFLUENCE_ROOT_CONTENT_TYPE:-ROUTING_REQUIRED}" \
    "Integration profile: $ROUTE_INTEGRATION_PROFILE" \
    "Cross-repository policy: $ROUTE_CROSS_REPO_POLICY"
  cat "$RELEASE_DIR/runtime/profiles/$ROUTE_PROFILE.md" ||
    die GOVERNANCE_NOT_READY 'Cannot read repository profile'
  if [ "$ROUTE_INTEGRATION_PROFILE" != none ]; then
    cat "$RELEASE_DIR/runtime/integrations/$ROUTE_INTEGRATION_PROFILE.md" ||
      die GOVERNANCE_NOT_READY 'Cannot read integration profile'
  fi
}
```

Call it from `cmd_context` after printing the routing state. Replace
`runtime/entrypoint.md` with short session instructions that treat the emitted
rules as authoritative and require preflight only for connector-dependent
writes. If the pinned release has no `runtime/routing-schema`, preserve its
legacy Context output and skip routing resolution. `preflight` requires marker
value `1` before remote, connector, or OAuth checks.

- [ ] **Step 9: Run focused and regression tests**

Run:

```bash
sh -n bin/beroka-governance
sh tests/routing.sh
sh tests/smoke.sh
sh tests/connectors.sh
```

Expected: all commands exit 0. Standalone Context contains no BE–FE integration
pack; Backend Context with `beroka-be-fe` contains exactly one integration pack.

- [ ] **Step 10: Commit strict profiles**

```bash
git add bin/beroka-governance runtime tests/routing.sh tests/smoke.sh
git commit -m "feat: render reviewed repository profiles"
```

---

### Task 3: Operation-scoped connector preflight

**Files:**
- Create: `runtime/compatibility/atlassian.tsv`
- Modify: `bin/beroka-governance:20-45`
- Modify: `bin/beroka-governance:710-1015`
- Modify: `bin/beroka-governance:1090-1135`
- Modify: `tests/routing.sh`
- Modify: `tests/connectors.sh`
- Modify: `tests/smoke.sh`

**Interfaces:**
- Consumes: trusted parsed routing from Tasks 1–2 and current `require_client`, `connector_state`, `connector_health`, `run_oauth`, `oauth_command`.
- Produces: `connector_inventory CLIENT`; globals `CAPABILITY_INVENTORY`, `CAPABILITY_INVENTORY_COMPLETE`, `CAPABILITY_TOOLSET`.
- Produces: `resolve_capability CLIENT CAPABILITY`; global `CAPABILITY_STATE`.
- Produces: `cmd_preflight REPO --client CLIENT --operation OPERATION [--non-interactive]`, with allowlisted operations `jira-write`, `jira-board-verify`, `confluence-write`, and `cross-repo-write`.

- [ ] **Step 1: Add failing CLI, auth, and capability tests**

Extend `tests/routing.sh` with fake `codex`, `claude`, and `cursor-agent`
executables using the existing patterns from `tests/connectors.sh`. The fake
Codex inventory must expose:

```json
{"name":"atlassian","tools":{"createJiraIssue":{},"getJiraIssue":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}
```

Add assertions:

```sh
output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive)
assert_contains "$output" 'Jira project: APP'
assert_contains "$output" 'Capability: jira-issue-write'
assert_contains "$output" 'Capability state: SUPPORTED'
assert_contains "$output" 'Result: PASS'

if output=$($CLI preflight "$consumer" \
  --client codex --operation jira-board-verify --non-interactive 2>&1)
then
  fail 'board verification passed without board capability evidence'
fi
assert_contains "$output" 'Capability state: UNKNOWN'
assert_contains "$output" 'Result: CONNECTOR_CAPABILITY_REQUIRED'

if output=$($CLI preflight "$consumer" \
  --client codex --operation invalid --non-interactive 2>&1)
then
  fail 'preflight accepted an unknown operation'
fi
```

Change the fake complete inventory to contain `getJiraIssue` but not
`createJiraIssue`, rerun `jira-write`, and assert:

```sh
assert_contains "$output" 'Capability state: UNSUPPORTED'
assert_contains "$output" 'Result: CONNECTOR_CAPABILITY_REQUIRED'
```

Publish a Folder-root config and assert `confluence-write` returns
`CONNECTOR_CAPABILITY_REQUIRED` without falling back to the space root.
Publish a config without `JIRA_PROJECT_KEY` and assert `ROUTING_REQUIRED`
occurs before any OAuth command is logged.

Run `cross-repo-write` against standalone routing and assert
`ROUTING_REQUIRED`. Publish an allowlisted Backend
`beroka-be-fe + profile-controlled` baseline and assert it prints the exact
integration profile plus `Required next preflight:
jira-write|confluence-write`; it must not claim that an underlying target write
has already passed.

Copy the exact `mcp login atlassian` branches from the fake executables in
`tests/connectors.sh` into the routing-test fakes, then assert:

- interactive preflight invokes only the selected client's login after `y`;
- declined login returns `ATLASSIAN_AUTH_REQUIRED`;
- `--non-interactive` never invokes login;
- the exact remediation command is printed; and
- no option accepts an API token or echoes its supplied value.

With a healthy Codex connector and no Board or Folder compatibility evidence,
assert base connector Doctor remains healthy:

```sh
output=$($CLI doctor "$consumer" --client codex)
assert_contains "$output" 'Connector: PASS'
assert_contains "$output" 'Authentication: PASS'
assert_contains "$output" 'Result: PASS'
```

Clear the fake-client call log, run base Doctor and Context, and assert neither
command logged `mcp login`.

- [ ] **Step 2: Run focused tests and verify they fail**

Run:

```bash
sh tests/routing.sh
```

Expected: FAIL with usage because `preflight` is not implemented.

- [ ] **Step 3: Add the reviewed compatibility-record schema**

Create `runtime/compatibility/atlassian.tsv`:

```text
# schema=1
# client<TAB>version<TAB>endpoint<TAB>toolset<TAB>tested_on<TAB>capability<TAB>state
```

Do not add a production capability row until an isolated connector pilot
produces evidence. Add this file to the release required-file loop and both
release fixtures.

Compatibility fixture tests may append an exact fake-client row to the tagged
test release:

```text
claude	1.2.3	https://mcp.atlassian.com/v1/mcp/authv2	UNAVAILABLE	2026-07-23	confluence-folder-parent-write	SUPPORTED
```

The production file remains evidence-free and therefore yields `UNKNOWN`.
Make the fake Claude executable return `claude 1.2.3` for `--version`, publish
a Folder-root baseline, and assert `confluence-write` changes from `UNKNOWN`
to `SUPPORTED` only in the tagged test release containing this exact record.

- [ ] **Step 4: Capture selected-client tool inventory without printing it**

Refactor the existing health probes so their captured output can be classified
without being emitted. Add a one-command cache:

```sh
connector_probe() {
  cp_client=$1
  [ "${CONNECTOR_PROBE_CLIENT:-}" = "$cp_client" ] && return 0
  CONNECTOR_PROBE_CLIENT=$cp_client CONNECTOR_PROBE_OUTPUT=
  CONNECTOR_PROBE_TOOLS=
  case "$cp_client" in
    codex)
      CONNECTOR_PROBE_OUTPUT=$(
        {
          printf '%s\n' \
            '{"method":"initialize","id":0,"params":{"clientInfo":{"name":"beroka-governance","title":"Beroka Governance","version":"1"}}}' \
            '{"method":"initialized","params":{}}' \
            '{"method":"mcpServerStatus/list","id":1,"params":{"detail":"toolsAndAuthOnly","limit":100}}'
          sleep 3
        } | codex app-server --stdio 2>&1
      ) || return 1
      ;;
    claude)
      CONNECTOR_PROBE_OUTPUT=$(claude mcp list 2>&1) || :
      ;;
    cursor)
      CONNECTOR_PROBE_OUTPUT=$(cursor-agent mcp list 2>&1) || :
      case "$CONNECTOR_PROBE_OUTPUT" in
        *atlassian*ready*|*atlassian*Ready*|*atlassian*connected*|*atlassian*Connected*)
          CONNECTOR_PROBE_TOOLS=$(
            cursor-agent mcp list-tools atlassian 2>&1
          ) || :
          ;;
      esac
      ;;
  esac
}

connector_inventory() {
  ci_client=$1
  CAPABILITY_INVENTORY= CAPABILITY_INVENTORY_COMPLETE=0
  CAPABILITY_TOOLSET=UNAVAILABLE
  case "$ci_client" in
    codex)
      connector_probe codex || return 1
      CAPABILITY_INVENTORY=$CONNECTOR_PROBE_OUTPUT
      case "$CAPABILITY_INVENTORY" in
        *'"name":"atlassian"'*'"tools":{'*)
          CAPABILITY_INVENTORY_COMPLETE=1
          ;;
      esac
      ;;
    claude)
      CAPABILITY_INVENTORY_COMPLETE=0
      ;;
    cursor)
      connector_probe cursor || return 1
      [ -n "$CONNECTOR_PROBE_TOOLS" ] || return 1
      CAPABILITY_INVENTORY=$CONNECTOR_PROBE_TOOLS
      CAPABILITY_INVENTORY_COMPLETE=1
      ;;
  esac
  [ "$CAPABILITY_INVENTORY_COMPLETE" -eq 1 ] || return 0
  CAPABILITY_TOOLSET=
  for ci_tool in \
    createConfluencePage createJiraIssue getConfluencePage getJiraIssue
  do
    if inventory_has_tool "$ci_tool"; then
      if [ -n "$CAPABILITY_TOOLSET" ]; then
        CAPABILITY_TOOLSET=$CAPABILITY_TOOLSET,$ci_tool
      else
        CAPABILITY_TOOLSET=$ci_tool
      fi
    fi
  done
  [ -n "$CAPABILITY_TOOLSET" ] || CAPABILITY_TOOLSET=EMPTY
}

inventory_has_tool() {
  iht_tool=$1
  case "$CAPABILITY_INVENTORY" in
    *"\"$iht_tool\""*|*"$iht_tool"*) return 0 ;;
    *) return 1 ;;
  esac
}

```

Make `connector_health` call `connector_probe` and classify
`CONNECTOR_PROBE_OUTPUT` plus Cursor's `CONNECTOR_PROBE_TOOLS`. Reset
`CONNECTOR_PROBE_CLIENT` and
`CONNECTOR_PROBE_OUTPUT` and `CONNECTOR_PROBE_TOOLS` after a successful OAuth
command so the post-login health check cannot reuse the pre-login result.
Keep every raw output value suppressed.

- [ ] **Step 5: Implement tri-state semantic capability resolution**

Add:

```sh
runtime_capability() {
  rc_capability=$1
  CAPABILITY_STATE=UNKNOWN
  case "$rc_capability" in
    jira-issue-write)
      if inventory_has_tool createJiraIssue &&
         inventory_has_tool getJiraIssue
      then
        CAPABILITY_STATE=SUPPORTED
      elif [ "$CAPABILITY_INVENTORY_COMPLETE" -eq 1 ]; then
        CAPABILITY_STATE=UNSUPPORTED
      fi
      ;;
    confluence-page-parent-write)
      if inventory_has_tool createConfluencePage &&
         inventory_has_tool getConfluencePage
      then
        CAPABILITY_STATE=SUPPORTED
      elif [ "$CAPABILITY_INVENTORY_COMPLETE" -eq 1 ]
      then
        CAPABILITY_STATE=UNSUPPORTED
      fi
      ;;
    jira-board-verification|confluence-folder-parent-write)
      CAPABILITY_STATE=UNKNOWN
      ;;
    *) return 1 ;;
  esac
}

compatibility_capability() {
  cc_client=$1 cc_capability=$2
  cc_executable=$(client_executable "$cc_client")
  cc_version=$("$cc_executable" --version 2>/dev/null | sed -n '1{s/.* //;p;}') ||
    return 1
  printf '%s\n' "$cc_version" | grep -Eq '^[A-Za-z0-9._+-]+$' || return 1
  awk -F '\t' \
    -v client="$cc_client" \
    -v version="$cc_version" \
    -v endpoint="$ATLASSIAN_MCP_URL" \
    -v toolset="$CAPABILITY_TOOLSET" \
    -v capability="$cc_capability" '
      /^[[:space:]]*$/ || /^#/ { next }
      {
        if (NF != 7 ||
            $1 !~ /^(codex|claude|cursor)$/ ||
            $2 !~ /^[A-Za-z0-9._+-]+$/ ||
            $3 == "" ||
            $4 == "" ||
            $5 !~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/ ||
            $6 !~ /^[a-z][a-z0-9-]+$/ ||
            $7 !~ /^(SUPPORTED|UNSUPPORTED)$/) invalid=1
        if ($1 == client &&
            $2 == version &&
            $3 == endpoint &&
            $4 == toolset &&
            $6 == capability) {
          matches++
          result=$7
        }
      }
      END {
        if (invalid || matches > 1) exit 42
        if (matches == 1) print result
        else exit 1
      }
    ' "$RELEASE_DIR/runtime/compatibility/atlassian.tsv"
}

resolve_capability() {
  rcap_client=$1 rcap_capability=$2
  connector_inventory "$rcap_client" || {
    CAPABILITY_STATE=UNKNOWN
    return 0
  }
  runtime_capability "$rcap_capability" || return 1
  [ "$CAPABILITY_STATE" = UNKNOWN ] || return 0
  rcap_compat=$(compatibility_capability \
    "$rcap_client" "$rcap_capability") || rcap_compat=
  case "$rcap_compat" in
    SUPPORTED|UNSUPPORTED) CAPABILITY_STATE=$rcap_compat ;;
    *) CAPABILITY_STATE=UNKNOWN ;;
  esac
}
```

The parser rejects malformed or duplicate exact-match rows. A runtime inventory
overrides an older compatibility row because it is evaluated first.

- [ ] **Step 6: Implement operation routing gates**

Add:

```sh
require_operation_routing() {
  ror_operation=$1
  case "$ror_operation" in
    jira-write)
      [ -n "$ROUTE_JIRA_PROJECT_KEY" ] ||
        die ROUTING_REQUIRED 'JIRA_PROJECT_KEY is required for jira-write'
      PREFLIGHT_CAPABILITY=jira-issue-write
      ;;
    jira-board-verify)
      [ -n "$ROUTE_JIRA_PROJECT_KEY" ] ||
        die ROUTING_REQUIRED 'JIRA_PROJECT_KEY is required for jira-board-verify'
      [ -n "$ROUTE_JIRA_BOARD_ID" ] ||
        die ROUTING_REQUIRED 'JIRA_BOARD_ID is required for jira-board-verify'
      PREFLIGHT_CAPABILITY=jira-board-verification
      ;;
    confluence-write)
      [ -n "$ROUTE_CONFLUENCE_SPACE_KEY" ] &&
        [ -n "$ROUTE_CONFLUENCE_ROOT_CONTENT_ID" ] &&
        [ -n "$ROUTE_CONFLUENCE_ROOT_CONTENT_TYPE" ] ||
        die ROUTING_REQUIRED 'Confluence space, root content ID, and root type are required'
      case "$ROUTE_CONFLUENCE_ROOT_CONTENT_TYPE" in
        page) PREFLIGHT_CAPABILITY=confluence-page-parent-write ;;
        folder) PREFLIGHT_CAPABILITY=confluence-folder-parent-write ;;
      esac
      ;;
    cross-repo-write)
      [ "$ROUTE_CROSS_REPO_POLICY" = profile-controlled ] &&
        [ "$ROUTE_INTEGRATION_PROFILE" != none ] ||
        die ROUTING_REQUIRED 'Reviewed profile-controlled integration is required'
      PREFLIGHT_CAPABILITY=
      ;;
    *) usage >&2; exit 2 ;;
  esac
}
```

`cross-repo-write` verifies only the cross-repository policy and central
integration pack. The agent must immediately run the underlying
`jira-write` or `confluence-write` preflight before the target write; print
that required next preflight instead of claiming connector capability.

- [ ] **Step 7: Implement preflight argument parsing and fail-closed flow**

Add usage:

```text
beroka-governance preflight REPO --client codex|claude|cursor --operation OPERATION [--non-interactive]
```

Add `cmd_preflight`:

```sh
cmd_preflight() {
  pf_repo=$1
  shift
  pf_client= pf_operation= pf_non_interactive=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --client)
        [ -z "$pf_client" ] && [ "$#" -ge 2 ] || { usage >&2; exit 2; }
        case "$2" in codex|claude|cursor) pf_client=$2 ;; *) usage >&2; exit 2 ;; esac
        shift 2
        ;;
      --operation)
        [ -z "$pf_operation" ] && [ "$#" -ge 2 ] || { usage >&2; exit 2; }
        pf_operation=$2
        shift 2
        ;;
      --non-interactive)
        [ "$pf_non_interactive" -eq 0 ] || { usage >&2; exit 2; }
        pf_non_interactive=1
        shift
        ;;
      *) usage >&2; exit 2 ;;
    esac
  done
  [ -n "$pf_client" ] && [ -n "$pf_operation" ] ||
    { usage >&2; exit 2; }

  verify_registration "$pf_repo"
  resolve_routing
  case "$ROUTING_STATE" in
    ROUTING_ACTIVE) ;;
    ROUTING_REQUIRED) routing_cleanup; die ROUTING_REQUIRED ;;
    ROUTING_CHANGE_PENDING) routing_cleanup; die ROUTING_CHANGE_PENDING ;;
    ROUTING_INVALID) routing_cleanup; die ROUTING_INVALID ;;
    *) routing_cleanup; die ROUTING_VERIFICATION_REQUIRED ;;
  esac
  parse_routing "$ROUTING_BASELINE_FILE" || {
    routing_cleanup
    die ROUTING_INVALID
  }
  require_operation_routing "$pf_operation"

  require_client "$pf_client"
  pf_connector=0
  connector_state "$pf_client" || pf_connector=$?
  [ "$pf_connector" -eq 0 ] || {
    routing_cleanup
    die CONNECTOR_MISSING "Missing compatible Atlassian connector for $pf_client"
  }
  pf_health=0
  connector_health "$pf_client" || pf_health=$?
  if [ "$pf_health" -eq 1 ]; then
    pf_interactive=0
    if [ "$pf_non_interactive" -eq 0 ] && [ -t 0 ] && [ -t 1 ]; then
      pf_interactive=1
    fi
    if [ "$pf_interactive" -eq 1 ]; then
      printf '%s\n' "Client: $pf_client" 'Authentication: AUTH_REQUIRED'
      printf 'Start OAuth now? [y/N] '
      IFS= read -r pf_answer || pf_answer=
      case "$pf_answer" in
        y|Y|yes|YES)
          run_oauth "$pf_client" || {
            routing_cleanup
            auth_required "$pf_client"
          }
          connector_health "$pf_client" || {
            routing_cleanup
            auth_required "$pf_client"
          }
          ;;
        *) routing_cleanup; auth_required "$pf_client" ;;
      esac
    else
      routing_cleanup
      auth_required "$pf_client"
    fi
  elif [ "$pf_health" -ne 0 ]; then
    routing_cleanup
    die GOVERNANCE_NOT_READY 'Cannot verify Atlassian connector health'
  fi

  if [ -n "$PREFLIGHT_CAPABILITY" ]; then
    resolve_capability "$pf_client" "$PREFLIGHT_CAPABILITY"
    if [ "$CAPABILITY_STATE" != SUPPORTED ]; then
      printf '%s\n' \
        "Operation: $pf_operation" \
        "Capability: $PREFLIGHT_CAPABILITY" \
        "Capability state: $CAPABILITY_STATE"
      routing_cleanup
      die CONNECTOR_CAPABILITY_REQUIRED
    fi
  fi
  print_preflight_result "$pf_client" "$pf_operation"
  routing_cleanup
}
```

Implement `print_preflight_result` with only the route fields required by the
operation, plus selected client, baseline commit, profile, integration policy,
capability state where applicable, and `Result: PASS`. For
`cross-repo-write`, print:

```text
Required next preflight: jira-write|confluence-write
```

and do not perform the target write.

Add the `preflight` branch in `main`:

```sh
preflight)
  [ "$#" -ge 6 ] || { usage >&2; exit 2; }
  shift
  pf_repo=$1
  shift
  cmd_preflight "$pf_repo" "$@"
  ;;
```

- [ ] **Step 8: Run focused and regression tests**

Run:

```bash
sh -n bin/beroka-governance
sh tests/routing.sh
sh tests/connectors.sh
sh tests/smoke.sh
```

Expected: every test exits 0. Inspect fake-client call logs to verify no other
client and no login command was invoked in non-interactive cases.

- [ ] **Step 9: Commit preflight and capability checks**

```bash
git add bin/beroka-governance runtime/compatibility/atlassian.tsv tests
git commit -m "feat: gate connector writes by operation"
```

---

### Task 4: Onboarding documentation and release verification

**Files:**
- Modify: `README.md:7-45`
- Modify: `handbook.md:35-150`
- Modify: `handbook.md:239-286`
- Modify: `handbook.md:414-440`
- Modify: `runtime/entrypoint.md`
- Modify: `tests/routing.sh`

**Interfaces:**
- Consumes: final CLI and result codes from Tasks 1–3.
- Produces: an exact operator path for new standalone repositories, reviewed
  BE–FE profiles, offline source work, bootstrap routing PRs, and selected-client
  remediation.

- [ ] **Step 1: Add documentation contract assertions**

Append to `tests/routing.sh`:

```sh
grep -F 'beroka-governance preflight' "$ROOT/README.md" >/dev/null ||
  fail 'README does not document preflight'
grep -F 'ROUTING_CHANGE_PENDING' "$ROOT/handbook.md" >/dev/null ||
  fail 'handbook does not document pending routing'
grep -F 'central governance onboarding project' "$ROOT/handbook.md" >/dev/null ||
  fail 'handbook does not document bootstrap issue provenance'
grep -F 'CONNECTOR_CAPABILITY_REQUIRED' "$ROOT/handbook.md" >/dev/null ||
  fail 'handbook does not document capability remediation'
```

- [ ] **Step 2: Run the documentation assertions and verify they fail**

Run:

```bash
sh tests/routing.sh
```

Expected: FAIL at the first missing documentation contract.

- [ ] **Step 3: Update the README quick start**

After connector-aware Doctor, add:

```bash
beroka-governance context /srv/beroka/backend
beroka-governance preflight /srv/beroka/backend \
  --client "$client" \
  --operation jira-write
```

Explain in the surrounding prose:

- Context may continue source-only work while routing is unverified.
- Preflight is required immediately before each routing-dependent external
  write.
- The exact selected client owns OAuth.
- Repository routing comes only from the freshly fetched default-branch
  baseline.
- Pending local routing can be committed, pushed, and reviewed but cannot route
  Jira, Confluence, or cross-repository writes.

- [ ] **Step 4: Add the Vietnamese routing lifecycle to the handbook**

Add a section containing this exact standalone example:

```text
SCHEMA_VERSION=1
PROFILE=standalone
JIRA_PROJECT_KEY=APP
CONFLUENCE_SPACE_KEY=APP
CONFLUENCE_ROOT_CONTENT_ID=123456
CONFLUENCE_ROOT_CONTENT_TYPE=page
INTEGRATION_PROFILE=none
CROSS_REPO_POLICY=explicit-only
```

Document:

1. `ROUTING_REQUIRED` when neither trusted nor local routing exists.
2. `ROUTING_CHANGE_PENDING` while the first routing PR is unmerged.
3. The first PR references a manually created Jira issue or a central
   governance onboarding project independent of pending routing.
4. Branch, commit, push, current-repository Issue, and PR remain allowed.
5. After merge, start a new session and run fresh Context/Preflight.
6. Offline Context blocks only routing-dependent external writes.

Add the Backend schema from the design spec and state that `JIRA_BOARD_ID`
never proves Board capability.

- [ ] **Step 5: Document capability and result remediation**

Add this table to the handbook:

| Result | Remediation |
| --- | --- |
| `ROUTING_REQUIRED` | Add exact routing through the reviewed onboarding workflow. |
| `ROUTING_INVALID` | Fix the strict schema on a branch and merge it. |
| `ROUTING_CHANGE_PENDING` | Review and merge the routing PR; do not use local routing for writes. |
| `ROUTING_VERIFICATION_REQUIRED` | Restore authenticated remote access and rerun fresh preflight. |
| `DEPENDENCY_MISSING` | Install the explicitly selected client/helper. |
| `CONNECTOR_MISSING` | Run `beroka-governance setup-connectors --client <client>`. |
| `ATLASSIAN_AUTH_REQUIRED` | Run the exact remediation command printed for the selected client. |
| `CONNECTOR_CAPABILITY_REQUIRED` | Use a supported operation/client or add a reviewed compatibility record after an isolated pilot. |

State that `SUPPORTED`, `UNSUPPORTED`, and `UNKNOWN` are operation-scoped;
Folder and Board never fall back to Page, space root, JQL, or a guessed
capability.

- [ ] **Step 6: Run the complete release gate**

Capture the current tag object before testing:

```bash
v1_before=$(git rev-parse refs/tags/v1.0.0 2>/dev/null || printf absent)
sh -n bin/beroka-governance
sh tests/smoke.sh
sh tests/connectors.sh
sh tests/routing.sh
v1_after=$(git rev-parse refs/tags/v1.0.0 2>/dev/null || printf absent)
test "$v1_before" = "$v1_after"
git diff --check
```

Expected: every command exits 0, all test scripts print PASS, the tag object is
unchanged, and `git diff --check` prints nothing.

- [ ] **Step 7: Commit documentation and release coverage**

```bash
git add README.md handbook.md runtime/entrypoint.md tests/routing.sh
git commit -m "docs: add repository routing onboarding"
```

## Final Review Gate

- [ ] Compare every result code and state transition against
  `docs/superpowers/specs/2026-07-23-repository-routing-design.md`.
- [ ] Confirm Context loads only `general + selected profile + selected
  integration`.
- [ ] Confirm preflight validates routing before any OAuth prompt.
- [ ] Confirm a missing optional capability never changes base Doctor PASS.
- [ ] Confirm no test invokes a real client, keyring, browser, Jira project, or
  Confluence content.
- [ ] Confirm no developer API token option, prompt, environment contract,
  output, or stored field exists.
- [ ] Confirm `git status --short` contains no unrelated user changes.
- [ ] Confirm `v1.0.0` resolves to the same object as before implementation.
