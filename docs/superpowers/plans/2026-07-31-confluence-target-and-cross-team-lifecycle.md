# Confluence Target and Cross-Team Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Confluence writes fail closed against an exact reviewed target and publish one symmetric FE/BE Jira ownership, link, and status contract to every supported agent.

**Architecture:** Keep the enforcement in the existing POSIX shell CLI: one reviewed TSV inventory is validated at release load, and both direct preflight and the Cursor hook call the same target resolver before connector inspection. Keep live Jira assignee/readback and lifecycle behavior instruction-driven for Codex, Claude, and Cursor because the CLI neither stores Atlassian credentials nor proxies MCP traffic.

**Tech Stack:** POSIX `sh`, `awk`, `sed`, `grep`, `jq` for the existing Cursor hook, tab-separated runtime catalogs, shell regression tests.

## Global Constraints

- Add no dependency, daemon, webhook, background listener, credential store, or MCP proxy.
- Every Confluence create, update, move, and handoff validation requires exact repository, action, content ID, Capability ID, scope, domain, transport, parent ID, and Registry content ID.
- Known drift and legacy generic folders are deny-only; missing or ambiguous routing asks the user and waits.
- Initial production inventory contains no `ACTIVE` target and must not invent a Capability ID, Registry row, canonical parent, or API page.
- Jira `Task`, `Bug`, and `Feature` cross-team intake stays symmetric; opposite-project Epic creation requires receiving-team confirmation.
- Jira update authority compares authenticated and current-assignee Atlassian `accountId`; mismatch or unassigned returns `ASSIGNEE_CONFIRMATION_REQUIRED`.
- Cross-team Jira descriptions and handoffs must not contain opposite-team private GitHub links; shared documentation uses exact accessible Confluence pages.
- Provider Jira moves to `In Progress` when work starts, `In Review` when a human marks the PR ready, and `Done` only after delivery and documentation are complete.
- Do not mutate live Jira or Confluence, bump `VERSION`, merge, tag, or publish a release in this implementation.
- Preserve all current routing, connector, bootstrap, release, Cursor-hook, and documentation tests.

---

### Task 1: Reviewed Confluence target inventory

**Files:**
- Create: `runtime/integrations/beroka-be-fe.confluence-targets`
- Modify: `bin/beroka-governance:550-654`
- Modify: `tests/release.sh:102-133`
- Modify: `tests/routing.sh:708-734,1031-1062`

**Interfaces:**
- Consumes: repository catalog root passed to `validate_release_checkout`.
- Produces: `validate_confluence_target_inventory FILE CATALOG_ROOT`, returning zero only for a regular, exact, internally consistent inventory.

- [ ] **Step 1: Add failing release and routing tests for the inventory**

Add production assertions to `tests/release.sh`:

```sh
target_inventory=$ROOT/runtime/integrations/beroka-be-fe.confluence-targets
[ -f "$target_inventory" ] || fail 'missing Confluence target inventory'
[ "$(sed '/^#/d;/^[[:space:]]*$/d' "$target_inventory" | wc -l | tr -d ' ')" = 3 ] ||
  fail 'Confluence target inventory must contain three observed deny-only records'
require_text runtime/integrations/beroka-be-fe.confluence-targets \
  "$(printf 'beroka-vn/Beroka_Backend\tfolder\tLEGACY\t71237633\tMarket — API')"
require_text runtime/integrations/beroka-be-fe.confluence-targets \
  "$(printf 'beroka-vn/Beroka_Backend\tfolder\tLEGACY\t71303169\tMarket — WS')"
require_text runtime/integrations/beroka-be-fe.confluence-targets \
  "$(printf 'beroka-vn/Beroka_Backend\tpage\tDRIFTED\t70713366\tBB-11 — Market Data — Derivative Quote Stream Contract')"
```

Extend `pin_test_release` in `tests/routing.sh` so inventory mutations are committed into fixture tags:

```sh
git -C "$source_repo" add VERSION runtime/compatibility/atlassian.tsv \
  runtime/integrations runtime/repositories
```

Add a helper and two malformed-release cases after `pin_test_release` is defined:

```sh
assert_target_inventory_invalid() {
  ati_version=$1 ati_row=$2
  ati_file=$source_repo/runtime/integrations/beroka-be-fe.confluence-targets
  ati_backup=$TEST_ROOT/confluence-targets.valid
  cp "$ati_file" "$ati_backup"
  printf '%b\n' "$ati_row" >>"$ati_file"
  pin_test_release "$ati_version"
  if output=$($CLI context "$consumer" 2>&1); then
    fail 'invalid Confluence target inventory passed release validation'
  fi
  assert_contains "$output" 'Result: VERSION_MISMATCH'
  assert_contains "$output" 'Invalid Confluence target inventory'
  mv "$ati_backup" "$ati_file"
}

assert_target_inventory_invalid v1.1.9 \
  'beroka-vn/Beroka_Backend\tpage\tDRIFTED\t70713366\tDuplicate\t-\tMarket\tWebSocket\t71303169\t-\t-'
assert_target_inventory_invalid v1.1.10 \
  'beroka-vn/Beroka_Backend\tpage\tACTIVE\t900001\tInvalid active page\tShared\tMarket\tAPI\t900002\tNOT_UPPERCASE\t900003'
assert_target_inventory_invalid v1.1.11 \
  'beroka-vn/Unknown\tpage\tDRIFTED\t900004\tCross-repository row\t-\tMarket\tAPI\t-\t-\t-'

target_file=$source_repo/runtime/integrations/beroka-be-fe.confluence-targets
target_backup=$TEST_ROOT/confluence-targets.regular
cp "$target_file" "$target_backup"
rm "$target_file"
ln -s ../rules/general.md "$target_file"
pin_test_release v1.1.12
if output=$($CLI context "$consumer" 2>&1); then
  fail 'symlinked Confluence target inventory passed release validation'
fi
assert_contains "$output" 'Result: GOVERNANCE_NOT_READY'
assert_contains "$output" 'Release path is a symlink'
rm "$target_file"
mv "$target_backup" "$target_file"
pin_test_release v1.1.13
```

- [ ] **Step 2: Run the focused tests and confirm the expected failure**

Run:

```bash
sh tests/release.sh
sh tests/routing.sh
```

Expected: `tests/release.sh` fails with `missing Confluence target inventory`; after only the file is added, `tests/routing.sh` still fails because invalid fixture releases are accepted.

- [ ] **Step 3: Add the deny-only production inventory**

Create `runtime/integrations/beroka-be-fe.confluence-targets` with exactly these
literal tab-separated rows:

```text
# repository	record-type	state	content-id	title	scope	domain	transport	parent-id	capability-id	registry-content-id
beroka-vn/Beroka_Backend	folder	LEGACY	71237633	Market — API	-	Market	API	-	-	-
beroka-vn/Beroka_Backend	folder	LEGACY	71303169	Market — WS	-	Market	WebSocket	-	-	-
beroka-vn/Beroka_Backend	page	DRIFTED	70713366	BB-11 — Market Data — Derivative Quote Stream Contract	-	Market	WebSocket	71303169	-	-
```

- [ ] **Step 4: Implement the minimum release validator**

Add this call to the `v1.0.6`-and-newer block in `validate_release_checkout`; fixture releases are `v1.1.x`, while the immutable `v1.0.5` release remains readable by its own installed CLI:

```sh
if semver_not_older v1.0.6 "$vrc_version"; then
  assert_release_file "$vrc_checkout" \
    runtime/integrations/beroka-be-fe.confluence-targets
  validate_confluence_target_inventory \
    "$vrc_checkout/runtime/integrations/beroka-be-fe.confluence-targets" \
    "$vrc_checkout/runtime/repositories" ||
    die VERSION_MISMATCH 'Invalid Confluence target inventory'
fi
```

Add `validate_confluence_target_inventory` beside `validate_intake_inventory`. Its single `awk` pass must enforce 11 tab-separated fields, allowed record/state/transport values, numeric IDs, unique repository/content ID, unique non-dash Capability ID, strict `ACTIVE`/`PLANNED` page fields, and deny-only `DRIFTED`/`LEGACY` rows. A second pass must verify every repository has a regular catalog record and every active/planned page parent resolves to one `ACTIVE` folder in the same repository:

```sh
validate_confluence_target_inventory() {
  vcti_file=$1 vcti_catalog=$2
  [ -f "$vcti_file" ] && [ ! -L "$vcti_file" ] &&
    [ -d "$vcti_catalog" ] && [ ! -L "$vcti_catalog" ] || return 1
  awk -F '\t' '
    /^#/ || /^[[:space:]]*$/ { next }
    NF != 11 { invalid=1; next }
    $1 !~ /^beroka-vn\/Beroka_(Backend|Frontend)$/ ||
      $2 !~ /^(page|folder)$/ ||
      $3 !~ /^(ACTIVE|PLANNED|DRIFTED|LEGACY)$/ ||
      $4 !~ /^([1-9][0-9]*|-)$/ || $5 == "" ||
      $7 !~ /^(Market|User|-)$/ ||
      $8 !~ /^(API|WebSocket)$/ ||
      $9 !~ /^([1-9][0-9]*|-)$/ ||
      $10 !~ /^([A-Z][A-Z0-9]*(-[A-Z0-9]+)*|-)$/ ||
      $11 !~ /^([1-9][0-9]*|-)$/ { invalid=1 }
    $3 == "ACTIVE" && $2 == "page" &&
      ($4 == "-" || $6 !~ /^(Shared|Derivatives|Underlying)$/ ||
       $9 == "-" || $10 == "-" || $11 == "-") { invalid=1 }
    $3 == "ACTIVE" && $2 == "folder" &&
      ($4 == "-" || $6 !~ /^(Shared|Derivatives|Underlying)$/ ||
       $9 == "-" || $10 != "-" || $11 != "-") { invalid=1 }
    $3 == "PLANNED" &&
      ($2 != "page" || $4 != "-" ||
       $6 !~ /^(Shared|Derivatives|Underlying)$/ ||
       $9 == "-" || $10 == "-" || $11 == "-") { invalid=1 }
    $3 == "DRIFTED" && ($2 != "page" || $4 == "-") { invalid=1 }
    $3 == "LEGACY" && ($2 != "folder" || $4 == "-") { invalid=1 }
    $4 != "-" && ++content[$1 SUBSEP $4] > 1 { invalid=1 }
    $10 != "-" && ++capability[$1 SUBSEP $10] > 1 { invalid=1 }
    { rows++; state[NR]=$3; type[NR]=$2; repo[NR]=$1; id[NR]=$4; parent[NR]=$9 }
    END {
      for (i in state) if ((state[i] == "ACTIVE" || state[i] == "PLANNED") && type[i] == "page") {
        matches=0
        for (j in state) if (repo[j] == repo[i] && type[j] == "folder" &&
          state[j] == "ACTIVE" && id[j] == parent[i]) matches++
        if (matches != 1) invalid=1
      }
      exit invalid || rows == 0
    }
  ' "$vcti_file" || return 1
  cut -f1 "$vcti_file" | sed '/^#/d;/^[[:space:]]*$/d' | LC_ALL=C sort -u |
  while IFS= read -r vcti_repository; do
    vcti_record=$vcti_catalog/$vcti_repository.conf
    [ -f "$vcti_record" ] && [ ! -L "$vcti_record" ] || exit 1
  done
}
```

- [ ] **Step 5: Run tests and commit**

Run:

```bash
sh tests/release.sh
sh tests/routing.sh
```

Expected: both print their PASS footer.

Commit:

```bash
git add bin/beroka-governance runtime/integrations/beroka-be-fe.confluence-targets tests/release.sh tests/routing.sh
git commit -m "feat: validate reviewed Confluence targets"
```

### Task 2: Target-bound Confluence preflight

**Files:**
- Modify: `bin/beroka-governance:61-74,3075-3299,3438-3657`
- Modify: `runtime/compatibility/atlassian.tsv`
- Modify: `tests/routing.sh:1430-1570,1887-1970`

**Interfaces:**
- Consumes: the validated target inventory and eight Confluence CLI arguments.
- Produces: `resolve_confluence_target`, populated `CONFLUENCE_TARGET_*` fields, `confluence-write`, and read-only `confluence-handoff-verify` preflights.

- [ ] **Step 1: Add failing target-resolution tests before implementation**

Add a helper in `tests/routing.sh`:

```sh
confluence_args() {
  printf '%s\n' \
    --confluence-action update \
    --target-content-id 70713366 \
    --capability-id MARKET-FU-INDEX-API \
    --scope Shared \
    --domain Market \
    --transport API \
    --expected-parent-id 71303169 \
    --registry-content-id 900003
}
```

Add the issue #44 reproduction before the existing connector capability cases:

```sh
set -- $(confluence_args)
: >"$CALLS"
if output=$($CLI preflight "$canonical_backend" --client codex \
  --operation confluence-write --non-interactive "$@" 2>&1)
then
  fail 'REST API update passed against the drifted WebSocket page'
fi
assert_contains "$output" 'Target content ID: 70713366'
assert_contains "$output" 'Intended transport: API'
assert_contains "$output" 'Target transport: WebSocket'
assert_contains "$output" 'Result: MAPPING_CONFLICT'
[ ! -s "$CALLS" ] || fail 'mapping conflict inspected a connector'

set -- $(confluence_args | sed 's/^API$/WebSocket/')
if output=$($CLI preflight "$canonical_backend" --client codex \
  --operation confluence-write --non-interactive "$@" 2>&1)
then
  fail 'drifted page passed with matching transport'
fi
assert_contains "$output" 'Result: ROUTING_REQUIRED'

if output=$($CLI preflight "$canonical_backend" --client codex \
  --operation confluence-write --non-interactive 2>&1)
then
  fail 'root-only Confluence preflight still passed'
fi
assert_contains "$output" 'Result: ROUTING_REQUIRED'

if output=$($CLI preflight "$canonical_backend" --client codex \
  --operation confluence-write --non-interactive \
  --confluence-action create --target-content-id new \
  --capability-id MARKET-FU-INDEX-API --scope Shared --domain Market \
  --transport API --expected-parent-id 71237633 \
  --registry-content-id 900003 2>&1)
then
  fail 'legacy generic API folder passed as a canonical parent'
fi
assert_contains "$output" 'Result: FOLDER_CREATION_REQUIRED'
```

Add an `ACTIVE` fixture release, assert an exact write and handoff pass, then restore the production inventory and pin another fixture release:

```sh
target_file=$source_repo/runtime/integrations/beroka-be-fe.confluence-targets
cp "$target_file" "$target_file.deny-only"
printf '%b\n' \
  '# repository\trecord-type\tstate\tcontent-id\ttitle\tscope\tdomain\ttransport\tparent-id\tcapability-id\tregistry-content-id' \
  'beroka-vn/Beroka_Backend\tfolder\tACTIVE\t900002\tShared — Market — API\tShared\tMarket\tAPI\t65962274\t-\t-' \
  'beroka-vn/Beroka_Backend\tpage\tACTIVE\t900001\tFU_INDEX REST contract\tShared\tMarket\tAPI\t900002\tMARKET-FU-INDEX-API\t900003' \
  'beroka-vn/Beroka_Backend\tfolder\tACTIVE\t900005\tShared — Market — WebSocket\tShared\tMarket\tWebSocket\t65962274\t-\t-' \
  'beroka-vn/Beroka_Backend\tpage\tACTIVE\t900004\tDerivative quote stream\tShared\tMarket\tWebSocket\t900005\tMARKET-DERIVATIVE-QUOTE-WS\t900003' \
  >"$target_file"
pin_test_release v1.1.14

output=$($CLI preflight "$canonical_backend" --client codex \
  --operation confluence-write --non-interactive \
  --confluence-action update --target-content-id 900001 \
  --capability-id MARKET-FU-INDEX-API --scope Shared --domain Market \
  --transport API --expected-parent-id 900002 \
  --registry-content-id 900003)
assert_contains "$output" 'Target transport: API'
assert_contains "$output" 'Result: PASS'

output=$($CLI preflight "$canonical_backend" --client codex \
  --operation confluence-write --non-interactive \
  --confluence-action update --target-content-id 900004 \
  --capability-id MARKET-DERIVATIVE-QUOTE-WS --scope Shared --domain Market \
  --transport WebSocket --expected-parent-id 900005 \
  --registry-content-id 900003)
assert_contains "$output" 'Target transport: WebSocket'
assert_contains "$output" 'Result: PASS'

if output=$($CLI preflight "$canonical_backend" --client codex \
  --operation confluence-handoff-verify --non-interactive \
  --confluence-action update --target-content-id 900001 \
  --capability-id MARKET-WRONG-API --scope Shared --domain Market \
  --transport API --expected-parent-id 900002 \
  --registry-content-id 900003 2>&1)
then
  fail 'handoff accepted a conflicting Capability ID'
fi
assert_contains "$output" 'Result: MAPPING_CONFLICT'

output=$($CLI preflight "$canonical_backend" --client codex \
  --operation confluence-handoff-verify --non-interactive \
  --confluence-action update --target-content-id 900001 \
  --capability-id MARKET-FU-INDEX-API --scope Shared --domain Market \
  --transport API --expected-parent-id 900002 \
  --registry-content-id 900003)
assert_contains "$output" 'Capability: confluence-page-read'
assert_contains "$output" 'Result: PASS'

mv "$target_file.deny-only" "$target_file"
pin_test_release v1.1.15
```

- [ ] **Step 2: Run the focused routing test and confirm it fails**

Run:

```bash
sh tests/routing.sh
```

Expected: the new commands fail with usage or the old broad preflight passes.

- [ ] **Step 3: Parse and validate the target arguments**

Add empty `CONFLUENCE_TARGET_*` globals beside the existing route globals. Extend `usage` with the exact target options. In `cmd_preflight`, parse each option once and reject target options on non-Confluence operations. Missing or malformed Confluence fields must reach `die ROUTING_REQUIRED`, not generic usage.

Use the existing option loop for all eight values without dynamic evaluation:

```sh
--confluence-action)
  [ -z "$CONFLUENCE_TARGET_ACTION" ] && [ "$#" -ge 2 ] || { usage >&2; exit 2; }
  CONFLUENCE_TARGET_ACTION=$2; shift 2 ;;
--target-content-id)
  [ -z "$CONFLUENCE_TARGET_CONTENT_ID" ] && [ "$#" -ge 2 ] || { usage >&2; exit 2; }
  CONFLUENCE_TARGET_CONTENT_ID=$2; shift 2 ;;
--capability-id)
  [ -z "$CONFLUENCE_TARGET_CAPABILITY_ID" ] && [ "$#" -ge 2 ] || { usage >&2; exit 2; }
  CONFLUENCE_TARGET_CAPABILITY_ID=$2; shift 2 ;;
--scope)
  [ -z "$CONFLUENCE_TARGET_SCOPE" ] && [ "$#" -ge 2 ] || { usage >&2; exit 2; }
  CONFLUENCE_TARGET_SCOPE=$2; shift 2 ;;
--domain)
  [ -z "$CONFLUENCE_TARGET_DOMAIN" ] && [ "$#" -ge 2 ] || { usage >&2; exit 2; }
  CONFLUENCE_TARGET_DOMAIN=$2; shift 2 ;;
--transport)
  [ -z "$CONFLUENCE_TARGET_TRANSPORT" ] && [ "$#" -ge 2 ] || { usage >&2; exit 2; }
  CONFLUENCE_TARGET_TRANSPORT=$2; shift 2 ;;
--expected-parent-id)
  [ -z "$CONFLUENCE_TARGET_PARENT_ID" ] && [ "$#" -ge 2 ] || { usage >&2; exit 2; }
  CONFLUENCE_TARGET_PARENT_ID=$2; shift 2 ;;
--registry-content-id)
  [ -z "$CONFLUENCE_TARGET_REGISTRY_CONTENT_ID" ] && [ "$#" -ge 2 ] || { usage >&2; exit 2; }
  CONFLUENCE_TARGET_REGISTRY_CONTENT_ID=$2; shift 2 ;;
```

After parsing, reject any populated target variable unless the operation is
`confluence-write` or `confluence-handoff-verify`.

The resolver must select one row by repository plus numeric content ID, or by repository plus Capability ID for `create/new`. It must fail in this order before `verify_github_role`, `connector_state`, or `connector_health`:

```sh
resolve_confluence_target() {
  rct_file=$RELEASE_DIR/runtime/integrations/beroka-be-fe.confluence-targets
  validate_confluence_target_inventory "$rct_file" \
    "$RELEASE_DIR/runtime/repositories" ||
    die ROUTING_REQUIRED 'Reviewed Confluence target inventory is unavailable'

  case "$CONFLUENCE_TARGET_ACTION:$CONFLUENCE_TARGET_CONTENT_ID" in
    create:new) ;;
    update:[1-9]*|move:[1-9]*)
      printf '%s\n' "$CONFLUENCE_TARGET_CONTENT_ID" |
        grep -Eq '^[1-9][0-9]*$' ||
        die ROUTING_REQUIRED 'A numeric Confluence target content ID is required'
      ;;
    *) die ROUTING_REQUIRED 'Confluence action and target content ID conflict' ;;
  esac
  printf '%s\n' "$CONFLUENCE_TARGET_CAPABILITY_ID" |
    grep -Eq '^[A-Z][A-Z0-9]*(-[A-Z0-9]+)*$' ||
    die ROUTING_REQUIRED 'An uppercase-kebab-case Capability ID is required'
  case "$CONFLUENCE_TARGET_SCOPE" in Shared|Derivatives|Underlying) ;; *) die ROUTING_REQUIRED 'A reviewed Confluence scope is required' ;; esac
  case "$CONFLUENCE_TARGET_DOMAIN" in Market|User) ;; *) die ROUTING_REQUIRED 'A reviewed Confluence domain is required' ;; esac
  case "$CONFLUENCE_TARGET_TRANSPORT" in API|WebSocket) ;; *) die ROUTING_REQUIRED 'API or WebSocket transport is required' ;; esac
  for rct_id in "$CONFLUENCE_TARGET_PARENT_ID" "$CONFLUENCE_TARGET_REGISTRY_CONTENT_ID"; do
    printf '%s\n' "$rct_id" | grep -Eq '^[1-9][0-9]*$' ||
      die ROUTING_REQUIRED 'Numeric parent and Registry content IDs are required'
  done

  rct_record=$(awk -F '\t' \
    -v repository="$REPOSITORY_SLUG" \
    -v action="$CONFLUENCE_TARGET_ACTION" \
    -v content="$CONFLUENCE_TARGET_CONTENT_ID" \
    -v capability="$CONFLUENCE_TARGET_CAPABILITY_ID" '
      /^#/ || /^[[:space:]]*$/ { next }
      $1 == repository &&
        ((action == "create" && $3 == "PLANNED" && $4 == "-" && $10 == capability) ||
         (action != "create" && $4 == content)) { matches++; row=$0 }
      END { if (matches != 1) exit 1; print row }
    ' "$rct_file") || {
      if awk -F '\t' -v repository="$REPOSITORY_SLUG" \
        -v parent="$CONFLUENCE_TARGET_PARENT_ID" '
          /^#/ || /^[[:space:]]*$/ { next }
          $1 == repository && $2 == "folder" && $3 == "LEGACY" && $4 == parent { found=1 }
          END { exit !found }
        ' "$rct_file"
      then
        die FOLDER_CREATION_REQUIRED 'The requested parent is a legacy generic folder'
      fi
      die ROUTING_REQUIRED 'No exact reviewed Confluence target exists'
    }
  while IFS="$(printf '\t')" read -r rct_repository rct_type rct_state \
    rct_content rct_title rct_scope rct_domain rct_transport rct_parent \
    rct_capability rct_registry
  do :; done <<EOF
$rct_record
EOF

  case "$rct_state" in
    DRIFTED)
      if [ "$CONFLUENCE_TARGET_TRANSPORT" != "$rct_transport" ]; then
        printf '%s\n' \
          "Target content ID: $CONFLUENCE_TARGET_CONTENT_ID" \
          "Intended transport: $CONFLUENCE_TARGET_TRANSPORT" \
          "Target transport: $rct_transport"
        die MAPPING_CONFLICT
      fi
      die ROUTING_REQUIRED 'The exact Confluence target is drifted'
      ;;
    LEGACY) die FOLDER_CREATION_REQUIRED 'A legacy folder is not a canonical target' ;;
  esac
  [ "$rct_scope" = "$CONFLUENCE_TARGET_SCOPE" ] &&
    [ "$rct_domain" = "$CONFLUENCE_TARGET_DOMAIN" ] &&
    [ "$rct_transport" = "$CONFLUENCE_TARGET_TRANSPORT" ] &&
    [ "$rct_parent" = "$CONFLUENCE_TARGET_PARENT_ID" ] &&
    [ "$rct_capability" = "$CONFLUENCE_TARGET_CAPABILITY_ID" ] &&
    [ "$rct_registry" = "$CONFLUENCE_TARGET_REGISTRY_CONTENT_ID" ] ||
    die MAPPING_CONFLICT 'Requested Confluence metadata conflicts with the reviewed target'
}
```

Keep this in the existing CLI; do not add a parser module.

Call `resolve_confluence_target` from `require_operation_routing` for both operations before selecting capability:

```sh
confluence-write)
  require_confluence_route
  resolve_confluence_target
  PREFLIGHT_CAPABILITY=confluence-page-parent-write
  ;;
confluence-handoff-verify)
  require_confluence_route
  resolve_confluence_target
  PREFLIGHT_CAPABILITY=confluence-page-read
  ;;
```

- [ ] **Step 4: Add the read-only provider capability and PASS output**

Add the provider row:

```text
https://mcp.atlassian.com/v1/mcp/authv2\tgetAccessibleAtlassianResources,getConfluencePage\t2026-07-31\tconfluence-page-read\tofficial-contract\tSUPPORTED
```

Allow `confluence-page-read` in `load_provider_capability`, and add a `runtime_capability` case requiring `getConfluencePage`. Update `print_preflight_result` so both Confluence operations print exact content, Capability ID, scope, domain, transport, expected parent, and Registry content ID.

- [ ] **Step 5: Run tests and commit**

Run:

```bash
sh tests/routing.sh
sh tests/connectors.sh
sh tests/release.sh
```

Expected: all print PASS.

Commit:

```bash
git add bin/beroka-governance runtime/compatibility/atlassian.tsv tests/routing.sh
git commit -m "fix: bind Confluence preflight to exact targets"
```

### Task 3: Cursor Confluence and cross-team link enforcement

**Files:**
- Modify: `bin/beroka-governance:3999-4153`
- Modify: `tests/cursor-hooks.sh:27-56,84-123`

**Interfaces:**
- Consumes: normal Cursor MCP fields (`pageId`/`contentId`, `parentId`) plus canonical metadata markers already defined by `templates/jira-confluence.md`.
- Produces: `CURSOR_PROVIDER=confluence`, exact target arguments for shared `cmd_preflight`, and `CROSS_TEAM_LINK_SCOPE_DENIED` for private GitHub links in intake payloads.

- [ ] **Step 1: Add failing Cursor hook regressions**

Enroll Cursor in `tests/cursor-hooks.sh` after active-release setup so target failures reach the shared resolver:

```sh
printf '%s\n' cursor >"$XDG_CONFIG_HOME/beroka-ai-governance/clients"
git --git-dir=/dev/null hash-object --no-filters \
  "$release/templates/agent-entrypoints/CURSOR-USER-RULE.txt" \
  >"$XDG_CONFIG_HOME/beroka-ai-governance/cursor-user-rule.sha256"
```

Add ambiguous and conflicting Confluence writes:

```sh
confluence_update=$(printf '%s\n' "$base_input" | jq -c '. + {
  tool_name:"confluence.update_page",
  url:"https://beroka.atlassian.net/wiki",
  tool_input:{
    pageId:"70713366",
    parentId:"71303169",
    body:"Capability ID: MARKET-FU-INDEX-API\nRegistry content ID: 900003\nScope: Shared\nDomain: Market\nTransport: API\nConfluence content ID: 70713366"
  }}')
assert_denied "$(hook beforeMCPExecution "$confluence_update")" MAPPING_CONFLICT
assert_denied "$(hook beforeMCPExecution "$(printf '%s\n' "$confluence_update" | jq -c 'del(.tool_input.parentId)')")" ROUTING_REQUIRED
```

Add a private-link intake case:

```sh
private_link_intake=$(printf '%s\n' "$intake_base" | jq -c \
  '.tool_input.github="https://github.com/beroka-vn/Beroka_Backend/issues/138"')
assert_denied "$(hook beforeMCPExecution "$private_link_intake")" CROSS_TEAM_LINK_SCOPE_DENIED
```

- [ ] **Step 2: Run the Cursor test and confirm it fails**

Run:

```bash
sh tests/cursor-hooks.sh
```

Expected: Confluence is misclassified as Jira or unknown, and the private-link intake does not return the required denial code.

- [ ] **Step 3: Classify Confluence before generic Atlassian URLs**

Change provider order in `cursor_tool_provider`:

```sh
case "$CURSOR_TOOL_TEXT" in
  *github.com*|*github*) CURSOR_PROVIDER=github ;;
  *confluence*|*/wiki*) CURSOR_PROVIDER=confluence ;;
  *atlassian.net*|*jira*) CURSOR_PROVIDER=jira ;;
  *) CURSOR_PROVIDER= ;;
esac
```

Also include `*move*` in `CURSOR_TOOL_WRITE`; read-only Confluence calls still
pass through unchanged.

Derive action from the tool name, extract one unique metadata value from the body for `Capability ID`, `Capability Registry content ID`, `Scope`, `Domain`, `Transport`, and `Confluence content ID`, and use structured `pageId`/`contentId` plus `parentId`. Missing or duplicate markers deny with `ROUTING_REQUIRED`. Pass the resulting arguments directly to `cmd_preflight`; do not duplicate inventory matching in the hook.

```sh
cursor_confluence_preflight() {
  ccp_action=update
  case "$CURSOR_TOOL_TEXT" in *create*) ccp_action=create ;; *move*) ccp_action=move ;; esac
  if [ "$ccp_action" = create ]; then
    ccp_target=new
  else
    ccp_target=$(printf '%s\n' "$CURSOR_TOOL_INPUT" | jq -er \
      '[.. | objects | (.pageId?, .contentId?) | select(type == "string")] | unique | if length == 1 then .[0] else error("target") end') || return 1
  fi
  ccp_parent=$(printf '%s\n' "$CURSOR_TOOL_INPUT" | jq -er \
    '[.. | objects | .parentId? | select(type == "string")] | unique | if length == 1 then .[0] else error("parent") end') || return 1
  ccp_body=$(printf '%s\n' "$CURSOR_TOOL_INPUT" | jq -er \
    '[.. | objects | (.body?, .content?) | select(type == "string")] | unique | if length == 1 then .[0] else error("body") end') || return 1
  ccp_capability=$(printf '%s\n' "$ccp_body" | cursor_confluence_marker 'Capability ID') || return 1
  ccp_registry=$(printf '%s\n' "$ccp_body" | cursor_confluence_marker 'Registry content ID') || return 1
  ccp_scope=$(printf '%s\n' "$ccp_body" | cursor_confluence_marker Scope) || return 1
  ccp_domain=$(printf '%s\n' "$ccp_body" | cursor_confluence_marker Domain) || return 1
  ccp_transport=$(printf '%s\n' "$ccp_body" | cursor_confluence_marker Transport) || return 1
  ccp_body_target=$(printf '%s\n' "$ccp_body" | cursor_confluence_marker 'Confluence content ID') || return 1
  [ "$ccp_target" = "$ccp_body_target" ] || return 2
  cmd_preflight "$CURSOR_WORKSPACE" --client cursor \
    --operation confluence-write --non-interactive \
    --confluence-action "$ccp_action" \
    --target-content-id "$ccp_target" \
    --capability-id "$ccp_capability" \
    --scope "$ccp_scope" --domain "$ccp_domain" \
    --transport "$ccp_transport" \
    --expected-parent-id "$ccp_parent" \
    --registry-content-id "$ccp_registry"
}
```

Define the exact marker parser immediately above it:

```sh
cursor_confluence_marker() {
  ccm_label=$1
  awk -v label="$ccm_label" '
    {
      sub(/\r$/, "")
      prefix=label ":"
      if (index($0, prefix) == 1) {
        value=substr($0, length(prefix) + 1)
        sub(/^[[:space:]]+/, "", value)
        if (value == "" || seen++) invalid=1
        result=value
      }
    }
    END { if (invalid || seen != 1) exit 1; print result }
  '
}
```

In `cmd_cursor_before_mcp_execution`, handle the provider before work-item
template validation:

```sh
confluence)
  cursor_preflight_state=0
  cursor_preflight=$(cursor_confluence_preflight 2>&1) ||
    cursor_preflight_state=$?
  case "$cursor_preflight_state" in
    0)
      printf '%s\n' "$cursor_preflight" | grep -F 'Result: PASS' >/dev/null &&
        { cursor_allow; return; }
      ;;
    2) cursor_deny MAPPING_CONFLICT 'Confluence body and structured target IDs conflict.'; return ;;
  esac
  cursor_result=$(printf '%s\n' "$cursor_preflight" |
    awk '/^Result: / { result=$0 } END { sub(/^Result: /, "", result); print result }')
  [ -n "$cursor_result" ] || cursor_result=ROUTING_REQUIRED
  cursor_deny "$cursor_result" "${cursor_preflight:-Exact Confluence target metadata is required.}"
  return
  ;;
```

For create operations, use target `new` and require the body marker `Confluence content ID: new`. The shared resolver remains the only authority for state and mapping results.

- [ ] **Step 4: Deny private GitHub links only on cross-team intake**

Before template validation, inspect `CURSOR_TOOL_INPUT` when `cursor_operation=jira-intake-write`:

```sh
if [ "$cursor_operation" = jira-intake-write ] &&
   printf '%s\n' "$CURSOR_TOOL_INPUT" |
     grep -Eiq 'https://github\.com/beroka-vn/Beroka_(Backend|Frontend)(/|"|$)'
then
  cursor_deny CROSS_TEAM_LINK_SCOPE_DENIED \
    'Use an accessible exact Confluence page for cross-team documentation.'
  return
fi
```

Do not reject same-team Jira links to the current repository.

- [ ] **Step 5: Run tests and commit**

Run:

```bash
sh tests/cursor-hooks.sh
sh tests/routing.sh
```

Expected: both print PASS.

Commit:

```bash
git add bin/beroka-governance tests/cursor-hooks.sh
git commit -m "fix: enforce Confluence targets in Cursor"
```

### Task 4: Provider-neutral Jira, documentation, and lifecycle contract

**Files:**
- Modify: `runtime/rules/general.md:24-31`
- Modify: `runtime/rules/work-items.md:13-51`
- Modify: `runtime/integrations/beroka-be-fe.md:16-28`
- Modify: `templates/agent-entrypoints/AGENTS.md:17-29`
- Modify: `templates/agent-entrypoints/CLAUDE.md:17-30`
- Modify: `templates/agent-entrypoints/CURSOR-USER-RULE.txt:19-31`
- Modify: `templates/jira-confluence.md:97-276,546-575`
- Modify: `governance.md:324-379,395-415,430-439`
- Modify: `workflow.md:97-115,172-187,194-252,295-323`
- Modify: `tests/documentation-architecture.sh:75-205`

**Interfaces:**
- Consumes: target-bound CLI results and Atlassian readbacks performed by the active agent.
- Produces: the same mandatory assignee, private-link, Confluence target, and status rules in every supported agent instruction and governed context.

- [ ] **Step 1: Add failing documentation contract assertions**

Add exact assertions to `tests/documentation-architecture.sh`:

```sh
for file in templates/agent-entrypoints/AGENTS.md \
  templates/agent-entrypoints/CLAUDE.md \
  templates/agent-entrypoints/CURSOR-USER-RULE.txt; do
  require_text "$file" 'exact Confluence target'
  require_text "$file" 'ASSIGNEE_CONFIRMATION_REQUIRED'
  require_text "$file" 'opposite-team private GitHub links'
done
for file in runtime/rules/general.md governance.md workflow.md \
  templates/jira-confluence.md; do
  require_text "$file" 'confluence-handoff-verify'
  require_text "$file" 'MAPPING_CONFLICT'
done
for file in runtime/rules/work-items.md runtime/integrations/beroka-be-fe.md \
  governance.md workflow.md templates/jira-confluence.md; do
  require_text "$file" 'ASSIGNEE_CONFIRMATION_REQUIRED'
  require_text "$file" 'CROSS_TEAM_LINK_SCOPE_DENIED'
  require_text "$file" 'In Review'
done
reject_text templates/jira-confluence.md 'Frontend Jira/GitHub issue(s):'
```

- [ ] **Step 2: Run the documentation test and confirm it fails**

Run:

```bash
sh tests/documentation-architecture.sh
```

Expected: it reports the first missing new contract phrase.

- [ ] **Step 3: Update the shared runtime rules and integration pack**

Add concise provider-neutral rules:

```markdown
- Before a Confluence create, update, move, or handoff, resolve the exact content
  ID, Capability ID, scope, domain, transport, parent ID, and Registry content ID;
  run target-bound `confluence-write` or `confluence-handoff-verify`. Unknown or
  ambiguous targets return `ROUTING_REQUIRED`; ask the user and wait.
- Before any Jira field, description, comment, or status update, read the
  authenticated and current-assignee Atlassian `accountId`. A mismatch or
  unassigned item returns `ASSIGNEE_CONFIRMATION_REQUIRED` and waits for exact
  user authorization.
- Cross-team intake and handoff text must not contain opposite-team private
  GitHub links. Return `CROSS_TEAM_LINK_SCOPE_DENIED` and use an accessible exact
  Confluence page instead.
```

In the integration pack, state that `Task`, `Bug`, and `Feature` intake is allowed, opposite-project Epic creation requires receiving-team confirmation, FE owns BF updates, BE owns BB updates, and assignment/readiness do not bypass the separate GitHub Issue gate.
Replace the unconditional “intake starts unassigned” wording: an exact
receiving-team account may be assigned only after the user or receiving team
confirms that `accountId`; otherwise leave assignee, Sprint, and parent unset.

- [ ] **Step 4: Update all three supported-client entrypoints**

Append the same short rule block after each producer-specific OAuth paragraph:

```markdown
Before a Confluence write, identify the exact Confluence target and run its
target-bound preflight; if any target field is unknown, ask the user and wait.
Before a Jira update, compare the authenticated and current-assignee Atlassian
account IDs; mismatch or unassigned returns `ASSIGNEE_CONFIRMATION_REQUIRED`.
Never place opposite-team private GitHub links in cross-team Jira or handoff
text; use the exact accessible Confluence page.
```

Do not alter the producer-specific login commands.

- [ ] **Step 5: Update templates and lifecycle docs**

Add a Confluence target confirmation block to `templates/jira-confluence.md`:

```text
CONFLUENCE TARGET
- Action: create | update | move
- Target content ID: <numeric ID | new>
- Capability ID: <UPPERCASE-KEBAB-ID>
- Scope: Shared | Derivatives | Underlying
- Domain: Market | User
- Transport: API | WebSocket
- Expected parent ID: <numeric ID>
- Registry content ID: <numeric ID>
- Preflight: confluence-write | confluence-handoff-verify
- Result: PASS | ROUTING_REQUIRED | FOLDER_CREATION_REQUIRED | MAPPING_CONFLICT
```

Document the symmetric lifecycle in `governance.md` and `workflow.md` with these exact transitions:

```text
To Do -> In Progress: receiving assignee starts accepted, ready work
In Progress -> In Review: human marks the provider PR ready for review
In Review -> Done: reviewed PR is merged and exact Confluence delivery/readback is complete
```

State that `Closes #<issue>` normally closes the GitHub Issue; an agent closes it manually only after exact merge/link readback proves it remains open and the write is authorized. The provider updates only its project item; the consumer reviews through Confluence and updates its own item.
Remove `Frontend Jira/GitHub issue(s):` from the shared handoff block. Provider
private delivery links stay only in the provider-owned Jira/GitHub records; the
consumer-facing Confluence handoff carries Jira keys, delivered behavior,
contract identity, and accessible Confluence references.

- [ ] **Step 6: Run documentation and bootstrap tests, then commit**

Run:

```bash
sh tests/documentation-architecture.sh
sh tests/bootstrap.sh
```

Expected: both print PASS and the existing producer-specific OAuth contract remains unchanged.

Commit:

```bash
git add runtime/rules/general.md runtime/rules/work-items.md \
  runtime/integrations/beroka-be-fe.md templates/agent-entrypoints/AGENTS.md \
  templates/agent-entrypoints/CLAUDE.md \
  templates/agent-entrypoints/CURSOR-USER-RULE.txt \
  templates/jira-confluence.md governance.md workflow.md \
  tests/documentation-architecture.sh
git commit -m "docs: define cross-team delivery boundaries"
```

### Task 5: Full verification and draft pull request

**Files:**
- Verify: all changed files from Tasks 1-4
- Create externally: one draft PR for issue #44

**Interfaces:**
- Consumes: the four task commits and GitHub issue #44 authority.
- Produces: green repository checks, a pushed `fix/44-confluence-mapping-boundary` branch, and one draft PR; no merge or release.

- [ ] **Step 1: Run every repository test fail-fast**

Run:

```bash
for test in tests/*.sh; do
  sh "$test" || exit 1
done
```

Expected PASS footers: bootstrap, connectors, Cursor hooks, documentation architecture, launcher, release, routing, and smoke.

- [ ] **Step 2: Inspect the final diff and repository state**

Run:

```bash
git diff --check origin/main...HEAD
git status --short
git log --oneline --decorate origin/main..HEAD
```

Expected: no whitespace errors, only issue #44 files, and no uncommitted changes.

- [ ] **Step 3: Run a fresh GitHub-write preflight**

Run:

```bash
beroka-governance preflight "$PWD" --client codex \
  --operation github-write --non-interactive
```

Expected: `Result: PASS`. Stop without pushing if it returns any other result.

- [ ] **Step 4: Push and open one draft PR**

Run:

```bash
git push -u origin fix/44-confluence-mapping-boundary
gh pr create --draft --base main \
  --title "fix: bind Confluence writes to reviewed targets" \
  --body "$(printf '%s\n' \
    'Closes #44' \
    '' \
    '## Summary' \
    '- fail closed when Confluence target metadata or transport conflicts' \
    '- apply the same Jira assignee, link, and lifecycle contract to supported agents' \
    '- add Cursor enforcement and deny-only records for the observed drift' \
    '' \
    '## Validation' \
    '- all tests/*.sh pass')"
```

Expected: one draft PR URL. Do not mark ready, merge, tag, publish a release, or mutate live Jira/Confluence.
