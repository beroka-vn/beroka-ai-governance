# AGENTS.md

## Cursor Cloud specific instructions

`beroka-ai-governance` is a single product: a user-scoped **POSIX shell CLI**
(`bin/beroka-governance`) plus governance docs, templates, and the Central
repository catalog under `runtime/`. There is **no application server, database,
or web UI** in this repo, so there is no long-running service to start — the CLI
is invoked on demand and the "app" is exercised by running it directly.

### Toolchain (already present in the cloud image)

Runtime deps are system tools only: `sh` (`/bin/sh` is `dash`), `git`, `jq`,
`gh`, `curl`. There are no language package managers, lockfiles, or `node_modules`
— nothing to `npm/pip/uv install`. The update script only ensures the CLI is
executable.

### Lint

Pure shell; lint == syntax check with `sh -n`. There is no ESLint/shellcheck
config in the repo (shellcheck is not installed):

```sh
for f in bin/beroka-governance release/bootstrap.sh.in tests/*.sh; do sh -n "$f"; done
```

### Test (release gate)

Run each test with `sh` (they are `#!/bin/sh`/dash scripts; some are not marked
executable, so invoke via `sh`, not `./`). The canonical gate is listed in
`handbook.md` / `PACKAGE-DESIGN.md`. Full sweep:

```sh
for t in tests/*.sh; do echo "== $t =="; sh "$t" || break; done
```

Each test is hermetic: it creates its own temp `$HOME`/XDG dirs and fake
`gh`/`codex`/`claude`/`cursor-agent` binaries, so **no network, secrets, or live
GitHub/Atlassian access is required**. The full suite takes ~70s.

### Run the CLI

`beroka-governance --help` lists commands. Read-only commands that work fully
offline against a local git repo: `context REPO`, `doctor REPO`,
`show REPO governance|handbook|workflow|template <name>`.

Non-obvious startup caveats when driving the CLI directly:

- The CLI installs into user-owned paths (`~/.local/bin`, `$XDG_*`). To avoid
  touching the real cloud `HOME`, always run against isolated dirs by exporting
  `HOME`, `XDG_DATA_HOME`, `XDG_CONFIG_HOME`, `XDG_STATE_HOME`, and
  `BEROKA_GOV_BIN_DIR` to temp locations (this is exactly what `tests/*.sh` do).
- `install VERSION` clones the private release repo over HTTPS. Offline, mirror
  the working tree into a local git repo, tag it with the value in `VERSION`,
  and add
  `git config --global url."file://<mirror>".insteadOf https://github.com/beroka-vn/beroka-ai-governance.git`
  so `install` resolves the tag+commit with no GitHub auth.
- Routing comes from the Central catalog in `runtime/repositories/beroka-vn/`
  (e.g. `Beroka_Backend` → Jira `BB`, board `34`, Confluence `Berokaback`).
  A repo is matched by its exact `origin` URL; set the git remote accordingly.
- Routed Backend/Frontend commands require a stored GitHub role
  (`$XDG_CONFIG_HOME/beroka-ai-governance/github-role` = `BE`/`FE`/`FULL_STACK`),
  normally written by `bootstrap` after a live GitHub Teams lookup. Seed this
  file to exercise routed profiles offline.
- `doctor REPO --client cursor` (and other `--client` paths) enforce full client
  enrollment (e.g. it returns `CURSOR_USER_RULE_REQUIRED` until the Cursor User
  Rule is acknowledged via `bootstrap`). For a release+routing health check
  only, run `doctor REPO` without `--client`.
- Live `preflight` for `jira-write`/`github-write` needs real `gh` auth and a
  live Atlassian MCP connector for the enrolled client — out of scope for
  offline runs and not required to validate the CLI.
