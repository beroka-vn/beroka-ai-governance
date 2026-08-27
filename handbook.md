# Handbook cài đặt và rollout AI agent integrations

Tài liệu này hướng dẫn cài governance theo user scope và kiểm tra connector.
Release đã verify cùng client setup thuộc workstation; repository ứng dụng chỉ
được đọc để xác định canonical GitHub origin.

## Phạm vi team workflow

| Hệ thống | Target cần truy cập |
| --- | --- |
| GitHub Backend | [`beroka-vn/Beroka_Backend`](https://github.com/beroka-vn/Beroka_Backend) |
| GitHub Frontend | [`beroka-vn/Beroka_Frontend`](https://github.com/beroka-vn/Beroka_Frontend) |
| Jira Backend | Project `BB`, board `34` |
| Jira Frontend | Project `BF`, board `35` |
| Confluence Backend | Space [`Beroka-backend`](https://beroka.atlassian.net/wiki/spaces/Berokaback/overview) |
| Confluence Frontend | Space [`Beroka-frontend`](https://beroka.atlassian.net/wiki/spaces/Berokafron) |

Read/write access chỉ dùng cho selected profile, requested operation và integration profile. Repository ngoài boundary BE/FE cần exact catalog record; agent không suy đoán từ IDE workspace.
Nếu target hoặc scope chưa rõ, **Chuyển quyết định cho developer**; không suy đoán từ thông tin gần giống.

## Quy tắc chung

- Dùng account cá nhân và least privilege.
- Không đặt token trong repository, prompt, log, hoặc tài liệu. GitHub và Atlassian credential do client hoặc OS keyring sở hữu.
- Agent không tạo live issue/page chỉ để kiểm tra connector.
- Central repository catalog là nguồn routing duy nhất, keyed bằng canonical GitHub origin. Không đoán routing từ tên repository gần giống.
- Catalog changes require an explicitly authorized governance-repository task.

`Application repository changes: NONE`

`Legacy repository metadata: PRESENT_IGNORED`

Legacy tracked files không bị CLI parse, sửa, hay xóa. Repository owner có thể yêu cầu cleanup riêng với scope rõ ràng.

### Điều kiện trước khi cài

- Có POSIX shell, `gh`, `jq`, và selected Codex/Claude client. Interactive Cursor bootstrap tự cài Cursor Agent nếu còn thiếu. Native Windows PowerShell không thuộc V1; dùng WSL trên Windows.
- `gh` phải authenticate để download private release. Không yêu cầu, in, sao chép, ghi log hoặc lưu token.
- `v1.0.15` là capability release được hỗ trợ hiện tại.

### Bootstrap và install

Chạy từ bất kỳ directory nào. Healthy client-owned GitHub OAuth được dùng lại; nếu thiếu authentication, `gh` mới chạy browser OAuth:

```bash
bash -e -o pipefail -c '
  gh auth status --hostname github.com >/dev/null 2>&1 ||
    gh auth login --hostname github.com --web
  gh auth setup-git --hostname github.com
  gh release download \
    --repo beroka-vn/beroka-ai-governance \
    --pattern bootstrap.sh \
    --output - |
    sh -s -- --client codex
'
```

`gh auth setup-git --hostname github.com` dùng lại client-owned GitHub OAuth cho private HTTPS clone. Thay `codex` bằng `claude` hoặc `cursor`; mỗi run chỉ enroll đúng client đã chọn và giữ nguyên healthy setup của các client khác.

Bootstrap có thể hỏi cài `jq` hoặc `curl` bằng `apt-get`, `dnf`, hoặc `brew`. Từ chối trả `DEPENDENCY_MISSING`. Bootstrap tự cài Cursor Agent còn thiếu sau một lần xác nhận. Developer dùng release cũ hơn release được publish mới nhất phải chạy [Upgrade](README.md#upgrade) trước khi thêm client khác. Atlassian OAuth vẫn do client đã chọn sở hữu. Thiếu OAuth trả remediation của client đó; `AUTH_PENDING` không làm mất user setup.

Bootstrap xác minh membership của GitHub Team `beroka-vn/frontend` và
`beroka-vn/backend`, rồi lưu role `FE`, `BE`, hoặc `FULL_STACK` ở user scope.
Không thuộc Team nào trả `GITHUB_ROLE_REQUIRED`; thuộc cả hai Team nhưng chưa
chọn role ở non-interactive mode trả `GITHUB_ROLE_SELECTION_REQUIRED`.
Preflight hợp lệ xác minh lại membership và trả `ROLE_SCOPE_DENIED` nếu role
không cho phép profile của repository. `FULL_STACK` được mở Cursor multi-root
đúng cặp catalog `Beroka_Backend` + `Beroka_Frontend`; governed write phải chỉ
đúng project BB/BF, parent/epic key, hoặc repository target. Target selection ưu
tiên project có cấu trúc đó và không dùng substring path trong `workspace_roots`
làm tín hiệu BE/FE, nên clone tên thư mục sản phẩm thật không bị `TARGET_REQUIRED`
khi đã chỉ đúng một project. Write FULL_STACK không có target vẫn
`TARGET_REQUIRED`. Cursor hook append user bin (`~/.local/bin`) vào PATH khi
thiếu `cursor-agent`/`gh`, tránh `DEPENDENCY_MISSING` mà không shadow executable
đã có sẵn trên PATH. Khi `origin` là fork, governance ưu tiên remote khác có
exact catalog record (ví dụ `beroka`/`upstream`). Nhiều remote cùng một catalog slug
được chấp nhận và ưu tiên `origin`. Confluence documentation is
allow-by-default: ordinary create/update/move is allowed unless the target or
parent is `UNACTIVATED` in the pinned governance release inventory
(`DOCS_UNACTIVATED`). Create/update bodies must carry handoff delta markers
(`Jira:`, `GitHub:`, and a `## Handoff —` section or `Handoff form: child-page`
with `Canonical:`) or
return `HANDOFF_DELTA_REQUIRED`. `confluence-discover` and optional
`confluence-bootstrap-*` remain hierarchy guidance only, not write gates.
An unknown repository returns `NOT_GOVERNED`, loads no governance rules, and
passes through Cursor hooks without inheriting BE/FE routing.

Repository registration is a reviewed governance-repository change: add the
exact canonical GitHub slug at
`runtime/repositories/<owner>/<repository>.conf`, validate its profile and
routing, merge it through review, and publish a new immutable release. Users
then upgrade their user-scoped installation. The retired local `register`
command and application-repository files are not registration paths.

Cursor Individual không có supported CLI để ghi User Rules. Với `cursor`, copy
User Rule được in ra vào **Cursor Settings > Rules** một lần, rồi xác nhận khi
bootstrap hỏi. Bootstrap also atomically installs documented global local hooks
and preserves personal hooks. Doctor reports `Instruction: USER_CONFIRMED`,
`Runtime hook: INSTALLED`, and `Runtime enforcement: PASS`. Technical artifacts
default to English across clients; chat language does not select artifact
language. Use another language only with `Work-item language: <language>` for
the current generation.

### Upgrade

Khi có same-major release mới, dùng đúng một upgrade path. Nó thay verified user-owned release và giữ enabled clients:

```bash
bash -e -o pipefail -c '
  gh auth status --hostname github.com >/dev/null 2>&1 ||
    gh auth login --hostname github.com --web
  gh auth setup-git --hostname github.com
  gh release download \
    --repo beroka-vn/beroka-ai-governance \
    --pattern bootstrap.sh \
    --output - |
    sh -s -- --client codex --upgrade
'
```

`--upgrade` in-place **không** cho target cũ hơn (`VERSION_MISMATCH`). Lệnh
`rollback` đã retire.

### Downgrade

Muốn về release đã publish cũ hơn (cùng major): uninstall trước, rồi cài từ
launcher của đúng release đó. Ví dụ về `v1.0.10`:

```bash
beroka-governance uninstall --force
bash -e -o pipefail -c '
  gh auth status --hostname github.com >/dev/null 2>&1 ||
    gh auth login --hostname github.com --web
  gh auth setup-git --hostname github.com
  gh release download v1.0.10 \
    --repo beroka-vn/beroka-ai-governance \
    --pattern bootstrap.sh \
    --output - |
    sh -s -- --client cursor
'
```

Đổi `v1.0.10` / `cursor` theo tag và client cần dùng. Không truyền `--version`
cho launcher — `gh release download v1.0.10` đã chọn asset nhúng sẵn `v1.0.10`.
Sau khi cài lại, chạy `beroka-governance context "$PWD"`. User Rule dán trong
**Cursor Settings > Rules** không bị uninstall xóa — tự xóa/sửa nếu không còn
cần.

### Uninstall

Gỡ CLI user-scoped, release data, enrollment, Cursor acknowledgement, GitHub
role file, và managed block trong file instruction cá nhân Codex/Claude. Text
cá nhân ngoài managed block được giữ. Không đụng application repository.

```bash
beroka-governance uninstall --force
```

### Automation / CI

Automation không cài package và không mở browser. Cài sẵn selected client, `gh`, `jq`, authenticate `gh`, rồi chạy:

```bash
bash -e -o pipefail -c '
  gh auth status --hostname github.com >/dev/null 2>&1 || {
    printf "%s\n" \
      "Result: GITHUB_AUTH_REQUIRED" \
      "Remediation: gh auth login --hostname github.com --web" >&2
      exit 1
  }
  gh auth setup-git --hostname github.com
  gh release download \
    --repo beroka-vn/beroka-ai-governance \
    --pattern bootstrap.sh \
    --output - |
    sh -s -- --client codex --non-interactive
'
```

## Context, routing, và preflight

Trong fresh session, chạy `beroka-governance context "$PWD"` trước planning, implementation, hoặc external action. Chạy lại context khi IDE workspace hoặc current Git repository thay đổi, task thêm repository khác, hoặc plan chuyển thành shared/full-stack; shared plan cần exact targets, context riêng cho từng target, và một primary tracking repository. Chạy operation-specific preflight ngay trước mỗi external write. Unknown repository trả compact `NOT_GOVERNED`, không load governance rules, và nằm ngoài governance enforcement.

Active release tìm exact record trong Central repository catalog theo canonical origin. Repository-local metadata không override catalog. Catalog change là governance-repository task được authorize rõ ràng, không phải application repository task.

CLI hard-enforces installation, release integrity, catalog routing, connector, authentication, and operation preflight. Workflow rules are instruction-driven; CI, hooks, branch protection, hoặc platform policy mới hard-enforce behavior.

## Connector health và capability evidence

Chạy `beroka-governance setup-connectors --client codex` chỉ sau khi selected
client đã được cài. Mỗi invocation configures exactly one client.
Missing/expired authentication trả `ATLASSIAN_AUTH_REQUIRED`; với Codex,
remediation là `codex mcp login atlassian`. Interactive OAuth output đi trực
tiếp tới terminal và governance không parse, log, hay store output đó.

Once Atlassian authentication is known to be missing, expired, or invalid,
interactive setup, bootstrap, and preflight start re-authentication
immediately and wait for the selected producer command: Codex uses
`codex mcp login atlassian`, Claude uses
`claude mcp login atlassian --no-browser`, and Cursor uses
`cursor-agent mcp login atlassian`. Claude checks
`claude mcp login --help` for `--no-browser` only at this OAuth boundary; if
unsupported, governance returns `DEPENDENCY_MISSING` with
`Remediation: claude update`.

Non-interactive setup, bootstrap, and preflight and all Doctor paths never
invoke login. Cursor hooks retain non-interactive preflight, and Cursor
first-run still requires its global-MCP configuration confirmation before
OAuth starts. An active agent receiving `ATLASSIAN_AUTH_REQUIRED` stops the
dependent write, runs the selected command in an interactive terminal,
streams producer output so the user receives the one-time login URL, and
waits for completion. It never synthesizes, parses, persists, or copies that
URL or credentials into an issue, commit, or durable log. It then runs a
fresh operation-specific preflight and continues only on `Result: PASS`.

Connector health có 15-second total deadline. Nếu chưa có classifiable record, trả `CONNECTOR_HEALTH_UNAVAILABLE`; unknown không được xem là `PASS`.
Capability được request nhưng không có provider-owned evidence trả
`CONNECTOR_CAPABILITY_REQUIRED`.

Beroka governance yêu cầu global `~/.cursor/mcp.json` cho Atlassian setup.
Cursor vẫn có thể dùng project connector; connector đó được báo
`Project MCP: PRESENT_IGNORED`, không bao giờ bị sửa và không được chấp nhận là
global setup. Compatible global connector giữ idempotent; unknown health
remains fail-closed.

schema-1 compatibility remains for existing releases. `provider-owned evidence` là baseline cho capability decision; `cross-client adapters` chỉ normalize inventory của Codex, Claude Code, và Cursor. Workflow rules are instruction-driven, không phải hard CLI enforcement.

Trước Jira create, resolve exact metadata, search record, create once, rồi read-back key. Indeterminate create trả `CREATION_STATUS_UNKNOWN`; never retry automatically. Confluence create cũng read-back content và parent.

## Capability documentation

Backend Capability Registry lưu canonical cross-Epic capability. Mỗi semantic capability có một transport và một Registry row. Durable hierarchy dùng globally unique Folder theo `<Scope> — <Domain> — <Transport>`; Epic Folder chỉ chứa planning, decision, completion, và Integration Hub. Frontend Capability Index link exact Registry rows và Backend content ID, không copy contract.

## Quyền tối thiểu và release gate

Provider permission là boundary thực thi; instruction không thay thế OAuth, CI, hooks, branch protection, hay platform policy. Không có evidence thì dừng dependent external scope, không tạo record để thử connector.

Trước central release publish, maintainer chạy:

```bash
sh tests/documentation-architecture.sh
sh tests/release.sh
sh tests/bootstrap.sh
sh tests/connectors.sh
sh tests/cursor-hooks.sh
```

Release gate cũng cần evidence fresh sessions cho Codex, Claude Code, và Cursor trên supported environments. Việc publish catalog/release là central governance-repository work và cần authorization riêng.

## Tài liệu chính thức

- [Codex AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md)
- [Claude Code memory](https://code.claude.com/docs/en/memory)
- [Cursor Rules](https://docs.cursor.com/context/rules)
