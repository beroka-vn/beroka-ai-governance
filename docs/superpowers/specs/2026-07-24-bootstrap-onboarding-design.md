# Bootstrap Onboarding Design

## Goal

Replace the repetitive install, connector setup, registration, and doctor
sequence with one first-class command while preserving pinned releases,
explicit client selection, operation-scoped OAuth, and reviewed repository
changes.

```bash
beroka-governance bootstrap "$PWD" --client codex
```

The same command may be invoked from a checked-out release before the CLI is
installed:

```bash
sh bin/beroka-governance bootstrap "$PWD" --client codex
```

Bootstrap is part of `bin/beroka-governance`; there is no second orchestration
script whose behavior could drift from the CLI.

## Command

```text
beroka-governance bootstrap REPO
  [--client codex|claude|cursor]
  [--version vX.Y.Z]
  [--non-interactive]
```

Unknown, duplicate, token, and secret-bearing flags are rejected by the normal
CLI parser.

## Release Selection

When the repository already contains a valid `.beroka-governance.lock`,
bootstrap uses the exact `VERSION` and `COMMIT` in that lock. It never silently
upgrades an existing registration. A conflicting `--version` returns
`VERSION_MISMATCH` and directs the maintainer to the explicit update workflow.

For an unregistered repository:

- Interactive mode defaults to `latest`. `latest` is resolved online to the
  highest canonical remote annotated tag matching exactly `vMAJOR.MINOR.PATCH`.
  Local tags, branches, lightweight tags, and prerelease names are ignored.
- Bootstrap prints the resolved tag and peeled commit and asks for confirmation
  before installing or modifying the repository.
- The lock stores only the resolved exact version and commit; it never stores
  the word `latest`.
- `--version vX.Y.Z` overrides interactive latest resolution.
- Non-interactive mode requires an exact `--version vX.Y.Z`.
- Failed or unverifiable remote resolution returns
  `RELEASE_RESOLUTION_REQUIRED`; it never falls back to `main`, a cached tag,
  or an unverified local version.

The first official team rollout must happen only after a non-legacy stable tag
has been published. Until then, latest may resolve to an older published tag
and must not be presented as the new release.

## Client Selection

`--client` has highest priority and selects exactly one client for the entire
invocation: dependency validation, connector configuration, OAuth health, and
connector-aware doctor.

Without `--client`, only an interactive terminal may continue:

- exactly one supported executable detected: show it and ask for confirmation;
- multiple detected: ask the user to select exactly one;
- none detected: return `DEPENDENCY_MISSING`.

Non-interactive mode without `--client` fails usage validation. Bootstrap never
configures all installed clients. Running bootstrap again with another explicit
client remains supported.

Bootstrap does not install Codex, Claude Code, Cursor, `jq`, or system packages.
It validates the selected client and its required commands. Missing software
returns `DEPENDENCY_MISSING` with exact remediation. Connector configuration
runs only after the Governance release is installed.

## Workflow

Bootstrap performs these stages:

1. Resolve the canonical Git repository and selected client.
2. Resolve an existing lock or an exact confirmed release.
3. Validate the complete repository/client prerequisites before mutation.
4. Install or verify the exact Governance release.
5. Register or reconcile the repository with the exact release.
6. Configure the selected client's Atlassian connector.
7. Check connector authentication health.
8. Run base and connector-aware doctor.
9. Print the resolved version, selected client, repository status, and next
   action.

For a first registration, bootstrap creates the normal managed files but never
commits or pushes them. It prints `Repository changes: REVIEW_REQUIRED` and
requires the maintainer to review and merge those files through the repository's
normal pull-request workflow.

For an already registered clean repository, rerunning bootstrap must not create
a repository diff. It may repair missing local package installation or the
selected client's connector.

Install and repository registration remain transaction-safe within their
existing boundaries. OAuth belongs to the client and cannot participate in a
cross-system rollback. If the user declines OAuth or authentication fails, the
completed install/registration remains resumable and bootstrap returns the
existing provider-specific auth-required result.

## OAuth

Bootstrap configures only Atlassian because connector setup is part of local
client onboarding. It does not check GitHub auth: GitHub authentication remains
scoped to `preflight --operation github-write`.

Healthy Atlassian auth is reused. Missing, expired, or invalid auth:

- interactive: print `AUTH_REQUIRED`, ask once, then run the selected client's
  supported provider-owned OAuth flow directly;
- non-interactive: return `ATLASSIAN_AUTH_REQUIRED` and the exact remediation
  command without creating an OAuth session or opening a browser.

Governance never accepts, parses, prints itself, logs, or stores developer API
tokens, OAuth URLs, device codes, OAuth state, or credentials.

## Repository and Session Behavior

Registration activates Governance through the managed `AGENTS.md`, `CLAUDE.md`,
and Cursor rule only after those changes are reviewed in the application
repository. Bootstrap prints:

```text
Next: review and merge repository changes, then start a fresh AI session
```

An existing registered repository instead prints:

```text
Next: start a fresh AI session in the repository
```

Bootstrap does not guess Jira projects, Confluence spaces, routing, integration
profiles, or cross-repository dependencies. A repository without reviewed
routing can perform source and current-repository GitHub work, while
routing-dependent Jira/Confluence writes remain blocked.

## Tests

All tests use temporary HOME, XDG, Codex, GitHub, repository, and remote
directories with fake clients and no real credentials. They cover:

- registered repo derives exact version/commit from lock and produces no diff;
- unregistered interactive repo resolves latest annotated stable tag, confirms,
  installs, and registers the exact result;
- lightweight, prerelease, malformed, local-only, and branch refs are ignored;
- non-interactive unregistered repo without exact version fails closed;
- remote resolution failure returns `RELEASE_RESOLUTION_REQUIRED`;
- explicit client is reused for dependency, connector, OAuth, and doctor;
- one detected client is confirmed, multiple require selection, and none return
  `DEPENDENCY_MISSING`;
- no invocation configures more than one client;
- auth-required behavior delegates to the existing provider-owned flow;
- rerunning bootstrap is safe and another explicit client can be configured;
- managed repository files are never committed or pushed automatically;
- published `v1.0.0` remains unchanged.
