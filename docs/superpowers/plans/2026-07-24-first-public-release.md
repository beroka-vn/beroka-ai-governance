# First Public Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prepare the first public `v1.0.0` release locally with official Backend and Frontend onboarding, then stop before every GitHub push.

**Architecture:** Reuse the tested `beroka-governance bootstrap` command without changing CLI behavior. Add one POSIX release-readiness test and update the three existing rollout documents so release identity, repository scope, interactive choices, and developer decision ownership are unambiguous.

**Tech Stack:** POSIX shell, Git, existing Markdown documentation

## Global Constraints

- `v1.0.0` is the first public stable release.
- Each bootstrap invocation registers exactly one explicit Backend or Frontend Git repository.
- Interactive mode presents safe options and transfers ambiguous decisions to the developer.
- Non-interactive mode requires exact repository, client, and version and fails closed.
- Never request, print from storage, log, or store API tokens or OAuth credentials.
- Do not push a branch, tag, or GitHub Release before the developer approves the pre-push report.
- Do not push the unpublished local `v1.1.0` candidate.

---

### Task 1: Lock the release contract with a failing test

**Files:**
- Create: `tests/release.sh`

**Interfaces:**
- Consumes: `VERSION`, `README.md`, `handbook.md`, and `PACKAGE-DESIGN.md`
- Produces: executable `tests/release.sh` with stable release-readiness assertions

- [ ] **Step 1: Add the release-readiness test**

```sh
#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

require_text() {
  file=$1 text=$2
  grep -F "$text" "$ROOT/$file" >/dev/null ||
    fail "missing [$text] in $file"
}

reject_text() {
  file=$1 text=$2
  if grep -F "$text" "$ROOT/$file" >/dev/null; then
    fail "forbidden [$text] in $file"
  fi
}

[ "$(cat "$ROOT/VERSION")" = v1.0.0 ] ||
  fail 'VERSION is not v1.0.0'

require_text README.md '`v1.0.0` is the first public stable release'
require_text README.md 'Backend and Frontend repositories'
require_text README.md 'repo=$(git rev-parse --show-toplevel)'
require_text handbook.md 'Chuyển quyết định cho developer'
require_text PACKAGE-DESIGN.md \
  '`v1.0.0` is the first public stable release'

for file in README.md handbook.md PACKAGE-DESIGN.md; do
  reject_text "$file" 'immutable legacy test sample'
  reject_text "$file" 'Backend-only'
  reject_text "$file" 'do not register a Frontend repository'
done

printf '%s\n' 'First public release readiness: PASS'
```

- [ ] **Step 2: Make the test executable**

Run:

```bash
chmod 755 tests/release.sh
```

- [ ] **Step 3: Run the test and verify RED**

Run:

```bash
sh tests/release.sh
```

Expected: `FAIL: VERSION is not v1.0.0`.

---

### Task 2: Publish the Backend/Frontend bootstrap workflow in the package

**Files:**
- Modify: `VERSION`
- Modify: `README.md:7-80`
- Modify: `handbook.md:35-100`
- Modify: `handbook.md:430-560`
- Modify: `PACKAGE-DESIGN.md:74-78`
- Modify: `PACKAGE-DESIGN.md:425-440`
- Modify: `tests/bootstrap.sh:304-307`
- Test: `tests/release.sh`

**Interfaces:**
- Consumes: existing `bootstrap REPO [--client ...] [--version ...] [--non-interactive]`
- Produces: one official copy-paste onboarding flow and fail-closed decision guidance for both repository types

- [ ] **Step 1: Set the package release identity**

Replace `VERSION` with:

```text
v1.0.0
```

In `README.md`, replace candidate language with:

```markdown
`v1.0.0` is the first public stable release. The bootstrap checkout is
temporary; bootstrap installs the pinned release and user CLI, registers one
explicit Backend or Frontend repository, configures one selected client, and
runs Doctor.
```

In `PACKAGE-DESIGN.md`, replace the legacy/candidate policy with:

```markdown
Each release is an immutable annotated SemVer tag. `v1.0.0` is the first public
stable release. After publication, its tag must never be moved or replaced.
```

- [ ] **Step 2: Replace the quick-start block**

Use the same interactive block in `README.md` and `handbook.md`:

```bash
repo=$(git rev-parse --show-toplevel)
bootstrap_dir=$(mktemp -d "${TMPDIR:-/tmp}/beroka-governance-bootstrap.XXXXXX")

git clone --depth 1 --single-branch --branch v1.0.0 \
  https://github.com/beroka-vn/beroka-ai-governance.git \
  "$bootstrap_dir/repo"

sh "$bootstrap_dir/repo/bin/beroka-governance" bootstrap "$repo"
```

Document the explicit form:

```bash
sh "$bootstrap_dir/repo/bin/beroka-governance" bootstrap \
  "$repo" --client codex
```

Document the automation form:

```bash
sh "$bootstrap_dir/repo/bin/beroka-governance" bootstrap \
  "$repo" \
  --client codex \
  --version v1.0.0 \
  --non-interactive
```

- [ ] **Step 3: Make ambiguous context developer-owned**

Add this handbook rule:

```markdown
### Thiếu context hoặc lựa chọn chưa rõ

Interactive mode hiển thị các client/repository/release choices đã xác minh và
yêu cầu developer chọn đúng một option. Nếu quyết định ảnh hưởng scope,
ownership, routing hoặc external write, AI phải **Chuyển quyết định cho
developer**, nêu các option và dừng cho đến khi developer xác nhận exact target.
Không tự suy đoán theo tên gần giống.

Non-interactive mode không chọn thay developer và không mở browser. Thiếu
client, exact version, authentication hoặc routing phải trả stable fail-closed
result cùng remediation phù hợp.
```

Replace Backend-only rollout language with:

```markdown
Backend và Frontend đều được hỗ trợ chính thức. Mỗi lần bootstrap chỉ đăng ký
đúng một repository đã truyền rõ; chạy lại explicit trong repository còn lại
khi cần. Governance không tự scan hoặc đăng ký mọi repository trên máy.
```

- [ ] **Step 4: Convert the candidate release gate to the official gate**

Replace `handbook.md` from `## Release gate trước khi publish tag` through the
end of `## Deployment checklist sau khi publish` with:

````markdown
## Release gate trước khi publish tag

`v1.0.0` là first public stable release. Trước mọi push, coordinator phải nhận:

- exact local branch và release commit;
- full automated validation output;
- xác nhận canonical remote chưa có `v1.0.0`;
- full interactive/non-interactive developer bootstrap workflow; và
- các manual checks còn `UNVERIFIED`.

Không tạo hoặc push tag trước khi coordinator duyệt report này. Sau khi release
PR merge, fetch canonical `main`, xác minh exact merge commit, xóa local test
candidate, rồi tạo annotated `v1.0.0` tại commit đó. Nếu remote đã xuất hiện
tag cùng tên thì dừng; không force hoặc overwrite.

Automated gate:

```bash
sh -n bin/beroka-governance tests/*.sh
sh tests/release.sh
sh tests/bootstrap.sh
sh tests/connectors.sh
sh tests/documentation-architecture.sh
sh tests/smoke.sh
```

`tests/routing.sh` phải chạy trong isolated clone không kế thừa unpublished
local tags. Linux automated evidence không thay thế manual macOS/WSL và fresh
client-session checks.

Manual gate:

- [ ] **UNVERIFIED** — Bootstrap một exact Backend repository trong isolated
      HOME/XDG, review managed-file diff và chạy governance/client Doctor.
- [ ] **UNVERIFIED** — Bootstrap một exact Frontend repository độc lập với cùng
      checks; không reuse Backend routing.
- [ ] **UNVERIFIED** — Fresh Codex, Claude Code và Cursor sessions load đúng
      pinned release trên các client thuộc rollout.
- [ ] **UNVERIFIED** — Coordinator review full evidence và cho phép push release
      branch/PR, rồi cho phép publish tag sau merge.

Nếu gate fail, không publish. Sửa qua reviewed release PR và chạy lại từ exact
commit mới.

## Deployment checklist sau khi publish

- [ ] Install published `v1.0.0` từ canonical repository.
- [ ] Bootstrap từng Backend/Frontend repository riêng, review và merge
      managed-file diff bằng application-repository PR.
- [ ] Mở fresh agent session và xác minh pinned version bằng Doctor.
- [ ] Merge exact repository routing trước Jira/Confluence/cross-repository
      writes; không dùng pending local routing.
- [ ] Tạo hoặc xác minh Backend Capability Registry và globally unique
      Confluence Folders trước documentation writes.
- [ ] Không tự migration tài liệu Confluence cũ; missing exact content ID hoặc
      parent phải dừng và chuyển quyết định cho developer.
- [ ] Chạy operation-specific preflight ngay trước external write.

Chỉ đăng ký repository developer đã chọn rõ; không bulk-register và không
silent update.
````

In `PACKAGE-DESIGN.md`, state:

```markdown
The first public rollout supports explicit Backend and Frontend repository
registration. Each repository keeps an independent pinned lock and routing
configuration.
```

- [ ] **Step 5: Remove the obsolete local tag-object assertion**

Delete this block from `tests/bootstrap.sh`:

```sh
[ "$(git -C "$ROOT" rev-parse v1.0.0^{tag} 2>/dev/null)" = \
  1f2db6bd75cf9d9a68d501c351fb2455448e04e1 ] ||
  fail 'real v1.0.0 tag object changed'
```

Tag immutability is checked by the publication gate against the canonical
remote; the unpublished local candidate is intentionally replaced once.

- [ ] **Step 6: Run the release test and verify GREEN**

Run:

```bash
sh tests/release.sh
```

Expected: `First public release readiness: PASS`.

- [ ] **Step 7: Scan for conflicting rollout language**

Run:

```bash
! rg -n \
  'immutable legacy test sample|Backend-only|do not register a Frontend repository|v1\.1\.0 is the current unpublished candidate' \
  README.md handbook.md PACKAGE-DESIGN.md
```

Expected: exit `0` with no matches.

- [ ] **Step 8: Commit**

```bash
git add VERSION README.md handbook.md PACKAGE-DESIGN.md \
  tests/bootstrap.sh tests/release.sh
git commit -m "docs: prepare first public release"
```

---

### Task 3: Verify and produce the pre-push handoff

**Files:**
- Verify only; no source changes expected

**Interfaces:**
- Consumes: the local release-preparation commit
- Produces: evidence-backed developer workflow and an exact no-push handoff

- [ ] **Step 1: Run all project checks**

Run:

```bash
sh -n bin/beroka-governance tests/*.sh
sh tests/release.sh
sh tests/bootstrap.sh
sh tests/connectors.sh
sh tests/documentation-architecture.sh
sh tests/smoke.sh
```

Run `tests/routing.sh` from an isolated clone that does not inherit unpublished
local candidate tags.

Expected: every suite prints `PASS`.

- [ ] **Step 2: Run integrity scans**

Run:

```bash
git diff --check origin/main...HEAD
! rg -n '(ghp_|github_pat_|access_token|refresh_token)' \
  bin tests README.md handbook.md PACKAGE-DESIGN.md governance.md workflow.md \
  templates runtime examples
git status --short
```

Expected: no diff errors, credential matches, or uncommitted files.

- [ ] **Step 3: Verify publication has not happened**

Run:

```bash
test -z "$(git ls-remote --tags origin \
  refs/tags/v1.0.0 'refs/tags/v1.0.0^{}')"
gh release view v1.0.0 \
  --repo beroka-vn/beroka-ai-governance >/dev/null 2>&1 && exit 1 || true
```

Expected: no canonical remote tag and no GitHub Release.

- [ ] **Step 4: Stop before push**

Report:

- the full interactive and non-interactive developer bootstrap workflows;
- Backend and Frontend registration behavior;
- managed files the developer must review;
- fresh-session, Doctor, and preflight steps;
- local branch, commit, validation evidence, and remote tag absence; and
- the exact post-approval PR, merge, annotated-tag, and GitHub Release sequence.

Do not run `git push`, create a pull request, delete/recreate the local
`v1.0.0` tag, or create a GitHub Release in this task.
