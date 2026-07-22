# Beroka AI Governance Package V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a version-pinned POSIX governance package that applies only to explicitly registered repositories and can be installed, validated, updated, rolled back, and removed without copying the governance bundle into application repositories.

**Architecture:** One POSIX shell CLI installs immutable shallow Git checkouts under the developer's user data directory. A four-key lock file and thin Codex, Claude Code, and Cursor entrypoints route each registered repository through the exact pinned release. Read-only `doctor`, `context`, and `show` commands share one validation path; mutating commands stage all target content before applying marker-delimited changes.

**Tech Stack:** POSIX `sh`, Git, standard POSIX utilities, Markdown, and one framework-free shell smoke test.

## Global Constraints

- Supported environments are Linux, macOS, and Windows through WSL.
- Do not require Python, Node.js, a daemon, a package registry, or another service.
- Use only the private source `beroka-vn/beroka-ai-governance` in production.
- Store no GitHub, Jira, Confluence, or agent credentials.
- Never execute the lock file with `source` or `eval`.
- Never pipe network output to a shell or fetch an unpinned branch for runtime use.
- Apply governance only when a repository contains a valid lock and managed entrypoints.
- Preserve all repository-owned content outside package markers.
- Keep updates explicit; do not select the latest release automatically.
- Pin both annotated SemVer tag and full 40-character commit SHA.
- Preserve stricter repository-specific security, architecture, ownership, and validation rules.
- The first release is `v1.0.0`; no tag is published before automated and three-client smoke checks pass.
- Do not register Frontend repositories during the Backend pilot.

## File Map

| Path | Responsibility |
| --- | --- |
| `VERSION` | Exact package SemVer, initially `v1.0.0` |
| `bin/beroka-governance` | Entire POSIX CLI and all validation/mutation logic |
| `runtime/entrypoint.md` | Vendor-neutral routing printed by `context` |
| `tests/smoke.sh` | Isolated Git fixtures and end-to-end CLI assertions |
| `templates/agent-entrypoints/AGENTS.md` | Marker-delimited Codex/repository entrypoint |
| `templates/agent-entrypoints/CLAUDE.md` | Marker-delimited local import of `AGENTS.md` |
| `templates/agent-entrypoints/team-dev-ai-workflow.mdc` | Dedicated always-applied Cursor entrypoint |
| `README.md` | Maintainer overview and developer bootstrap |
| `handbook.md` | Vietnamese install, register, update, rollback, and troubleshooting guide |
| `PACKAGE-DESIGN.md` | Approved design status and compatibility references |

---

### Task 1: Read-only package validation and context loading

**Files:**
- Create: `VERSION`
- Create: `bin/beroka-governance`
- Create: `runtime/entrypoint.md`
- Create: `tests/smoke.sh`

**Interfaces:**
- Consumes: application repository path, `.beroka-governance.lock`, Git `origin`, and a detached release checkout under the configured data directory.
- Produces: `doctor REPO`, `context REPO`, and `show REPO DOCUMENT [NAME]`; stable result codes; `PASS` only after source, repository, version, commit, tag, and clean-checkout validation.

- [ ] **Step 1: Write the failing read-only smoke test**

Create `tests/smoke.sh` with isolated XDG directories, a tagged central fixture, and a registered consumer fixture:

```sh
#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
CLI=$ROOT/bin/beroka-governance
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/beroka-governance-test.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

export HOME=$TMP_ROOT/home
export XDG_DATA_HOME=$TMP_ROOT/data
export XDG_CONFIG_HOME=$TMP_ROOT/config
export BEROKA_GOV_BIN_DIR=$TMP_ROOT/bin
mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$BEROKA_GOV_BIN_DIR"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  haystack=$1
  needle=$2
  case "$haystack" in
    *"$needle"*) ;;
    *) fail "expected [$needle] in [$haystack]" ;;
  esac
}

new_repo() {
  path=$1
  mkdir -p "$path"
  git -C "$path" init -q
  git -C "$path" config user.name test-user
  git -C "$path" config user.email test@example.invalid
}

make_release_fixture() {
  source_repo=$TMP_ROOT/source
  new_repo "$source_repo"
  mkdir -p "$source_repo/runtime" "$source_repo/templates/agent-entrypoints"
  printf 'v1.0.0\n' >"$source_repo/VERSION"
  printf 'PINNED ENTRYPOINT v1.0.0\n' >"$source_repo/runtime/entrypoint.md"
  printf 'GOVERNANCE v1.0.0\n' >"$source_repo/governance.md"
  printf 'HANDBOOK v1.0.0\n' >"$source_repo/handbook.md"
  printf 'WORKFLOW v1.0.0\n' >"$source_repo/workflow.md"
  printf 'JIRA TEMPLATE v1.0.0\n' >"$source_repo/templates/jira-confluence.md"
  cp "$ROOT/templates/agent-entrypoints/AGENTS.md" "$source_repo/templates/agent-entrypoints/AGENTS.md"
  cp "$ROOT/templates/agent-entrypoints/CLAUDE.md" "$source_repo/templates/agent-entrypoints/CLAUDE.md"
  cp "$ROOT/templates/agent-entrypoints/team-dev-ai-workflow.mdc" "$source_repo/templates/agent-entrypoints/team-dev-ai-workflow.mdc"
  git -C "$source_repo" add .
  git -C "$source_repo" commit -qm 'test: create v1 fixture'
  git -C "$source_repo" tag -a v1.0.0 -m 'v1.0.0'
  release_dir=$XDG_DATA_HOME/beroka-ai-governance/releases/v1.0.0
  mkdir -p "$(dirname -- "$release_dir")"
  git clone -q --depth 1 --branch v1.0.0 "file://$source_repo" "$release_dir"
  RELEASE_COMMIT=$(git -C "$release_dir" rev-parse HEAD)
  export RELEASE_COMMIT
}

make_consumer_fixture() {
  consumer=$TMP_ROOT/consumer
  new_repo "$consumer"
  git -C "$consumer" remote add origin https://github.com/beroka-vn/example-backend.git
  printf '%s\n' \
    'SOURCE=beroka-vn/beroka-ai-governance' \
    'REPOSITORY=beroka-vn/example-backend' \
    'VERSION=v1.0.0' \
    "COMMIT=$RELEASE_COMMIT" >"$consumer/.beroka-governance.lock"
  cp "$source_repo/templates/agent-entrypoints/AGENTS.md" "$consumer/AGENTS.md"
  cp "$source_repo/templates/agent-entrypoints/CLAUDE.md" "$consumer/CLAUDE.md"
  mkdir -p "$consumer/.cursor/rules"
  cp "$source_repo/templates/agent-entrypoints/team-dev-ai-workflow.mdc" "$consumer/.cursor/rules/beroka-governance.mdc"
  git -C "$consumer" add .beroka-governance.lock AGENTS.md CLAUDE.md .cursor/rules/beroka-governance.mdc
  git -C "$consumer" commit -qm 'test: register governance lock'
}

make_release_fixture
make_consumer_fixture

doctor_output=$($CLI doctor "$consumer")
assert_contains "$doctor_output" 'Result: PASS'
assert_contains "$doctor_output" 'Version: v1.0.0'

context_output=$($CLI context "$consumer")
assert_contains "$context_output" 'PINNED ENTRYPOINT v1.0.0'

show_output=$($CLI show "$consumer" governance)
assert_contains "$show_output" 'GOVERNANCE v1.0.0'

template_output=$($CLI show "$consumer" template jira-confluence)
assert_contains "$template_output" 'JIRA TEMPLATE v1.0.0'

if $CLI show "$consumer" ../../etc/passwd >/dev/null 2>&1; then
  fail 'show accepted path traversal'
fi

printf 'PASS: read-only package validation\n'
```

- [ ] **Step 2: Run the smoke test and confirm the expected failure**

Run:

```bash
sh tests/smoke.sh
```

Expected: non-zero exit because `bin/beroka-governance` does not exist.

- [ ] **Step 3: Add the package version and runtime entrypoint**

Create `VERSION`:

```text
v1.0.0
```

Create `runtime/entrypoint.md`:

```markdown
# Beroka Team Development AI Workflow

Result: PASS

The current repository and governance release were validated by
`beroka-governance context`.

Before Jira, GitHub, Confluence, planning, or implementation work:

1. Read the repository rules and exact assigned issue first.
2. Run `beroka-governance show "$PWD" handbook` before provider setup or preflight.
3. Run `beroka-governance show "$PWD" governance` for authority, ownership, readiness, mapping, and stop conditions.
4. Run `beroka-governance show "$PWD" workflow` for the relevant lifecycle steps.
5. Load only the required template with `beroka-governance show "$PWD" template NAME`.

Never guess a Jira project, Epic, counterpart, assignee, Capability ID, Hub row,
documentation location, permission, repository, or contract version. A missing
or failed package/provider check blocks only the dependent scope and must never
be reported as PASS.
```

- [ ] **Step 4: Implement the read-only CLI core**

Create `bin/beroka-governance` with these exact constants, validators, and public routing:

```sh
#!/bin/sh
set -eu

PROGRAM=beroka-governance
SOURCE_SLUG=beroka-vn/beroka-ai-governance
DATA_ROOT=${XDG_DATA_HOME:-$HOME/.local/share}/beroka-ai-governance
CONFIG_ROOT=${XDG_CONFIG_HOME:-$HOME/.config}/beroka-ai-governance
BIN_DIR=${BEROKA_GOV_BIN_DIR:-$HOME/.local/bin}
REMOTE_URL=https://github.com/beroka-vn/beroka-ai-governance.git

die() {
  code=$1
  shift
  printf '%s\n' "Result: $code" >&2
  if [ "$#" -gt 0 ]; then printf '%s\n' "$*" >&2; fi
  exit 1
}

usage() {
  printf '%s\n' \
    'Usage:' \
    '  beroka-governance doctor REPO' \
    '  beroka-governance context REPO' \
    '  beroka-governance show REPO governance|handbook|workflow' \
    '  beroka-governance show REPO template ai-agent-assignment|github-issue|jira-confluence|pull-request'
}

canonical_repo() {
  requested=$1
  root=$(git -C "$requested" rev-parse --show-toplevel 2>/dev/null) ||
    die REPOSITORY_NOT_REGISTERED "Not a Git repository: $requested"
  (CDPATH= cd -- "$root" && pwd -P)
}

normalize_origin() {
  repo=$1
  url=$(git -C "$repo" remote get-url origin 2>/dev/null) || die REMOTE_MISMATCH 'Git origin is missing'
  case "$url" in
    https://github.com/*) slug=${url#https://github.com/} ;;
    git@github.com:*) slug=${url#git@github.com:} ;;
    ssh://git@github.com/*) slug=${url#ssh://git@github.com/} ;;
    *) die REMOTE_MISMATCH "Unsupported GitHub origin: $url" ;;
  esac
  slug=${slug%.git}
  slug=${slug%/}
  printf '%s\n' "$slug" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' ||
    die REMOTE_MISMATCH "Invalid GitHub repository slug: $slug"
  printf '%s\n' "$slug"
}

read_lock() {
  repo=$1
  lock=$repo/.beroka-governance.lock
  [ -f "$lock" ] || die REPOSITORY_NOT_REGISTERED "Missing $lock"
  LOCK_SOURCE= LOCK_REPOSITORY= LOCK_VERSION= LOCK_COMMIT=
  seen_source= seen_repository= seen_version= seen_commit=
  while IFS='=' read -r key value; do
    [ -n "$key" ] || continue
    case "$key" in
      SOURCE) [ -z "$seen_source" ] || die GOVERNANCE_NOT_READY 'Duplicate SOURCE'; LOCK_SOURCE=$value; seen_source=1 ;;
      REPOSITORY) [ -z "$seen_repository" ] || die GOVERNANCE_NOT_READY 'Duplicate REPOSITORY'; LOCK_REPOSITORY=$value; seen_repository=1 ;;
      VERSION) [ -z "$seen_version" ] || die GOVERNANCE_NOT_READY 'Duplicate VERSION'; LOCK_VERSION=$value; seen_version=1 ;;
      COMMIT) [ -z "$seen_commit" ] || die GOVERNANCE_NOT_READY 'Duplicate COMMIT'; LOCK_COMMIT=$value; seen_commit=1 ;;
      *) die GOVERNANCE_NOT_READY "Unknown lock key: $key" ;;
    esac
  done <"$lock"
  [ "$LOCK_SOURCE" = "$SOURCE_SLUG" ] || die GOVERNANCE_NOT_READY 'Unexpected SOURCE'
  printf '%s\n' "$LOCK_REPOSITORY" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' || die GOVERNANCE_NOT_READY 'Invalid REPOSITORY'
  printf '%s\n' "$LOCK_VERSION" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' || die GOVERNANCE_NOT_READY 'Invalid VERSION'
  printf '%s\n' "$LOCK_COMMIT" | grep -Eq '^[0-9a-f]{40}$' || die GOVERNANCE_NOT_READY 'Invalid COMMIT'
}

verify_release() {
  RELEASE_DIR=$DATA_ROOT/releases/$LOCK_VERSION
  [ -d "$RELEASE_DIR/.git" ] || die GOVERNANCE_NOT_READY "Release is not installed: $LOCK_VERSION"
  head=$(git -C "$RELEASE_DIR" rev-parse HEAD 2>/dev/null) || die VERSION_MISMATCH 'Installed release has no commit'
  [ "$head" = "$LOCK_COMMIT" ] || die VERSION_MISMATCH 'Installed commit differs from lock'
  tag_commit=$(git -C "$RELEASE_DIR" rev-parse "$LOCK_VERSION^{commit}" 2>/dev/null) || die VERSION_MISMATCH 'Installed tag is missing'
  [ "$tag_commit" = "$LOCK_COMMIT" ] || die VERSION_MISMATCH 'Tag commit differs from lock'
  [ "$(sed -n '1p' "$RELEASE_DIR/VERSION")" = "$LOCK_VERSION" ] || die VERSION_MISMATCH 'VERSION file differs from lock'
  [ -z "$(git -C "$RELEASE_DIR" status --porcelain --untracked-files=all)" ] || die VERSION_MISMATCH 'Installed release contains local modifications'
}

verify_registration() {
  REPO=$(canonical_repo "$1")
  read_lock "$REPO"
  origin_slug=$(normalize_origin "$REPO")
  [ "$origin_slug" = "$LOCK_REPOSITORY" ] || die REMOTE_MISMATCH "Origin $origin_slug differs from $LOCK_REPOSITORY"
  verify_release
}

cmd_doctor() {
  verify_registration "$1"
  printf '%s\n' "Repository: $LOCK_REPOSITORY" "Version: $LOCK_VERSION" "Commit: $LOCK_COMMIT" 'Result: PASS'
}

cmd_context() { verify_registration "$1"; cat "$RELEASE_DIR/runtime/entrypoint.md"; }

cmd_show() {
  repo=$1 kind=$2 name=${3:-}
  verify_registration "$repo"
  case "$kind:$name" in
    governance:) file=governance.md ;;
    handbook:) file=handbook.md ;;
    workflow:) file=workflow.md ;;
    template:ai-agent-assignment) file=templates/ai-agent-assignment.md ;;
    template:github-issue) file=templates/github-issue.md ;;
    template:jira-confluence) file=templates/jira-confluence.md ;;
    template:pull-request) file=templates/pull-request.md ;;
    *) die GOVERNANCE_NOT_READY "Unknown document selection: $kind ${name}" ;;
  esac
  [ -f "$RELEASE_DIR/$file" ] || die GOVERNANCE_NOT_READY "Missing package file: $file"
  cat "$RELEASE_DIR/$file"
}

main() {
  command=${1:-}
  case "$command" in
    doctor) [ "$#" -eq 2 ] || { usage >&2; exit 2; }; cmd_doctor "$2" ;;
    context) [ "$#" -eq 2 ] || { usage >&2; exit 2; }; cmd_context "$2" ;;
    show) [ "$#" -ge 3 ] && [ "$#" -le 4 ] || { usage >&2; exit 2; }; cmd_show "$2" "$3" "${4:-}" ;;
    *) usage >&2; exit 2 ;;
  esac
}

main "$@"
```

Make it executable:

```bash
chmod 755 bin/beroka-governance tests/smoke.sh
```

- [ ] **Step 5: Run the focused checks**

```bash
sh -n bin/beroka-governance
sh -n tests/smoke.sh
sh tests/smoke.sh
```

Expected: syntax checks exit `0`; smoke output ends with `PASS: read-only package validation`.

- [ ] **Step 6: Commit the read-only core**

```bash
git add VERSION bin/beroka-governance runtime/entrypoint.md tests/smoke.sh
git commit -m "feat(package): validate pinned governance context"
```

---

### Task 2: Transactional repository registration and thin entrypoints

**Files:**
- Modify: `bin/beroka-governance`
- Modify: `tests/smoke.sh`
- Modify: `templates/agent-entrypoints/AGENTS.md`
- Modify: `templates/agent-entrypoints/CLAUDE.md`
- Modify: `templates/agent-entrypoints/team-dev-ai-workflow.mdc`

**Interfaces:**
- Consumes: installed release version, clean target entrypoint paths, and normalized application `origin`.
- Produces: `register REPO --version VERSION [--dry-run]`, `.beroka-governance.lock`, marker-delimited `AGENTS.md` and `CLAUDE.md` content, dedicated Cursor rule, and one local registry row formatted as `absolute-path<TAB>repository<TAB>version`.

- [ ] **Step 1: Add failing registration cases to the smoke test**

```sh
register_repo=$TMP_ROOT/register-consumer
new_repo "$register_repo"
git -C "$register_repo" remote add origin git@github.com:beroka-vn/register-backend.git
printf '# Existing repository rules\n\nKeep this line.\n' >"$register_repo/AGENTS.md"
printf '# Existing Claude rules\n\nKeep this Claude line.\n' >"$register_repo/CLAUDE.md"
git -C "$register_repo" add AGENTS.md CLAUDE.md
git -C "$register_repo" commit -qm 'test: add existing agent rules'

$CLI register "$register_repo" --version v1.0.0
first_hash=$(git -C "$register_repo" hash-object AGENTS.md CLAUDE.md .beroka-governance.lock .cursor/rules/beroka-governance.mdc)
$CLI register "$register_repo" --version v1.0.0
second_hash=$(git -C "$register_repo" hash-object AGENTS.md CLAUDE.md .beroka-governance.lock .cursor/rules/beroka-governance.mdc)
[ "$first_hash" = "$second_hash" ] || fail 'repeated register changed managed files'
assert_contains "$(cat "$register_repo/AGENTS.md")" 'Keep this line.'
assert_contains "$(cat "$register_repo/CLAUDE.md")" 'Keep this Claude line.'
assert_contains "$(cat "$register_repo/.beroka-governance.lock")" 'REPOSITORY=beroka-vn/register-backend'

dry_repo=$TMP_ROOT/dry-consumer
new_repo "$dry_repo"
git -C "$dry_repo" remote add origin https://github.com/beroka-vn/dry-backend.git
$CLI register "$dry_repo" --version v1.0.0 --dry-run >/dev/null
[ ! -e "$dry_repo/.beroka-governance.lock" ] || fail 'dry-run created a lock'

dirty_repo=$TMP_ROOT/dirty-consumer
new_repo "$dirty_repo"
git -C "$dirty_repo" remote add origin https://github.com/beroka-vn/dirty-backend.git
printf 'uncommitted rules\n' >"$dirty_repo/AGENTS.md"
if $CLI register "$dirty_repo" --version v1.0.0 >/dev/null 2>&1; then fail 'register accepted a dirty target entrypoint'; fi
[ "$(cat "$dirty_repo/AGENTS.md")" = 'uncommitted rules' ] || fail 'failed preflight modified AGENTS.md'

printf 'PASS: repository registration\n'
```

Expected before implementation: usage error because `register` is unknown.

- [ ] **Step 2: Replace the three source entrypoint templates with thin managed content**

Set `templates/agent-entrypoints/AGENTS.md` to:

````markdown
<!-- BEROKA-GOVERNANCE:START -->
## Beroka AI Governance

This repository uses a pinned central governance release. Before Jira, GitHub,
Confluence, planning, or implementation work, run:

```bash
beroka-governance context "$PWD"
```

Follow the returned routing and load only the required document or template with
`beroka-governance show`. If validation does not return `Result: PASS`, stop the
dependent scope and report the exact governance result.

Repository-specific instructions may narrow central governance. They must not
broaden authority or bypass a central stop condition.
<!-- BEROKA-GOVERNANCE:END -->
````

Set `templates/agent-entrypoints/CLAUDE.md` to:

```markdown
<!-- BEROKA-GOVERNANCE:START -->
@AGENTS.md
<!-- BEROKA-GOVERNANCE:END -->
```

Set `templates/agent-entrypoints/team-dev-ai-workflow.mdc` to:

```markdown
---
description: Load the exact pinned Beroka Jira, GitHub, Confluence, ownership, and handoff workflow.
globs:
alwaysApply: true
---

Follow @AGENTS.md. Run `beroka-governance context "$PWD"` before governed work.
Continue only when it returns `Result: PASS`; then use `beroka-governance show`
to load only the relevant document or template.
```

- [ ] **Step 3: Add safe staging, marker validation, and transaction helpers**

Add these constants and helpers before command handlers:

```sh
START_MARKER='<!-- BEROKA-GOVERNANCE:START -->'
END_MARKER='<!-- BEROKA-GOVERNANCE:END -->'
REGISTRY=$CONFIG_ROOT/registered-repos
TX_DIR= TX_REPO= TX_COMMITTED=0

target_dirty() { [ -z "$(git -C "$1" status --porcelain -- "$2")" ]; }

assert_valid_template() {
  template=$1
  [ "$(grep -Fxc "$START_MARKER" "$template")" -eq 1 ] || die ENTRYPOINT_DRIFT "Invalid start marker in $template"
  [ "$(grep -Fxc "$END_MARKER" "$template")" -eq 1 ] || die ENTRYPOINT_DRIFT "Invalid end marker in $template"
}

strip_managed_block() {
  input=$1 output=$2
  awk -v start="$START_MARKER" -v end="$END_MARKER" '
    $0 == start { if (inside) exit 42; inside=1; found++; next }
    $0 == end { if (!inside) exit 42; inside=0; next }
    !inside { print }
    END { if (inside || found > 1) exit 42 }
  ' "$input" >"$output" || die ENTRYPOINT_DRIFT "Malformed managed block in $input"
}

tx_begin() {
  TX_REPO=$1
  TX_DIR=$(mktemp -d "${TMPDIR:-/tmp}/beroka-governance-tx.XXXXXX")
  mkdir -p "$TX_DIR/staged" "$TX_DIR/backup"
  : >"$TX_DIR/manifest"
  TX_COMMITTED=0
  trap 'tx_abort' EXIT HUP INT TERM
}

tx_stage_write() {
  relative=$1 source_file=$2
  mkdir -p "$TX_DIR/staged/$(dirname -- "$relative")"
  cp "$source_file" "$TX_DIR/staged/$relative"
  printf 'W\t%s\n' "$relative" >>"$TX_DIR/manifest"
}

tx_stage_delete() { printf 'D\t%s\n' "$1" >>"$TX_DIR/manifest"; }

tx_snapshot() {
  relative=$1
  if [ -e "$TX_REPO/$relative" ]; then
    mkdir -p "$TX_DIR/backup/$(dirname -- "$relative")"
    cp -p "$TX_REPO/$relative" "$TX_DIR/backup/$relative"
    printf 'E\t%s\n' "$relative" >>"$TX_DIR/originals"
  else
    printf 'M\t%s\n' "$relative" >>"$TX_DIR/originals"
  fi
}

tx_apply() {
  : >"$TX_DIR/originals"
  while IFS="$(printf '\t')" read -r operation relative; do
    tx_snapshot "$relative"
    case "$operation" in
      W)
        mkdir -p "$TX_REPO/$(dirname -- "$relative")"
        temp_file=$(mktemp "$TX_REPO/$(dirname -- "$relative")/.beroka-write.XXXXXX")
        cp "$TX_DIR/staged/$relative" "$temp_file"
        mv "$temp_file" "$TX_REPO/$relative"
        ;;
      D) rm -f "$TX_REPO/$relative" ;;
      *) die GOVERNANCE_NOT_READY "Unknown transaction operation: $operation" ;;
    esac
  done <"$TX_DIR/manifest"
}

tx_abort() {
  [ -n "$TX_DIR" ] || return 0
  if [ "$TX_COMMITTED" -eq 0 ] && [ -f "$TX_DIR/originals" ]; then
    while IFS="$(printf '\t')" read -r state relative; do
      case "$state" in
        E) mkdir -p "$TX_REPO/$(dirname -- "$relative")"; cp -p "$TX_DIR/backup/$relative" "$TX_REPO/$relative" ;;
        M) rm -f "$TX_REPO/$relative" ;;
      esac
    done <"$TX_DIR/originals"
  fi
  rm -rf "$TX_DIR"
  TX_DIR=
}

tx_commit() { TX_COMMITTED=1; rm -rf "$TX_DIR"; TX_DIR=; trap - EXIT HUP INT TERM; }
```

- [ ] **Step 4: Implement registration and local-registry replacement**

Add these version and persistence helpers:

```sh
release_for_version() {
  version=$1
  printf '%s\n' "$version" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' || die GOVERNANCE_NOT_READY "Invalid version: $version"
  RELEASE_DIR=$DATA_ROOT/releases/$version
  [ -d "$RELEASE_DIR/.git" ] || die GOVERNANCE_NOT_READY "Release is not installed: $version"
  [ "$(sed -n '1p' "$RELEASE_DIR/VERSION")" = "$version" ] || die VERSION_MISMATCH 'Installed VERSION does not match requested version'
  RELEASE_COMMIT=$(git -C "$RELEASE_DIR" rev-parse "$version^{commit}" 2>/dev/null) || die VERSION_MISMATCH "Installed tag is missing: $version"
  [ "$(git -C "$RELEASE_DIR" rev-parse HEAD)" = "$RELEASE_COMMIT" ] || die VERSION_MISMATCH 'Installed checkout is not at its tag commit'
  [ -z "$(git -C "$RELEASE_DIR" status --porcelain --untracked-files=all)" ] || die VERSION_MISMATCH 'Installed release contains local modifications'
}

write_lock_file() {
  destination=$1 repository=$2 version=$3 commit=$4
  printf '%s\n' "SOURCE=$SOURCE_SLUG" "REPOSITORY=$repository" "VERSION=$version" "COMMIT=$commit" >"$destination"
}

replace_registry_row() {
  repo=$1 repository=$2 version=$3
  mkdir -p "$CONFIG_ROOT"
  temp_registry=$(mktemp "$CONFIG_ROOT/.registered-repos.XXXXXX")
  if [ -f "$REGISTRY" ]; then awk -F '\t' -v repo="$repo" '$1 != repo' "$REGISTRY" >"$temp_registry"; fi
  printf '%s\t%s\t%s\n' "$repo" "$repository" "$version" >>"$temp_registry"
  mv "$temp_registry" "$REGISTRY"
}
```

`cmd_register` must:

1. accept only `REPO --version VERSION` with optional final `--dry-run`;
2. resolve and validate `origin` before any write;
3. call `release_for_version` and validate all three source templates;
4. return `PASS` without writing when lock and entrypoints already match;
5. return `WORKTREE_CONFLICT` when a target differs and is dirty;
6. stage the lock, append the AGENTS managed block, append the CLAUDE block only when `@AGENTS.md` is absent, and write the dedicated Cursor rule;
7. print the exact four target paths and version during dry-run;
8. apply all staged files in one transaction; and
9. update the local registry only after the file transaction succeeds.

Extend `usage` and `main` with:

```sh
    register) cmd_register "${2:-}" "${3:-}" "${4:-}" "${5:-}" ;;
```

- [ ] **Step 5: Run registration checks**

```bash
sh -n bin/beroka-governance
sh -n tests/smoke.sh
sh tests/smoke.sh
```

Expected: output includes both `PASS: read-only package validation` and `PASS: repository registration`.

- [ ] **Step 6: Commit registration**

```bash
git add bin/beroka-governance tests/smoke.sh templates/agent-entrypoints
git commit -m "feat(package): register thin agent entrypoints"
```

---

### Task 3: Release installation, update, and rollback

**Files:**
- Modify: `bin/beroka-governance`
- Modify: `tests/smoke.sh`

**Interfaces:**
- Consumes: annotated SemVer tag from the central source, existing Git/GitHub authentication, and current valid registration for update or rollback.
- Produces: `install VERSION`, `update REPO --to VERSION [--dry-run]`, `rollback REPO --to VERSION [--dry-run]`, side-by-side detached release checkouts, atomically replaced user CLI, and updated lock/registry state.

- [ ] **Step 1: Extend the tagged fixture and write failing lifecycle tests**

Add a second tagged release to `make_release_fixture` after `v1.0.0`:

```sh
printf 'v1.1.0\n' >"$source_repo/VERSION"
printf 'PINNED ENTRYPOINT v1.1.0\n' >"$source_repo/runtime/entrypoint.md"
printf 'GOVERNANCE v1.1.0\n' >"$source_repo/governance.md"
mkdir -p "$source_repo/bin"
cp "$CLI" "$source_repo/bin/beroka-governance"
chmod 755 "$source_repo/bin/beroka-governance"
git -C "$source_repo" add .
git -C "$source_repo" commit -qm 'test: create v1.1 fixture'
git -C "$source_repo" tag -a v1.1.0 -m 'v1.1.0'
git config --global url."file://$source_repo".insteadOf \
  https://github.com/beroka-vn/beroka-ai-governance.git
```

Add lifecycle assertions:

```sh
git -C "$register_repo" add .
git -C "$register_repo" commit -qm 'test: commit v1.0 registration'

$CLI install v1.1.0
[ -d "$XDG_DATA_HOME/beroka-ai-governance/releases/v1.1.0/.git" ] || fail 'install did not create v1.1.0'
[ -x "$BEROKA_GOV_BIN_DIR/beroka-governance" ] || fail 'install did not update the user CLI'

$CLI update "$register_repo" --to v1.1.0
assert_contains "$(cat "$register_repo/.beroka-governance.lock")" 'VERSION=v1.1.0'
assert_contains "$($CLI context "$register_repo")" 'PINNED ENTRYPOINT v1.1.0'
git -C "$register_repo" add .
git -C "$register_repo" commit -qm 'test: commit v1.1 update'

$CLI rollback "$register_repo" --to v1.0.0
assert_contains "$(cat "$register_repo/.beroka-governance.lock")" 'VERSION=v1.0.0'
assert_contains "$($CLI context "$register_repo")" 'PINNED ENTRYPOINT v1.0.0'
git -C "$register_repo" add .
git -C "$register_repo" commit -qm 'test: commit v1.0 rollback'

before_dry_update=$(git -C "$register_repo" hash-object .beroka-governance.lock)
$CLI update "$register_repo" --to v1.1.0 --dry-run >/dev/null
after_dry_update=$(git -C "$register_repo" hash-object .beroka-governance.lock)
[ "$before_dry_update" = "$after_dry_update" ] || fail 'update dry-run changed the lock'

printf 'PASS: release lifecycle\n'
```

Expected before implementation: usage error because lifecycle commands are unknown.

- [ ] **Step 2: Implement immutable release installation**

Add:

```sh
cmd_install() {
  version=$1
  printf '%s\n' "$version" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' || die GOVERNANCE_NOT_READY "Invalid version: $version"
  mkdir -p "$DATA_ROOT/releases" "$BIN_DIR"
  target=$DATA_ROOT/releases/$version
  if [ -e "$target" ]; then
    release_for_version "$version"
  else
    stage=$(mktemp -d "$DATA_ROOT/releases/.install.XXXXXX")
    if ! git clone -q --depth 1 --single-branch --branch "$version" "$REMOTE_URL" "$stage/checkout"; then
      rm -rf "$stage"
      die GOVERNANCE_ACCESS_DENIED "Cannot clone $SOURCE_SLUG at $version"
    fi
    [ "$(sed -n '1p' "$stage/checkout/VERSION")" = "$version" ] || { rm -rf "$stage"; die VERSION_MISMATCH 'Cloned VERSION differs from requested tag'; }
    tag_commit=$(git -C "$stage/checkout" rev-parse "$version^{commit}")
    [ "$(git -C "$stage/checkout" rev-parse HEAD)" = "$tag_commit" ] || { rm -rf "$stage"; die VERSION_MISMATCH 'Cloned checkout differs from tag commit'; }
    mv "$stage/checkout" "$target"
    rmdir "$stage"
  fi
  [ -f "$target/bin/beroka-governance" ] || die GOVERNANCE_NOT_READY 'Release does not contain the CLI'
  temp_cli=$(mktemp "$BIN_DIR/.beroka-governance.XXXXXX")
  cp "$target/bin/beroka-governance" "$temp_cli"
  chmod 755 "$temp_cli"
  mv "$temp_cli" "$BIN_DIR/beroka-governance"
  printf '%s\n' "Installed: $version" 'Result: PASS'
}
```

The production clone URL is fixed. Isolated tests rewrite that exact URL through
temporary Git configuration without changing the stored canonical `origin`.

- [ ] **Step 3: Implement one validated repin path for update and rollback**

Add `cmd_repin MODE REPO --to VERSION [--dry-run]` with these rules:

1. validate current registration and current managed blocks;
2. reject a target with a different SemVer major in V1;
3. print `INSTALL VERSION` during dry-run when the target is absent;
4. call `cmd_install VERSION` during a real update when needed;
5. validate target templates;
6. replace only managed blocks and the dedicated Cursor rule;
7. write the target tag commit into the lock;
8. apply lock and entrypoints through the Task 2 transaction; and
9. replace the local registry row after commit.

Route both commands through the same function:

```sh
    update) cmd_repin update "${2:-}" "${3:-}" "${4:-}" "${5:-}" ;;
    rollback) cmd_repin rollback "${2:-}" "${3:-}" "${4:-}" "${5:-}" ;;
```

Do not add version-ordering dependencies. Explicit target, same-major compatibility, tag existence, and commit identity are the V1 checks.

- [ ] **Step 4: Run lifecycle checks**

```bash
sh -n bin/beroka-governance
sh -n tests/smoke.sh
sh tests/smoke.sh
```

Expected: output ends with `PASS: release lifecycle`.

- [ ] **Step 5: Commit lifecycle support**

```bash
git add bin/beroka-governance tests/smoke.sh
git commit -m "feat(package): install and repin governance releases"
```

---

### Task 4: Safe unregister, uninstall, and drift failures

**Files:**
- Modify: `bin/beroka-governance`
- Modify: `tests/smoke.sh`

**Interfaces:**
- Consumes: a valid registration or explicit `uninstall --force`.
- Produces: `unregister REPO [--dry-run]`, `uninstall [--force]`, marker-only removal, empty package-created file cleanup, registry removal, and stable drift failures.

- [ ] **Step 1: Write failing removal and drift tests**

Add:

```sh
$CLI update "$register_repo" --to v1.1.0
git -C "$register_repo" add .
git -C "$register_repo" commit -qm 'test: commit v1.1 registration'
printf '\nmanual mutation\n' >>"$register_repo/AGENTS.md"
if $CLI doctor "$register_repo" >/dev/null 2>&1; then fail 'doctor accepted entrypoint drift'; fi
git -C "$register_repo" checkout -- AGENTS.md

if $CLI uninstall >/dev/null 2>&1; then fail 'uninstall accepted a registered repository'; fi

unregister_dry_hash=$(git -C "$register_repo" hash-object AGENTS.md CLAUDE.md .beroka-governance.lock)
$CLI unregister "$register_repo" --dry-run >/dev/null
[ "$unregister_dry_hash" = "$(git -C "$register_repo" hash-object AGENTS.md CLAUDE.md .beroka-governance.lock)" ] || fail 'unregister dry-run modified files'

$CLI unregister "$register_repo"
[ ! -e "$register_repo/.beroka-governance.lock" ] || fail 'unregister kept the lock'
[ ! -e "$register_repo/.cursor/rules/beroka-governance.mdc" ] || fail 'unregister kept Cursor rule'
assert_contains "$(cat "$register_repo/AGENTS.md")" 'Keep this line.'
assert_contains "$(cat "$register_repo/CLAUDE.md")" 'Keep this Claude line.'

$CLI uninstall
[ ! -e "$BEROKA_GOV_BIN_DIR/beroka-governance" ] || fail 'uninstall kept user CLI'
[ ! -e "$XDG_DATA_HOME/beroka-ai-governance" ] || fail 'uninstall kept release data'

$CLI install v1.1.0
force_repo=$TMP_ROOT/force-consumer
new_repo "$force_repo"
git -C "$force_repo" remote add origin https://github.com/beroka-vn/force-backend.git
$CLI register "$force_repo" --version v1.1.0
$CLI uninstall --force
[ -e "$force_repo/.beroka-governance.lock" ] || fail 'force uninstall edited application repository'
if $CLI doctor "$force_repo" >/dev/null 2>&1; then fail 'force-uninstalled repository did not fail closed'; fi

printf 'PASS: safe removal and drift detection\n'
```

Expected before implementation: Doctor does not inspect managed templates and removal commands are unknown.

- [ ] **Step 2: Make Doctor validate all managed entrypoints**

Add `verify_entrypoints REPO RELEASE_DIR` and call it from `verify_registration`. It must require one exact AGENTS managed block, accept a pre-existing unmanaged `@AGENTS.md` or require the exact managed CLAUDE block, and require the exact dedicated Cursor file. Missing, duplicate, malformed, or modified package content returns `ENTRYPOINT_DRIFT`. Compare only package-owned content.

- [ ] **Step 3: Implement unregister through the existing transaction**

For each package-managed file, strip markers and preserve non-whitespace unmanaged content:

```sh
strip_managed_block "$REPO/AGENTS.md" "$TX_DIR/agents.unmanaged"
if grep -q '[^[:space:]]' "$TX_DIR/agents.unmanaged"; then
  tx_stage_write AGENTS.md "$TX_DIR/agents.unmanaged"
else
  tx_stage_delete AGENTS.md
fi
```

Apply the same rule to a package-managed CLAUDE block. Never remove an unmanaged pre-existing `@AGENTS.md`. Stage deletion of the lock and Cursor rule, apply once, remove the exact local registry row atomically, and print `Result: PASS`.

- [ ] **Step 4: Implement bounded user-level uninstall**

Add:

```sh
safe_user_path() {
  candidate=$1
  [ -n "$candidate" ] || return 1
  [ "$candidate" != / ] || return 1
  [ "$candidate" != "$HOME" ] || return 1
  case "$candidate" in
    "$HOME"/*|"${TMPDIR:-/tmp}"/*) return 0 ;;
    *) return 1 ;;
  esac
}
```

`cmd_uninstall` accepts only optional `--force`, refuses a non-empty registry without force, validates `DATA_ROOT`, `CONFIG_ROOT`, and the CLI path, and removes only those exact package-owned targets. Force uninstall never scans or edits application repositories.

- [ ] **Step 5: Run the complete automated gate**

```bash
sh -n bin/beroka-governance
sh -n tests/smoke.sh
sh tests/smoke.sh
git diff --check
```

Expected: all commands exit `0`; smoke output ends with `PASS: safe removal and drift detection`.

- [ ] **Step 6: Commit safe removal**

```bash
git add bin/beroka-governance tests/smoke.sh
git commit -m "feat(package): remove governance state safely"
```

---

### Task 5: Developer documentation and V1 release readiness

**Files:**
- Modify: `README.md`
- Modify: `handbook.md`
- Modify: `PACKAGE-DESIGN.md`
- Test: `tests/smoke.sh`

**Interfaces:**
- Consumes: completed CLI, approved design, provider setup guide, and an exact Backend pilot repository supplied by the coordinator after implementation PR merge.
- Produces: copy-paste bootstrap, command guide, release checklist, automated evidence, and an explicit stop before publishing `v1.0.0` without the three-client pilot.

- [ ] **Step 1: Replace README copy-based rollout with package bootstrap**

Add this Vietnamese quick start while keeping source-of-truth and traceability sections:

```bash
release=v1.0.0
bootstrap_dir=$(mktemp -d "${TMPDIR:-/tmp}/beroka-governance-bootstrap.XXXXXX")
git clone --depth 1 --single-branch --branch "$release" \
  https://github.com/beroka-vn/beroka-ai-governance.git \
  "$bootstrap_dir/repo"
sh "$bootstrap_dir/repo/bin/beroka-governance" install "$release"
beroka-governance register /srv/beroka/backend --version "$release"
beroka-governance doctor /srv/beroka/backend
```

State that bootstrap checkout is temporary, the application-repository diff needs review, and a fresh agent session is required after merge.

- [ ] **Step 2: Rewrite handbook activation and deployment sections**

Replace copy instructions with prerequisites and exact bootstrap, register, doctor, update, rollback, unregister, and uninstall commands. Explain the lock and thin entrypoints. Add all seven failure results to troubleshooting. Keep connector preflight after package Doctor. Keep the handbook Vietnamese and agent runtime/templates English. Keep the pilot Backend-only.

- [ ] **Step 3: Mark the design approved**

Change the status to:

```text
Status: Approved — V1 implementation in review
```

Do not claim `v1.0.0` is released before the tag is pushed.

- [ ] **Step 4: Run automated verification**

```bash
sh -n bin/beroka-governance
sh -n tests/smoke.sh
sh tests/smoke.sh
git diff --check
git status --short
```

Expected: syntax and smoke checks exit `0`; `git diff --check` emits nothing; status lists only intended documentation changes before commit.

- [ ] **Step 5: Commit documentation**

```bash
git add README.md handbook.md PACKAGE-DESIGN.md
git commit -m "docs(package): document pinned governance rollout"
```

- [ ] **Step 6: Open the implementation pull request**

Push the implementation branch and open a Draft PR linking `PACKAGE-DESIGN.md`. Include exact automated output, Linux result, macOS and WSL results or named `UNVERIFIED` owners, confirmation that no application repository was registered, and confirmation that `v1.0.0` remains unpublished.

- [ ] **Step 7: Stop at the release authorization gate after merge**

After implementation PR merge, the coordinator must provide one exact Backend pilot repository. Create an annotated local tag on merged `main`, install it locally, register the pilot through its own reviewed PR, and record fresh-session evidence:

```bash
git switch main
git pull --ff-only origin main
git tag -a v1.0.0 -m 'Beroka AI governance package v1.0.0'
sh -n bin/beroka-governance
sh tests/smoke.sh
```

Required manual evidence:

- Codex loads repository `AGENTS.md` and reports pinned `v1.0.0`.
- Claude Code `/memory` shows the project import and reports pinned `v1.0.0`.
- Cursor applies `.cursor/rules/beroka-governance.mdc` and reports pinned `v1.0.0`.
- `beroka-governance doctor` returns `Result: PASS` in the pilot repository.

Do not run `git push origin v1.0.0` until all checks pass and the coordinator explicitly authorizes tag publication. If a client fails, delete only the unpushed local tag, fix through another reviewed implementation PR, and repeat the gate on the new merged commit.
