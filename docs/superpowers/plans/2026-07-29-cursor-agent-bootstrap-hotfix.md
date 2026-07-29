# Cursor Agent Bootstrap Hotfix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `v1.0.1` so one interactive Cursor bootstrap command installs a missing Cursor Agent automatically and connector setup works when invoked from `$HOME`.

**Architecture:** Keep vendor installation in the verified release launcher, before package installation or upgrade, and keep direct package calls fail-closed through the existing `require_client` boundary. Route every governance-owned `cursor-agent mcp` call through one subshell that runs from `/`, preventing Cursor from treating global `~/.cursor/mcp.json` as project-local configuration.

**Tech Stack:** POSIX shell, existing shell test harness, Git, official Cursor HTTPS installer.

## Global Constraints

- Target release is exactly `v1.0.1`; the published `v1.0.0` tag remains immutable.
- Interactive bootstrap may install Cursor Agent only after one `[y/N]` confirmation.
- `--non-interactive` never installs packages or opens a browser.
- Use only `https://cursor.com/install`; stage the complete response before executing it with `bash`.
- Do not edit shell startup files, Cursor's settings database, or Cursor's MCP approval store.
- Preserve Codex and Claude behavior.
- The affected developer runs one bootstrap command and no manual Cursor installation command.
- Use no new dependency or abstraction beyond one shared Cursor MCP shell helper.

---

### Task 1: Release launcher installs Cursor Agent

**Files:**
- Modify: `tests/launcher.sh`
- Modify: `release/bootstrap.sh.in`

**Interfaces:**
- Consumes: existing launcher variables `client`, `non_interactive`, `bootstrap_root`, and the existing interactive OS-package flow.
- Produces: `ensure_os_dependency NAME`, `ensure_cursor_agent`, and a launcher `PATH` containing `$HOME/.local/bin` after successful installation.

- [ ] **Step 1: Add failing launcher regressions**

Add an isolated Cursor fixture after the existing jq tests in
`tests/launcher.sh`. Its fake `curl` must accept exactly the staged-download
shape and emit an installer which creates a working
`$HOME/.local/bin/cursor-agent`:

```sh
cursor_root=$TEST_ROOT/cursor-dependency
cursor_bin=$cursor_root/bin
cursor_calls=$cursor_root/calls
mkdir -p "$cursor_bin"
for executable in bash cat git grep id jq mktemp rm sh; do
  ln -s "$(command -v "$executable")" "$cursor_bin/$executable"
done
cursor_success=$cursor_root/install-success.sh
cursor_failure=$cursor_root/install-failure.sh
cursor_invalid=$cursor_root/install-invalid.sh
cat >"$cursor_success" <<'EOF'
#!/bin/sh
set -eu
/bin/mkdir -p "$HOME/.local/bin"
cat >"$HOME/.local/bin/cursor-agent" <<'AGENT'
#!/bin/sh
case "$*" in
  --version) printf '%s\n' 2026.07.23-test ;;
  'mcp login --help') exit 0 ;;
  *) exit 0 ;;
esac
AGENT
/bin/chmod 755 "$HOME/.local/bin/cursor-agent"
EOF
cat >"$cursor_failure" <<'EOF'
#!/bin/sh
exit 9
EOF
cat >"$cursor_invalid" <<'EOF'
#!/bin/sh
set -eu
/bin/mkdir -p "$HOME/.local/bin"
cat >"$HOME/.local/bin/cursor-agent" <<'AGENT'
#!/bin/sh
case "$*" in
  --version) printf '%s\n' broken-test ;;
  *) exit 1 ;;
esac
AGENT
/bin/chmod 755 "$HOME/.local/bin/cursor-agent"
EOF
cat >"$cursor_bin/curl" <<'EOF'
#!/bin/sh
set -eu
printf 'curl %s\n' "$*" >>"$CURSOR_INSTALL_CALLS"
[ "$1" = -fsS ] &&
  [ "$2" = https://cursor.com/install ] &&
  [ "$3" = -o ] &&
  [ "$#" -eq 4 ] ||
  exit 64
case "${CURSOR_INSTALL_MODE:-success}" in
  success) /bin/cp "$CURSOR_SUCCESS_INSTALLER" "$4" ;;
  failure) /bin/cp "$CURSOR_FAILURE_INSTALLER" "$4" ;;
  invalid) /bin/cp "$CURSOR_INVALID_INSTALLER" "$4" ;;
  *) exit 64 ;;
esac
EOF
chmod 755 "$cursor_bin/curl"
: >"$cursor_calls"
output=$(
  printf 'y\n' |
  PATH="$cursor_bin" CURSOR_INSTALL_CALLS="$cursor_calls" \
  CURSOR_SUCCESS_INSTALLER="$cursor_success" \
  CURSOR_FAILURE_INSTALLER="$cursor_failure" \
  CURSOR_INVALID_INSTALLER="$cursor_invalid" \
  /usr/bin/script -qec \
    "/bin/sh $asset --client cursor" /dev/null 2>&1
)
assert_contains "$output" \
  'Install Cursor Agent CLI from https://cursor.com/install? [y/N]'
assert_contains "$output" 'LAUNCHER_INTERACTIVE=PASS'
grep -F 'curl -fsS https://cursor.com/install -o ' "$cursor_calls" \
  >/dev/null ||
  fail 'launcher did not stage the official Cursor installer'
```

Add these exact adjacent cases:

```sh
: >"$cursor_calls"
output=$(PATH="$HOME/.local/bin:$cursor_bin" \
  CURSOR_INSTALL_CALLS="$cursor_calls" \
  /bin/sh "$asset" --client cursor --non-interactive)
assert_contains "$output" 'LAUNCHER_NON_INTERACTIVE=PASS'
[ ! -s "$cursor_calls" ] ||
  fail 'launcher reinstalled a healthy cursor-agent'

rm -f "$HOME/.local/bin/cursor-agent"
: >"$cursor_calls"
if output=$(PATH="$cursor_bin" CURSOR_INSTALL_CALLS="$cursor_calls" \
  /bin/sh "$asset" --client cursor --non-interactive 2>&1)
then
  fail 'non-interactive launcher installed cursor-agent'
fi
assert_contains "$output" 'Result: DEPENDENCY_MISSING'
[ ! -s "$cursor_calls" ] ||
  fail 'non-interactive launcher called the Cursor installer'

: >"$cursor_calls"
if output=$(
  printf 'n\n' |
  PATH="$cursor_bin" CURSOR_INSTALL_CALLS="$cursor_calls" \
  /usr/bin/script -qec \
    "/bin/sh $asset --client cursor" /dev/null 2>&1
)
then
  fail 'launcher accepted declined Cursor installation'
fi
assert_contains "$output" 'Result: DEPENDENCY_MISSING'
[ ! -s "$cursor_calls" ] ||
  fail 'declined Cursor installation called curl'

for cursor_mode in failure invalid; do
  rm -f "$HOME/.local/bin/cursor-agent"
  : >"$cursor_calls"
  if output=$(
    printf 'y\n' |
    PATH="$cursor_bin" \
    CURSOR_INSTALL_CALLS="$cursor_calls" \
    CURSOR_INSTALL_MODE="$cursor_mode" \
    CURSOR_SUCCESS_INSTALLER="$cursor_success" \
    CURSOR_FAILURE_INSTALLER="$cursor_failure" \
    CURSOR_INVALID_INSTALLER="$cursor_invalid" \
    /usr/bin/script -qec \
      "/bin/sh $asset --client cursor" /dev/null 2>&1
  )
  then
    fail "launcher accepted $cursor_mode Cursor installation"
  fi
  assert_contains "$output" 'Result: DEPENDENCY_MISSING'
done
```

- [ ] **Step 2: Run the launcher test and verify RED**

Run:

```bash
sh tests/launcher.sh
```

Expected: FAIL because the launcher currently reaches the package CLI without
printing the Cursor installation confirmation or invoking the fake `curl`.

- [ ] **Step 3: Generalize the existing package installer minimally**

Replace `ensure_jq` in `release/bootstrap.sh.in` with the same logic parameterized
by one command/package name:

```sh
ensure_os_dependency() {
  dependency=$1
  command -v "$dependency" >/dev/null 2>&1 && return
  [ "$non_interactive" -eq 0 ] ||
    die DEPENDENCY_MISSING "Remediation: install $dependency"
  [ -t 1 ] && ( : </dev/tty ) 2>/dev/null ||
    die TTY_REQUIRED \
      "Retry with: $PROGRAM --client $client --non-interactive"

  installer=
  for candidate in apt-get dnf brew; do
    if command -v "$candidate" >/dev/null 2>&1; then
      installer=$candidate
      break
    fi
  done
  [ -n "$installer" ] ||
    die DEPENDENCY_MISSING "Remediation: install $dependency"

  printf 'Missing dependency: %s. Install with %s (may request sudo)? [y/N] ' \
    "$dependency" "$installer" >/dev/tty
  IFS= read -r answer </dev/tty || answer=
  case "$answer" in
    y|Y|yes|YES) ;;
    *) die DEPENDENCY_MISSING "Remediation: install $dependency" ;;
  esac

  case "$installer" in
    apt-get)
      run_as_root apt-get update &&
        run_as_root apt-get install -y "$dependency" ||
        die DEPENDENCY_MISSING "Remediation: install $dependency"
      ;;
    dnf)
      run_as_root dnf install -y "$dependency" ||
        die DEPENDENCY_MISSING "Remediation: install $dependency"
      ;;
    brew)
      brew install "$dependency" ||
        die DEPENDENCY_MISSING "Remediation: install $dependency"
      ;;
  esac
  command -v "$dependency" >/dev/null 2>&1 ||
    die DEPENDENCY_MISSING "Remediation: install $dependency"
}
```

Replace the existing `ensure_jq` call with:

```sh
ensure_os_dependency jq
```

- [ ] **Step 4: Implement automatic Cursor installation before package execution**

Add this function after `ensure_os_dependency`:

```sh
ensure_cursor_agent() {
  [ "$client" = cursor ] || return
  if command -v cursor-agent >/dev/null 2>&1 &&
     cursor-agent mcp login --help >/dev/null 2>&1
  then
    return
  fi
  [ "$non_interactive" -eq 0 ] ||
    die DEPENDENCY_MISSING \
      'Missing dependency: cursor-agent; https://cursor.com/install'
  command -v bash >/dev/null 2>&1 ||
    die DEPENDENCY_MISSING 'Missing dependency: bash'
  printf 'Install Cursor Agent CLI from https://cursor.com/install? [y/N] ' \
    >/dev/tty
  IFS= read -r answer </dev/tty || answer=
  case "$answer" in
    y|Y|yes|YES) ;;
    *)
      die DEPENDENCY_MISSING \
        'Missing dependency: cursor-agent; https://cursor.com/install'
      ;;
  esac
  ensure_os_dependency curl
  cursor_installer=$bootstrap_root/cursor-install.sh
  curl -fsS https://cursor.com/install -o "$cursor_installer" ||
    die DEPENDENCY_MISSING 'Cursor Agent installer download failed'
  bash "$cursor_installer" ||
    die DEPENDENCY_MISSING 'Cursor Agent installer failed'
  PATH=$HOME/.local/bin:$PATH
  export PATH
  cursor-agent --version >/dev/null 2>&1 &&
    cursor-agent mcp login --help >/dev/null 2>&1 ||
    die DEPENDENCY_MISSING \
      'Installed Cursor Agent lacks required MCP login support'
}
```

Call `ensure_cursor_agent` immediately after `ensure_os_dependency jq` and
before constructing the package CLI invocation.

- [ ] **Step 5: Run focused launcher checks**

Run:

```bash
sh -n release/bootstrap.sh.in
sh tests/launcher.sh
```

Expected: both PASS; Codex jq tests remain unchanged, Cursor installs into the
temporary HOME and continues in the same launcher process.

- [ ] **Step 6: Commit the launcher slice**

```bash
git add release/bootstrap.sh.in tests/launcher.sh
git commit -m "fix: install cursor agent during bootstrap"
```

### Task 2: Package fails early and Cursor MCP ignores caller cwd

**Files:**
- Modify: `tests/bootstrap.sh`
- Modify: `tests/connectors.sh`
- Modify: `bin/beroka-governance`

**Interfaces:**
- Consumes: `require_client CLIENT`, `connector_probe CLIENT`, and
  `run_oauth CLIENT`.
- Produces: `cursor_mcp ARGS...`, which preserves HOME and credentials but
  executes `cursor-agent mcp ARGS...` from `/`.

- [ ] **Step 1: Add a failing direct-bootstrap atomicity test**

Before the first successful bootstrap in `tests/bootstrap.sh`, invoke Cursor
while no `cursor-agent` exists:

```sh
if output=$($CLI bootstrap "$repo" --client cursor \
  --version v1.1.0 --non-interactive 2>&1)
then
  fail 'direct Cursor bootstrap accepted a missing cursor-agent'
fi
assert_contains "$output" 'Result: DEPENDENCY_MISSING'
[ ! -e "$XDG_CONFIG_HOME/beroka-ai-governance/active-release" ] ||
  fail 'missing cursor-agent changed active-release state'
```

- [ ] **Step 2: Add the exact `$HOME` connector regression**

In the fake `cursor-agent` in `tests/connectors.sh`, record the working
directory and reproduce Cursor's global/project collision:

```sh
printf 'cursor-agent %s | %s\n' "$*" "$PWD" >>"$CALLS"
```

For `mcp list`, return this only when governance leaked the caller's HOME:

```sh
if [ "$PWD" = "$HOME" ]; then
  printf '%s\n' 'atlassian: not loaded (needs approval)'
  exit 0
fi
```

Then add:

```sh
printf '%s\n' auth-required >"$XDG_CONFIG_HOME/fake-cursor-health"
: >"$CALLS"
if output=$(cd "$HOME" &&
  $CLI setup-connectors --client cursor --non-interactive 2>&1)
then
  fail 'Cursor HOME setup accepted missing authentication'
fi
assert_contains "$output" 'Result: ATLASSIAN_AUTH_REQUIRED'
assert_not_contains "$output" 'CONNECTOR_HEALTH_UNAVAILABLE'
if grep '^cursor-agent mcp .* | ' "$CALLS" |
  grep -Fv ' | /' >/dev/null
then
  fail 'governance ran Cursor MCP outside the neutral directory'
fi
```

Keep the existing interactive Cursor OAuth test and additionally assert its
`mcp login atlassian` entry ends in ` | /`.

- [ ] **Step 3: Run both tests and verify RED**

Run:

```bash
sh tests/bootstrap.sh
sh tests/connectors.sh
```

Expected: bootstrap FAILS because active release state changes before the
missing client is rejected; connectors FAIL because `cursor-agent mcp list`
runs from `$HOME` and becomes `CONNECTOR_HEALTH_UNAVAILABLE`.

- [ ] **Step 4: Add the shared neutral-directory helper**

Add beside `oauth_command` in `bin/beroka-governance`:

```sh
cursor_mcp() {
  (cd / && cursor-agent mcp "$@")
}
```

Replace only governance-owned Cursor MCP executions:

```sh
cursor_mcp login --help
cursor_mcp list
cursor_mcp list-tools atlassian
cursor_mcp login atlassian
```

Do not change the printed remediation string from
`cursor-agent mcp login atlassian`.

- [ ] **Step 5: Validate the selected client before package installation**

In `cmd_bootstrap`, call:

```sh
require_client "$bs_client"
```

after client selection and before release resolution or `cmd_install`. The
launcher-installed Cursor Agent is already on `PATH`, while direct calls now
fail before active release, enrollment, or instruction changes.

- [ ] **Step 6: Run focused package checks**

Run:

```bash
sh -n bin/beroka-governance
sh tests/bootstrap.sh
sh tests/connectors.sh
```

Expected: all PASS; the `$HOME` regression returns
`ATLASSIAN_AUTH_REQUIRED`, and every logged Cursor MCP call uses `/`.

- [ ] **Step 7: Commit the package slice**

```bash
git add bin/beroka-governance tests/bootstrap.sh tests/connectors.sh
git commit -m "fix: isolate cursor mcp setup from caller cwd"
```

### Task 3: Declare the `v1.0.1` hotfix and one-command recovery

**Files:**
- Modify: `VERSION`
- Modify: `README.md`
- Modify: `handbook.md`
- Modify: `PACKAGE-DESIGN.md`
- Modify: `tests/release.sh`

**Interfaces:**
- Consumes: the existing public release launcher and explicit `--upgrade`
  contract.
- Produces: one documented affected-developer command pinned to `v1.0.1`.

- [ ] **Step 1: Change release assertions first**

Replace the current version assertions in `tests/release.sh` with:

```sh
[ "$(cat "$ROOT/VERSION")" = v1.0.1 ] ||
  fail 'VERSION is not v1.0.1'

require_text README.md '`v1.0.1` is the current supported capability release.'
reject_text README.md '`v1.0.0` is the current supported capability release.'
require_text handbook.md \
  '`v1.0.1` là capability release được hỗ trợ hiện tại.'
reject_text handbook.md \
  '`v1.0.0` là capability release được hỗ trợ hiện tại.'
require_text PACKAGE-DESIGN.md \
  '`v1.0.1` is the current supported capability release.'
reject_text PACKAGE-DESIGN.md \
  '`v1.0.0` is the current supported capability release.'
```

Add these behavior assertions:

```sh
require_text README.md \
  'gh release download v1.0.1 --repo beroka-vn/beroka-ai-governance'
require_text README.md \
  'Bootstrap installs a missing Cursor Agent after one confirmation.'
require_text handbook.md \
  'Bootstrap tự cài Cursor Agent còn thiếu sau một lần xác nhận.'
require_text PACKAGE-DESIGN.md \
  'Cursor MCP commands run from `/`'
```

- [ ] **Step 2: Run release checks and verify RED**

Run:

```bash
sh tests/release.sh
```

Expected: FAIL because `VERSION` and the three current-release statements are
still `v1.0.0`, and the hotfix behavior is undocumented.

- [ ] **Step 3: Update version and user documentation**

Set `VERSION` to:

```text
v1.0.1
```

Replace the current supported capability release in `README.md`,
`handbook.md`, and `PACKAGE-DESIGN.md` with `v1.0.1`.

Add one recovery command only in `README.md`:

```bash
bash -e -o pipefail -c 'gh release download v1.0.1 --repo beroka-vn/beroka-ai-governance --pattern bootstrap.sh --output - | sh -s -- --client cursor --upgrade'
```

Use this README section:

````markdown
### Cursor v1.0.0 hotfix

Bootstrap installs a missing Cursor Agent after one confirmation. Developers
upgrading from `v1.0.0` run this once; installation and Atlassian connector
setup continue in the same process:

```bash
bash -e -o pipefail -c 'gh release download v1.0.1 --repo beroka-vn/beroka-ai-governance --pattern bootstrap.sh --output - | sh -s -- --client cursor --upgrade'
```
````

Use this handbook sentence without duplicating the command:

```markdown
Bootstrap tự cài Cursor Agent còn thiếu sau một lần xác nhận; developer đang ở
`v1.0.0` dùng đúng một lệnh trong
[Cursor v1.0.0 hotfix](README.md#cursor-v100-hotfix).
```

Keep the existing automation statement that the selected client is
preinstalled.

In `PACKAGE-DESIGN.md`, update the launcher prerequisite contract: Codex and
Claude remain preinstalled; interactive Cursor bootstrap installs a missing
Cursor Agent from `https://cursor.com/install`; Cursor MCP commands run from
`/`.

- [ ] **Step 4: Run documentation and release checks**

Run:

```bash
sh tests/documentation-architecture.sh
sh tests/release.sh
```

Expected: both PASS and the existing generic quick-start, upgrade, and CI code
blocks remain byte-for-byte compatible with their release-test fixtures.

- [ ] **Step 5: Commit the release declaration**

```bash
git add VERSION README.md handbook.md PACKAGE-DESIGN.md tests/release.sh
git commit -m "docs: declare v1.0.1 cursor hotfix"
```

### Task 4: Full verification and issue-ready handoff

**Files:**
- Verify only; no source file is created.

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces: fresh validation evidence for a pull request or later authorized
  release publication.

- [ ] **Step 1: Run syntax and whitespace checks**

```bash
sh -n bin/beroka-governance
sh -n release/bootstrap.sh.in
git diff --check origin/main...HEAD
```

Expected: all exit zero.

- [ ] **Step 2: Run the complete repository gate**

```bash
sh tests/smoke.sh
sh tests/connectors.sh
sh tests/bootstrap.sh
sh tests/documentation-architecture.sh
sh tests/release.sh
sh tests/launcher.sh
sh tests/routing.sh
```

Expected: every script prints its PASS footer and exits zero.

- [ ] **Step 3: Inspect the final branch**

```bash
git status --short
git log --oneline --decorate origin/main..HEAD
git diff --stat origin/main...HEAD
```

Expected: clean worktree, the design/plan and three implementation commits are
present, and changes remain limited to the files named by this plan.

- [ ] **Step 4: Report the one user command**

Hand off exactly:

```bash
bash -e -o pipefail -c 'gh release download v1.0.1 --repo beroka-vn/beroka-ai-governance --pattern bootstrap.sh --output - | sh -s -- --client cursor --upgrade'
```

State that tag creation, GitHub Release publication, issue comments, push, and
pull request creation were not performed without separate authorization.
