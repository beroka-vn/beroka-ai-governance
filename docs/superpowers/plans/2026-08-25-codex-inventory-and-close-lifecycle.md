# Codex Inventory and GitHub Close Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make live Codex Jira and Confluence preflights accept validated overlapping inventories, then require agents to reconcile a closed GitHub Issue to Jira `In Review` and exact Confluence documentation without advancing Jira to `Done`.

**Architecture:** Validate the direct Atlassian and authenticated reviewed Codex Apps tool sets independently, then set-union their canonical names so cross-record corroboration is not treated as ambiguity. Preserve partial-page state with duplicate-aware cursor parsing so exact presence can authorize while absence cannot. Express the normative close follow-up once in the general runtime rules rendered by every profile, with explanatory published copies; no listener or new runtime component is added.

**Tech Stack:** POSIX shell, `awk`, `jq`, existing shell test harness, Markdown governance rules.

**Spec:** `docs/superpowers/specs/2026-08-24-codex-inventory-and-close-lifecycle-design.md`

## Global Constraints

- Technical artifacts remain in English.
- No new dependency, daemon, webhook, credential, or configuration value. The
  only capability-alias expansion is the explicitly authorized exact
  `atlassian_rovo.createConfluencePage`, `atlassian_rovo.getConfluencePage`,
  and `atlassian_rovo.updateConfluencePage` aliases; no legacy, hashed,
  preview, suffixed, or other aliases are allowed.
- Only exact reviewed aliases from the optional single `codex_apps` record with
  exact `authStatus: bearerToken` are accepted.
- Malformed or duplicate names within one record remain blocked.
- Missing `result.nextCursor` or exactly one null cursor is terminal. Any other
  value or duplicate cursor key cannot make missing tools authoritative.
- Every Jira or Confluence write still requires its own fresh operation-specific preflight.
- Missing or ambiguous Confluence context must be asked of the user, never guessed.
- Documentation readback leaves Jira in `In Review`; no automatic transition to `Done`.

---

### Task 1: Resolve overlapping Codex inventories

**Files:**
- Modify: `tests/routing.sh`
- Modify: `bin/beroka-governance`

**Interfaces:**
- Consumes: one `mcpServerStatus/list` response containing the required single `atlassian` record, an optional single `codex_apps` record, and optional `result.nextCursor`.
- Produces: `CAPABILITY_INVENTORY` as unique canonical names, `CAPABILITY_INVENTORY_FORMAT=json`, and `CAPABILITY_INVENTORY_COMPLETE=1` only when `result.nextCursor` is absent or occurs exactly once with value `null`.
- Produces helper: `codex_inventory_page_complete()`, stdin JSON-RPC response to shell success for a terminal page and failure otherwise.

- [ ] **Step 1: Add the populated/populated overlap fixture**

Add a `healthy-codex-apps-overlap` case beside `healthy-codex-apps-split-jira` in the fake Codex app-server. The direct record contains the existing `healthy-all` Jira and Confluence tools. The Codex Apps record contains the six existing reviewed `atlassian_rovo.*` Jira aliases:

```sh
healthy-codex-apps-overlap)
  printf '%s\n' '{"id":1,"result":{"data":[{"name":"atlassian","tools":{"createJiraIssue":{},"getAccessibleAtlassianResources":{},"getJiraIssue":{},"getJiraIssueTypeMetaWithFields":{},"getJiraProjectIssueTypesMetadata":{},"searchJiraIssuesUsingJql":{},"createConfluencePage":{},"getConfluencePage":{},"updateConfluencePage":{}},"authStatus":"oAuth"},{"name":"codex_apps","tools":{"atlassian_rovo.createJiraIssue":{},"atlassian_rovo.getAccessibleAtlassianResources":{},"atlassian_rovo.getJiraIssue":{},"atlassian_rovo.getJiraIssueTypeMetaWithFields":{},"atlassian_rovo.getJiraProjectIssueTypesMetadata":{},"atlassian_rovo.searchJiraIssuesUsingJql":{}},"authStatus":"bearerToken"}],"nextCursor":null}}'
  ;;
```

Add assertions after the existing split-Jira case:

```sh
printf '%s\n' healthy-codex-apps-overlap \
  >"$XDG_CONFIG_HOME/fake-codex-health"
output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive)
assert_contains "$output" 'Capability state: SUPPORTED'
assert_contains "$output" 'Runtime inventory: COMPLETE'
assert_contains "$output" 'Result: PASS'
```

After `page_config` is published, run target-bound Confluence preflight with the same fixture and assert `SUPPORTED`, `COMPLETE`, and `PASS`.

- [ ] **Step 2: Run the overlap test and verify RED**

Run:

```bash
sh tests/routing.sh
```

Expected: FAIL in `healthy-codex-apps-overlap`; the canonical overlap currently makes runtime inventory unavailable.

- [ ] **Step 3: Canonicalize each trusted record before the union**

In the Codex arm of `connector_inventory()`, replace the combined duplicate-sensitive canonicalization with independent validation and a unique union:

```sh
ci_tools=$(printf '%s\n' "$ci_record" |
  json_top_level_tools |
  codex_canonical_tool_names) || return 1
ci_apps_record=$(printf '%s\n' "$CONNECTOR_PROBE_OUTPUT" |
  codex_atlassian_record codex_apps optional) || return 1
ci_apps_tools=
if [ -n "$ci_apps_record" ]; then
  ci_apps_tools=$(printf '%s\n' "$ci_apps_record" |
    json_top_level_tools tools |
    codex_canonical_tool_names apps-only) || return 1
fi
CAPABILITY_INVENTORY=$({
  [ -z "$ci_tools" ] || printf '%s\n' "$ci_tools"
  [ -z "$ci_apps_tools" ] || printf '%s\n' "$ci_apps_tools"
} | LC_ALL=C sort -u) || return 1
CAPABILITY_INVENTORY_FORMAT=json
```

Before extracting `ci_apps_tools`, require the optional exact `codex_apps`
record's `authStatus` to equal `bearerToken`; otherwise it contributes no
aliases. Keep direct-record OAuth handling and `codex_canonical_tool_names`
duplicate rejection intact. The later
integrated fix adds only the three explicitly authorized exact Confluence
aliases named in Global Constraints; it does not add any legacy, hashed,
preview, suffixed, or other aliases.

- [ ] **Step 4: Run routing tests and verify GREEN for overlap and existing negatives**

Run:

```bash
sh tests/routing.sh
```

Expected: PASS, including `healthy-codex-apps-ambiguous`, malformed, near-match, cross-provider, and unreviewed-alias negatives.

- [ ] **Step 5: Add a partial-page absence regression and verify RED**

Add a `partial-codex-apps-read-only` fixture with authenticated records, reviewed read aliases, and `"nextCursor":"page-2"`. Assert Jira preflight is `UNKNOWN`, is not `UNSUPPORTED`, and does not pass:

```sh
printf '%s\n' partial-codex-apps-read-only \
  >"$XDG_CONFIG_HOME/fake-codex-health"
if output=$($CLI preflight "$consumer" \
  --client codex --operation jira-write --non-interactive 2>&1)
then
  fail 'partial Codex inventory authorized Jira write'
fi
assert_contains "$output" 'Capability state: UNKNOWN'
assert_not_contains "$output" 'Capability state: UNSUPPORTED'
assert_contains "$output" 'Result: CONNECTOR_CAPABILITY_REQUIRED'
```

Run `sh tests/routing.sh`.

Expected: FAIL because the current adapter marks every parsed response complete and reports authoritative absence.

- [ ] **Step 6: Preserve partial-page evidence without authorizing absence**

Add a streaming/key-count cursor classifier immediately before
`connector_inventory()`. It must distinguish absent, exactly one literal null,
all other JSON value types, and duplicate semantic `nextCursor` keys without
collapsing duplicates.

In the Codex arm of `connector_inventory()`, set completeness after building the validated inventory:

```sh
if printf '%s\n' "$CONNECTOR_PROBE_OUTPUT" |
   codex_inventory_page_complete
then
  CAPABILITY_INVENTORY_COMPLETE=1
fi
```

Leave the initial value at zero. In `resolve_provider_capability()`, distinguish a present partial inventory from clients with no runtime inventory:

```sh
connector_inventory "$rpc_client" || return 0
if [ -n "$CAPABILITY_INVENTORY_FORMAT" ]; then
  if inventory_has_required_tools; then
    :
  elif [ "$CAPABILITY_INVENTORY_COMPLETE" -eq 1 ]; then
    CAPABILITY_INVENTORY_STATE=COMPLETE
    CAPABILITY_STATE=UNSUPPORTED
    CAPABILITY_EVIDENCE_SOURCE=RUNTIME_INVENTORY
    return 0
  else
    return 0
  fi
fi
if [ "$CAPABILITY_INVENTORY_COMPLETE" -eq 1 ]; then
  CAPABILITY_INVENTORY_STATE=COMPLETE
fi
CAPABILITY_STATE=SUPPORTED
CAPABILITY_EVIDENCE_SOURCE=PROVIDER_CONTRACT
```

This preserves provider-contract behavior for Claude, which has no inventory format, while preventing a partial Codex page with missing tools from authorizing or proving absence.

- [ ] **Step 7: Add final-review authentication and cursor regressions**

Add direct-empty OAuth fixtures whose exact Codex Apps Confluence aliases have
missing, unknown, and `notLoggedIn` auth states. Each must remain blocked and
must not report `SUPPORTED`; retain authenticated `bearerToken` create/update
PASS cases. Add boolean-false and duplicate `nextCursor` fixtures. Each must
resolve missing required tools to `UNKNOWN`, never `UNSUPPORTED` or PASS.

- [ ] **Step 8: Verify the complete routing matrix**

Run:

```bash
sh -n bin/beroka-governance
sh -n tests/routing.sh
sh tests/routing.sh
git diff --check
```

Expected: all commands exit 0.

- [ ] **Step 9: Commit the inventory fix**

```bash
git add bin/beroka-governance tests/routing.sh
git commit -m "fix: accept corroborating Codex inventories"
```

---

### Task 2: Require the GitHub-close Jira and Confluence follow-up

**Files:**
- Modify: `tests/documentation-architecture.sh`
- Modify: `tests/routing.sh`
- Modify: `runtime/rules/general.md`
- Modify: `runtime/rules/work-items.md` (remove duplicate lifecycle rule)
- Modify: `runtime/integrations/beroka-be-fe.md` (remove duplicate lifecycle rule)
- Modify: `governance.md`
- Modify: `workflow.md`
- Modify: `templates/jira-confluence.md`

**Interfaces:**
- Consumes: an automatic `Closes #<issue>` close or an authorized manual close after exact merge/link readback.
- Produces: an ordered instruction contract: exact linked Jira resolution, assignee verification, fresh `jira-write` preflight, idempotent `In Review`, exact Confluence ID or user clarification, target-bound preflight, update, readback, Jira remaining `In Review`, and separate GitHub, Jira, and Confluence outcomes.

- [ ] **Step 1: Add lifecycle documentation-contract assertions**

In `tests/documentation-architecture.sh`, add exact assertions for the general
runtime rule and three explanatory copies, reject duplicate lifecycle rules in
the work-item and BE/FE integration sources, and reject the old automatic Done
rule across every published copy. In `tests/routing.sh`, require a routed
standalone context to render the lifecycle and a BE/FE context to render it
exactly once:

```sh
for file in runtime/rules/general.md governance.md workflow.md \
  templates/jira-confluence.md; do
  require_text "$file" 'closes the current primary GitHub Issue'
  require_text "$file" 'exact linked Jira item'
  require_text "$file" 'already in `In Review`'
  require_text "$file" 'exact Confluence content ID'
  require_text "$file" 'ask the user'
  require_text "$file" 'documentation readback'
  require_text "$file" 'remains in `In Review`'
  reject_text "$file" 'In Review -> Done'
done
```

- [ ] **Step 2: Run the documentation test and verify RED**

Run:

```bash
sh tests/documentation-architecture.sh
```

Expected: FAIL because the general runtime source lacks the lifecycle, the
profile-specific sources duplicate it, and the published contracts lack the
manual-close and separate-outcome requirements.

- [ ] **Step 3: Move the normative lifecycle to the general runtime rule**

Use the existing prose style in each file, preserving surrounding role and
cross-team rules. Put the normative content in `runtime/rules/general.md`, keep
the three explanatory copies, and remove the normative lifecycle from
`runtime/rules/work-items.md` and `runtime/integrations/beroka-be-fe.md`. Restore
the prior exact merge/link readback and authorized close-write gate before the
follow-up trigger. The normative content must state:

```markdown
After `Closes #<issue>` automatically closes the current primary GitHub Issue,
or after an agent completes an authorized manual close under the preceding
gate, resolve the exact linked Jira
item, verifies the authenticated account against the current assignee, runs a
fresh `jira-write` preflight, and transitions the item to `In Review`; an item
already in `In Review` is idempotently complete. It then resolves related
documentation only by exact Confluence content ID. If the page, parent, or
required change is missing or ambiguous, ask the user and wait. Otherwise run
a fresh target-bound Confluence preflight, update the documentation, and read
it back. After documentation readback Jira remains in `In Review`; do not move
it to `Done` automatically. After success, report the GitHub, Jira, and
Confluence outcomes separately. Report a blocked Jira or Confluence step
separately and do not reopen the GitHub Issue.
```

Keep `To Do -> In Progress` when accepted work starts and `In Progress -> In Review` when a human marks the provider PR ready. The close follow-up is idempotent when that earlier transition already occurred.

- [ ] **Step 4: Verify the lifecycle contract and context rendering**

Run:

```bash
sh tests/documentation-architecture.sh
sh tests/routing.sh
git diff --check
```

Expected: both tests exit 0; routed standalone context contains the close
follow-up, BE/FE context contains it exactly once, and neither contains an
`In Review -> Done` rule.

- [ ] **Step 5: Commit the lifecycle rule**

```bash
git add tests/documentation-architecture.sh tests/routing.sh \
  runtime/rules/general.md runtime/rules/work-items.md \
  runtime/integrations/beroka-be-fe.md governance.md workflow.md \
  templates/jira-confluence.md
git commit -m "feat: require post-close Jira and docs follow-up"
```

---

### Task 3: Verify the integrated change

**Files:**
- No source changes expected.

**Interfaces:**
- Consumes: Tasks 1 and 2 commits.
- Produces: fresh local-suite and live Codex preflight evidence for issue #77.

- [ ] **Step 1: Run the full repository suite**

Run:

```bash
for test_file in tests/*.sh; do sh "$test_file"; done
git diff --check
git status --short
```

Expected: every test exits 0, the diff check exits 0, and the working tree is clean.

- [ ] **Step 2: Rehydrate Backend governance before live qualification**

Run:

```bash
beroka-governance context /home/cuongngo/Beroka_Backend
```

Expected: repository `beroka-vn/Beroka_Backend`, routing `ROUTING_ACTIVE`, Jira project `BB`, and Confluence root content `65962274`.

- [ ] **Step 3: Run live source-branch preflights**

Run:

```bash
bin/beroka-governance preflight /home/cuongngo/Beroka_Backend \
  --client codex --operation jira-write --non-interactive
bin/beroka-governance preflight /home/cuongngo/Beroka_Backend \
  --client codex --operation confluence-write --non-interactive \
  --confluence-action create --target-content-id new \
  --expected-parent-id 65962274
bin/beroka-governance preflight /home/cuongngo/Beroka_Backend \
  --client codex --operation confluence-write --non-interactive \
  --confluence-action update --target-content-id 65962274
```

Expected for all three: `Capability state: SUPPORTED`, `Runtime inventory:
COMPLETE`, and `Result: PASS`. These commands perform no Jira or Confluence
write.

- [ ] **Step 4: Review the final diff against the spec**

Run:

```bash
git diff origin/main...HEAD --check
git log --oneline --decorate origin/main..HEAD
git status --short
```

Confirm every spec requirement has code or documentation coverage, no raw tool inventory is printed, and no external record was changed.
