# Handbook cài đặt và rollout AI agent integrations

Tài liệu này là preflight và rollout guide cho Backend/Frontend workflow.
Developer cài integration một lần trên client đang dùng; agent kiểm tra lại
trước khi đọc hoặc ghi GitHub, Jira hay Confluence.

## Phạm vi team workflow

| Hệ thống | Target cần truy cập |
| --- | --- |
| GitHub Backend | [`hungnx77/Beroka_Backend`](https://github.com/hungnx77/Beroka_Backend) |
| GitHub Frontend | Exact repository theo task trong [`cuongngo1801-beroka`](https://github.com/cuongngo1801-beroka?tab=repositories) |
| Jira Backend | Project `BB`, board `34` |
| Jira Frontend | Project `BF`, board `35` |
| Confluence Backend | Space [`Beroka-backend`](https://beroka.atlassian.net/wiki/spaces/Berokaback/overview) |
| Confluence Frontend | Space [`Beroka-frontend`](https://beroka.atlassian.net/wiki/spaces/Berokafron) |

Read access chỉ cần cho selected profile, requested operation và selected integration profile.
BE–FE targets chỉ áp dụng khi reviewed beroka-be-fe integration profile được chọn và operation yêu cầu.
Write access chỉ dùng trong project/repository/space thuộc request đã xác nhận. Nếu
Frontend repository chưa resolve thành một exact URL, agent dừng external write
và hỏi developer; không tự chọn từ organization list.

## Quy tắc chung

- Dùng account cá nhân của developer và least privilege.
- Không đặt token trong repository, `.env` được commit, `AGENTS.md`,
  `CLAUDE.md`, Cursor rules, prompt, log hoặc tài liệu này.
- Dùng OAuth/connector UI được client hỗ trợ. GitHub credential do client hoặc
  OS keyring sở hữu; governance không nhận hoặc lưu developer token.
- Không cấu hình đồng thời plugin và MCP trùng nhau cho cùng provider.
- Cài đặt không đồng nghĩa với authorization. Developer phải hoàn thành OAuth
  và chọn đúng GitHub/Atlassian account.
- Agent không tạo live issue/page chỉ để kiểm tra connector.

## Kích hoạt trong repository

Package chỉ áp dụng cho repository được đăng ký rõ ràng. Backend và Frontend
đều được hỗ trợ chính thức. Mỗi lần bootstrap chỉ đăng ký đúng một repository
đã truyền rõ; chạy lại explicit trong repository còn lại khi cần. Governance
không tự scan hoặc đăng ký mọi repository trên máy. Linux, macOS và Windows qua
WSL là target environments; native Windows PowerShell không thuộc V1.

### Điều kiện trước khi cài

- Có Git, POSIX shell, `gh` đã cài và đã authenticate cho private repository;
  package không chứa credentials. Nếu thiếu GitHub authentication, chạy
  `gh auth login --hostname github.com --web`.
- `$HOME/.local/bin` phải có trong `PATH` sau khi `install` để gọi
  `beroka-governance`.
- Dùng một annotated SemVer tag đã được review và publish. `v1.0.1` là
  corrective release được hỗ trợ hiện tại. `v1.0.0` vẫn immutable nhưng đã được
  thay thế cho onboarding; mọi tag publish sau đó là immutable.
- Repository đích là Git repository có đúng một canonical GitHub remote khớp
  repository identity. Tên local remote không bắt buộc là `origin`. Review
  diff của repository đích bằng PR trước khi merge; không đăng ký trực tiếp
  vào production branch chỉ để thử nghiệm.
- macOS, WSL và fresh-session checks của Codex IDE, Claude Code, Cursor vẫn
  **UNVERIFIED** cho đến khi release-gate evidence được ghi nhận. Linux
  automated shell smoke không thay thế các manual checks này.

### Bootstrap và install

Từ Git root của repository cần đăng ký, chạy release launcher đã authenticate.
`gh` phải được cài và authenticate cho private repository; nếu thiếu auth, chạy
`gh auth login --hostname github.com --web`. Launcher chỉ chạy package sau khi
xác minh annotated tag và embedded commit:

```bash
(
  set -eu
  bootstrap_file=$(mktemp "${TMPDIR:-/tmp}/beroka-bootstrap.XXXXXX")
  trap 'rm -f "$bootstrap_file"' EXIT HUP INT TERM
  gh auth setup-git --hostname github.com
  gh release download \
    --repo beroka-vn/beroka-ai-governance \
    --pattern bootstrap.sh \
    --output "$bootstrap_file"
  sh "$bootstrap_file" --client codex --non-interactive
)
```

`gh auth setup-git --hostname github.com` cấu hình Git để dùng lại
client-owned GitHub OAuth cho private HTTPS clone của launcher.
Không yêu cầu, in, sao chép, ghi log hoặc lưu token.

Command không mở browser. Nếu OAuth thiếu hoặc invalid, installation và
registration vẫn được giữ nguyên, command trả
`ATLASSIAN_AUTH_REQUIRED` cùng remediation của selected client. Hoàn tất OAuth
do client sở hữu rồi chạy lại đúng command trên.

Thay `codex` bằng `claude` hoặc `cursor`; `--client` là bắt buộc và mỗi lần
chạy chỉ chọn đúng một client. Lặp lại setup một lần cho mỗi client trên mỗi
execution environment. Các client enabled cùng load một pinned governance
release; đổi model bên trong cùng một client không cần setup lại.

Repository đã đăng ký luôn giữ lock hiện tại; không silent upgrade. Sau khi
command PASS, review và commit các managed files qua PR rồi mở **fresh AI session**;
command không tự commit hoặc push.

AUTH_PENDING means installation and repository registration succeeded but the
selected client's OAuth is incomplete. Run the printed Resume command; do not
delete or recreate the lock.

CONNECTOR_HEALTH_UNAVAILABLE means governance could not classify connector
health before the 15-second deadline. External connector-dependent writes
remain blocked. Run the printed Resume command after connectivity recovers.

A client started from a VS Code Remote SSH terminal runs on the remote host.
Repository entrypoints are shared through Git, while the CLI, connector, and
OAuth setup are local to that remote execution environment.

### Thiếu context hoặc lựa chọn chưa rõ

Target repository phải được truyền explicit; bootstrap không scan máy để tự
chọn repository. Interactive mode hiển thị các client/release choices đã xác
minh và yêu cầu developer chọn đúng một option. Nếu AI chưa resolve được target
hoặc quyết định ảnh hưởng scope, ownership, routing hay external write, AI phải
**Chuyển quyết định cho developer**, nêu các option và dừng cho đến khi
developer xác nhận exact target. Không tự suy đoán theo tên gần giống.

Non-interactive mode không chọn thay developer và không mở browser. Thiếu
client, exact version, authentication hoặc routing phải trả stable fail-closed
result cùng remediation phù hợp.

### Chọn đúng một client và setup Atlassian connector

Chỉ chạy setup sau khi client đã được cài và có MCP commands cần thiết. Cách
khuyến nghị là luôn chọn rõ đúng một client:

```bash
beroka-governance setup-connectors --client codex
beroka-governance setup-connectors --client claude
beroka-governance setup-connectors --client cursor
```

Mỗi lần chạy chỉ cấu hình client được chọn. Có thể chạy lại rõ ràng cho client
thứ hai; command không tự cấu hình tất cả client đã cài. Nếu bỏ `--client`,
chỉ interactive terminal mới auto-detect: một client thì hỏi xác nhận, nhiều
client thì yêu cầu chọn một, không có client thì trả `DEPENDENCY_MISSING`.

Sau khi tạo connector, interactive mode báo `AUTH_REQUIRED` và hỏi trước khi mở
OAuth flow của client. Non-interactive mode phải dùng explicit `--client`:

```bash
beroka-governance setup-connectors --client codex --non-interactive
```

Mode này không mở browser. Khi credential thiếu, hết hạn hoặc invalid, command
trả `ATLASSIAN_AUTH_REQUIRED` và in đúng một remediation command:

```bash
codex mcp login atlassian
claude
# Trong Claude: /mcp -> atlassian -> Authenticate
cursor-agent mcp login atlassian
```

OAuth state/credential do client hoặc OS keyring sở hữu. Package không yêu cầu,
nhận, in, log hay lưu Atlassian developer API token.

Khi user xác nhận interactive OAuth, governance chạy trực tiếp flow của client
và để client in exact one-time URL hoặc device URL/code ra terminal. Governance
không parse, log hoặc lưu output OAuth đó. Non-interactive không tạo OAuth
session nên dynamic URL chưa tồn tại; output chỉ có exact remediation command.

GitHub push hoặc tạo PR dùng operation riêng:

```bash
beroka-governance preflight /path/to/repo \
  --client codex \
  --operation github-write
```

Operation này chỉ chạy `gh auth status --hostname github.com`. Nếu auth còn
khỏe thì trả `PASS` và không login lại. Nếu GitHub yêu cầu auth, interactive
mode hỏi xác nhận rồi chạy flow hiển thị URL:

```bash
gh auth login --hostname github.com --web
```

Non-interactive mode không mở browser và trả `GITHUB_AUTH_REQUIRED` cùng command
trên. `github-write` không đọc Jira/Confluence routing hoặc Atlassian connector,
vì vậy vẫn dùng được khi routing đang thiếu hoặc pending.

### Register, Doctor, update, rollback và removal

```bash
repo=/srv/beroka/backend
release=v1.0.1

beroka-governance register "$repo" --version "$release" --client codex
git -C "$repo" diff -- .beroka-governance.lock AGENTS.md
beroka-governance doctor "$repo"
beroka-governance doctor "$repo" --client codex

beroka-governance update "$repo" --to "$release"
beroka-governance rollback "$repo" --to "$release"
beroka-governance unregister "$repo"
beroka-governance uninstall
```

Thêm Claude Code là explicit và additive; command này chỉ thêm `CLAUDE.md`,
không rewrite Codex entrypoint đang có:

```bash
beroka-governance bootstrap "$repo" --client claude
git -C "$repo" diff -- .beroka-governance.lock CLAUDE.md
```

`register`, `update`, `rollback` và `unregister` hỗ trợ `--dry-run`. Review và
merge application-repository diff trước khi package version mới có hiệu lực,
sau đó mở **fresh agent session**. `unregister` chỉ xóa managed markers, lock và
Cursor rule; `uninstall` chỉ xóa local package khi registry không còn repository
đăng ký. `uninstall --force` cũng không sửa application repositories.

### Repository routing lifecycle

`context` load general rules cùng **selected profile** và **selected integration
profile**; không load mọi Backend, Frontend và standalone profile. Khi chưa có
baseline routing đã xác minh, agent vẫn có thể làm source-only work, nhưng mọi
external write phụ thuộc routing phải chờ `preflight` mới ngay trước operation.
Routing chỉ lấy từ default branch baseline vừa fetch, không lấy từ local branch,
index hay worktree.

Repository standalone mới dùng file `.beroka-governance.conf` strict sau:

```text
SCHEMA_VERSION=1
PROFILE=standalone
JIRA_PROJECT_KEY=APP
CONFLUENCE_SPACE_KEY=APP
CONFLUENCE_ROOT_CONTENT_ID=123456
CONFLUENCE_ROOT_CONTENT_TYPE=page
INTEGRATION_PROFILE=none
CROSS_REPO_POLICY=explicit-only
```

Backend profile được review dùng schema sau; `JIRA_BOARD_ID` optional và chỉ
cần cho board/backlog/sprint verification:

```text
SCHEMA_VERSION=1
PROFILE=backend
JIRA_PROJECT_KEY=BB
JIRA_BOARD_ID=34
CONFLUENCE_SPACE_KEY=Berokaback
CONFLUENCE_ROOT_CONTENT_ID=123456
CONFLUENCE_ROOT_CONTENT_TYPE=page
INTEGRATION_PROFILE=beroka-be-fe
CROSS_REPO_POLICY=profile-controlled
```

`JIRA_BOARD_ID` là routing data, không bao giờ chứng minh Board capability.

Lifecycle onboarding:

1. Không có trusted hoặc local routing thì `ROUTING_REQUIRED`.
2. Thêm file trên branch đầu tiên thì `ROUTING_CHANGE_PENDING` cho đến khi PR
   routing được merge; local routing không được dùng cho external write.
3. PR đầu tiên phải tham chiếu Jira issue được tạo thủ công hoặc issue trong
   **central governance onboarding project**, độc lập với pending routing.
4. Branch, commit, push, current-repository Issue và PR vẫn được phép khi
   routing pending.
5. Sau merge, mở fresh session rồi chạy `context` mới và `preflight` mới trước
   external write phụ thuộc routing.
6. Khi offline, `context` chỉ block routing-dependent external writes;
   source-only work vẫn tiếp tục.

### Confluence capability hierarchy

Backend canonical documentation uses one `Backend Capability Registry` and
globally unique Folder names:

```text
<Scope> — <Domain> — <Transport>
<Scope> — <Domain> — <Capability group> — <Transport>
```

Scope is `Shared`, `Derivatives`, or `Underlying`; domain is `Market` or `User`;
transport is `API` or `WebSocket`. Examples include
`Shared — Market — API`, `Derivatives — User — WebSocket`,
`Shared — Market — Market Indices — API`, and
`Shared — Market — Market Indices — WebSocket`. Do not create repeated generic
Folders named only `Market`, `User`, `API`, or `WebSocket`.

Each Capability ID maps one semantic capability, one transport, one Registry
row, and one canonical page. Epic Integration Hubs reference Registry rows.
Frontend module pages use `<Module> — Capability Index` and link exact Backend
content IDs and artifact versions; they never copy contract payloads.

Nếu thiếu exact Registry content ID, scope/domain/transport, parent hoặc
Capability ID, trả `ROUTING_REQUIRED`. Nếu Folder thiếu, trả
`FOLDER_CREATION_REQUIRED`; nếu readback sai parent, trả
`DOC_HIERARCHY_FAILED`. Không fallback sang space root hoặc tìm bằng title gần
giống.

### Lock và thin entrypoints

Register tạo `.beroka-governance.lock` và chỉ entrypoint của client được chọn;
không copy toàn bộ runtime hay templates vào application repository. `CLIENTS`
trong lock là source of truth cho entrypoints managed:

| Client | Managed entrypoint |
| --- | --- |
| Codex | managed block trong root `AGENTS.md` |
| Claude Code | managed block trong root `CLAUDE.md` |
| Cursor | `.cursor/rules/beroka-governance.mdc` |

Entrypoints mỏng (thin) chỉ route agent tới release đã pin. Khi mở session mới,
Codex, Claude Code hoặc Cursor đọc entrypoint theo client, xác minh lock và
canonical remote đã discover, rồi chạy `beroka-governance context` để load
runtime English từ cùng exact release. Client không có trong `CLIENTS` không có
Beroka-managed entrypoint; managed content chưa được list là `ENTRYPOINT_DRIFT`.
Repository chưa register không được package áp dụng.

### Rehydrate context và boundary đa client

Sau context compaction, session resume hoặc new chat, agent phải chạy lại
`beroka-governance context "$PWD"` trước governed action tiếp theo; không dựa
vào governance detail chỉ còn trong conversation summary. Source work đang làm
không cần bỏ, nhưng phải rehydrate governance trước planning, implementation
hoặc external action tiếp theo. Mỗi external write cần operation-specific
preflight mới ngay trước action; không reuse kết quả từ trước compaction.

Codex personal instructions thuộc `~/.codex/AGENTS.md`; shared instructions
thuộc repository `AGENTS.md`. Claude personal instructions thuộc
`~/.claude/CLAUDE.md` hoặc ignored `CLAUDE.local.md`; shared instructions thuộc
repository `CLAUDE.md`. Cursor personal instructions thuộc User Rules;
governance chỉ sở hữu `.cursor/rules/beroka-governance.mdc` và không sửa Cursor
rules khác.

Enable client mới là one-time reviewed repository change: thêm client vào
`CLIENTS` và tạo managed entrypoint của client đó. Bootstrap configures the
selected client locally trước review. Repository enablement trở thành shared sau merge;
execution environment khác chỉ configure connector/OAuth của client đó sau này
khi health yêu cầu.
CLI hard-enforce technical stop conditions cho registration,
release/lock/entrypoint integrity, routing, connector/authentication và
operation preflight. Workflow rules như ownership, issue scope, branch use và
validation vẫn instruction-driven trừ khi CI, hooks, branch protection hoặc
platform policy khác enforce chúng. Personal hoặc repository-local instructions
có thể narrow governance nhưng không authorize bypass central technical stop
condition.

## Quyền tối thiểu

| Provider | Read bắt buộc | Write chỉ khi request cần | Không yêu cầu mặc định |
| --- | --- | --- | --- |
| GitHub | Current repository; exact counterpart chỉ khi selected integration/operation cần | Create/update Issue, comment, branch/PR trong owned scope | Repository admin, secret management, destructive actions |
| Jira | Project của selected profile; board/backlog chỉ khi operation yêu cầu và Board capability được chứng minh | Create/edit/assign/link/transition item trong confirmed project | Jira admin, sửa board filter/workflow/scheme |
| Confluence | Space/root của selected profile; shared Integration Hub chỉ khi selected integration/operation cần | Tạo/update Folder/page trong confirmed owning space | Space admin, delete/move hàng loạt |

Permission không được mở rộng chỉ để làm preflight pass. Nếu action thực tế cần
quyền cao hơn, agent báo exact target/action và chờ người có authority.

## Codex

GitHub có thể tiếp tục dùng OpenAI plugin:

```bash
codex plugin add github@openai-curated
codex plugin list
```

Atlassian dùng MCP do package setup quản lý:

```bash
beroka-governance setup-connectors --client codex
```

Nếu cần re-login, remediation là `codex mcp login atlassian`. Package chỉ ghi
Atlassian MCP URL bằng Codex config API; Codex/OS keyring giữ OAuth credential.
GitHub connector và authentication vẫn là rollout riêng.

## Claude Code

Atlassian dùng user-scoped remote MCP và OAuth:

```bash
beroka-governance setup-connectors --client claude
```

Nếu cần authenticate lại, package in launch command `claude` và bước trong
client `/mcp -> atlassian -> Authenticate`. Claude Code không dùng
`claude mcp login atlassian`; package chỉ dùng `mcp add`, `mcp get`, `mcp list`
cho setup/health, rồi launch `claude` sau khi developer xác nhận interactive.

Governance không cấu hình GitHub hosted MCP hoặc nhận developer token cho
Claude. GitHub push/PR dùng `github-write` preflight và OAuth flow của `gh`;
GitHub app khác phải được developer cài qua official client UI, để client/keyring
sở hữu authentication.

## Cursor

### Atlassian

Đảm bảo Cursor Agent CLI đã được cài, rồi chạy:

```bash
beroka-governance setup-connectors --client cursor
```

Command merge Atlassian server vào user-level `~/.cursor/mcp.json` mà không xóa
server khác. Nếu cần re-login, remediation là
`cursor-agent mcp login atlassian`.

### GitHub

Governance không cấu hình GitHub hosted MCP hoặc nhận developer token cho
Cursor. Nếu developer cài GitHub app qua official **Install in Cursor** flow,
Cursor/keyring phải sở hữu authentication; không ghi credential vào project
`.cursor/mcp.json`. Restart Cursor rồi kiểm tra server trong **Settings → Tools
& Integrations → MCP Tools**. Cursor Agent CLI có thể kiểm tra thêm:

```bash
cursor-agent mcp list
cursor-agent mcp list-tools github
cursor-agent mcp list-tools atlassian
```

## Preflight connector bắt buộc

Sau khi `beroka-governance doctor <repo>` trả `Result: PASS`, agent chạy
`beroka-governance doctor <repo> --client <client>`, `context`, rồi preflight
mới ngay trước mỗi routing-dependent external write:

```bash
beroka-governance preflight <repo> --client <client> --operation jira-write
```

Preflight xác minh routing trước bất kỳ OAuth prompt nào. Governance-only
`doctor <repo>`, `context`, `show`, register/update/rollback/remove không kiểm
tra hoặc kích hoạt OAuth. GitHub authentication vẫn được complete riêng trên
từng client.

1. Xác định authenticated GitHub và Atlassian account của đúng client được
   chọn.
2. Load chỉ general rules, selected `PROFILE` và selected allowlisted
   `INTEGRATION_PROFILE` từ trusted routing baseline.
3. Kiểm tra target và capability đúng operation: `jira-write` chỉ cần selected
   Jira project; `jira-board-verify` chỉ kiểm tra `JIRA_BOARD_ID` khi operation
   đó được yêu cầu, và Board capability vẫn phải được chứng minh riêng.
4. `confluence-write` chỉ kiểm tra selected space và root content; Page/Folder
   hierarchy chỉ theo root type đã route. Mọi `cross-repo-write` hiện trả
   `ROUTING_REQUIRED` trước khi inspect client vì central release chưa có exact
   reviewed counterpart/workflow mapping và CLI chưa nhận exact target.
   `INTEGRATION_PROFILE=none` không trigger BE–FE hoặc cross-repository
   discovery.
5. Chỉ kiểm tra write permission khi request thực tế cần routing-dependent
   external write; không tạo test record.

Kết quả đạt yêu cầu:

```text
Client: <selected client>
Routing baseline commit: <fresh default-branch commit>
Profile: <selected profile>
Integration profile: <selected integration profile>
Cross-repository policy: <selected policy>
Operation: <requested operation>
Jira project: <only for jira-write>
Capability: <only for the requested capability>
Capability state: SUPPORTED
Result: PASS
```

Output `PASS` trên áp dụng cho operation có exact routed target và reviewed
capability evidence; `cross-repo-write` hiện không có PASS hoặc “next
preflight”.

Khi thất bại, agent dừng phần phụ thuộc và báo đúng nguyên nhân:

```text
Integration blocked
- Client:
- Provider: GitHub | Atlassian
- Failure: PLUGIN_MISSING | AUTH_REQUIRED | WRONG_ACCOUNT | PERMISSION_DENIED | CONNECTION_FAILED
- Required target/action:
- Setup section:
- Work that can continue safely:
```

Không diễn giải `AUTH_REQUIRED` hoặc `PERMISSION_DENIED` thành record không tồn
tại. Sau khi developer sửa kết nối, agent phải chạy lại preflight.

## Release gate trước khi publish tag

`v1.0.1` là corrective release được hỗ trợ hiện tại. `v1.0.0` vẫn immutable
nhưng đã được thay thế cho onboarding; mọi tag publish sau đó là immutable.
Trước mọi push tag,
coordinator phải nhận:

- exact local branch, candidate version và release commit;
- full automated validation output;
- xác nhận canonical remote chưa có candidate tag;
- full interactive/non-interactive developer bootstrap workflow; và
- các manual checks còn `UNVERIFIED`.

Không tạo hoặc push tag trước khi coordinator duyệt report này. Sau khi release
PR merge, fetch canonical `main`, xác minh exact merge commit, rồi tạo
annotated candidate tag tại commit đó. Nếu remote đã có candidate tag thì dừng;
không force hoặc overwrite.

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

- [ ] Cài release đã publish bằng latest release launcher từ canonical
      repository.
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

## Troubleshooting nhanh

| Hiện tượng | Kiểm tra |
| --- | --- |
| Không thấy tools | Plugin/MCP status, restart client hoặc mở session mới |
| OAuth lặp lại | Đúng account, browser callback, workspace admin policy |
| Đọc được nhưng không ghi được | Repository/project/space permission của account |
| GitHub `401`/`403` | Chạy `gh auth status`; nếu cần thì dùng exact OAuth remediation được preflight in ra. |
| Jira có nhưng Confluence không có | Atlassian product access và space permission riêng |
| Kết quả thuộc nhầm team | Authenticated identity và target URL/project/space |

CLI fail closed với các stable result codes sau:

| Result | Ý nghĩa / xử lý |
| --- | --- |
| `GOVERNANCE_NOT_READY` | Thiếu release hoặc registration hợp lệ; cài release đúng hoặc sửa lock. |
| `GOVERNANCE_ACCESS_DENIED` | Không đọc được central private repository; kiểm tra Git/GitHub access, không thêm credential vào repo. |
| `REPOSITORY_NOT_REGISTERED` | Thiếu lock/managed entrypoint hợp lệ; register đúng repository qua reviewed PR. |
| `REMOTE_MISMATCH` | Canonical remote không khớp `REPOSITORY` trong lock; dùng đúng clone hoặc sửa qua lifecycle CLI. |
| `VERSION_MISMATCH` | Tag, commit hoặc installed release khác lock; install/pin lại reviewed version. |
| `ENTRYPOINT_DRIFT` | Managed content bị sửa ngoài CLI; restore/reconcile qua reviewed CLI lifecycle. |
| `WORKTREE_CONFLICT` | Target entrypoint có uncommitted changes; review, commit hoặc stash thay đổi trước khi chạy lại. |
| `DEPENDENCY_MISSING` | Client hoặc command dependency chưa có; cài đúng client/dependency rồi chạy lại explicit setup. |
| `CONNECTOR_MISSING` | Atlassian connector thiếu hoặc URL hiện tại xung đột; chạy `setup-connectors --client <client>` và review config. |
| `ATLASSIAN_AUTH_REQUIRED` | OAuth thiếu, hết hạn hoặc invalid; chạy exact remediation command được in ra. |
| `GITHUB_AUTH_REQUIRED` | GitHub OAuth thiếu, hết hạn hoặc invalid cho `github-write`; chạy exact remediation command được in ra. |
| `PASS` | Governance và, khi có `--client`, connector/authentication health đều đạt. |

Routing và selected-client preflight trả các result sau:

| Result | Remediation |
| --- | --- |
| `ROUTING_REQUIRED` | Add exact routing through the reviewed onboarding workflow. |
| `ROUTING_INVALID` | Fix the strict schema on a branch and merge it. |
| `ROUTING_CHANGE_PENDING` | Review and merge the routing PR; do not use local routing for writes. |
| `ROUTING_VERIFICATION_REQUIRED` | Restore authenticated remote access and rerun fresh preflight. |
| `DEPENDENCY_MISSING` | Install the explicitly selected client/helper. |
| `CONNECTOR_MISSING` | Run `beroka-governance setup-connectors --client <client>`. |
| `ATLASSIAN_AUTH_REQUIRED` | Run the exact remediation command printed for the selected client. |
| `CONNECTOR_CAPABILITY_REQUIRED` | Use a supported operation/client or add a reviewed compatibility record after an isolated pilot. |

`SUPPORTED`, `UNSUPPORTED` và `UNKNOWN` là operation-scoped. Folder và Board
không bao giờ fallback sang Page, space root, JQL hoặc guessed capability.

## Tài liệu chính thức

- [GitHub MCP Server](https://github.com/github/github-mcp-server)
- [GitHub MCP for Codex](https://github.com/github/github-mcp-server/blob/main/docs/installation-guides/install-codex.md)
- [GitHub MCP for Claude Code](https://github.com/github/github-mcp-server/blob/main/docs/installation-guides/install-claude.md)
- [GitHub MCP for Cursor](https://github.com/github/github-mcp-server/blob/main/docs/installation-guides/install-cursor.md)
- [Atlassian Rovo MCP getting started](https://support.atlassian.com/atlassian-rovo-mcp-server/docs/getting-started-with-the-atlassian-remote-mcp-server/)
- [Claude Code MCP](https://code.claude.com/docs/en/mcp)
- [Cursor MCP](https://docs.cursor.com/context/model-context-protocol)
