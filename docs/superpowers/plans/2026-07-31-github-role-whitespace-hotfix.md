# GitHub Role Whitespace Hotfix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Accept existing GitHub role tokens with leading or trailing POSIX whitespace while preserving canonical storage and fail-closed validation.

**Architecture:** Normalize the interactive answer once inside the existing `configure_github_role` input boundary, immediately after `IFS= read -r`. Keep the existing `case`, eligibility checks, and role writer as the only validation and persistence paths.

**Tech Stack:** POSIX `sh`, POSIX `sed`, and the existing shell regression suites.

## Global Constraints

- Change only interactive role-input normalization in `configure_github_role` and focused coverage in `tests/bootstrap.sh`.
- Trim complete leading and trailing `[[:space:]]` runs in one normalization step; preserve internal whitespace.
- Keep accepted tokens exactly `FE`, `fe`, `BE`, `be`, `Full-stack`, `full-stack`, and `FULL_STACK`.
- Keep stored values exactly `FE`, `BE`, and `FULL_STACK`.
- Empty, whitespace-only, unknown, internal-space, and ineligible inputs must remain blocked.
- Add no helper, dependency, configuration, retry, or alternate input path.
- Do not change `VERSION`, supported-release documentation, launcher commands, release assertions, Team discovery, routing, Jira, connectors, or application repositories.

---

### Task 1: Normalize the Existing Interactive Role Answer

**Files:**
- Modify: `tests/bootstrap.sh:389-417`
- Modify: `bin/beroka-governance:1569-1605`

**Interfaces:**
- Consumes: `configure_github_role(client, interactive)`, its existing terminal input, Team membership globals, and `write_github_role`.
- Produces: the same `FE`, `BE`, or `FULL_STACK` role file, with only leading/trailing POSIX whitespace newly ignored.

- [ ] **Step 1: Write the failing regression and boundary matrix**

Replace the single interactive `Full-stack` assertion in `tests/bootstrap.sh` with:

```sh
for role_case in \
  '  Full-stack  |FULL_STACK' \
  'FE|FE' 'fe|FE' \
  'BE|BE' 'be|BE' \
  'Full-stack|FULL_STACK' 'full-stack|FULL_STACK' 'FULL_STACK|FULL_STACK'
do
  role_input=${role_case%%|*}
  expected_role=${role_case#*|}
  rm -f "$role_file"
  if ! output=$(printf '%s\n' "$role_input" | script -qec \
    "$CLI bootstrap $repo --client codex --version v1.1.0" \
    /dev/null 2>&1)
  then
    fail "interactive [$role_input] was rejected"
  fi
  assert_contains "$output" "GitHub role: $expected_role"
  [ "$(cat "$role_file")" = "$expected_role" ] ||
    fail "interactive [$role_input] stored the wrong GitHub role"
done

for role_input in '' '   ' unknown 'Full stack'; do
  rm -f "$role_file"
  if output=$(printf '%s\n' "$role_input" | script -qec \
    "$CLI bootstrap $repo --client codex --version v1.1.0" \
    /dev/null 2>&1)
  then
    fail "interactive [$role_input] bypassed role validation"
  fi
  assert_contains "$output" 'Result: GITHUB_ROLE_SELECTION_REQUIRED'
  [ ! -e "$role_file" ] ||
    fail "invalid interactive [$role_input] stored a GitHub role"
done
```

Keep the adjacent non-interactive dual-membership, stored-role, and no-eligible-Team assertions unchanged.

- [ ] **Step 2: Run the focused suite and verify RED**

Run:

```bash
sh tests/bootstrap.sh
```

Expected: FAIL at `interactive [  Full-stack  ] was rejected`; the current exact `case` comparison rejects the padded token.

- [ ] **Step 3: Add the minimal input-boundary normalization**

Immediately after `IFS= read -r cgr_answer || cgr_answer=` in `configure_github_role`, add:

```sh
        cgr_answer=$(
          printf '%s\n' "$cgr_answer" |
            sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
        )
```

Do not alter the following role `case` patterns or any eligibility/persistence function.

- [ ] **Step 4: Run the focused suite and verify GREEN**

Run:

```bash
sh tests/bootstrap.sh
```

Expected: PASS; padded and canonical tokens store their existing canonical values, invalid inputs remain `GITHUB_ROLE_SELECTION_REQUIRED`, and no-Team membership remains `GITHUB_ROLE_REQUIRED`.

- [ ] **Step 5: Run full verification**

Run each suite separately:

```bash
sh tests/bootstrap.sh
sh tests/connectors.sh
sh tests/cursor-hooks.sh
sh tests/documentation-architecture.sh
sh tests/launcher.sh
sh tests/release.sh
sh tests/routing.sh
sh tests/smoke.sh
dash -n bin/beroka-governance tests/*.sh
git diff --check
git diff --exit-code HEAD -- VERSION README.md handbook.md PACKAGE-DESIGN.md \
  release/bootstrap.sh.in tests/release.sh
```

Expected: all suites and syntax checks PASS, `git diff --check` is clean, and the release-only files have no diff.

- [ ] **Step 6: Commit only the hotfix**

```bash
git add bin/beroka-governance tests/bootstrap.sh
git diff --cached --check
git commit -m "fix: trim GitHub role whitespace"
```

Expected: one commit containing only the runtime normalization and bootstrap regression coverage.
