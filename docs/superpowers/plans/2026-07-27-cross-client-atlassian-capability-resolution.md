# Cross-client Atlassian Capability Resolution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve reviewed Jira Issue and ordinary Confluence Page capabilities consistently for Codex, Claude Code, and Cursor without matching every client patch version.

**Architecture:** Keep schema-1 compatibility behavior for old pinned releases and publish provider-owned capability records in schema 2 for new releases. Resolve provider evidence first, then use authoritative client inventory to reject missing tools when available; Claude may use the provider record when its healthy connector cannot expose inventory.

**Tech Stack:** POSIX `sh`, `awk`, `sed`, `grep`, Git fixtures, Atlassian Rovo MCP, Codex app-server, Claude Code MCP CLI, Cursor Agent `mcp list-tools`.

## Global Constraints

- Do not create or change `VERSION`, a Git tag, or a GitHub Release.
- Do not request, print, log, or store OAuth credentials or developer API tokens.
- Keep OAuth credentials owned by the selected client or OS keyring.
- Keep `SUPPORTED`, `UNSUPPORTED`, and `UNKNOWN` operation-scoped.
- Preserve schema-1 behavior for repositories pinned to existing releases.
- Schema-2 provider records are independent of Codex, Claude Code, and Cursor patch versions.
- Jira Issue and ordinary Confluence Page writes require post-write read-back.
- Jira Board/sprint and Confluence Folder-parent capabilities remain `UNKNOWN`.
- Tests use temporary `HOME`, `XDG_CONFIG_HOME`, and `XDG_DATA_HOME` and no real credentials.
- Do not stage repository-controller `.beroka-governance.lock` or `AGENTS.md`.

---

## File map

| File | Responsibility |
| --- | --- |
| `runtime/compatibility/atlassian.tsv` | Reviewed provider-owned schema-2 capability records |
| `bin/beroka-governance` | Backward-compatible schema validation, inventory normalization, resolution, and output |
| `tests/routing.sh` | Cross-client semantic capability and malformed-evidence regression coverage |
| `tests/connectors.sh` | Selected-client health and Cursor inventory-command behavior |
| `tests/smoke.sh` | Old/new installed-release schema compatibility |
| `runtime/rules/general.md` | Agent-facing create/read-back and no-duplicate requirement |
| `governance.md` | Human-readable operation safety and administration boundary |
| `handbook.md` | Operator outcomes and remediation |
| `PACKAGE-DESIGN.md` | Package contract for provider evidence and adapters |

---

### Task 1: Preserve schema 1 and admit schema 2 releases

**Files:**
- Modify: `bin/beroka-governance:620-655`
- Modify: `runtime/compatibility/atlassian.tsv`
- Modify: `tests/smoke.sh`
- Modify: `tests/routing.sh`

**Interfaces:**
- Consumes: first line of `runtime/compatibility/atlassian.tsv`.
- Produces: `atlassian_compatibility_schema FILE`, which prints `1` or `2` and fails for every other value.

- [ ] **Step 1: Add failing old/new release validation tests**

In `tests/smoke.sh`, keep a schema-1 routed release fixture and make the new
routed fixture use schema 2:

```sh
printf '%s\n' \
  '# schema=1' \
  '# client	version	endpoint	toolset	tested_on	capability	state' \
  >"$source_repo/runtime/compatibility/atlassian.tsv"
git -C "$source_repo" add runtime/compatibility/atlassian.tsv
git -C "$source_repo" commit -qm 'test: preserve schema-1 release'
git -C "$source_repo" tag -a v1.1.0 -m 'v1.1.0'

printf '%s\n' \
  '# schema=2' \
  '# endpoint	required_tools	tested_on	capability	evidence	state' \
  >"$source_repo/runtime/compatibility/atlassian.tsv"
git -C "$source_repo" add runtime/compatibility/atlassian.tsv
git -C "$source_repo" commit -qm 'test: add schema-2 release'
git -C "$source_repo" tag -a v1.1.1 -m 'v1.1.1'
```

Assert `doctor` accepts both tagged fixtures and rejects a fixture whose first
line is `# schema=3` with `VERSION_MISMATCH`.

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
sh tests/smoke.sh
```

Expected: the schema-2 fixture fails with
`Unsupported Atlassian compatibility schema`.

- [ ] **Step 3: Implement the schema reader and release validation**

Add before `validate_release_checkout`:

```sh
atlassian_compatibility_schema() {
  acs_file=$1
  case "$(sed -n '1p' "$acs_file" 2>/dev/null)" in
    '# schema=1') printf '%s\n' 1 ;;
    '# schema=2') printf '%s\n' 2 ;;
    *) return 1 ;;
  esac
}
```

Replace the exact schema-1 comparison inside `validate_release_checkout` with:

```sh
atlassian_compatibility_schema \
  "$vrc_checkout/runtime/compatibility/atlassian.tsv" >/dev/null ||
  die VERSION_MISMATCH 'Unsupported Atlassian compatibility schema'
```

Change the production file to:

```text
# schema=2
# endpoint	required_tools	tested_on	capability	evidence	state
https://mcp.atlassian.com/v1/mcp/authv2	createJiraIssue,getJiraIssue,getJiraIssueTypeMetaWithFields,getJiraProjectIssueTypesMetadata	2026-07-27	jira-issue-write	official-contract	SUPPORTED
https://mcp.atlassian.com/v1/mcp/authv2	createConfluencePage,getConfluencePage	2026-07-27	confluence-page-parent-write	official-contract	SUPPORTED
```

- [ ] **Step 4: Run focused validation**

Run:

```bash
sh tests/smoke.sh
sh tests/release.sh
```

Expected: both suites PASS; schema 1 and schema 2 are accepted, schema 3 is
rejected.

- [ ] **Step 5: Commit**

```bash
git add bin/beroka-governance runtime/compatibility/atlassian.tsv \
  tests/smoke.sh tests/routing.sh
git commit -m "feat(capabilities): add provider evidence schema"
```

---

### Task 2: Resolve provider evidence for Codex and Claude

**Files:**
- Modify: `bin/beroka-governance:2125-2345`
- Modify: `tests/routing.sh`

**Interfaces:**
- Consumes: `atlassian_compatibility_schema FILE` from Task 1.
- Produces: `load_provider_capability CAPABILITY`, setting
  `CAPABILITY_REQUIRED_TOOLS`, `CAPABILITY_EVIDENCE`, and
  `CAPABILITY_PROVIDER_STATE`.
- Produces: `resolve_capability CLIENT CAPABILITY`, setting
  `CAPABILITY_STATE`, `CAPABILITY_EVIDENCE_SOURCE`, and
  `CAPABILITY_INVENTORY_STATE`.

- [ ] **Step 1: Extend fake inventories and add failing provider tests**

Change the Codex `healthy-all` fixture in `tests/routing.sh` to include the
metadata tools:

```json
{"id":1,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"createConfluencePage":{},"getConfluencePage":{}},"authStatus":"oAuth"}]}}
```

Make fake versions variable:

```sh
'--version')
  printf 'codex %s\n' "${FAKE_CODEX_VERSION:-1.0.0}"
  ;;
```

Add assertions after pinning a schema-2 release:

```sh
output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive)
assert_contains "$output" 'Capability state: SUPPORTED'

FAKE_CODEX_VERSION=99.77.55
export FAKE_CODEX_VERSION
output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive)
assert_contains "$output" 'Capability state: SUPPORTED'
unset FAKE_CODEX_VERSION

printf '%s\n' healthy >"$XDG_CONFIG_HOME/fake-claude-health"
output=$($CLI preflight "$consumer" \
  --client claude --operation jira-write --non-interactive)
assert_contains "$output" 'Capability state: SUPPORTED'
```

Retain a schema-1 tagged fixture with an exact `codex 1.0.0` row and assert that
changing its fake version to `99.77.55` still returns `UNKNOWN`.

Add schema-2 fixtures with a duplicate row, malformed required toolset,
unrecognized evidence, and invalid date; each must return
`CONNECTOR_CAPABILITY_REQUIRED` with state `UNKNOWN`.

- [ ] **Step 2: Run the routing suite and verify RED**

Run:

```bash
sh tests/routing.sh
```

Expected: schema-2 Jira preflight is `UNKNOWN`; Claude and changed Codex version
do not pass.

- [ ] **Step 3: Add strict provider-record parsing**

Add:

```sh
load_provider_capability() {
  lpc_capability=$1
  lpc_file=$RELEASE_DIR/runtime/compatibility/atlassian.tsv
  CAPABILITY_REQUIRED_TOOLS=
  CAPABILITY_EVIDENCE=
  CAPABILITY_PROVIDER_STATE=UNKNOWN
  lpc_row=$(awk -F '\t' \
    -v endpoint="$ATLASSIAN_MCP_URL" \
    -v capability="$lpc_capability" '
      /^[[:space:]]*$/ || /^#/ { next }
      {
        allowed["createConfluencePage"]=1
        allowed["createJiraIssue"]=1
        allowed["getConfluencePage"]=1
        allowed["getJiraIssue"]=1
        allowed["getJiraIssueTypeMetaWithFields"]=1
        allowed["getJiraProjectIssueTypesMetadata"]=1
        tool_count=split($2, tools, ",")
        for (i=1; i<=tool_count; i++)
          if (!allowed[tools[i]]) invalid=1
        if (NF != 6 ||
            $1 == "" ||
            $2 !~ /^[A-Za-z][A-Za-z0-9_]*(,[A-Za-z][A-Za-z0-9_]*)*$/ ||
            $3 !~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/ ||
            $4 !~ /^(jira-issue-write|confluence-page-parent-write|jira-board-verification|confluence-folder-parent-write)$/ ||
            $5 !~ /^(official-contract|isolated-pilot)$/ ||
            $6 !~ /^(SUPPORTED|UNSUPPORTED)$/) invalid=1
        if ($1 == endpoint && $4 == capability) {
          matches++
          row=$2 "\t" $5 "\t" $6
        }
      }
      END {
        if (invalid || matches != 1) exit 1
        print row
      }
    ' "$lpc_file") || return 1
  lpc_old_ifs=$IFS
  IFS="$(printf '\t')"
  set -- $lpc_row
  IFS=$lpc_old_ifs
  [ "$#" -eq 3 ] || return 1
  CAPABILITY_REQUIRED_TOOLS=$1
  CAPABILITY_EVIDENCE=$2
  CAPABILITY_PROVIDER_STATE=$3
}
```

Before assigning the row, validate that `required_tools` equals its canonical
sorted unique form:

```sh
lpc_canonical=$(printf '%s\n' "$1" | tr ',' '\n' |
  LC_ALL=C sort -u | paste -sd, -)
[ "$lpc_canonical" = "$1" ] || return 1
```

Do not add a new dependency; `sort`, `paste`, and `tr` are existing POSIX
command-line prerequisites already available in supported Linux/macOS/WSL
environments.

- [ ] **Step 4: Preserve the schema-1 resolver**

Rename the current `compatibility_capability` to
`legacy_compatibility_capability` without changing its exact client/version
matching.

Route by release schema:

```sh
rcap_schema=$(atlassian_compatibility_schema \
  "$RELEASE_DIR/runtime/compatibility/atlassian.tsv") || {
  CAPABILITY_STATE=UNKNOWN
  return 0
}
case "$rcap_schema" in
  1) resolve_legacy_capability "$rcap_client" "$rcap_capability" ;;
  2) resolve_provider_capability "$rcap_client" "$rcap_capability" ;;
esac
```

`resolve_legacy_capability` contains the current `connector_inventory`,
`runtime_capability`, and exact compatibility-row flow unchanged.
Initialize `CAPABILITY_INVENTORY_STATE` from the legacy inventory result and
classify successful legacy-row evidence as `LEGACY_COMPATIBILITY`; classify a
complete inventory that proves a missing tool as `RUNTIME_INVENTORY`. These
classified values affect output only and do not change the legacy state.

- [ ] **Step 5: Implement schema-2 resolution**

Add a comma-list helper:

```sh
inventory_has_required_tools() {
  ihrr_old_ifs=$IFS
  IFS=,
  set -- $CAPABILITY_REQUIRED_TOOLS
  IFS=$ihrr_old_ifs
  for ihrr_tool in "$@"; do
    inventory_has_tool "$ihrr_tool" || return 1
  done
}
```

Add:

```sh
resolve_provider_capability() {
  rpc_client=$1 rpc_capability=$2
  CAPABILITY_STATE=UNKNOWN
  CAPABILITY_EVIDENCE_SOURCE=NONE
  CAPABILITY_INVENTORY_STATE=UNAVAILABLE
  load_provider_capability "$rpc_capability" || return 0
  [ "$CAPABILITY_PROVIDER_STATE" = SUPPORTED ] || {
    CAPABILITY_STATE=UNSUPPORTED
    CAPABILITY_EVIDENCE_SOURCE=PROVIDER_CONTRACT
    return 0
  }
  connector_inventory "$rpc_client" || return 0
  if [ "$CAPABILITY_INVENTORY_COMPLETE" -eq 1 ]; then
    CAPABILITY_INVENTORY_STATE=COMPLETE
    inventory_has_required_tools || {
      CAPABILITY_STATE=UNSUPPORTED
      CAPABILITY_EVIDENCE_SOURCE=RUNTIME_INVENTORY
      return 0
    }
  fi
  CAPABILITY_STATE=SUPPORTED
  CAPABILITY_EVIDENCE_SOURCE=PROVIDER_CONTRACT
}
```

Extend the canonical inventory list with:

```text
getJiraIssueTypeMetaWithFields
getJiraProjectIssueTypesMetadata
```

Do not print `CAPABILITY_REQUIRED_TOOLS` or `CAPABILITY_INVENTORY`.

- [ ] **Step 6: Run focused tests**

Run:

```bash
sh tests/routing.sh
sh tests/connectors.sh
```

Expected: provider-record Codex and Claude tests PASS; schema-1 version matching
remains exact; malformed records fail closed.

- [ ] **Step 7: Commit**

```bash
git add bin/beroka-governance tests/routing.sh
git commit -m "feat(capabilities): resolve Atlassian provider contracts"
```

---

### Task 3: Normalize Cursor inventory without free-text false positives

**Files:**
- Modify: `bin/beroka-governance:1560-2185`
- Modify: `tests/connectors.sh`
- Modify: `tests/routing.sh`

**Interfaces:**
- Consumes: output of `cursor-agent mcp list-tools atlassian`.
- Produces: `cursor_tool_names`, one exact normalized tool identifier per line.
- Supplies schema-2 `resolve_provider_capability` from Task 2.

- [ ] **Step 1: Add failing Cursor inventory fixtures**

Make the fake Cursor client emit an inventory containing all Jira tools:

```sh
'mcp list-tools atlassian')
  case "$(sed -n '1p' "$XDG_CONFIG_HOME/fake-cursor-health" 2>/dev/null || :)" in
    healthy)
      printf '%s\n' \
        'createJiraIssue(projectKey, issueType, summary)' \
        'getJiraIssue(issueKey)' \
        'getJiraIssueTypeMetaWithFields(projectKey, issueType)' \
        'getJiraProjectIssueTypesMetadata(projectKey)'
      ;;
    similar)
      printf '%s\n' \
        'createJiraIssuePreview(projectKey)' \
        'description: call getJiraIssue after creation'
      ;;
    missing)
      printf '%s\n' 'getJiraIssue(issueKey)'
      ;;
    *) exit 1 ;;
  esac
  ;;
```

Add preflight assertions:

```sh
printf '%s\n' healthy >"$XDG_CONFIG_HOME/fake-cursor-health"
output=$($CLI preflight "$consumer" \
  --client cursor --operation jira-write --non-interactive)
assert_contains "$output" 'Capability state: SUPPORTED'

for cursor_health in similar missing; do
  printf '%s\n' "$cursor_health" >"$XDG_CONFIG_HOME/fake-cursor-health"
  if output=$($CLI preflight "$consumer" \
    --client cursor --operation jira-write --non-interactive 2>&1); then
    fail "Cursor $cursor_health inventory passed"
  fi
  assert_contains "$output" 'Capability state: UNSUPPORTED'
done
```

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```bash
sh tests/connectors.sh
sh tests/routing.sh
```

Expected: the complete Cursor fixture does not pass or the similar-name fixture
is incorrectly accepted by the current free-text parser.

- [ ] **Step 3: Implement exact first-token normalization**

Add:

```sh
cursor_tool_names() {
  awk '
    {
      line=$0
      sub(/^[[:space:]]*[-*]?[[:space:]]*/, "", line)
      if (match(line, /^[A-Za-z][A-Za-z0-9_]*/)) {
        name=substr(line, RSTART, RLENGTH)
        rest=substr(line, RLENGTH + 1, 1)
        if (rest == "" || rest ~ /[[:space:](:]/) print name
      }
    }
  '
}
```

In the Cursor branch of `connector_inventory`, normalize once:

```sh
CAPABILITY_INVENTORY=$(printf '%s\n' "$CONNECTOR_PROBE_TOOLS" |
  cursor_tool_names) || return 1
[ -n "$CAPABILITY_INVENTORY" ] || return 1
CAPABILITY_INVENTORY_FORMAT=json
CAPABILITY_INVENTORY_COMPLETE=1
```

Reusing the existing exact-line `json` inventory matcher prevents tool names
mentioned only in descriptions or argument text from counting.

- [ ] **Step 4: Verify connector and routing behavior**

Run:

```bash
sh tests/connectors.sh
sh tests/routing.sh
```

Expected: complete Cursor inventory PASS; similar/missing inventories are
`UNSUPPORTED`; authentication and failed-inventory tests remain unchanged.

- [ ] **Step 5: Commit**

```bash
git add bin/beroka-governance tests/connectors.sh tests/routing.sh
git commit -m "fix(capabilities): normalize Cursor tool inventory"
```

---

### Task 4: Expose evidence safely and require create/read-back

**Files:**
- Modify: `bin/beroka-governance:2520-2550`
- Modify: `runtime/rules/general.md`
- Modify: `governance.md`
- Modify: `handbook.md`
- Modify: `PACKAGE-DESIGN.md`
- Modify: `tests/routing.sh`
- Modify: `tests/documentation-architecture.sh`

**Interfaces:**
- Consumes: `CAPABILITY_EVIDENCE_SOURCE` and
  `CAPABILITY_INVENTORY_STATE` from Task 2.
- Produces: stable preflight lines `Capability evidence:` and
  `Runtime inventory:`.

- [ ] **Step 1: Add failing safe-output assertions**

For successful Codex, Claude, and Cursor Jira preflights in
`tests/routing.sh`, assert:

```sh
assert_contains "$output" 'Capability evidence: PROVIDER_CONTRACT'
assert_contains "$output" 'Runtime inventory: COMPLETE'
```

For Claude, require:

```sh
assert_contains "$output" 'Runtime inventory: UNAVAILABLE'
```

For every output, reject raw tools:

```sh
assert_not_contains "$output" 'createJiraIssue'
assert_not_contains "$output" 'getJiraIssueTypeMetaWithFields'
```

Add documentation checks for `CREATION_STATUS_UNKNOWN`, mandatory read-back,
and no automatic retry.

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
sh tests/routing.sh
sh tests/documentation-architecture.sh
```

Expected: evidence output and create/read-back documentation assertions fail.

- [ ] **Step 3: Print only classified evidence**

Extend `print_preflight_result`:

```sh
printf '%s\n' \
  "Capability: $PREFLIGHT_CAPABILITY" \
  "Capability state: $CAPABILITY_STATE" \
  "Capability evidence: $CAPABILITY_EVIDENCE_SOURCE" \
  "Runtime inventory: $CAPABILITY_INVENTORY_STATE" \
  'Result: PASS'
```

Extend the capability failure block with the same two classified lines. Never
include the provider required toolset, observed inventory, raw connector
response, client version, or OAuth state.

- [ ] **Step 4: Add operation-safety instructions**

Add to `runtime/rules/general.md` and mirror the human-readable rule in
`governance.md`:

```markdown
- Before Jira creation, resolve exact project create metadata and search for the
  intended existing record. Create once, then read back the returned key and
  validate project, issue type, summary, and required linkage.
- If create status is indeterminate, return `CREATION_STATUS_UNKNOWN`; never
  retry automatically or create a second record.
- Confluence creation uses exact trusted space/root routing and reads back the
  created content and parent. Folder routing remains blocked without isolated
  pilot evidence.
```

In `handbook.md` and `PACKAGE-DESIGN.md`, document provider-owned evidence,
schema-1 compatibility, cross-client adapters, and the administration boundary.

- [ ] **Step 5: Run focused tests**

Run:

```bash
sh tests/routing.sh
sh tests/documentation-architecture.sh
```

Expected: PASS with classified evidence only.

- [ ] **Step 6: Commit**

```bash
git add bin/beroka-governance runtime/rules/general.md governance.md \
  handbook.md PACKAGE-DESIGN.md tests/routing.sh \
  tests/documentation-architecture.sh
git commit -m "docs(capabilities): require safe Atlassian read-back"
```

---

### Task 5: Full verification and candidate handoff

**Files:**
- Modify only if a verification failure proves a defect in a file already
  listed in Tasks 1-4.

**Interfaces:**
- Consumes: all preceding commits.
- Produces: a tested source candidate and review evidence; no release artifact.

- [ ] **Step 1: Run all isolated suites**

Run each separately so a process-level test cannot hide the next suite:

```bash
sh tests/bootstrap.sh
sh tests/connectors.sh
sh tests/documentation-architecture.sh
sh tests/launcher.sh
sh tests/release.sh
sh tests/routing.sh
sh tests/smoke.sh
```

Expected: all seven suites PASS.

- [ ] **Step 2: Run static repository checks**

```bash
dash -n bin/beroka-governance tests/bootstrap.sh tests/connectors.sh \
  tests/launcher.sh tests/release.sh tests/routing.sh tests/smoke.sh
git diff --check origin/main...HEAD
test "$(cat VERSION)" = v1.0.1
git status --short
```

Expected: syntax and diff checks PASS; `VERSION` remains `v1.0.1`; only local
controller `.beroka-governance.lock` and `AGENTS.md` may remain untracked.

- [ ] **Step 3: Run a credential-free candidate pilot**

Create a temporary clone of the source branch and a temporary MDL consumer.
Rewrite only the temporary test HOME's canonical governance URL to that local
source, render a temporary annotated `v9.9.9` candidate tag, and run:

```bash
candidate_cli=$candidate_root/source/bin/beroka-governance
sh "$candidate_cli" doctor "$candidate_repo" --client codex
sh "$candidate_cli" preflight "$candidate_repo" \
  --client codex --operation jira-write --non-interactive
```

Use the same fake Codex, Claude, and Cursor adapters from `tests/routing.sh`.
Expected for all three: `Capability state: SUPPORTED`; no OAuth URL, credential,
raw tool inventory, or real external write occurs.

- [ ] **Step 4: Record unavailable manual pilots honestly**

Because Claude Code and Cursor Agent are not installed on the maintainer host,
record these as:

```text
Claude Code live-client pilot: UNVERIFIED
Cursor Agent live-client pilot: UNVERIFIED
```

Do not convert strict fake coverage into a live-client PASS claim. Codex live
connector health may be observed read-only, but do not use real Jira writes for
candidate qualification.

- [ ] **Step 5: Review the final diff**

```bash
git log --oneline origin/main..HEAD
git diff --stat origin/main...HEAD
git diff --check origin/main...HEAD
git status --short
```

Confirm:

- no release/tag/version change;
- no credential or OAuth material;
- schema-1 behavior remains covered;
- schema-2 state is client-patch-independent;
- Board and Folder gates remain blocked; and
- repository-controller files are not staged.

- [ ] **Step 6: Push and open a review PR**

Immediately before each external GitHub write:

```bash
beroka-governance preflight "$PWD" \
  --client codex --operation github-write
```

Then push the branch and create a PR whose body lists the seven test suites,
credential-free pilot, and unavailable live-client pilots. Do not merge and do
not publish a release.
