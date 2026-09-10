# GitHub and Atlassian client, connector, OAuth, and capability adapters.

client_executable() {
  case "$1" in
    codex) printf '%s\n' codex ;;
    claude) printf '%s\n' claude ;;
    cursor) printf '%s\n' cursor-agent ;;
    *) usage >&2; exit 2 ;;
  esac
}

oauth_command() {
  case "$1" in
    codex) printf '%s\n' 'codex mcp login atlassian' ;;
    claude)
      printf '%s\n' 'claude mcp login atlassian --no-browser'
      ;;
    cursor) printf '%s\n' 'cursor-agent mcp login atlassian' ;;
    *) usage >&2; exit 2 ;;
  esac
}

cursor_mcp() {
  (cd / && cursor-agent mcp "$@")
}

github_oauth_command() {
  printf '%s\n' 'gh auth login --hostname github.com --web'
}

require_client() {
  rc_client=$1
  rc_executable=$(client_executable "$rc_client")
  command -v "$rc_executable" >/dev/null 2>&1 ||
    die DEPENDENCY_MISSING "Missing dependency: $rc_executable"
  command -v jq >/dev/null 2>&1 ||
    die DEPENDENCY_MISSING 'Missing dependency: jq'
  case "$rc_client" in
    codex)
      codex mcp login --help >/dev/null 2>&1 &&
        codex app-server --help >/dev/null 2>&1 ||
        die DEPENDENCY_MISSING 'Codex lacks required MCP/app-server commands'
      ;;
    claude)
      claude mcp add --help >/dev/null 2>&1 &&
        claude mcp get --help >/dev/null 2>&1 &&
        claude mcp list --help >/dev/null 2>&1 ||
        die DEPENDENCY_MISSING 'Claude Code lacks required MCP commands'
      ;;
    cursor)
      cursor_mcp login --help >/dev/null 2>&1 ||
        die DEPENDENCY_MISSING 'Cursor Agent lacks required MCP login support'
      ;;
  esac
}

require_github_client() {
  rgc_client=$1
  rgc_executable=$(client_executable "$rgc_client")
  command -v "$rgc_executable" >/dev/null 2>&1 ||
    die DEPENDENCY_MISSING "Missing dependency: $rgc_executable"
  command -v gh >/dev/null 2>&1 ||
    die DEPENDENCY_MISSING 'Missing dependency: gh'
  gh auth status --help >/dev/null 2>&1 &&
    gh auth login --help >/dev/null 2>&1 &&
    gh api --help >/dev/null 2>&1 ||
    die DEPENDENCY_MISSING 'GitHub CLI lacks required auth commands'
}

github_auth_health() {
  gah_output=$(gh auth status --hostname github.com 2>&1) && return 0
  printf '%s\n' "$gah_output" | awk '
    {
      line=tolower($0)
      if (line ~ /not logged into any github hosts/ ||
          line ~ /failed to log in/ ||
          line ~ /token.*(invalid|expired|revoked)/) required=1
    }
    END { exit !required }
  ' && return 1
  return 2
}

require_github_auth() {
  rga_client=$1
  require_github_client "$rga_client"
  rga_health=0
  github_auth_health || rga_health=$?
  case "$rga_health" in
    0) ;;
    1) github_auth_required "$rga_client" ;;
    *)
      die GITHUB_ROLE_UNAVAILABLE \
        'Cannot verify GitHub authentication health'
      ;;
  esac
}

github_team_memberships() {
  GITHUB_FRONTEND_MEMBER=0
  GITHUB_BACKEND_MEMBER=0
  gtm_output=$(gh api --paginate /user/teams 2>/dev/null) ||
    die GITHUB_ROLE_UNAVAILABLE \
      'Cannot verify beroka-vn GitHub Team membership'
  gtm_memberships=$(
    printf '%s\n' "$gtm_output" |
      jq -e -s -r '
        if (all(.[]; type == "array") and
            all(.[][];
              (.slug | type) == "string" and
              (.organization.login | type) == "string"))
        then
          [ .[][] |
            select(.organization.login == "beroka-vn") |
            select(.slug == "frontend" or .slug == "backend") |
            .slug
          ] | unique | join(",")
        else
          error("invalid team response")
        end
      '
  ) || die GITHUB_ROLE_UNAVAILABLE \
    'Invalid GitHub Team membership response'
  case "$gtm_memberships" in
    frontend) GITHUB_FRONTEND_MEMBER=1 ;;
    backend) GITHUB_BACKEND_MEMBER=1 ;;
    backend,frontend)
      GITHUB_FRONTEND_MEMBER=1
      GITHUB_BACKEND_MEMBER=1
      ;;
    '') ;;
    *) die GITHUB_ROLE_UNAVAILABLE 'Invalid GitHub Team membership response' ;;
  esac
}

github_role_is_eligible() {
  case "$GITHUB_ROLE" in
    FE) [ "$GITHUB_FRONTEND_MEMBER" -eq 1 ] ;;
    BE) [ "$GITHUB_BACKEND_MEMBER" -eq 1 ] ;;
    FULL_STACK)
      [ "$GITHUB_FRONTEND_MEMBER" -eq 1 ] &&
        [ "$GITHUB_BACKEND_MEMBER" -eq 1 ]
      ;;
    *) return 1 ;;
  esac
}

write_github_role() {
  wgr_role=$1
  PERSONAL_STAGE_ROOT=$(mktemp -d \
    "${TMPDIR:-/tmp}/beroka-governance-role.XXXXXX") ||
    die GOVERNANCE_NOT_READY 'Cannot stage GitHub role'
  wgr_stage=$PERSONAL_STAGE_ROOT/github-role
  printf '%s\n' "$wgr_role" >"$wgr_stage" ||
    die GOVERNANCE_NOT_READY 'Cannot stage GitHub role'
  apply_user_file "$wgr_stage" "$GITHUB_ROLE_FILE" 'GitHub role'
  cleanup_personal_stage ||
    die GOVERNANCE_NOT_READY 'Cannot finish GitHub role staging'
}

configure_github_role() {
  cgr_client=$1 cgr_interactive=$2
  require_github_auth "$cgr_client"
  github_team_memberships
  cgr_selected=
  case "$GITHUB_FRONTEND_MEMBER:$GITHUB_BACKEND_MEMBER" in
    1:0) cgr_selected=FE ;;
    0:1) cgr_selected=BE ;;
    0:0)
      die GITHUB_ROLE_REQUIRED \
        'No eligible beroka-vn GitHub Team membership'
      ;;
    1:1)
      if read_github_role && github_role_is_eligible; then
        cgr_selected=$GITHUB_ROLE
      else
        [ "$cgr_interactive" -eq 1 ] ||
          die GITHUB_ROLE_SELECTION_REQUIRED \
            'Choose FE, BE, or Full-stack in an interactive bootstrap'
        printf 'Select GitHub role [FE/BE/Full-stack]: '
        IFS= read -r cgr_answer || cgr_answer=
        cgr_answer=$(
          printf '%s\n' "$cgr_answer" |
            sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
        )
        case "$cgr_answer" in
          FE|fe) cgr_selected=FE ;;
          BE|be) cgr_selected=BE ;;
          Full-stack|full-stack|FULL_STACK) cgr_selected=FULL_STACK ;;
          *)
            die GITHUB_ROLE_SELECTION_REQUIRED \
              'Choose FE, BE, or Full-stack'
            ;;
        esac
      fi
      ;;
  esac
  write_github_role "$cgr_selected"
  GITHUB_ROLE=$cgr_selected
  printf '%s\n' "GitHub role: $GITHUB_ROLE"
}

verify_github_role_membership() {
  vgr_client=$1
  github_team_memberships
  load_github_role
  github_role_is_eligible ||
    die GITHUB_ROLE_REQUIRED \
      "Remediation: beroka-governance bootstrap --client $vgr_client"
}

verify_github_role() {
  vgr_client=$1
  require_github_auth "$vgr_client"
  verify_github_role_membership "$vgr_client"
}

connector_state() {
  cs_client=$1
  case "$cs_client" in
    codex)
      cs_output=$(codex mcp get atlassian --json 2>/dev/null) || return 1
      printf '%s\n' "$cs_output" |
        jq -e -s 'length == 1 and (.[0] | type == "object")' \
          >/dev/null 2>&1 || return 2
      printf '%s\n' "$cs_output" |
        jq -e -s --stream --arg url "$ATLASSIAN_MCP_URL" '
          def values($path):
            [.[] | select(length == 2 and .[0] == $path) | .[1]];
          (values(["name"]) == ["atlassian"]) and
          (
            (values(["url"]) == [$url] and
             values(["transport", "url"]) == [] and
             values(["transport", "type"]) == []) or
            (values(["url"]) == [] and
             values(["transport", "url"]) == [$url] and
             values(["transport", "type"]) == ["streamable_http"])
          )
        ' >/dev/null 2>&1 && return 0
      return 2
      ;;
    claude)
      cs_output=$(claude mcp get atlassian 2>/dev/null) || return 1
      printf '%s\n' "$cs_output" |
        claude_atlassian_endpoint "$ATLASSIAN_MCP_URL" >/dev/null &&
        return 0
      return 2
      ;;
    cursor)
      cs_file=$HOME/.cursor/mcp.json
      [ -f "$cs_file" ] || return 1
      jq -e --arg url "$ATLASSIAN_MCP_URL" \
        '.mcpServers.atlassian.url == $url' "$cs_file" >/dev/null 2>&1 && return 0
      jq -e '.mcpServers.atlassian != null' "$cs_file" >/dev/null 2>&1 && return 2
      return 1
      ;;
  esac
}

codex_configure_atlassian() {
  cca_output=$(
    {
      printf '%s\n' \
        '{"method":"initialize","id":0,"params":{"clientInfo":{"name":"beroka-governance","title":"Beroka Governance","version":"1"}}}' \
        '{"method":"initialized","params":{}}' \
        "{\"method\":\"config/value/write\",\"id\":1,\"params\":{\"keyPath\":\"mcp_servers.atlassian\",\"value\":{\"url\":\"$ATLASSIAN_MCP_URL\"},\"mergeStrategy\":\"upsert\"}}"
      sleep 1
    } |
      codex app-server --stdio 2>&1
  ) || die GOVERNANCE_NOT_READY 'Codex could not configure Atlassian MCP'
  case "$cca_output" in
    *'"id":1'*'"result"'*) ;;
    *) die GOVERNANCE_NOT_READY 'Codex rejected Atlassian MCP configuration' ;;
  esac
}

cursor_configure_atlassian() {
  cuca_dir=$HOME/.cursor
  cuca_file=$cuca_dir/mcp.json
  assert_safe_user_path "$cuca_dir" 'Cursor config'
  assert_safe_user_path "$cuca_file" 'Cursor MCP config'
  mkdir -p "$cuca_dir" ||
    die GOVERNANCE_NOT_READY 'Cannot create Cursor config directory'
  if [ -f "$cuca_file" ]; then
    jq -e -s 'length == 1 and (.[0] | type == "object")' \
      "$cuca_file" >/dev/null 2>&1 ||
      die GOVERNANCE_NOT_READY 'Cursor MCP config is invalid JSON'
    cuca_state=0
    connector_state cursor || cuca_state=$?
    case "$cuca_state" in
      0) return 0 ;;
      1) ;;
      2)
        die CONNECTOR_MISSING \
          'Existing atlassian connector has an unexpected URL for cursor'
        ;;
      *) die GOVERNANCE_NOT_READY 'Cannot inspect cursor Atlassian connector' ;;
    esac
  fi
  cuca_temp=$(mktemp "$cuca_dir/.beroka-mcp.XXXXXX") ||
    die GOVERNANCE_NOT_READY 'Cannot stage Cursor MCP config'
  if [ -f "$cuca_file" ]; then
    if ! jq --arg url "$ATLASSIAN_MCP_URL" \
      '.mcpServers = (.mcpServers // {}) | .mcpServers.atlassian = {"url": $url}' \
      "$cuca_file" >"$cuca_temp"
    then
      rm -f "$cuca_temp" || :
      die GOVERNANCE_NOT_READY 'Cursor MCP config is invalid JSON'
    fi
  elif ! printf '%s\n' '{}' | jq --arg url "$ATLASSIAN_MCP_URL" \
    '.mcpServers = {"atlassian":{"url":$url}}' >"$cuca_temp"
  then
    rm -f "$cuca_temp" || :
    die GOVERNANCE_NOT_READY 'Cannot stage Cursor MCP config'
  fi
  apply_user_file "$cuca_temp" "$cuca_file" cursor-mcp-config
  rm -f "$cuca_temp" || :
}

cursor_project_mcp_notice() {
  cpmp_root=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  cpmp_file=$cpmp_root/.cursor/mcp.json
  [ "$cpmp_file" != "$HOME/.cursor/mcp.json" ] || return 0
  [ -f "$cpmp_file" ] && [ ! -L "$cpmp_file" ] || return 0
  jq -e '.mcpServers.atlassian != null' "$cpmp_file" \
    >/dev/null 2>&1 || return 0
  printf '%s\n' 'Project MCP: PRESENT_IGNORED'
}

cursor_global_connector_required() {
  printf '%s\n' \
    'Client: cursor' \
    'Provider: atlassian' \
    'Authentication: AUTH_REQUIRED' \
    'Remediation: beroka-governance setup-connectors --client cursor'
  die ATLASSIAN_AUTH_REQUIRED
}

cursor_first_run_setup() {
  cfr_interactive=$1
  cfr_dir=$HOME/.cursor
  cfr_file=$cfr_dir/mcp.json
  assert_safe_user_path "$cfr_dir" 'Cursor config'
  assert_safe_user_path "$cfr_file" 'Cursor MCP config'
  if [ -e "$cfr_file" ]; then
    [ -f "$cfr_file" ] && [ ! -L "$cfr_file" ] &&
      jq -e -s 'length == 1 and (.[0] | type == "object")' \
        "$cfr_file" >/dev/null 2>&1 ||
      die GOVERNANCE_NOT_READY 'Cursor MCP config is invalid JSON'
  fi
  cursor_project_mcp_notice
  [ "$cfr_interactive" -eq 1 ] ||
    cursor_global_connector_required
  printf 'Install global Atlassian MCP and start OAuth now? [y/N] '
  IFS= read -r cfr_answer || cfr_answer=
  case "$cfr_answer" in
    y|Y|yes|YES)
      cursor_configure_atlassian
      run_oauth cursor || auth_pending cursor
      ;;
    *) cursor_global_connector_required ;;
  esac
}

configure_connector() {
  case "$1" in
    codex) codex_configure_atlassian ;;
    claude)
      claude mcp add --transport http --scope user atlassian "$ATLASSIAN_MCP_URL" \
        >/dev/null 2>&1 ||
        die GOVERNANCE_NOT_READY 'Claude Code could not configure Atlassian MCP'
      ;;
    cursor) cursor_configure_atlassian ;;
  esac
}

atlassian_status_line() {
  awk -F: '{
    label=$1
    sub(/^[[:space:]]*/, "", label)
    sub(/[[:space:]]*$/, "", label)
    if (tolower(label) == "atlassian") {
      print
      exit
    }
  }'
}

claude_atlassian_endpoint() {
  # `claude mcp get atlassian` names the server on the first unindented
  # line ("atlassian:"), not a "Name:" field. Only fields inside that
  # first block count; a later unindented line starts a different
  # server's section and its fields must not leak into this match.
  cae_url=$1
  awk -v expected_url="$cae_url" '
    /^[^[:space:]]/ {
      if (!header_seen) {
        header_seen=1
        header=$0
        sub(/:[[:space:]]*$/, "", header)
        if (header == $0) invalid=1
        else if (header == "atlassian") name_ok=1
      } else {
        section_ended=1
      }
      next
    }
    section_ended { next }
    /^[[:space:]]*URL:[[:space:]]*/ {
      endpoint=$0
      sub(/^[[:space:]]*URL:[[:space:]]*/, "", endpoint)
      if (endpoint == "") invalid=1
      url_matches++
    }
    END {
      if (invalid || !header_seen || !name_ok ||
          url_matches != 1 || endpoint != expected_url) exit 42
    }
  '
}

codex_probe_complete() {
  cpc_file=$1
  [ -s "$cpc_file" ] || return 1
  [ "$(codex_probe_file_transport_state "$cpc_file")" = VALID ] || return 1
  if codex_reauthentication_required <"$cpc_file" ||
     codex_http_auth_required <"$cpc_file"
  then
    return 0
  fi
  cpc_response=$(codex_probe_response "$cpc_file") || return 1
  cpc_kind=$(printf '%s\n' "$cpc_response" |
    codex_probe_response_kind) || return 1
  case "$cpc_kind" in
    error|invalid) return 0 ;;
    result) ;;
    *) return 1 ;;
  esac
  if cpc_record=$(printf '%s\n' "$cpc_response" |
    codex_atlassian_record)
  then
    :
  else
    cpc_record_status=$?
    [ "$cpc_record_status" -eq 2 ] && return 0
    return 1
  fi
  cpc_auth=$(printf '%s\n' "$cpc_record" |
    json_top_level_string authStatus) || return 1
  case "$cpc_auth" in
    notLoggedIn) return 0 ;;
    oAuth)
      if cpc_tools=$(printf '%s\n' "$cpc_record" |
        json_top_level_tools)
      then
        [ -n "$cpc_tools" ] ||
          [ "$(codex_probe_response_count "$cpc_file")" -ge 2 ]
      fi
      ;;
    *) return 1 ;;
  esac
}

codex_probe_response() {
  cpr_file=$1
  [ "$(codex_probe_file_transport_state "$cpr_file")" = VALID ] || return 1
  cpr_response=
  while IFS= read -r cpr_candidate; do
    cpr_kind=$(printf '%s\n' "$cpr_candidate" |
      codex_probe_response_kind) || continue
    case "$cpr_kind" in
      result|error|invalid) cpr_response=$cpr_candidate ;;
    esac
  done <"$cpr_file"
  [ -n "$cpr_response" ] || return 1
  printf '%s\n' "$cpr_response"
}

codex_probe_response_kind() {
  cprk_response=$(cat)
  if printf '%s\n' "$cprk_response" |
     jq -e -s 'length == 1 and (.[0] | type == "object" and .id == 1)' \
       >/dev/null 2>&1
  then
    cprk_id1=1
  else
    cprk_id1=0
  fi
  cprk_result=0
  cprk_error=0
  cprk_tokens=$(printf '%s\n' "$cprk_response" |
    json_rpc_tokens) || return 1
  while IFS= read -r cprk_token; do
    case "$cprk_token" in
      result) cprk_result=1 ;;
      error) cprk_error=1 ;;
    esac
  done <<EOF
$cprk_tokens
EOF
  if [ "$cprk_id1" -eq 0 ]; then
    printf '%s\n' unrelated
    return 0
  fi
  case "$cprk_result$cprk_error" in
    10) printf '%s\n' result ;;
    01) printf '%s\n' error ;;
    *) printf '%s\n' invalid ;;
  esac
}

codex_probe_response_count() {
  cprc_file=$1
  cprc_transport=$(codex_probe_file_transport_state "$cprc_file")
  case "$cprc_transport" in
    INVALID) printf '%s\n' -1; return 0 ;;
    INCOMPLETE_SUFFIX) printf '%s\n' -2; return 0 ;;
  esac
  cprc_responses=0
  while IFS= read -r cprc_candidate; do
    cprc_kind=$(printf '%s\n' "$cprc_candidate" |
      codex_probe_response_kind) || continue
    case "$cprc_kind" in
      result|error|invalid)
        cprc_responses=$((cprc_responses + 1))
        ;;
    esac
  done <"$cprc_file"
  printf '%s\n' "$cprc_responses"
}

codex_probe_file_transport_state() {
  LC_ALL=C od -An -v -t u1 "$1" 2>/dev/null |
    awk '{
      for (i=1; i<=NF; i++) {
        byte=$i
        if (remaining) {
          if (byte < next_min || byte > next_max) invalid=1
          remaining--
          next_min=128
          next_max=191
        } else if (byte == 0) {
          invalid=1
        } else if (byte <= 127) {
          continue
        } else if (byte >= 194 && byte <= 223) {
          remaining=1
          next_min=128
          next_max=191
        } else if (byte == 224) {
          remaining=2
          next_min=160
          next_max=191
        } else if (byte >= 225 && byte <= 236) {
          remaining=2
          next_min=128
          next_max=191
        } else if (byte == 237) {
          remaining=2
          next_min=128
          next_max=159
        } else if (byte >= 238 && byte <= 239) {
          remaining=2
          next_min=128
          next_max=191
        } else if (byte == 240) {
          remaining=3
          next_min=144
          next_max=191
        } else if (byte >= 241 && byte <= 243) {
          remaining=3
          next_min=128
          next_max=191
        } else if (byte == 244) {
          remaining=3
          next_min=128
          next_max=143
        } else {
          invalid=1
        }
      }
    }
    END {
      if (invalid) print "INVALID"
      else if (remaining) print "INCOMPLETE_SUFFIX"
      else print "VALID"
    }'
}

codex_probe_stop() {
  cps_pid=$1
  kill -TERM "$cps_pid" 2>/dev/null || :
  cps_polls=0
  while kill -0 "$cps_pid" 2>/dev/null &&
        [ "$cps_polls" -lt 2 ]
  do
    sleep 1
    cps_polls=$((cps_polls + 1))
  done
  if kill -0 "$cps_pid" 2>/dev/null; then
    kill -KILL "$cps_pid" 2>/dev/null || :
  fi
  wait "$cps_pid" 2>/dev/null || :
}

codex_connector_probe() {
  ccp_dir=$(mktemp -d \
    "${TMPDIR:-/tmp}/beroka-codex-probe.XXXXXX") || return 1
  ccp_input=$ccp_dir/input
  ccp_output=$ccp_dir/output
  mkfifo "$ccp_input" || {
    rm -rf "$ccp_dir"
    return 1
  }

  codex app-server --stdio <"$ccp_input" >"$ccp_output" 2>&1 &
  ccp_pid=$!
  exec 3<>"$ccp_input" || {
    codex_probe_stop "$ccp_pid"
    rm -rf "$ccp_dir"
    return 1
  }
  if ! printf '%s\n' \
    '{"method":"initialize","id":0,"params":{"clientInfo":{"name":"beroka-governance","title":"Beroka Governance","version":"1"}}}' \
    '{"method":"initialized","params":{}}' \
    >&3
  then
    exec 3>&-
    codex_probe_stop "$ccp_pid"
    rm -rf "$ccp_dir"
    return 1
  fi

  ccp_elapsed=0
  ccp_complete=0
  ccp_invalid_transport=0
  ccp_seen_responses=0
  printf '%s\n' \
    '{"method":"mcpServerStatus/list","id":1,"params":{"detail":"toolsAndAuthOnly","limit":100}}' \
    >&3 || ccp_elapsed=13
  while [ "$ccp_elapsed" -lt 13 ]; do
    sleep 1
    ccp_elapsed=$((ccp_elapsed + 1))
    ccp_transport=$(codex_probe_file_transport_state "$ccp_output")
    case "$ccp_transport" in
      INVALID)
        ccp_invalid_transport=1
        break
        ;;
      INCOMPLETE_SUFFIX)
        if kill -0 "$ccp_pid" 2>/dev/null; then
          continue
        fi
        ccp_invalid_transport=1
        break
        ;;
    esac
    if codex_probe_complete "$ccp_output"; then
      ccp_complete=1
      break
    fi
    ccp_responses=$(codex_probe_response_count "$ccp_output")
    if [ "$ccp_responses" -lt -1 ]; then
      continue
    elif [ "$ccp_responses" -lt 0 ]; then
      ccp_invalid_transport=1
      break
    fi
    if [ "$ccp_responses" -gt "$ccp_seen_responses" ]; then
      ccp_seen_responses=$ccp_responses
      printf '%s\n' \
        '{"method":"mcpServerStatus/list","id":1,"params":{"detail":"toolsAndAuthOnly","limit":100}}' \
        >&3 || break
    fi
  done

  exec 3>&-
  codex_probe_stop "$ccp_pid"
  ccp_transport=$(codex_probe_file_transport_state "$ccp_output")
  if [ "$ccp_transport" != VALID ]; then
    ccp_invalid_transport=1
  fi
  if [ "$ccp_invalid_transport" -eq 1 ]; then
    CONNECTOR_PROBE_OUTPUT=
  elif [ "$ccp_complete" -eq 1 ] &&
     ! codex_reauthentication_required <"$ccp_output" &&
     ! codex_http_auth_required <"$ccp_output"
  then
    CONNECTOR_PROBE_OUTPUT=$(codex_probe_response "$ccp_output" || :)
  else
    CONNECTOR_PROBE_OUTPUT=$(cat "$ccp_output" 2>/dev/null || :)
  fi
  rm -rf "$ccp_dir"
  [ "$ccp_complete" -eq 1 ] && [ "$ccp_invalid_transport" -eq 0 ]
}

connector_probe() {
  cp_client=$1
  [ "${CONNECTOR_PROBE_CLIENT:-}" = "$cp_client" ] && return 0
  CONNECTOR_PROBE_CLIENT=
  CONNECTOR_PROBE_OUTPUT=
  CONNECTOR_PROBE_STATUS=
  CONNECTOR_PROBE_STATE=
  CONNECTOR_PROBE_TOOLS=
  CONNECTOR_PROBE_TOOLS_OK=0
  case "$cp_client" in
    codex)
      codex_connector_probe || return 1
      ;;
    claude)
      CONNECTOR_PROBE_OUTPUT=$(claude mcp list 2>&1) || :
      CONNECTOR_PROBE_STATUS=$(printf '%s\n' "$CONNECTOR_PROBE_OUTPUT" |
        atlassian_status_line)
      CONNECTOR_PROBE_STATE=$(printf '%s\n' "$CONNECTOR_PROBE_STATUS" |
        awk '{
          sub(/^[^:]*:[[:space:]]*/, "")
          sub(/[[:space:]]*$/, "")
          print tolower($0)
        }')
      case "$CONNECTOR_PROBE_STATE" in
        connected|*' - ✓ connected'|*' - ✔ connected')
          CONNECTOR_PROBE_STATE=connected
          ;;
        'authentication required'|'! needs authentication'|\
        *' - authentication required'|*' - ! needs authentication')
          CONNECTOR_PROBE_STATE=authentication-required
          ;;
        *)
          CONNECTOR_PROBE_STATE=unknown
          ;;
      esac
      ;;
    cursor)
      CONNECTOR_PROBE_OUTPUT=$(cursor_mcp list 2>&1) || :
      CONNECTOR_PROBE_STATUS=$(printf '%s\n' "$CONNECTOR_PROBE_OUTPUT" |
        atlassian_status_line)
      CONNECTOR_PROBE_STATE=$(printf '%s\n' "$CONNECTOR_PROBE_STATUS" |
        awk '{
          sub(/^[^:]*:[[:space:]]*/, "")
          sub(/[[:space:]]*$/, "")
          print tolower($0)
        }')
      case "$CONNECTOR_PROBE_STATE" in
        ready|connected)
          if CONNECTOR_PROBE_TOOLS=$(
            cursor_mcp list-tools atlassian 2>&1
          ); then
            CONNECTOR_PROBE_TOOLS_OK=1
          fi
          ;;
      esac
      ;;
  esac
  CONNECTOR_PROBE_CLIENT=$cp_client
}

codex_atlassian_record() {
  car_server=${1:-atlassian}
  car_requirement=${2:-required}
  case "$car_requirement" in
    required|optional) ;;
    *) return 1 ;;
  esac
  car_response=$(cat)
  car_kind=$(printf '%s\n' "$car_response" |
    codex_probe_response_kind) || return 1
  [ "$car_kind" = result ] || return 1
  if printf '%s\n' "$car_response" | LC_ALL=C awk \
    -v expected_server="$car_server" \
    -v server_requirement="$car_requirement" '
    function hex_codepoint(hex,    c, i, value) {
      value=0
      for (i=1; i<=length(hex); i++) {
        c=tolower(substr(hex, i, 1))
        value=value * 16 + index("0123456789abcdef", c) - 1
      }
      return value
    }
    function string_at(start,    i, c, escaped, unicode, value) {
      parsed_string=""
      parsed_semantic_string=""
      semantic_string_comparable=1
      escaped=0
      if (substr(raw, start, 1) != "\"") return 0
      for (i=start+1; i<=length(raw); i++) {
        c=substr(raw, i, 1)
        if (escaped) {
          if (c == "u") {
            unicode=substr(raw, i + 1, 4)
            parsed_string=parsed_string c unicode
            value=hex_codepoint(unicode)
            if (semantic_string_comparable &&
                value >= 32 && value <= 126)
              parsed_semantic_string=parsed_semantic_string sprintf("%c", value)
            else
              semantic_string_comparable=0
            i+=4
          } else {
            parsed_string=parsed_string c
            if (semantic_string_comparable &&
                (c == "\"" || c == "\\" || c == "/"))
              parsed_semantic_string=parsed_semantic_string c
            else
              semantic_string_comparable=0
          }
          escaped=0
        } else if (c == "\\") {
          escaped=1
        } else if (c == "\"") {
          if (!semantic_string_comparable) parsed_semantic_string=""
          parsed_end=i
          return 1
        } else {
          parsed_string=parsed_string c
          if (semantic_string_comparable && c ~ /^[ -~]$/)
            parsed_semantic_string=parsed_semantic_string c
          else
            semantic_string_comparable=0
        }
      }
      return 0
    }
    function nonspace(start,    i) {
      i=start
      while (substr(raw, i, 1) ~ /[[:space:]]/) i++
      return i
    }
    {
      if (NR > 1) raw=raw "\n"
      raw=raw $0
    }
    END {
      depth=0
      array_depth=0
      result_depth=0
      data_array_depth=0
      server_depth=0
      invalid=0
      for (i=1; i<=length(raw); i++) {
        c=substr(raw, i, 1)
        if (c == "\"") {
          if (!string_at(i)) exit 42
          key=parsed_string
          semantic_key=parsed_semantic_string
          key_end=parsed_end
          separator=nonspace(key_end + 1)
          if (substr(raw, separator, 1) == ":") {
            value_start=nonspace(separator + 1)
            if (message_depth && depth == message_depth &&
                semantic_key == "result") {
              message_result_count++
              if (substr(raw, value_start, 1) == "{")
                result_open=value_start
              else
                message_result_invalid=1
            }
            if (result_depth && depth == result_depth &&
                semantic_key == "data") {
              message_data_count++
              if (message_data_count > 1) semantic_conflict=1
              if (substr(raw, value_start, 1) == "[")
                data_open=value_start
              else
                message_data_invalid=1
            }
            if (server_depth && depth == server_depth) {
              if (semantic_key == "name") {
                server_name_count++
                if (server_name_count > 1) semantic_conflict=1
                if (!string_at(value_start)) server_name_invalid=1
                else server_name=parsed_string
              } else if (semantic_key == "tools") {
                server_tools_count++
                if (server_tools_count > 1) semantic_conflict=1
              } else if (semantic_key == "authStatus") {
                server_auth_count++
                if (server_auth_count > 1) semantic_conflict=1
              }
            }
          }
          i=key_end
        } else if (c == "{") {
          parent_depth=depth
          if (parent_depth == 0 && array_depth == 0) {
            message_depth=1
            message_result_count=0
            message_result_invalid=0
            message_data_count=0
            message_data_invalid=0
            message_server_matches=0
            message_record=""
            result_open=0
            result_depth=0
            data_open=0
            data_array_depth=0
            server_depth=0
          }
          depth++
          if (i == result_open) result_depth=depth
          if (data_array_depth && array_depth == data_array_depth &&
              parent_depth == result_depth) {
            server_depth=depth
            server_start=i
            server_name=""
            server_name_count=0
            server_name_invalid=0
            server_tools_count=0
            server_auth_count=0
          }
        } else if (c == "}") {
          if (server_depth && depth == server_depth) {
            if (server_name_count > 1 || server_tools_count > 1 ||
                server_auth_count > 1) {
              invalid=1
            } else if (!server_name_invalid && server_name_count == 1 &&
                       server_name == expected_server) {
              message_server_matches++
              message_record=substr(raw, server_start, i - server_start + 1)
            }
            server_depth=0
          }
          if (result_depth && depth == result_depth) result_depth=0
          if (message_depth && depth == message_depth) {
            if (message_result_count != 1 || message_result_invalid ||
                message_data_count != 1 || message_data_invalid ||
                (server_requirement == "required" &&
                 message_server_matches != 1) ||
                (server_requirement == "optional" &&
                 message_server_matches > 1))
              invalid=1
            else
              record=message_record
            message_depth=0
          }
          depth--
        } else if (c == "[") {
          array_depth++
          if (i == data_open) data_array_depth=array_depth
        } else if (c == "]") {
          if (data_array_depth && array_depth == data_array_depth)
            data_array_depth=0
          array_depth--
        }
      }
      if (semantic_conflict) exit 43
      if (depth != 0 || array_depth != 0 || invalid) exit 42
      print record
    }
  '
  then
    return 0
  else
    car_status=$?
    [ "$car_status" -eq 43 ] && return 2
    return 1
  fi
}

json_top_level_string() {
  jtls_key=$1
  LC_ALL=C awk -v wanted="$jtls_key" '
    function hex_codepoint(hex,    c, i, value) {
      value=0
      for (i=1; i<=length(hex); i++) {
        c=tolower(substr(hex, i, 1))
        value=value * 16 + index("0123456789abcdef", c) - 1
      }
      return value
    }
    function string_at(start,    i, c, escaped, unicode, value) {
      parsed_string=""
      parsed_semantic_string=""
      semantic_string_comparable=1
      escaped=0
      if (substr(raw, start, 1) != "\"") return 0
      for (i=start+1; i<=length(raw); i++) {
        c=substr(raw, i, 1)
        if (escaped) {
          if (c == "u") {
            unicode=substr(raw, i + 1, 4)
            parsed_string=parsed_string c unicode
            value=hex_codepoint(unicode)
            if (semantic_string_comparable &&
                value >= 32 && value <= 126)
              parsed_semantic_string=parsed_semantic_string sprintf("%c", value)
            else
              semantic_string_comparable=0
            i+=4
          } else {
            parsed_string=parsed_string c
            if (semantic_string_comparable &&
                (c == "\"" || c == "\\" || c == "/"))
              parsed_semantic_string=parsed_semantic_string c
            else
              semantic_string_comparable=0
          }
          escaped=0
        } else if (c == "\\") {
          escaped=1
        } else if (c == "\"") {
          if (!semantic_string_comparable) parsed_semantic_string=""
          parsed_end=i
          return 1
        } else {
          parsed_string=parsed_string c
          if (semantic_string_comparable && c ~ /^[ -~]$/)
            parsed_semantic_string=parsed_semantic_string c
          else
            semantic_string_comparable=0
        }
      }
      return 0
    }
    function nonspace(start,    i) {
      i=start
      while (substr(raw, i, 1) ~ /[[:space:]]/) i++
      return i
    }
    {
      if (NR > 1) raw=raw "\n"
      raw=raw $0
    }
    END {
      depth=0
      matches=0
      for (i=1; i<=length(raw); i++) {
        c=substr(raw, i, 1)
        if (c == "{") {
          depth++
        } else if (c == "}") {
          depth--
        } else if (c == "\"") {
          if (!string_at(i)) exit 42
          key=parsed_string
          semantic_key=parsed_semantic_string
          key_end=parsed_end
          separator=nonspace(key_end + 1)
          if (depth == 1 && semantic_key == wanted &&
              substr(raw, separator, 1) == ":") {
            value_start=nonspace(separator + 1)
            if (!string_at(value_start)) exit 42
            value=parsed_string
            matches++
          }
          i=key_end
        }
      }
      if (matches != 1) exit 42
      print value
    }
  '
}

json_top_level_object() {
  jtlo_key=$1
  LC_ALL=C awk -v wanted="$jtlo_key" '
    function hex_codepoint(hex,    c, i, value) {
      value=0
      for (i=1; i<=length(hex); i++) {
        c=tolower(substr(hex, i, 1))
        value=value * 16 + index("0123456789abcdef", c) - 1
      }
      return value
    }
    function string_at(start,    i, c, escaped, unicode, value) {
      parsed_semantic_string=""
      semantic_string_comparable=1
      escaped=0
      if (substr(raw, start, 1) != "\"") return 0
      for (i=start+1; i<=length(raw); i++) {
        c=substr(raw, i, 1)
        if (escaped) {
          if (c == "u") {
            unicode=substr(raw, i + 1, 4)
            value=hex_codepoint(unicode)
            if (semantic_string_comparable &&
                value >= 32 && value <= 126)
              parsed_semantic_string=parsed_semantic_string sprintf("%c", value)
            else
              semantic_string_comparable=0
            i+=4
          } else if (semantic_string_comparable &&
                     (c == "\"" || c == "\\" || c == "/")) {
            parsed_semantic_string=parsed_semantic_string c
          } else {
            semantic_string_comparable=0
          }
          escaped=0
        } else if (c == "\\") {
          escaped=1
        } else if (c == "\"") {
          if (!semantic_string_comparable) parsed_semantic_string=""
          parsed_end=i
          return 1
        } else if (semantic_string_comparable && c ~ /^[ -~]$/) {
          parsed_semantic_string=parsed_semantic_string c
        } else {
          semantic_string_comparable=0
        }
      }
      return 0
    }
    {
      if (NR > 1) raw=raw "\n"
      raw=raw $0
    }
    END {
      length_raw=length(raw)
      depth=0
      matches=0
      for (i=1; i<=length_raw; i++) {
        c=substr(raw, i, 1)
        if (c == "\"") {
          if (!string_at(i)) exit 42
          j=parsed_end
          if (depth != 1) {
            i=j
            continue
          }
          key=parsed_semantic_string
        } else if (c == "{") {
          depth++
          continue
        } else if (c == "}") {
          depth--
          continue
        } else {
          continue
        }

        k=j+1
        while (substr(raw, k, 1) ~ /[[:space:]]/) k++
        if (substr(raw, k, 1) != ":") {
          i=j
          continue
        }
        k++
        while (substr(raw, k, 1) ~ /[[:space:]]/) k++
        if (key != wanted) {
          i=j
          continue
        }
        if (substr(raw, k, 1) != "{") exit 42

        object_start=k
        object_depth=0
        object_string=0
        object_escaped=0
        closed=0
        for (l=k; l<=length_raw; l++) {
          d=substr(raw, l, 1)
          if (object_string) {
            if (object_escaped) object_escaped=0
            else if (d == "\\") object_escaped=1
            else if (d == "\"") object_string=0
          } else if (d == "\"") {
            object_string=1
          } else if (d == "{") {
            object_depth++
          } else if (d == "}") {
            object_depth--
            if (object_depth == 0) {
              object=substr(raw, object_start, l - object_start + 1)
              matches++
              closed=1
              i=l
              break
            }
          }
        }
        if (!closed) exit 42
      }
      if (matches != 1) exit 42
      print object
    }
  '
}

json_top_level_keys() {
  jtlk_mode=${1:-objects}
  case "$jtlk_mode" in
    cursor|objects|rpc|tools) ;;
    *) return 1 ;;
  esac
  LC_ALL=C awk -v parse_mode="$jtlk_mode" '
    function skip_space(    c) {
      while (position <= object_length) {
        c=substr(object, position, 1)
        if (c != " " && c != "\t" && c != "\r" && c != "\n") break
        position++
      }
    }
    function hex_codepoint(hex,    c, i, value) {
      value=0
      for (i=1; i<=length(hex); i++) {
        c=tolower(substr(hex, i, 1))
        value=value * 16 + index("0123456789abcdef", c) - 1
      }
      return value
    }
    function append_semantic_character(c) {
      if (!semantic_key_comparable) return
      if (c ~ /^[ -~]$/)
        parsed_semantic_key=parsed_semantic_key c
      else
        semantic_key_comparable=0
    }
    function append_semantic_codepoint(hex,    value) {
      if (!semantic_key_comparable) return
      value=hex_codepoint(hex)
      if (value >= 32 && value <= 126)
        parsed_semantic_key=parsed_semantic_key sprintf("%c", value)
      else
        semantic_key_comparable=0
    }
    function parse_string(allow_escape,    c, escape, i, unicode) {
      parsed_string=""
      parsed_semantic_key=""
      semantic_key_comparable=1
      if (substr(object, position, 1) != "\"") return 0
      position++
      while (position <= object_length) {
        c=substr(object, position, 1)
        if (c == "\"") {
          if (!semantic_key_comparable) parsed_semantic_key=""
          position++
          return 1
        }
        if (c ~ /[[:cntrl:]]/ && c != sprintf("%c", 127)) return 0
        if (c != "\\") {
          parsed_string=parsed_string c
          append_semantic_character(c)
          position++
          continue
        }
        if (!allow_escape) return 0
        position++
        if (position > object_length) return 0
        escape=substr(object, position, 1)
        if (escape == "\"" || escape == "\\" || escape == "/" ||
            escape == "b" || escape == "f" || escape == "n" ||
            escape == "r" || escape == "t") {
          parsed_string=parsed_string "\\" escape
          if (escape == "\"" || escape == "\\" || escape == "/")
            append_semantic_character(escape)
          else
            semantic_key_comparable=0
          position++
          continue
        }
        if (escape != "u") return 0
        for (i=1; i<=4; i++) {
          if (substr(object, position + i, 1) !~ /^[0-9A-Fa-f]$/)
            return 0
        }
        unicode=substr(object, position + 1, 4)
        parsed_string=parsed_string "\\u" unicode
        append_semantic_codepoint(unicode)
        position+=5
      }
      return 0
    }
    function parse_json_number(    c) {
      c=substr(object, position, 1)
      if (c == "-") {
        position++
        c=substr(object, position, 1)
      }
      if (c == "0") {
        position++
        if (substr(object, position, 1) ~ /^[0-9]$/) return 0
      } else if (c ~ /^[1-9]$/) {
        while (substr(object, position, 1) ~ /^[0-9]$/) position++
      } else {
        return 0
      }
      if (substr(object, position, 1) == ".") {
        position++
        if (substr(object, position, 1) !~ /^[0-9]$/) return 0
        while (substr(object, position, 1) ~ /^[0-9]$/) position++
      }
      c=substr(object, position, 1)
      if (c == "e" || c == "E") {
        position++
        c=substr(object, position, 1)
        if (c == "+" || c == "-") position++
        if (substr(object, position, 1) !~ /^[0-9]$/) return 0
        while (substr(object, position, 1) ~ /^[0-9]$/) position++
      }
      return 1
    }
    function parse_json_literal(literal) {
      if (substr(object, position, length(literal)) != literal) return 0
      position+=length(literal)
      return 1
    }
    function parse_json_array(    separator) {
      if (substr(object, position, 1) != "[") return 0
      position++
      skip_space()
      if (substr(object, position, 1) == "]") {
        position++
        return 1
      }
      while (position <= object_length) {
        if (!parse_json_value()) return 0
        skip_space()
        separator=substr(object, position, 1)
        if (separator == "]") {
          position++
          return 1
        }
        if (separator != ",") return 0
        position++
        skip_space()
        if (substr(object, position, 1) == "]") return 0
      }
      return 0
    }
    function parse_json_object(    separator) {
      if (substr(object, position, 1) != "{") return 0
      position++
      skip_space()
      if (substr(object, position, 1) == "}") {
        position++
        return 1
      }
      while (position <= object_length) {
        if (!parse_string(1)) return 0
        skip_space()
        if (substr(object, position, 1) != ":") return 0
        position++
        if (!parse_json_value()) return 0
        skip_space()
        separator=substr(object, position, 1)
        if (separator == "}") {
          position++
          return 1
        }
        if (separator != ",") return 0
        position++
        skip_space()
        if (substr(object, position, 1) == "}") return 0
      }
      return 0
    }
    function parse_json_value(    c) {
      skip_space()
      c=substr(object, position, 1)
      if (c == "{") return parse_json_object()
      if (c == "[") return parse_json_array()
      if (c == "\"") return parse_string(1)
      if (c == "t") return parse_json_literal("true")
      if (c == "f") return parse_json_literal("false")
      if (c == "n") return parse_json_literal("null")
      return parse_json_number()
    }
    {
      if (NR > 1) object=object "\n"
      object=object $0
    }
    END {
      object_length=length(object)
      position=1
      skip_space()
      if (substr(object, position, 1) != "{") exit 42
      position++
      skip_space()
      if (substr(object, position, 1) == "}") {
        position++
      } else {
        while (position <= object_length) {
          if (parse_mode == "rpc" || parse_mode == "cursor") {
            if (!parse_string(1)) exit 42
          } else if (!parse_string(0)) {
            exit 42
          }
          key=parsed_string
          semantic_key=parsed_semantic_key
          if (parse_mode == "rpc") {
            if (semantic_key == "id" || semantic_key == "result" ||
                semantic_key == "error") {
              if (rpc_seen[semantic_key]) exit 42
              rpc_seen[semantic_key]=1
            }
          } else if (parse_mode == "cursor") {
            if (semantic_key == "nextCursor") {
              if (cursor_seen) exit 42
              cursor_seen=1
            }
          } else {
            if (parse_mode == "tools") {
              if (key !~ /^[A-Za-z][A-Za-z0-9_.-]*$/) exit 42
            } else if (key !~ /^[A-Za-z][A-Za-z0-9_]*$/) exit 42
            if (seen[key]) exit 42
            seen[key]=1
            keys[++key_count]=key
          }
          skip_space()
          if (substr(object, position, 1) != ":") exit 42
          position++
          skip_space()
          value_start=position
          if (parse_mode == "rpc" || parse_mode == "cursor") {
            if (!parse_json_value()) exit 42
          } else if (!parse_json_object()) {
            exit 42
          }
          if (parse_mode == "rpc" && semantic_key == "id" &&
              substr(object, value_start, position - value_start) == "1")
            rpc_id1=1
          if (parse_mode == "cursor" && semantic_key == "nextCursor")
            cursor_null=(substr(object, value_start,
              position - value_start) == "null")
          skip_space()
          separator=substr(object, position, 1)
          if (separator == "}") {
            position++
            break
          }
          if (separator != ",") exit 42
          position++
          skip_space()
          if (substr(object, position, 1) == "}") exit 42
        }
      }
      skip_space()
      if (position <= object_length) exit 42
      if (parse_mode == "rpc") {
        if (rpc_id1) print "id1"
        if (rpc_seen["result"]) print "result"
        if (rpc_seen["error"]) print "error"
      } else if (parse_mode == "cursor") {
        if (!cursor_seen) print "absent"
        else if (cursor_null) print "null"
        else print "other"
      } else {
        for (i=1; i<=key_count; i++) print keys[i]
      }
    }
  '
}

json_rpc_tokens() {
  json_top_level_keys rpc
}

json_validate_object() {
  jvo_keys=$({
    printf '%s' '{"object":'
    cat
    printf '%s\n' '}'
  } | json_top_level_keys) || return 1
  [ "$jvo_keys" = object ]
}

json_top_level_tools() {
  json_top_level_object tools | json_top_level_keys "${1:-objects}"
}

codex_canonical_tool_names() {
  cctn_mode=${1:-all}
  case "$cctn_mode" in
    all|apps-only) ;;
    *) return 1 ;;
  esac
  LC_ALL=C awk -v mode="$cctn_mode" '
    BEGIN {
      canonical["mcp__codex_apps__atlassian_rovo_createjiraissue"]="createJiraIssue"
      canonical["mcp__codex_apps__atlassian_rovo_createconfluencepage"]="createConfluencePage"
      canonical["mcp__codex_apps__atlassian_rovo_updateconfluencepage"]="updateConfluencePage"
      canonical["mcp__codex_apps__atlassian_rovo_getconfluencepage"]="getConfluencePage"
      canonical["mcp__codex_apps__atlassian_rovo_getaccessibleatla_4b5564c6c5e4"]="getAccessibleAtlassianResources"
      canonical["mcp__codex_apps__atlassian_rovo_getjiraissue"]="getJiraIssue"
      canonical["mcp__codex_apps__atlassian_rovo_getjiraissuetypemetawithfields"]="getJiraIssueTypeMetaWithFields"
      canonical["mcp__codex_apps__atlassian_rovo_getjiraprojectiss_ccce75cac970"]="getJiraProjectIssueTypesMetadata"
      canonical["mcp__codex_apps__atlassian_rovo_searchjiraissuesusingjql"]="searchJiraIssuesUsingJql"
      canonical["atlassian_rovo.createJiraIssue"]="createJiraIssue"
      canonical["atlassian_rovo.createConfluencePage"]="createConfluencePage"
      canonical["atlassian_rovo.getAccessibleAtlassianResources"]="getAccessibleAtlassianResources"
      canonical["atlassian_rovo.getConfluencePage"]="getConfluencePage"
      canonical["atlassian_rovo.getJiraIssue"]="getJiraIssue"
      canonical["atlassian_rovo.getJiraIssueTypeMetaWithFields"]="getJiraIssueTypeMetaWithFields"
      canonical["atlassian_rovo.getJiraProjectIssueTypesMetadata"]="getJiraProjectIssueTypesMetadata"
      canonical["atlassian_rovo.searchJiraIssuesUsingJql"]="searchJiraIssuesUsingJql"
      canonical["atlassian_rovo.updateConfluencePage"]="updateConfluencePage"
    }
    {
      if (mode == "apps-only" && !($0 in canonical)) next
      name=($0 in canonical ? canonical[$0] : $0)
      if (seen[name]++) invalid=1
      names[++name_count]=name
    }
    END {
      if (invalid) exit 42
      for (i=1; i<=name_count; i++) print names[i]
    }
  '
}

codex_reauthentication_required() {
  crr_matches=0
  while IFS= read -r crr_message; do
    printf '%s\n' "$crr_message" |
      json_validate_object >/dev/null || continue
    crr_method=$(printf '%s\n' "$crr_message" |
      json_top_level_string method) || continue
    [ "$crr_method" = mcpServer/startupStatus/updated ] || continue
    crr_params=$(printf '%s\n' "$crr_message" |
      json_top_level_object params) || continue
    crr_name=$(printf '%s\n' "$crr_params" |
      json_top_level_string name) || continue
    crr_reason=$(printf '%s\n' "$crr_params" |
      json_top_level_string failureReason) || continue
    [ "$crr_name" = atlassian ] &&
      [ "$crr_reason" = reauthenticationRequired ] || continue
    crr_matches=$((crr_matches + 1))
  done
  [ "$crr_matches" -gt 0 ]
}

codex_http_auth_required() {
  awk '
    {
      line=$0
      sub(/^[[:space:]]*/, "", line)
      sub(/[[:space:]]*$/, "", line)
      if ((line ~ /^server atlassian:/ &&
           (line ~ /unauthorized_client/ ||
            line ~ /401 Unauthorized/ ||
            line ~ /403 Forbidden/)) ||
          (line ~ /codex_rmcp_client::oauth::refresh_transaction/ &&
           line ~ /server atlassian:/ &&
           line ~ /unauthorized_client/ &&
           line ~ /refresh_token is invalid/)) found=1
    }
    END { exit !found }
  '
}

inventory_has_tool() {
  iht_tool=$1
  case "$CAPABILITY_INVENTORY_FORMAT" in
    json)
      printf '%s\n' "$CAPABILITY_INVENTORY" |
        grep -Fx "$iht_tool" >/dev/null
      ;;
    text)
      printf '%s\n' "$CAPABILITY_INVENTORY" |
        awk -v tool="$iht_tool" '
          {
            count=split($0, words, /[^A-Za-z0-9_]/)
            for (i=1; i<=count; i++) if (words[i] == tool) found=1
          }
          END { exit !found }
        '
      ;;
    *) return 1 ;;
  esac
}

cursor_tool_names() {
  awk '
    {
      line=$0
      sub(/^[[:space:]]*[-*]?[[:space:]]*/, "", line)
      if (match(line, /^[A-Za-z][A-Za-z0-9_]*/)) {
        name=substr(line, RSTART, RLENGTH)
        rest=substr(line, RLENGTH + 1)
        if (rest == "" ||
            rest ~ /^[[:space:]]*\([^()]*\)[[:space:]]*$/) print name
      }
    }
  '
}

codex_inventory_page_complete() {
  cipc_result=$(json_top_level_object result) || return 1
  cipc_cursor=$(printf '%s\n' "$cipc_result" |
    json_top_level_keys cursor) || return 1
  case "$cipc_cursor" in
    absent|null) ;;
    *) return 1 ;;
  esac
}

connector_inventory() {
  ci_client=$1
  ci_mode=${2:-provider}
  CAPABILITY_INVENTORY=
  CAPABILITY_INVENTORY_COMPLETE=0
  CAPABILITY_INVENTORY_FORMAT=
  if [ "$ci_mode" = legacy ]; then
    CAPABILITY_TOOLSET=UNAVAILABLE
  fi
  case "$ci_client" in
    codex)
      connector_probe codex || return 1
      ci_record=$(printf '%s\n' "$CONNECTOR_PROBE_OUTPUT" |
        codex_atlassian_record) || return 1
      ci_tools=$(printf '%s\n' "$ci_record" |
        json_top_level_tools) || return 1
      ci_tools=$(printf '%s\n' "$ci_tools" |
        codex_canonical_tool_names) || return 1
      ci_apps_record=$(printf '%s\n' "$CONNECTOR_PROBE_OUTPUT" |
        codex_atlassian_record codex_apps optional) || return 1
      ci_apps_tools=
      if [ -n "$ci_apps_record" ]; then
        ci_apps_auth=$(printf '%s\n' "$ci_apps_record" |
          json_top_level_string authStatus) || ci_apps_auth=
        if [ "$ci_apps_auth" = bearerToken ]; then
          ci_apps_tools=$(printf '%s\n' "$ci_apps_record" |
            json_top_level_tools tools) || return 1
          ci_apps_tools=$(printf '%s\n' "$ci_apps_tools" |
            codex_canonical_tool_names apps-only) || return 1
        fi
      fi
      CAPABILITY_INVENTORY=$({
        [ -z "$ci_tools" ] || printf '%s\n' "$ci_tools"
        [ -z "$ci_apps_tools" ] || printf '%s\n' "$ci_apps_tools"
      } | LC_ALL=C sort -u) || return 1
      CAPABILITY_INVENTORY_FORMAT=json
      if printf '%s\n' "$CONNECTOR_PROBE_OUTPUT" |
         codex_inventory_page_complete
      then
        CAPABILITY_INVENTORY_COMPLETE=1
      fi
      ;;
    claude)
      CAPABILITY_INVENTORY_COMPLETE=0
      ;;
    cursor)
      connector_probe cursor || return 1
      [ "$CONNECTOR_PROBE_TOOLS_OK" -eq 1 ] || return 1
      if [ "$ci_mode" = legacy ]; then
        [ -n "$CONNECTOR_PROBE_TOOLS" ] || return 1
        CAPABILITY_INVENTORY=$CONNECTOR_PROBE_TOOLS
        CAPABILITY_INVENTORY_FORMAT=text
      else
        CAPABILITY_INVENTORY=$(printf '%s\n' "$CONNECTOR_PROBE_TOOLS" |
          cursor_tool_names) || return 1
        CAPABILITY_INVENTORY_FORMAT=json
      fi
      CAPABILITY_INVENTORY_COMPLETE=1
      ;;
  esac
  [ "$CAPABILITY_INVENTORY_COMPLETE" -eq 1 ] || return 0
  [ "$ci_mode" = legacy ] || return 0
  CAPABILITY_TOOLSET=
  for ci_tool in \
    createConfluencePage createJiraIssue getConfluencePage getJiraIssue
  do
    if inventory_has_tool "$ci_tool"; then
      if [ -n "$CAPABILITY_TOOLSET" ]; then
        CAPABILITY_TOOLSET=$CAPABILITY_TOOLSET,$ci_tool
      else
        CAPABILITY_TOOLSET=$ci_tool
      fi
    fi
  done
  [ -n "$CAPABILITY_TOOLSET" ] || CAPABILITY_TOOLSET=EMPTY
}

connector_health() {
  ch_client=$1
  connector_probe "$ch_client" || return 2
  case "$ch_client" in
    codex)
      if printf '%s\n' "$CONNECTOR_PROBE_OUTPUT" |
        codex_reauthentication_required
      then
        return 1
      fi
      if printf '%s\n' "$CONNECTOR_PROBE_OUTPUT" |
        codex_http_auth_required
      then
        return 1
      fi
      ch_record=$(printf '%s\n' "$CONNECTOR_PROBE_OUTPUT" |
        codex_atlassian_record) || return 2
      ch_auth=$(printf '%s\n' "$ch_record" |
        json_top_level_string authStatus) || return 2
      case "$ch_auth" in
        notLoggedIn) return 1 ;;
        oAuth) return 0 ;;
        *) return 2 ;;
      esac
      ;;
    claude)
      case "$CONNECTOR_PROBE_STATE" in
        connected) return 0 ;;
        *auth*|*login*|*401*|*403*) return 1 ;;
        *) return 2 ;;
      esac
      ;;
    cursor)
      case "$CONNECTOR_PROBE_STATE" in
        ready|connected) return 0 ;;
        *auth*|*login*|*401*|*403*) return 1 ;;
        *) return 2 ;;
      esac
      ;;
  esac
}

run_oauth() {
  case "$1" in
    codex) codex mcp login atlassian ;;
    claude)
      claude mcp login --help 2>&1 |
        grep -F -- '--no-browser' >/dev/null ||
        die DEPENDENCY_MISSING 'Remediation: claude update'
      claude mcp login atlassian --no-browser
      ;;
    cursor) cursor_mcp login atlassian ;;
  esac || return $?
  CONNECTOR_PROBE_CLIENT=
  CONNECTOR_PROBE_OUTPUT=
  CONNECTOR_PROBE_STATUS=
  CONNECTOR_PROBE_STATE=
  CONNECTOR_PROBE_TOOLS=
  CONNECTOR_PROBE_TOOLS_OK=0
}

runtime_capability() {
  rc_capability=$1
  CAPABILITY_STATE=UNKNOWN
  case "$rc_capability" in
    jira-issue-write)
      if [ "$CAPABILITY_INVENTORY_COMPLETE" -eq 1 ] &&
         { ! inventory_has_tool createJiraIssue ||
           ! inventory_has_tool getJiraIssue; }
      then
        CAPABILITY_STATE=UNSUPPORTED
      fi
      ;;
    confluence-page-parent-write)
      if [ "$CAPABILITY_INVENTORY_COMPLETE" -eq 1 ] &&
         { ! inventory_has_tool createConfluencePage ||
           ! inventory_has_tool getConfluencePage; }
      then
        CAPABILITY_STATE=UNSUPPORTED
      fi
      ;;
    confluence-page-update)
      if [ "$CAPABILITY_INVENTORY_COMPLETE" -eq 1 ] &&
         { ! inventory_has_tool updateConfluencePage ||
           ! inventory_has_tool getConfluencePage; }
      then
        CAPABILITY_STATE=UNSUPPORTED
      fi
      ;;
    confluence-page-read)
      if [ "$CAPABILITY_INVENTORY_COMPLETE" -eq 1 ] &&
         ! inventory_has_tool getConfluencePage
      then
        CAPABILITY_STATE=UNSUPPORTED
      fi
      ;;
    jira-board-verification|confluence-folder-parent-write)
      CAPABILITY_STATE=UNKNOWN
      ;;
    *) return 1 ;;
  esac
}

legacy_compatibility_capability() {
  cc_client=$1 cc_capability=$2
  cc_file=$RELEASE_DIR/runtime/compatibility/atlassian.tsv
  [ "$(sed -n '1p' "$cc_file" 2>/dev/null)" = '# schema=1' ] || return 1
  cc_executable=$(client_executable "$cc_client")
  cc_version=$("$cc_executable" --version 2>/dev/null |
    awk 'NR == 1 {
      for (i=1; i<=NF; i++) {
        if ($i ~ /^v?[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$/) {
          sub(/^v/, "", $i)
          print $i
          exit
        }
      }
    }') || return 1
  [ -n "$cc_version" ] || return 1
  awk -F '\t' \
    -v client="$cc_client" \
    -v version="$cc_version" \
    -v endpoint="$ATLASSIAN_MCP_URL" \
    -v toolset="$CAPABILITY_TOOLSET" \
    -v capability="$cc_capability" '
      /^[[:space:]]*$/ || /^#/ { next }
      {
        if (NF != 7 ||
            $1 !~ /^(codex|claude|cursor)$/ ||
            $2 !~ /^[A-Za-z0-9._+-]+$/ ||
            $3 == "" ||
            $4 == "" ||
            $5 !~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/ ||
            $6 !~ /^[a-z][a-z0-9-]+$/ ||
            $7 !~ /^(SUPPORTED|UNSUPPORTED)$/) invalid=1
        if ($1 == client &&
            $2 == version &&
            $3 == endpoint &&
            $4 == toolset &&
            $6 == capability) {
          matches++
          result=$7
        }
      }
      END {
        if (invalid || matches > 1) exit 42
        if (matches == 1) print result
        else exit 1
      }
    ' "$cc_file"
}

load_provider_capability() {
  lpc_capability=$1
  lpc_file=$RELEASE_DIR/runtime/compatibility/atlassian.tsv
  CAPABILITY_REQUIRED_TOOLS=
  CAPABILITY_PROVIDER_STATE=UNKNOWN
  lpc_row=$(LC_ALL=C awk -F '\t' \
    -v endpoint="$ATLASSIAN_MCP_URL" \
    -v capability="$lpc_capability" '
      /^[[:space:]]*$/ || /^#/ { next }
      {
        allowed["createConfluencePage"]=1
        allowed["createJiraIssue"]=1
        allowed["getAccessibleAtlassianResources"]=1
        allowed["getConfluencePage"]=1
        allowed["updateConfluencePage"]=1
        allowed["getJiraIssue"]=1
        allowed["getJiraIssueTypeMetaWithFields"]=1
        allowed["getJiraProjectIssueTypesMetadata"]=1
        allowed["searchJiraIssuesUsingJql"]=1
        tool_count=split($2, tools, ",")
        for (i=1; i<=tool_count; i++) {
          if (!allowed[tools[i]] ||
              tool_seen[tools[i]] == NR ||
              (i > 1 && tools[i-1] >= tools[i])) invalid=1
          tool_seen[tools[i]]=NR
        }
        date_count=split($3, date, "-")
        year=date[1] + 0
        month=date[2] + 0
        day=date[3] + 0
        month_days[1]=31
        month_days[2]=28 + (year % 4 == 0 &&
          (year % 100 != 0 || year % 400 == 0))
        month_days[3]=31
        month_days[4]=30
        month_days[5]=31
        month_days[6]=30
        month_days[7]=31
        month_days[8]=31
        month_days[9]=30
        month_days[10]=31
        month_days[11]=30
        month_days[12]=31
        if (NF != 6 ||
            $1 != endpoint ||
            $2 !~ /^[A-Za-z][A-Za-z0-9_]*(,[A-Za-z][A-Za-z0-9_]*)*$/ ||
            $3 !~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/ ||
            date_count != 3 ||
            year < 1 ||
            month < 1 || month > 12 ||
            day < 1 || day > month_days[month] ||
            $4 !~ /^(jira-issue-write|confluence-page-parent-write|confluence-page-update|confluence-page-read|jira-board-verification|confluence-folder-parent-write)$/ ||
            $5 !~ /^(official-contract|isolated-pilot)$/ ||
            $6 !~ /^(SUPPORTED|UNSUPPORTED)$/) invalid=1
        pair=$1 SUBSEP $4
        if (++pair_count[pair] > 1) invalid=1
        if ($1 == endpoint && $4 == capability) {
          matches++
          row=$2 "\t" $6
        }
      }
      END {
        if (invalid || matches != 1) exit 1
        print row
      }
    ' "$lpc_file") || return 1
  lpc_old_ifs=$IFS
  IFS="$(printf '\t')"
  set -- $lpc_row
  IFS=$lpc_old_ifs
  [ "$#" -eq 2 ] || return 1
  CAPABILITY_REQUIRED_TOOLS=$1
  CAPABILITY_PROVIDER_STATE=$2
}

inventory_has_required_tools() {
  ihrr_old_ifs=$IFS
  IFS=,
  set -- $CAPABILITY_REQUIRED_TOOLS
  IFS=$ihrr_old_ifs
  for ihrr_tool in "$@"; do
    inventory_has_tool "$ihrr_tool" || return 1
  done
}

resolve_legacy_capability() {
  rcap_client=$1 rcap_capability=$2
  CAPABILITY_STATE=UNKNOWN
  CAPABILITY_EVIDENCE_SOURCE=NONE
  CAPABILITY_INVENTORY_STATE=UNAVAILABLE
  connector_inventory "$rcap_client" legacy || return 0
  if [ "$CAPABILITY_INVENTORY_COMPLETE" -eq 1 ]; then
    CAPABILITY_INVENTORY_STATE=COMPLETE
  fi
  runtime_capability "$rcap_capability" || return 1
  if [ "$CAPABILITY_STATE" != UNKNOWN ]; then
    CAPABILITY_EVIDENCE_SOURCE=RUNTIME_INVENTORY
    return 0
  fi
  rcap_compat=$(legacy_compatibility_capability \
    "$rcap_client" "$rcap_capability") || rcap_compat=
  case "$rcap_compat" in
    SUPPORTED|UNSUPPORTED)
      CAPABILITY_STATE=$rcap_compat
      CAPABILITY_EVIDENCE_SOURCE=LEGACY_COMPATIBILITY
      ;;
    *) CAPABILITY_STATE=UNKNOWN ;;
  esac
}

resolve_provider_capability() {
  rpc_client=$1 rpc_capability=$2
  CAPABILITY_STATE=UNKNOWN
  CAPABILITY_EVIDENCE_SOURCE=NONE
  CAPABILITY_INVENTORY_STATE=UNAVAILABLE
  case "$rpc_capability" in
    jira-board-verification|confluence-folder-parent-write) return 0 ;;
  esac
  load_provider_capability "$rpc_capability" || return 0
  [ "$CAPABILITY_PROVIDER_STATE" = SUPPORTED ] || {
    CAPABILITY_STATE=UNSUPPORTED
    CAPABILITY_EVIDENCE_SOURCE=PROVIDER_CONTRACT
    return 0
  }
  connector_inventory "$rpc_client" || return 0
  if [ -n "$CAPABILITY_INVENTORY_FORMAT" ]; then
    if inventory_has_required_tools; then
      :
    elif [ "$CAPABILITY_INVENTORY_COMPLETE" -eq 1 ]; then
      CAPABILITY_INVENTORY_STATE=COMPLETE
      CAPABILITY_STATE=UNSUPPORTED
      CAPABILITY_EVIDENCE_SOURCE=RUNTIME_INVENTORY
      return 0
    else
      return 0
    fi
  fi
  if [ "$CAPABILITY_INVENTORY_COMPLETE" -eq 1 ]; then
    CAPABILITY_INVENTORY_STATE=COMPLETE
  fi
  CAPABILITY_STATE=SUPPORTED
  CAPABILITY_EVIDENCE_SOURCE=PROVIDER_CONTRACT
}

resolve_capability() {
  rcap_client=$1 rcap_capability=$2
  rcap_schema=$(atlassian_compatibility_schema \
    "$RELEASE_DIR/runtime/compatibility/atlassian.tsv") || {
    CAPABILITY_STATE=UNKNOWN
    CAPABILITY_EVIDENCE_SOURCE=NONE
    CAPABILITY_INVENTORY_STATE=UNAVAILABLE
    return 0
  }
  case "$rcap_schema" in
    1) resolve_legacy_capability "$rcap_client" "$rcap_capability" ;;
    2) resolve_provider_capability "$rcap_client" "$rcap_capability" ;;
  esac
}

detect_client() {
  dc_count=0 dc_1= dc_2= dc_3=
  for dc_client in codex claude cursor; do
    dc_executable=$(client_executable "$dc_client")
    if command -v "$dc_executable" >/dev/null 2>&1; then
      dc_count=$((dc_count + 1))
      case "$dc_count" in
        1) dc_1=$dc_client ;;
        2) dc_2=$dc_client ;;
        3) dc_3=$dc_client ;;
      esac
    fi
  done
  case "$dc_count" in
    0) die DEPENDENCY_MISSING 'No supported client detected' ;;
    1)
      dc_client=$dc_1
      printf '%s\n' "Detected client: $dc_client" >&2
      printf 'Use this client? [y/N] ' >&2
      IFS= read -r dc_answer || dc_answer=
      case "$dc_answer" in
        y|Y|yes|YES) printf '%s\n' "$dc_client" ;;
        *) die GOVERNANCE_NOT_READY 'Connector setup cancelled' ;;
      esac
      ;;
    *)
      printf '%s\n' 'Select one client:' "  1) $dc_1" "  2) $dc_2" >&2
      [ -z "$dc_3" ] || printf '%s\n' "  3) $dc_3" >&2
      printf 'Client: ' >&2
      IFS= read -r dc_answer || dc_answer=
      case "$dc_answer" in
        1) dc_client=$dc_1 ;;
        2) dc_client=$dc_2 ;;
        3) dc_client=$dc_3 ;;
        *) usage >&2; exit 2 ;;
      esac
      [ -n "$dc_client" ] || { usage >&2; exit 2; }
      printf '%s\n' "$dc_client"
      ;;
  esac
}

auth_required() {
  ar_client=$1
  printf '%s\n' \
    "Client: $ar_client" \
    'Provider: atlassian' \
    'Authentication: AUTH_REQUIRED' \
    "Remediation: $(oauth_command "$ar_client")"
  die ATLASSIAN_AUTH_REQUIRED
}

auth_pending() {
  ap_client=$1
  printf '%s\n' \
    "Client: $ap_client" \
    'Provider: atlassian' \
    'Authentication: AUTH_REQUIRED' \
    'Connector: AUTH_PENDING' \
    "Remediation: $(oauth_command "$ap_client")" \
    "Resume: beroka-governance setup-connectors --client $ap_client"
  die AUTH_PENDING
}

connector_health_unavailable() {
  chu_client=$1
  printf '%s\n' \
    "Client: $chu_client" \
    'Provider: atlassian' \
    'Connector: HEALTH_UNAVAILABLE' \
    "Resume: beroka-governance setup-connectors --client $chu_client"
  die CONNECTOR_HEALTH_UNAVAILABLE
}

github_auth_required() {
  gar_client=$1
  printf '%s\n' \
    "Client: $gar_client" \
    'Provider: github' \
    'Authentication: AUTH_REQUIRED' \
    "Remediation: $(github_oauth_command)"
  die GITHUB_AUTH_REQUIRED
}

github_preflight() {
  gp_client=$1 gp_non_interactive=$2
  require_github_client "$gp_client"
  gp_health=0
  github_auth_health || gp_health=$?
  case "$gp_health" in
    0) ;;
    1)
      gp_interactive=0
      if [ "$gp_non_interactive" -eq 0 ] && [ -t 0 ] && [ -t 1 ]; then
        gp_interactive=1
      fi
      [ "$gp_interactive" -eq 1 ] ||
        github_auth_required "$gp_client"
      printf '%s\n' \
        "Client: $gp_client" \
        'Provider: github' \
        'Authentication: AUTH_REQUIRED'
      printf 'Start OAuth now? [y/N] '
      IFS= read -r gp_answer || gp_answer=
      case "$gp_answer" in
        y|Y|yes|YES)
          gh auth login --hostname github.com --web ||
            github_auth_required "$gp_client"
          gp_health=0
          github_auth_health || gp_health=$?
          case "$gp_health" in
            0) ;;
            1) github_auth_required "$gp_client" ;;
            *)
              die GITHUB_ROLE_UNAVAILABLE \
                'Cannot verify GitHub authentication health'
              ;;
          esac
          ;;
        *) github_auth_required "$gp_client" ;;
      esac
      ;;
    *)
      die GITHUB_ROLE_UNAVAILABLE \
        'Cannot verify GitHub authentication health'
      ;;
  esac
  verify_github_role_membership "$gp_client"
  printf '%s\n' \
    "Client: $gp_client" \
    'Provider: github' \
    'Operation: github-write' \
    'Authentication: PASS' \
    'Result: PASS'
}
