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
- Dùng một annotated SemVer tag đã được review và publish. `v1.1.0` là release
  candidate hiện tại; chỉ publish sau khi release gate hoàn tất và coordinator
  cho phép. `v1.0.0` là immutable legacy test sample; không push, move hoặc
  reuse tag đó cho feature này.
- Repository đích là Git repository có đúng một canonical GitHub remote khớp
  repository identity. Tên local remote không bắt buộc là `origin`. Review
  diff của repository đích bằng PR trước khi merge; không đăng ký trực tiếp
  vào production branch chỉ để thử nghiệm.
- macOS, WSL và fresh-session checks của Codex IDE, Claude Code, Cursor vẫn
  **UNVERIFIED** cho đến khi release-gate evidence được ghi nhận. Linux
  automated shell smoke không thay thế các manual checks này.

### Bootstrap và install

Bootstrap checkout chỉ là tạm thời. `install` tạo local pinned checkout và
user-level CLI; không sửa application repository.

```bash
release=v1.1.0
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
release=v1.1.0

beroka-governance register "$repo" --version "$release"
git -C "$repo" diff -- .beroka-governance.lock AGENTS.md CLAUDE.md .cursor/rules/beroka-governance.mdc
beroka-governance doctor "$repo"
beroka-governance doctor "$repo" --client codex

beroka-governance update "$repo" --to "$release"
beroka-governance rollback "$repo" --to "$release"
beroka-governance unregister "$repo"
beroka-governance uninstall
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

### Lock và thin entrypoints

Register tạo đúng các artifact package-owned sau, không copy toàn bộ runtime hay
templates vào application repository:

- `.beroka-governance.lock`: source, `REPOSITORY`, pinned `VERSION` và commit SHA;
- managed block trong root `AGENTS.md`;
- managed block hoặc `@AGENTS.md` import trong root `CLAUDE.md`; và
- `.cursor/rules/beroka-governance.mdc`.

Entrypoints mỏng (thin) chỉ route agent tới release đã pin. Khi mở session mới,
Codex, Claude Code hoặc Cursor đọc entrypoint theo client, xác minh lock và
canonical remote đã discover, rồi chạy `beroka-governance context` để load
runtime English từ đúng release. Repository chưa register không được package
áp dụng.

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

Tất cả manual gate bên dưới hiện là **UNVERIFIED**. Không được xem source-tree
smoke trên Linux là bằng chứng thay thế, không được claim `v1.1.0` đã release,
và không được publish candidate tag trước khi hoàn tất đúng thứ tự này.
`v1.0.0` là immutable legacy test sample và không thuộc release gate này.

### Chạy unpublished candidate trong môi trường cô lập

Sau khi implementation PR đã merge, coordinator đã chọn exact Backend pilot,
và local `main` là commit cần kiểm tra, tạo annotated tag **chỉ ở local**. Không
push tag trong bước này:

```bash
governance_repo=$(git rev-parse --show-toplevel)
pilot_repo=/exact/path/from/coordinator
release=v1.1.0

git -C "$governance_repo" switch main
git -C "$governance_repo" pull --ff-only origin main
git -C "$governance_repo" tag -a "$release" -m 'Beroka AI governance package v1.1.0'
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
- [ ] **UNVERIFIED** — Chỉ sau authorization, publish annotated `v1.1.0` từ chính
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
