# Cursor Agent Bootstrap Hotfix Design

**Date:** 2026-07-29
**Issue:** [GitHub #23](https://github.com/beroka-vn/beroka-ai-governance/issues/23)
**Target release:** `v1.0.1`

## Goal

Let developers affected by both Cursor failures reported on issue #23 recover
with one copy-paste command:

- bootstrap automatically installs a missing Cursor Agent after one
  confirmation; and
- connector setup does not misread the global Cursor MCP configuration as a
  project-local server requiring approval.

Keep installation interactive and fail-closed without silently changing
governance versions or accepting credentials.

## Supported Recovery Command

A developer with the active `v1.0.0` release runs:

```bash
bash -e -o pipefail -c 'gh release download v1.0.1 --repo beroka-vn/beroka-ai-governance --pattern bootstrap.sh --output - | sh -s -- --client cursor --upgrade'
```

This is one shell invocation. `gh` remains an authenticated prerequisite for
the private repository. The explicit release tag and `--upgrade` preserve the
existing rule that governance never upgrades silently.

New Cursor installations use the existing onboarding command without
`--upgrade`; this hotfix does not combine first installation and upgrade
semantics.

## Root Cause

There are two root causes in `v1.0.0`:

1. It maps the selected `cursor` client to `cursor-agent`, which is required
   for Cursor MCP inspection and login. The launcher offers to install `jq`,
   but does not check or install Cursor Agent CLI before the package installs
   the release and client instruction. Connector setup then returns
   `DEPENDENCY_MISSING`, leaving a valid but incomplete installation.
2. Governance writes the Atlassian MCP server to global
   `~/.cursor/mcp.json`, then runs `cursor-agent mcp` in the caller's current
   directory. When that directory is `$HOME`, Cursor Agent
   `2026.07.23-e383d2b` loads the same file as both global and project-local
   configuration and reports `atlassian: not loaded (needs approval)`.
   Governance does not classify this state and returns
   `CONNECTOR_HEALTH_UNAVAILABLE` on every retry.

Cursor IDE installation and the Cursor Agent CLI executable are separate
requirements on Linux and WSL. The official Cursor CLI installer places
`cursor-agent` under the user's installation directory, commonly
`$HOME/.local/bin`.

## Interactive Launcher Behavior

For `--client cursor`, the verified release launcher must resolve the client
dependency before installing or upgrading governance:

1. If `cursor-agent` is already executable and exposes the required MCP login
   command, continue without prompting.
2. If `cursor-agent` is missing, print its name and ask:

   ```text
   Install Cursor Agent CLI from https://cursor.com/install? [y/N]
   ```

3. On confirmation, ensure `curl` and `bash` are available. Install a missing
   `curl` through the launcher's existing interactive OS-package flow.
4. Download the official installer to the launcher's temporary directory with
   `curl -fsS`; do not execute a partial download through a pipeline.
5. Execute the staged installer with `bash`, prepend `$HOME/.local/bin` to the
   current launcher's `PATH`, and verify:

   ```bash
   cursor-agent --version
   cursor-agent mcp login --help
   ```

6. Only after verification succeeds may the launcher install or upgrade
   governance and start connector setup.

The launcher does not edit `.bashrc`, `.profile`, or Cursor's internal settings
database. The existing user-scoped binary directory contract remains
authoritative.

## Failure Behavior

Interactive decline returns:

```text
Result: DEPENDENCY_MISSING
Missing dependency: cursor-agent
Remediation: bash -e -o pipefail -c 'gh release download v1.0.1 --repo beroka-vn/beroka-ai-governance --pattern bootstrap.sh --output - | sh -s -- --client cursor --upgrade'
```

Download, installer, executable, or MCP-surface failure returns the same stable
result with a specific reason. Governance remains on `v1.0.0` because the
dependency gate runs before the release transition. Vendor-installer files are
owned by Cursor and are not rolled back by governance.

`--non-interactive` never installs OS packages or Cursor Agent CLI and never
opens a prompt. It returns `DEPENDENCY_MISSING` with the official Cursor CLI
installation URL and the exact command to resume.

Codex and Claude behavior is unchanged. This hotfix does not add automatic
installation for other vendor clients.

## Direct Package Bootstrap

The package-level `cmd_bootstrap` must call the existing selected-client
dependency validation before `cmd_install`. This keeps direct package
invocations from creating the same partial governance state when they bypass
the release launcher.

Automatic Cursor installation remains launcher-only. Direct package,
`setup-connectors`, Doctor, and preflight commands fail closed with remediation
when their selected client dependency is absent.

## Cursor MCP Working Directory

All governance-owned `cursor-agent mcp` inspection and login commands run from
the neutral directory `/`, while retaining the user's real `HOME` and
credentials. This keeps Cursor's global `~/.cursor/mcp.json` distinct from any
project-local `.cursor/mcp.json`, regardless of where the developer invoked
bootstrap.

Use one small shared shell helper for Cursor MCP calls. Do not modify Cursor's
approval store and do not run `cursor-agent mcp enable`: governance owns a
global connector, not a project-local approval.

True authentication states continue through the existing
`cursor-agent mcp login atlassian` flow. Genuine transport or unclassified
vendor failures remain fail-closed as `CONNECTOR_HEALTH_UNAVAILABLE`.

## Idempotency and Security

- An existing healthy `cursor-agent` is preserved and never reinstalled.
- Re-running the explicit `v1.0.1 --upgrade` command is safe when `v1.0.1` is
  already active.
- The installer runs only after an interactive confirmation.
- Only the official HTTPS Cursor installer endpoint is used.
- Raw installer failure is not reported as `PASS`.
- Governance never requests, reads, prints, logs, or stores Cursor or Atlassian
  credentials.
- Connector OAuth remains client-owned and starts only through the existing
  confirmation flow.

## Repository Changes

Keep the implementation focused on:

- `release/bootstrap.sh.in`: interactive Cursor dependency installation and
  verification before package execution;
- `bin/beroka-governance`: package-level fail-fast dependency validation and
  neutral working directory for all Cursor MCP commands;
- `tests/launcher.sh`, `tests/bootstrap.sh`, and `tests/connectors.sh`: isolated
  regression coverage;
- `README.md` and `handbook.md`: the one-command recovery path and the Cursor
  CLI prerequisite; and
- `PACKAGE-DESIGN.md`: the updated release-launcher dependency contract.

Do not change routing, capability resolution, OAuth ownership, catalog data, or
other client adapters.

## Validation

Tests use temporary HOME/XDG directories and fake `curl` and `cursor-agent`
executables. They must prove:

- an existing `cursor-agent` skips installation;
- confirming installation creates a usable fake client and continues in the
  same launcher process;
- decline, non-interactive mode, download failure, and invalid installed
  command fail before governance installation or upgrade;
- direct package bootstrap with a missing client fails before active-release
  state changes;
- Cursor connector setup invoked from `$HOME` reaches the existing
  authentication flow instead of `CONNECTOR_HEALTH_UNAVAILABLE`;
- every governance-owned Cursor MCP inspection and login runs from `/`;
- the affected-developer documentation contains exactly one recovery command;
  and
- all existing shell release gates remain green.

A WSL2 Ubuntu Noble pilot must run the published `v1.0.1` asset and confirm that
the one recovery command reaches Cursor connector setup without requiring
`source`, shell restart, or a second governance command.

## Release Boundary

The implementation and tests land through one issue branch and pull request.
Tag creation and GitHub Release publication require separate explicit
authorization after the reviewed pull request is merged. The published
`v1.0.0` tag remains immutable.

The release procedure must verify the remote tag set immediately before
creating `v1.0.1`; stale local tags are not release authority.

## Acceptance Criteria

- The affected `v1.0.0` developer runs one copy-paste upgrade command.
- Missing Cursor Agent CLI requires one Cursor installation confirmation, then
  bootstrap continues without another command. Existing OS-package prompts may
  still appear when `curl` or `jq` is also missing.
- Running the one command from `$HOME` does not require
  `cursor-agent mcp enable`, a directory change, or a second governance command.
- Decline and non-interactive execution remain fail-closed.
- No governance version or connector state changes before dependency
  verification succeeds.
- Existing client, routing, and credential boundaries remain unchanged.
- Isolated shell tests and the WSL2 pilot pass before release publication.
