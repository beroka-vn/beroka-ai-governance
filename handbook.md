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

Read access tới cả `BB` và `BF` là bắt buộc cho counterpart discovery. Write
access chỉ dùng trong project/repository/space thuộc request đã xác nhận. Nếu
Frontend repository chưa resolve thành một exact URL, agent dừng external write
và hỏi developer; không tự chọn từ organization list.

## Quy tắc chung

- Dùng account cá nhân của developer và least privilege.
- Không đặt token trong repository, `.env` được commit, `AGENTS.md`,
  `CLAUDE.md`, Cursor rules, prompt, log hoặc tài liệu này.
- Ưu tiên OAuth/connector UI. Nếu GitHub client bắt buộc PAT, lưu token trong
  user-level secret/config, giới hạn quyền và rotate khi bị lộ.
- Không cấu hình đồng thời plugin và MCP trùng nhau cho cùng provider.
- Cài đặt không đồng nghĩa với authorization. Developer phải hoàn thành OAuth
  và chọn đúng GitHub/Atlassian account.
- Agent không tạo live issue/page chỉ để kiểm tra connector.

## Kích hoạt trong repository

Package chỉ áp dụng cho repository được đăng ký rõ ràng. V1 pilot chỉ đăng ký
một Backend repository do coordinator chỉ định; **không đăng ký Frontend
repository**. Linux, macOS và Windows qua WSL là target environments; native
Windows PowerShell không thuộc V1.

### Điều kiện trước khi cài

- Có Git, POSIX shell và quyền Git/GitHub đã authenticate để clone private
  repository; package không chứa credentials.
- `$HOME/.local/bin` phải có trong `PATH` sau khi `install` để gọi
  `beroka-governance`.
- Dùng một annotated SemVer tag đã được review và publish. `v1.0.0` chưa được
  publish cho đến khi release gate hoàn tất và coordinator cho phép.
- Repository đích là Git repository có `origin` GitHub chính xác. Review diff
  của repository đích bằng PR trước khi merge; không đăng ký trực tiếp vào
  production branch chỉ để thử nghiệm.
- macOS, WSL và fresh-session checks của Codex IDE, Claude Code, Cursor vẫn
  **UNVERIFIED** cho đến khi release-gate evidence được ghi nhận. Linux
  automated shell smoke không thay thế các manual checks này.

### Bootstrap và install

Bootstrap checkout chỉ là tạm thời. `install` tạo local pinned checkout và
user-level CLI; không sửa application repository.

```bash
release=v1.0.0
client=codex # codex | claude | cursor
bootstrap_dir=$(mktemp -d "${TMPDIR:-/tmp}/beroka-governance-bootstrap.XXXXXX")
git clone --depth 1 --single-branch --branch "$release" \
  https://github.com/beroka-vn/beroka-ai-governance.git \
  "$bootstrap_dir/repo"
sh "$bootstrap_dir/repo/bin/beroka-governance" install "$release"
beroka-governance setup-connectors --client "$client"
beroka-governance doctor /srv/beroka/backend
```

`doctor` trước khi register sẽ trả `REPOSITORY_NOT_REGISTERED`; đó là expected.
Sau khi install thành công, có thể xóa bootstrap checkout bằng
`rm -rf "$bootstrap_dir"`.

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
claude mcp login atlassian
cursor-agent mcp login atlassian
```

OAuth state/credential do client hoặc OS keyring sở hữu. Package không yêu cầu,
nhận, in, log hay lưu Atlassian developer API token.

### Register, Doctor, update, rollback và removal

```bash
repo=/srv/beroka/backend
release=v1.0.0

beroka-governance register "$repo" --version "$release"
git -C "$repo" diff -- .beroka-governance.lock AGENTS.md CLAUDE.md .cursor/rules/beroka-governance.mdc
beroka-governance doctor "$repo"
beroka-governance doctor "$repo" --client codex

beroka-governance update "$repo" --to v1.1.0
beroka-governance rollback "$repo" --to "$release"
beroka-governance unregister "$repo"
beroka-governance uninstall
```

`register`, `update`, `rollback` và `unregister` hỗ trợ `--dry-run`. Review và
merge application-repository diff trước khi package version mới có hiệu lực,
sau đó mở **fresh agent session**. `unregister` chỉ xóa managed markers, lock và
Cursor rule; `uninstall` chỉ xóa local package khi registry không còn repository
đăng ký. `uninstall --force` cũng không sửa application repositories.

### Lock và thin entrypoints

Register tạo đúng các artifact package-owned sau, không copy toàn bộ runtime hay
templates vào application repository:

- `.beroka-governance.lock`: source, `REPOSITORY`, pinned `VERSION` và commit SHA;
- managed block trong root `AGENTS.md`;
- managed block hoặc `@AGENTS.md` import trong root `CLAUDE.md`; và
- `.cursor/rules/beroka-governance.mdc`.

Entrypoints mỏng (thin) chỉ route agent tới release đã pin. Khi mở session mới,
Codex, Claude Code hoặc Cursor đọc entrypoint theo client, xác minh lock và
`origin`, rồi chạy `beroka-governance context` để load runtime English từ đúng
release. Repository chưa register không được package áp dụng.

## Quyền tối thiểu

| Provider | Read bắt buộc | Write chỉ khi request cần | Không yêu cầu mặc định |
| --- | --- | --- | --- |
| GitHub | Repositories, Issues, PRs, checks | Create/update Issue, comment, branch/PR trong owned scope | Repository admin, secret management, destructive actions |
| Jira | Browse `BB` và `BF`, board/backlog, users, links | Create/edit/assign/link/transition item trong confirmed project | Jira admin, sửa board filter/workflow/scheme |
| Confluence | Đọc hai team spaces và shared Integration Hub | Tạo/update Folder/page trong confirmed owning space | Space admin, delete/move hàng loạt |

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

Nếu cần re-login, remediation là `claude mcp login atlassian`. Package gọi
Claude Code MCP commands riêng; không giả định chúng giống Codex.

GitHub hosted MCP hiện cần GitHub PAT. Export PAT trong shell rồi thêm ở scope
`local` mặc định; không dùng `--scope project` vì cách đó tạo shared
`.mcp.json`:

```bash
claude mcp add-json github "{\"type\":\"http\",\"url\":\"https://api.githubcopilot.com/mcp\",\"headers\":{\"Authorization\":\"Bearer ${GITHUB_PAT}\"}}"
claude mcp list
claude mcp get github
```

Nếu `GITHUB_PAT` rỗng hoặc Claude version không hỗ trợ `add-json`, dừng và làm
theo official GitHub MCP guide; không hardcode token vào project file.

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

Dùng GitHub hosted MCP tại `https://api.githubcopilot.com/mcp/` theo official
GitHub **Install in Cursor** flow. Nếu cấu hình thủ công, dùng user-level
`~/.cursor/mcp.json`, không dùng project-level `.cursor/mcp.json` vì GitHub PAT
không được chia sẻ qua repository. Giới hạn permission của file nếu có token:

```bash
chmod 600 ~/.cursor/mcp.json
```

Restart Cursor, rồi kiểm tra server có green status trong **Settings → Tools &
Integrations → MCP Tools**. Cursor Agent CLI có thể kiểm tra thêm:

```bash
cursor-agent mcp list
cursor-agent mcp list-tools github
cursor-agent mcp list-tools atlassian
```

## Preflight connector bắt buộc

Sau khi `beroka-governance doctor <repo>` trả `Result: PASS`, agent chạy
`beroka-governance doctor <repo> --client <client>` rồi chạy read-only connector
preflight trước workflow. Governance-only `doctor <repo>`, `context`, `show`,
register/update/rollback/remove không kiểm tra hoặc kích hoạt OAuth. GitHub
authentication vẫn được complete riêng trên từng client.

1. Xác định authenticated GitHub và Atlassian account.
2. Đọc metadata của Backend repository; nếu request thuộc FE, resolve và đọc
   exact Frontend repository.
3. Đọc project `BB`/board `34` và project `BF`/board `35` để counterpart
   discovery hoạt động hai chiều.
4. Đọc hai Confluence spaces và xác nhận agent mở được shared Integration Hub;
   chỉ kiểm tra Folder/page hierarchy của owning space liên quan.
5. Chỉ kiểm tra write permission khi request thực tế cần external write; không
   tạo test record.

Kết quả đạt yêu cầu:

```text
Integration preflight
- Client: Codex | Claude Code | Cursor
- GitHub identity/Backend read: PASS
- GitHub Frontend target/read: PASS | NOT_REQUIRED | TARGET_REQUIRED
- Jira identity/BB read: PASS
- Jira BF read: PASS
- Confluence Beroka-backend read: PASS
- Confluence Beroka-frontend read: PASS
- Shared Integration Hub access: PASS | NOT_REQUIRED | FAIL
- Required write scope: NOT_REQUIRED | PASS | FAIL
- Result: PASS | INTEGRATION_BLOCKED
```

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

Tất cả manual gate bên dưới hiện là **UNVERIFIED**. Không được xem source-tree
smoke trên Linux là bằng chứng thay thế, không được claim `v1.0.0` đã release,
và không được publish tag trước khi hoàn tất đúng thứ tự này:

### Chạy unpublished candidate trong môi trường cô lập

Sau khi implementation PR đã merge, coordinator đã chọn exact Backend pilot,
và local `main` là commit cần kiểm tra, tạo annotated tag **chỉ ở local**. Không
push tag trong bước này:

```bash
governance_repo=$(git rev-parse --show-toplevel)
pilot_repo=/exact/path/from/coordinator
release=v1.0.0

git -C "$governance_repo" switch main
git -C "$governance_repo" pull --ff-only origin main
git -C "$governance_repo" tag -a "$release" -m 'Beroka AI governance package v1.0.0'
```

Tạo một HOME/XDG/PATH riêng cho candidate. Git rewrite này chỉ nằm trong
`$candidate_home/.gitconfig`; nó chuyển exact canonical HTTPS URL sang local
checkout để `install` kiểm tra unpublished tag mà vẫn lưu canonical `origin`:

```bash
original_home=$HOME
original_path=$PATH
candidate_root=$(mktemp -d "${TMPDIR:-/tmp}/beroka-governance-candidate.XXXXXX")
candidate_home=$candidate_root/home
canonical_url=https://github.com/beroka-vn/beroka-ai-governance.git

export HOME=$candidate_home
export XDG_DATA_HOME=$candidate_root/data
export XDG_CONFIG_HOME=$candidate_root/config
export BEROKA_GOV_BIN_DIR=$candidate_root/bin
export PATH=$BEROKA_GOV_BIN_DIR:$original_path
mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$BEROKA_GOV_BIN_DIR"

git config --global url."file://$governance_repo".insteadOf "$canonical_url"
sh "$governance_repo/bin/beroka-governance" install "$release"
git config --global --unset-all url."file://$governance_repo".insteadOf

beroka-governance register "$pilot_repo" --version "$release"
git -C "$pilot_repo" diff -- \
  .beroka-governance.lock AGENTS.md CLAUDE.md \
  .cursor/rules/beroka-governance.mdc
beroka-governance doctor "$pilot_repo"
```

Phải remove Git rewrite ngay sau `install`, trước `register`/`doctor`. Nếu
`install` fail, vẫn chạy lệnh `git config --global --unset-all ...` ở trên trước
khi điều tra hoặc retry. Không export hoặc dùng CLI remote override.

Thoát hoàn toàn các process client đang chạy, rồi launch từng client từ chính
shell đang giữ candidate environment để process mới kế thừa HOME/XDG/PATH:

```bash
(cd "$pilot_repo" && claude)
code --new-window "$pilot_repo"       # mở VS Code và dùng Codex extension
cursor --new-window "$pilot_repo"
```

Vì candidate HOME/XDG là cô lập, Claude Code, VS Code/Codex extension và Cursor
có thể yêu cầu login và connector authentication riêng. Ghi evidence trong
fresh session của từng client; không copy credential từ HOME thật vào candidate.
Sau khi evidence hoàn tất, restore shell và xóa environment cô lập:

```bash
export HOME=$original_home
export PATH=$original_path
unset XDG_DATA_HOME XDG_CONFIG_HOME BEROKA_GOV_BIN_DIR
rm -rf "$candidate_root"
```

- [ ] **UNVERIFIED** — Coordinator chỉ định một exact Backend pilot repository
      và exact reviewed release-candidate commit; Frontend chưa được register.
- [ ] **UNVERIFIED** — Tạo annotated candidate tag chỉ ở local trên đúng commit
      để chạy gate; không push hoặc tái sử dụng tag nếu candidate thất bại.
- [ ] **UNVERIFIED** — Chạy `sh -n bin/beroka-governance`,
      `sh -n tests/smoke.sh` và `sh tests/smoke.sh` trên Linux, macOS và WSL từ
      cùng candidate; lưu exact command, commit và output của từng môi trường.
- [ ] **UNVERIFIED** — Cài candidate trong isolated test environment, tạo
      reviewed registration diff cho Backend pilot, và xác nhận
      `beroka-governance doctor <repo>` trả `Result: PASS`.
- [ ] **UNVERIFIED** — Fresh Codex IDE session load `AGENTS.md` và đúng candidate.
- [ ] **UNVERIFIED** — Fresh Claude Code session `/memory` hiển thị project import
      và đúng candidate.
- [ ] **UNVERIFIED** — Fresh Cursor session áp dụng dedicated project rule và
      đúng candidate.
- [ ] **UNVERIFIED** — Coordinator review toàn bộ automated/manual evidence và
      đưa ra authorization rõ ràng cho việc publish annotated tag.
- [ ] **UNVERIFIED** — Chỉ sau authorization, publish annotated `v1.0.0` từ chính
      candidate commit đã pass; không move hoặc reuse tag.

Nếu bất kỳ candidate gate nào fail, chỉ xóa local unpublished tag, sửa qua một
reviewed implementation PR mới và chạy lại toàn bộ gate trên commit mới.

## Deployment checklist sau khi publish

Các bước này cũng đang **UNVERIFIED** và chỉ bắt đầu sau khi annotated tag đã
được publish hợp lệ:

- [ ] **UNVERIFIED** — Install published tag từ canonical central repository
      trên client rollout.
- [ ] **UNVERIFIED** — Chạy `register` cho exact Backend pilot; review và merge
      application-repository diff bằng PR.
- [ ] **UNVERIFIED** — Mở fresh agent session, xác nhận pinned published version,
      entrypoint đã load và `doctor` trả `Result: PASS`.
- [ ] **UNVERIFIED** — GitHub Backend và exact Frontend repository routing đã
      được xác nhận nhưng Frontend vẫn chưa được register.
- [ ] **UNVERIFIED** — Jira có Epic/Feature/Story/Task/Bug, backlog được enable,
      status map đúng trên `BB/34` và `BF/35`, và link types `Relates`/`Blocks`
      khả dụng trong required scope.
- [ ] **UNVERIFIED** — Hai Confluence spaces có native Folder/page permissions;
      FE mở được shared Integration Hub trong owning BE Folder.
- [ ] **UNVERIFIED** — Plugin/MCP dùng đúng account, không duplicate, không chứa
      secret trong repository, và connector preflight pass cho action thực tế.
- [ ] **UNVERIFIED** — Một Backend pilot task thật, nhỏ đã pass trước team-wide
      rollout; không tạo fake issue/page chỉ để test.

Chỉ đăng ký thêm repository sau Backend pilot và post-publication evidence được
coordinator review. Không register Frontend trước authorization riêng và không
thêm automation đồng bộ nếu manual drift chưa thực sự lặp lại.

## Troubleshooting nhanh

| Hiện tượng | Kiểm tra |
| --- | --- |
| Không thấy tools | Plugin/MCP status, restart client hoặc mở session mới |
| OAuth lặp lại | Đúng account, browser callback, workspace admin policy |
| Đọc được nhưng không ghi được | Repository/project/space permission của account |
| GitHub `401`/`403` | PAT hết hạn hoặc thiếu scope; không tăng scope nếu chưa cần |
| Jira có nhưng Confluence không có | Atlassian product access và space permission riêng |
| Kết quả thuộc nhầm team | Authenticated identity và target URL/project/space |

CLI fail closed với các stable result codes sau:

| Result | Ý nghĩa / xử lý |
| --- | --- |
| `GOVERNANCE_NOT_READY` | Thiếu release hoặc registration hợp lệ; cài release đúng hoặc sửa lock. |
| `GOVERNANCE_ACCESS_DENIED` | Không đọc được central private repository; kiểm tra Git/GitHub access, không thêm credential vào repo. |
| `REPOSITORY_NOT_REGISTERED` | Thiếu lock/managed entrypoint hợp lệ; register đúng repository qua reviewed PR. |
| `REMOTE_MISMATCH` | Git `origin` không khớp `REPOSITORY` trong lock; dùng đúng clone hoặc sửa qua lifecycle CLI. |
| `VERSION_MISMATCH` | Tag, commit hoặc installed release khác lock; install/pin lại reviewed version. |
| `ENTRYPOINT_DRIFT` | Managed content bị sửa ngoài CLI; restore/reconcile qua reviewed CLI lifecycle. |
| `WORKTREE_CONFLICT` | Target entrypoint có uncommitted changes; review, commit hoặc stash thay đổi trước khi chạy lại. |
| `DEPENDENCY_MISSING` | Client hoặc command dependency chưa có; cài đúng client/dependency rồi chạy lại explicit setup. |
| `CONNECTOR_MISSING` | Atlassian connector thiếu hoặc URL hiện tại xung đột; chạy `setup-connectors --client <client>` và review config. |
| `ATLASSIAN_AUTH_REQUIRED` | OAuth thiếu, hết hạn hoặc invalid; chạy exact remediation command được in ra. |
| `PASS` | Governance và, khi có `--client`, connector/authentication health đều đạt. |

## Tài liệu chính thức

- [GitHub MCP Server](https://github.com/github/github-mcp-server)
- [GitHub MCP for Codex](https://github.com/github/github-mcp-server/blob/main/docs/installation-guides/install-codex.md)
- [GitHub MCP for Claude Code](https://github.com/github/github-mcp-server/blob/main/docs/installation-guides/install-claude.md)
- [GitHub MCP for Cursor](https://github.com/github/github-mcp-server/blob/main/docs/installation-guides/install-cursor.md)
- [Atlassian Rovo MCP getting started](https://support.atlassian.com/atlassian-rovo-mcp-server/docs/getting-started-with-the-atlassian-remote-mcp-server/)
- [Claude Code MCP](https://code.claude.com/docs/en/mcp)
- [Cursor MCP](https://docs.cursor.com/context/model-context-protocol)
