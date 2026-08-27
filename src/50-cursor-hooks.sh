# Cursor workspace classification, receipts, validation, and hook commands.

cursor_require_jq() {
  command -v jq >/dev/null 2>&1 ||
    die GOVERNANCE_NOT_READY 'cursor-hook requires jq'
}

cursor_read_request() {
  cursor_require_jq
  CURSOR_REQUEST=$(cat) || return 1
  cursor_parse_request_fields || return 1
  cursor_resolve_workspaces
}

cursor_parse_request_fields() {
  printf '%s\n' "$CURSOR_REQUEST" | jq -se '
    length == 1 and (.[] |
      type == "object" and
      (.conversation_id | type == "string" and length > 0) and
      (.generation_id | type == "string" and length > 0) and
      (.workspace_roots | type == "array" and length >= 1 and
        all(.[]; type == "string" and length > 0)))
  ' >/dev/null 2>&1 || return 1
  CURSOR_CONVERSATION=$(printf '%s\n' "$CURSOR_REQUEST" | jq -r .conversation_id) || return 1
  CURSOR_GENERATION=$(printf '%s\n' "$CURSOR_REQUEST" | jq -r .generation_id) || return 1
}

cursor_probe_workspace_profile() {
  # Print "profile\tslug\trouting" for a git toplevel without altering caller state.
  cpw_top=$1
  (
    load_active_release
    resolve_repository_context "$cpw_top"
    printf '%s\t%s\t%s\n' "$ROUTE_PROFILE" "$REPOSITORY_SLUG" "$ROUTING_STATE"
  )
}

cursor_classify_governance() {
  CURSOR_GOVERNANCE_STATE=NOT_GOVERNED
  while IFS= read -r ccg_top; do
    [ -n "$ccg_top" ] || continue
    ccg_probe=$(cursor_probe_workspace_profile "$ccg_top") || return 1
    ccg_state=${ccg_probe##*	}
    [ "$ccg_state" != ROUTING_ACTIVE ] || {
      CURSOR_GOVERNANCE_STATE=ROUTING_ACTIVE
      return 0
    }
  done <<CURSOR_GOVERNANCE_EOF
$CURSOR_WORKSPACES
CURSOR_GOVERNANCE_EOF
}

cursor_resolve_workspaces() {
  CURSOR_WORKSPACE=
  CURSOR_WORKSPACE_MODE=single
  CURSOR_BACKEND_WORKSPACE=
  CURSOR_FRONTEND_WORKSPACE=
  CURSOR_WORKSPACES=
  crr_count=0
  crr_list=
  while IFS= read -r crr_root; do
    [ -n "$crr_root" ] || continue
    crr_top=$(git -C "$crr_root" rev-parse --show-toplevel 2>/dev/null) || continue
    crr_top=$(CDPATH= cd -- "$crr_top" && pwd -P) || continue
    case "$crr_list" in
      *"|$crr_top|"*) continue ;;
    esac
    crr_list="$crr_list|$crr_top|"
    crr_count=$((crr_count + 1))
    CURSOR_WORKSPACES="$CURSOR_WORKSPACES
$crr_top"
  done <<CURSOR_ROOTS_EOF
$(printf '%s\n' "$CURSOR_REQUEST" | jq -r '.workspace_roots[]')
CURSOR_ROOTS_EOF
  CURSOR_WORKSPACES=$(printf '%s\n' "$CURSOR_WORKSPACES" | sed '/^$/d')
  [ "$crr_count" -ge 1 ] || return 1
  CURSOR_WORKSPACE=$(printf '%s\n' "$CURSOR_WORKSPACES" | sed -n '1p')
  cursor_classify_governance || return 1
  if [ "$CURSOR_GOVERNANCE_STATE" = NOT_GOVERNED ]; then
    return 0
  fi
  if [ "$crr_count" -eq 1 ]; then
    CURSOR_WORKSPACE_MODE=single
    return 0
  fi

  # FULL_STACK may open the exact Backend+Frontend catalog pair. Any other
  # multi-root shape stays fail-closed so unknown repos never inherit BE/FE.
  load_active_release || return 1
  read_github_role || return 1
  [ "$GITHUB_ROLE" = FULL_STACK ] || return 1
  [ "$crr_count" -eq 2 ] || return 1
  crr_backend=
  crr_frontend=
  while IFS= read -r crr_top; do
    [ -n "$crr_top" ] || continue
    crr_probe=$(cursor_probe_workspace_profile "$crr_top") || return 1
    crr_profile=${crr_probe%%	*}
    crr_rest=${crr_probe#*	}
    crr_slug=${crr_rest%%	*}
    crr_routing=${crr_rest##*	}
    [ "$crr_routing" = ROUTING_ACTIVE ] || return 1
    case "$crr_profile:$crr_slug" in
      backend:beroka-vn/Beroka_Backend)
        [ -z "$crr_backend" ] || return 1
        crr_backend=$crr_top
        ;;
      frontend:beroka-vn/Beroka_Frontend)
        [ -z "$crr_frontend" ] || return 1
        crr_frontend=$crr_top
        ;;
      *) return 1 ;;
    esac
  done <<CURSOR_PAIR_EOF
$CURSOR_WORKSPACES
CURSOR_PAIR_EOF
  [ -n "$crr_backend" ] && [ -n "$crr_frontend" ] || return 1
  CURSOR_BACKEND_WORKSPACE=$crr_backend
  CURSOR_FRONTEND_WORKSPACE=$crr_frontend
  CURSOR_WORKSPACE=$crr_backend
  CURSOR_WORKSPACE_MODE=be-fe
  return 0
}

# Extract one Jira project key from structured MCP/tool JSON. Accepts bare
# project keys and issue keys (BB-34 -> BB), including parent/epic fields that
# Atlassian create payloads commonly send without a separate projectKey.
cursor_jira_project_values_jq='
  [
    .. | objects |
    (.projectKey?, .project?, .issueKey?, .issue_key?, .issueIdOrKey?,
     .parent?, .parentKey?, .parent_key?, .epic?, .epicKey?, .epic_key?) |
    select(type == "string") |
    if test("^[A-Z][A-Z0-9_]*$") then .
    elif test("^[A-Z][A-Z0-9_]*-[1-9][0-9]*$") then
      capture("^(?<project>[A-Z][A-Z0-9_]*)-").project
    else empty end
  ] | unique
'

cursor_extract_single_jira_project() {
  printf '%s\n' "$1" | jq -r \
    "$cursor_jira_project_values_jq | if length == 1 then .[0] else empty end" \
    2>/dev/null
}

# Cursor hooks often inherit a minimal PATH that omits the user bin where
# bootstrap installs beroka-governance and cursor-agent. Append those dirs only
# when a required dependency is missing, so an earlier healthy executable keeps
# precedence over ~/.local/bin.
cursor_ensure_user_path() {
  cup_need=0
  command -v cursor-agent >/dev/null 2>&1 || cup_need=1
  command -v gh >/dev/null 2>&1 || cup_need=1
  [ "$cup_need" -eq 1 ] || return 0
  for cup_dir in "$BIN_DIR" "${HOME}/.local/bin"; do
    [ -n "$cup_dir" ] || continue
    case ":${PATH}:" in
      *":${cup_dir}:"*) continue ;;
    esac
    [ -d "$cup_dir" ] || continue
    PATH="${PATH}:${cup_dir}"
  done
  export PATH
}

# Drop workspace_roots before path/name heuristics so real clone folders named
# Beroka_Backend + Beroka_Frontend cannot permanently set both BE and FE flags.
cursor_request_without_roots() {
  printf '%s\n' "$CURSOR_REQUEST" | jq -c 'del(.workspace_roots)' 2>/dev/null ||
    printf '%s\n' "$CURSOR_REQUEST"
}

cursor_select_be_fe_workspace() {
  [ "$CURSOR_WORKSPACE_MODE" = be-fe ] || return 1

  # Unique structured Jira project from tool_input wins over any name heuristic.
  csw_source=${CURSOR_TOOL_INPUT:-}
  if [ -z "$csw_source" ] || [ "$csw_source" = '{}' ]; then
    csw_source=$(cursor_request_without_roots)
  fi
  csw_project=$(cursor_extract_single_jira_project "$csw_source") || csw_project=
  case "$csw_project" in
    BB)
      CURSOR_WORKSPACE=$CURSOR_BACKEND_WORKSPACE
      return 0
      ;;
    BF)
      CURSOR_WORKSPACE=$CURSOR_FRONTEND_WORKSPACE
      return 0
      ;;
  esac

  csw_text=$(cursor_request_without_roots | tr '[:upper:]' '[:lower:]')
  csw_be=0
  csw_fe=0
  case "$csw_text" in
    *beroka_backend*|*beroka-backend*|*berokaback*) csw_be=1 ;;
  esac
  case "$csw_text" in
    *beroka_frontend*|*beroka-frontend*|*berokafront*) csw_fe=1 ;;
  esac
  if [ "$csw_be" -eq 1 ] && [ "$csw_fe" -eq 0 ]; then
    CURSOR_WORKSPACE=$CURSOR_BACKEND_WORKSPACE
    return 0
  fi
  if [ "$csw_fe" -eq 1 ] && [ "$csw_be" -eq 0 ]; then
    CURSOR_WORKSPACE=$CURSOR_FRONTEND_WORKSPACE
    return 0
  fi
  return 1
}

cursor_receipt_path() {
  cursor_hash=$(printf '%s' "$CURSOR_CONVERSATION" | shasum -a 256 2>/dev/null | awk '{print $1}') || return 1
  printf '%s\n' "$cursor_hash" | grep -Eq '^[0-9a-f]{64}$' || return 1
  printf '%s\n' "$CURSOR_STATE_ROOT/$cursor_hash.json"
}

cursor_write_receipt() {
  cursor_language=$1
  mkdir -p "$CURSOR_STATE_ROOT" || die GOVERNANCE_NOT_READY 'Cannot create Cursor state directory'
  chmod 700 "$CURSOR_STATE_ROOT" || die GOVERNANCE_NOT_READY 'Cannot secure Cursor state directory'
  cursor_receipt=$(cursor_receipt_path) || die GOVERNANCE_NOT_READY 'Cannot derive Cursor receipt path'
  cursor_tmp=$(umask 077; mktemp "$CURSOR_STATE_ROOT/.receipt.XXXXXX") ||
    die GOVERNANCE_NOT_READY 'Cannot create Cursor receipt'
  if [ "$CURSOR_WORKSPACE_MODE" = be-fe ]; then
    if ! jq -nc \
      --arg workspace "$CURSOR_WORKSPACE" \
      --arg repository "$REPOSITORY_SLUG" \
      --arg backend "$CURSOR_BACKEND_WORKSPACE" \
      --arg frontend "$CURSOR_FRONTEND_WORKSPACE" \
      --arg generation "$CURSOR_GENERATION" \
      --arg version "$ACTIVE_VERSION" \
      --arg commit "$ACTIVE_COMMIT" \
      --arg language "$cursor_language" \
      '{
         mode:"be-fe",
         workspace:$workspace,
         repository:$repository,
         workspaces:[$backend,$frontend],
         repositories:["beroka-vn/Beroka_Backend","beroka-vn/Beroka_Frontend"],
         generation:$generation,
         version:$version,
         commit:$commit,
         language:$language
       }' >"$cursor_tmp" || ! chmod 600 "$cursor_tmp" || ! mv "$cursor_tmp" "$cursor_receipt"
    then
      rm -f "$cursor_tmp" || :
      die GOVERNANCE_NOT_READY 'Cannot write Cursor receipt'
    fi
    return
  fi
  if ! jq -nc \
    --arg workspace "$CURSOR_WORKSPACE" \
    --arg repository "$REPOSITORY_SLUG" \
    --arg generation "$CURSOR_GENERATION" \
    --arg version "$ACTIVE_VERSION" \
    --arg commit "$ACTIVE_COMMIT" \
    --arg language "$cursor_language" \
    '{mode:"single",workspace:$workspace,repository:$repository,generation:$generation,version:$version,commit:$commit,language:$language}' \
    >"$cursor_tmp" || ! chmod 600 "$cursor_tmp" || ! mv "$cursor_tmp" "$cursor_receipt"; then
    rm -f "$cursor_tmp" || :
    die GOVERNANCE_NOT_READY 'Cannot write Cursor receipt'
  fi
}

cursor_invalidate_receipt() {
  cursor_receipt=$(cursor_receipt_path) || return 1
  [ -f "$cursor_receipt" ] && [ ! -L "$cursor_receipt" ] || return 1
  cursor_tmp=$(umask 077; mktemp "$CURSOR_STATE_ROOT/.receipt.XXXXXX") || return 1
  if ! jq '.generation = ""' "$cursor_receipt" >"$cursor_tmp" ||
     ! chmod 600 "$cursor_tmp" || ! mv "$cursor_tmp" "$cursor_receipt"; then
    rm -f "$cursor_tmp" || :
    return 1
  fi
}

cursor_clear_receipts() {
  assert_safe_user_path "$CURSOR_STATE_ROOT" 'Cursor state'
  [ ! -e "$CURSOR_STATE_ROOT" ] || [ -d "$CURSOR_STATE_ROOT" ] ||
    die GOVERNANCE_NOT_READY 'Cursor state is not a directory'
  [ -d "$CURSOR_STATE_ROOT" ] || return 0
  for cursor_receipt in "$CURSOR_STATE_ROOT"/*.json; do
    [ -e "$cursor_receipt" ] || continue
    [ -f "$cursor_receipt" ] && [ ! -L "$cursor_receipt" ] ||
      die GOVERNANCE_NOT_READY 'Unsafe Cursor receipt'
    rm -f "$cursor_receipt" ||
      die GOVERNANCE_NOT_READY 'Cannot clear Cursor receipt'
  done
}

cursor_receipt_matches() {
  cursor_generation_required=$1
  cursor_receipt=$(cursor_receipt_path) || return 1
  [ -f "$cursor_receipt" ] && [ ! -L "$cursor_receipt" ] || return 1
  if [ "$cursor_generation_required" -eq 1 ]; then
    jq -e \
      --arg workspace "$CURSOR_WORKSPACE" \
      --arg repository "$REPOSITORY_SLUG" \
      --arg generation "$CURSOR_GENERATION" \
      --arg version "$ACTIVE_VERSION" \
      --arg commit "$ACTIVE_COMMIT" \
      --arg mode "$CURSOR_WORKSPACE_MODE" \
      '
       .version == $version and .commit == $commit and
       .generation == $generation and
       (.language | type == "string" and length > 0) and
       (
         ((.mode // "single") == "single" and $mode == "single" and
          .workspace == $workspace and .repository == $repository) or
         ((.mode // "single") == "be-fe" and $mode == "be-fe" and
          (.workspaces | type == "array") and
          (.repositories | type == "array") and
          any(.workspaces[]; . == $workspace) and
          any(.repositories[]; . == $repository))
       )
      ' "$cursor_receipt" >/dev/null 2>&1 || return 1
  else
    jq -e \
      --arg workspace "$CURSOR_WORKSPACE" \
      --arg repository "$REPOSITORY_SLUG" \
      --arg version "$ACTIVE_VERSION" \
      --arg commit "$ACTIVE_COMMIT" \
      --arg mode "$CURSOR_WORKSPACE_MODE" \
      '
       .version == $version and .commit == $commit and
       (.language | type == "string" and length > 0) and
       (
         ((.mode // "single") == "single" and $mode == "single" and
          .workspace == $workspace and .repository == $repository) or
         ((.mode // "single") == "be-fe" and $mode == "be-fe" and
          (.workspaces | type == "array") and
          (.repositories | type == "array") and
          any(.workspaces[]; . == $workspace) and
          any(.repositories[]; . == $repository))
       )
      ' "$cursor_receipt" >/dev/null 2>&1 || return 1
  fi
  CURSOR_LANGUAGE=$(jq -r .language "$cursor_receipt") || return 1
}

cursor_deny() {
  cursor_code=$1 cursor_message=$2
  jq -nc --arg code "$cursor_code" --arg message "$cursor_message" \
    '{permission:"deny",user_message:("Result: " + $code),agent_message:$message}'
}

cursor_allow() {
  jq -nc '{permission:"allow"}'
}

cursor_block_prompt() {
  cbp_code=$1 cbp_message=$2
  jq -nc --arg code "$cbp_code" --arg message "$cbp_message" \
    '{continue:false,user_message:("Result: " + $code + " — " + $message)}'
}

cursor_language_from_prompt() {
  cursor_prompt=$1
  printf '%s\n' "$cursor_prompt" | awk '
    function lower(value) { return tolower(value) }
    {
      candidate=$0
      if (lower(candidate) ~ /^work-item language:/) {
        value=candidate
        sub(/^[^:]*:[[:space:]]*/, "", value)
        normalized=lower(value)
        if (normalized == "english") normalized="en"
        else if (normalized == "vietnamese") normalized="vi"
        else if (normalized !~ /^[a-z][a-z0-9-]{1,31}$/) invalid=1
        if (seen++ || invalid) exit 42
        language=normalized
      }
    }
    END { if (invalid || seen > 1) exit 42; if (seen == 1) print language }
  '
}

cursor_context() {
  load_active_release
  resolve_repository_context "$CURSOR_WORKSPACE"
}

cmd_cursor_session_start() {
  cursor_read_request || die GOVERNANCE_CONTEXT_REQUIRED \
    'Cursor hook input requires one Git workspace or a FULL_STACK Backend+Frontend pair.'
  if [ "$CURSOR_GOVERNANCE_STATE" = NOT_GOVERNED ]; then
    cursor_context_output=$(cmd_context "$CURSOR_WORKSPACE") ||
      die GOVERNANCE_CONTEXT_REQUIRED
    jq -nc --arg context "$cursor_context_output" \
      '{env:{BEROKA_GOVERNANCE_CONTEXT:"NOT_GOVERNED"},additional_context:$context}'
    return
  fi
  if [ "$CURSOR_WORKSPACE_MODE" = be-fe ]; then
    cursor_backend_context=$(cmd_context "$CURSOR_BACKEND_WORKSPACE") ||
      die GOVERNANCE_CONTEXT_REQUIRED
    cursor_frontend_context=$(cmd_context "$CURSOR_FRONTEND_WORKSPACE") ||
      die GOVERNANCE_CONTEXT_REQUIRED
    CURSOR_WORKSPACE=$CURSOR_BACKEND_WORKSPACE
    cursor_context
    cursor_context_output=$(printf '%s\n%s\n\n%s\n' \
      'Multi-root mode: FULL_STACK Backend+Frontend. Governed writes must name the exact BB/BF project or beroka-vn Backend/Frontend repository target.' \
      "$cursor_backend_context" "$cursor_frontend_context")
  else
    cursor_context
    cursor_context_output=$(cmd_context "$CURSOR_WORKSPACE") || die GOVERNANCE_CONTEXT_REQUIRED
  fi
  cursor_write_receipt en
  jq -nc --arg context "$cursor_context_output" \
    '{env:{BEROKA_GOVERNANCE_CONTEXT:"PASS"},additional_context:$context}'
}

cmd_cursor_before_submit_prompt() {
  # Cursor only blocks a submission on {"continue":false} (exit 0) or exit code 2;
  # any other non-zero exit is treated as a hook failure and fails open. Emit an
  # explicit decision so the governed submit-time checks actually take effect.
  cursor_read_request || {
    cursor_block_prompt GOVERNANCE_CONTEXT_REQUIRED \
      'Cursor hook input requires one Git workspace or a FULL_STACK Backend+Frontend pair.'
    return
  }
  if [ "$CURSOR_GOVERNANCE_STATE" = NOT_GOVERNED ]; then
    printf '%s\n' '{}'
    return
  fi
  cursor_context
  cursor_prompt=$(printf '%s\n' "$CURSOR_REQUEST" | jq -er '.prompt // "" | if type == "string" then . else error("prompt") end') || {
    cursor_block_prompt WORK_ITEM_LANGUAGE_REQUIRED 'Prompt must be text.'
    return
  }
  cursor_language_state=0
  cursor_language=$(cursor_language_from_prompt "$cursor_prompt") || cursor_language_state=$?
  if [ "$cursor_language_state" -ne 0 ]; then
    cursor_block_prompt WORK_ITEM_LANGUAGE_REQUIRED \
      'Use one complete "Work-item language: <language>" directive.'
    return
  fi
  [ -n "$cursor_language" ] || cursor_language=en
  # Missing or stale receipts (for example after a release upgrade) are
  # rewritten here. Cursor does not re-fire sessionStart mid-conversation.
  cursor_write_receipt "$cursor_language"
  printf '%s\n' '{}'
}

cmd_cursor_pre_compact() {
  cursor_read_request || die GOVERNANCE_CONTEXT_REQUIRED 'Cursor hook input requires one Git workspace'
  if [ "$CURSOR_GOVERNANCE_STATE" = NOT_GOVERNED ]; then
    printf '%s\n' '{}'
    return
  fi
  cursor_context
  cursor_receipt_matches 0 ||
    die GOVERNANCE_CONTEXT_REQUIRED 'Run cursor-hook sessionStart first'
  cursor_invalidate_receipt ||
    die GOVERNANCE_NOT_READY 'Cannot invalidate Cursor receipt'
  jq -nc '{}'
}

cursor_tool_provider() {
  CURSOR_TOOL_NAME=$(printf '%s\n' "$CURSOR_REQUEST" | jq -r '.tool_name // .name // ""') || return 1
  CURSOR_TOOL_URL=$(printf '%s\n' "$CURSOR_REQUEST" | jq -r '.url // ""') || return 1
  CURSOR_TOOL_COMMAND=$(printf '%s\n' "$CURSOR_REQUEST" | jq -r '.command // ""') || return 1
  # Cursor may pass tool_input as an object or as a JSON string. Parse strings
  # so createJiraIssue fields remain visible to template and BE/FE selection.
  CURSOR_TOOL_INPUT=$(printf '%s\n' "$CURSOR_REQUEST" | jq -c '
    .tool_input // {} |
    if type == "object" then .
    elif type == "string" then (fromjson? // {})
    else {} end
  ') || return 1
  CURSOR_TOOL_TEXT=$(printf '%s %s %s' "$CURSOR_TOOL_NAME" "$CURSOR_TOOL_URL" "$CURSOR_TOOL_COMMAND" | tr '[:upper:]' '[:lower:]')
  case "$CURSOR_TOOL_TEXT" in
    *github.com*|*github*) CURSOR_PROVIDER=github ;;
    *confluence*|*/wiki*) CURSOR_PROVIDER=confluence ;;
    *atlassian.net*|*jira*) CURSOR_PROVIDER=jira ;;
    *) CURSOR_PROVIDER= ;;
  esac
  case "$CURSOR_TOOL_TEXT" in
    *create*|*update*|*edit*|*comment*|*move*|*transition*) CURSOR_TOOL_WRITE=1 ;;
    *) CURSOR_TOOL_WRITE=0 ;;
  esac
}

cursor_private_repo_link() {
  cprl_slug=$1
  # Ignore workspace_roots so multi-root BE+FE paths never look like a
  # cross-team private link by themselves.
  cursor_request_without_roots |
    tr '[:upper:]' '[:lower:]' |
    grep -F "$cprl_slug" >/dev/null
}

cursor_cross_team_private_link() {
  case "$REPOSITORY_SLUG" in
    beroka-vn/Beroka_Backend)
      cursor_private_repo_link beroka-vn/beroka_frontend ;;
    beroka-vn/Beroka_Frontend)
      cursor_private_repo_link beroka-vn/beroka_backend ;;
    *) return 1 ;;
  esac
}

cursor_has_nonempty_field() {
  printf '%s\n' "$CURSOR_TOOL_INPUT" | jq -e --arg field "$1" \
    '.. | objects | .[$field]? | strings | select(length > 0)' >/dev/null 2>&1
}

cursor_has_value() {
  printf '%s\n' "$CURSOR_TOOL_INPUT" | jq -e --arg field "$1" \
    '.. | objects | .[$field]? | select(. != null and . != "")' >/dev/null 2>&1
}

cursor_stage_exact_body() {
  cseb_kind=$1
  case "$cseb_kind" in
    confluence)
      cseb_query='[.. | objects | (.body?, .content?) | select(type == "string" and length > 0)] | unique'
      ;;
    jira)
      cseb_query='[.. | strings | select(length > 0)]'
      ;;
    *) return 1 ;;
  esac
  cseb_count=$(printf '%s\n' "$CURSOR_TOOL_INPUT" | jq -r "$cseb_query | length") ||
    return 1
  case "$cseb_kind:$cseb_count" in confluence:1|jira:[1-9]*) ;; *) return 1 ;; esac
  PERSONAL_STAGE_ROOT=$(umask 077; mktemp -d \
    "${TMPDIR:-/tmp}/beroka-governance-cursor-body.XXXXXX") || return 1
  trap 'cursor_cleanup_staged_body || :' EXIT
  trap 'cursor_cleanup_staged_body || :; exit 1' HUP INT TERM
  CURSOR_EXACT_BODY_FILE=$PERSONAL_STAGE_ROOT/body
  printf '%s\n' "$CURSOR_TOOL_INPUT" | {
    if [ "$cseb_kind" = jira ]; then
      jq -jr "$cseb_query | .[] | ., \"\\n\""
    else
      jq -jr "$cseb_query | .[0]"
    fi
  } >"$CURSOR_EXACT_BODY_FILE" || {
      cursor_cleanup_staged_body || :
      return 1
    }
  [ -s "$CURSOR_EXACT_BODY_FILE" ] || {
    cursor_cleanup_staged_body || :
    return 1
  }
}

cursor_handoff_intent() {
  LC_ALL=C awk '
    function strip_markdown_prefixes(line) {
      sub(/^[[:space:]]+/, "", line)
      while (line ~ /^(#+|>|[-+*]|[0-9]+[.)])[[:space:]]+/) {
        sub(/^(#+|>|[-+*]|[0-9]+[.)])[[:space:]]+/, "", line)
        sub(/^[[:space:]]+/, "", line)
      }
      return line
    }
    {
      line = strip_markdown_prefixes(tolower($0))
      if (line ~ /^(handoff schema|handoff state|provider jira|consumer jira|confluence content id|confluence page version|owner account id|effective date|supersedes|superseded by|api impact|websocket impact|missing sections|fe acknowledgment)[[:space:]]*(:|$)/) {
        header = 1
      }
      if (line ~ /^handoff[[:space:]]+[—-]/ ||
          line ~ /^handoff form[[:space:]]*:/) legacy=1
      if (line ~ /ready_for_fe|ready[[:space:]_-]+for[[:space:]_-]+fe/) readiness=1
      if (line ~ /(^|[^[:alnum:]])bb-[1-9][0-9]*([^[:alnum:]]|$)/) backend=1
      if (line ~ /(^|[^[:alnum:]])bf-[1-9][0-9]*([^[:alnum:]]|$)/) frontend=1
      if (line ~ /github[.]com|git@github/) repository=1
      if (line ~ /acknowledg|reviewed|accepted/) acknowledgment=1
      if (line ~ /confluence|atlassian[.]net\/wiki|content[[:space:]]+id|page[[:space:]]+[1-9][0-9]*/) confluence=1
    }
    END {
      found = header || readiness || (backend && frontend) ||
        (legacy && repository) || (acknowledgment && confluence)
      exit(found ? 0 : 1)
    }
  '
}

cursor_jira_handoff_shaped() {
  printf '%s\n' "$CURSOR_TOOL_INPUT" |
    jq -r '.. | strings | select(length > 0)' 2>/dev/null |
    cursor_handoff_intent
}

cursor_cleanup_staged_body() {
  [ -n "$PERSONAL_STAGE_ROOT" ] || return 0
  cleanup_personal_stage || return 1
  trap - EXIT HUP INT TERM
}

cursor_staged_preflight() {
  trap 'cursor_cleanup_staged_body || :' EXIT
  trap 'cursor_cleanup_staged_body || :; exit 1' HUP INT TERM
  cmd_preflight "$@"
  csp_status=$?
  cursor_cleanup_staged_body || return 1
  return "$csp_status"
}

# Atlassian MCP createJiraIssue uses issueTypeName / assignee_account_id /
# additional_fields.priority{name} and forbids unknown top-level keys. Accept
# those official shapes as aliases of the governance template fields.
cursor_jira_has_project() {
  cursor_has_nonempty_field project ||
    cursor_has_nonempty_field projectKey
}

cursor_jira_has_issue_type() {
  cursor_has_nonempty_field issue_type ||
    cursor_has_nonempty_field issueTypeName ||
    cursor_has_nonempty_field issueType ||
    cursor_has_nonempty_field issuetype
}

cursor_jira_has_priority() {
  cursor_has_nonempty_field priority && return 0
  printf '%s\n' "$CURSOR_TOOL_INPUT" | jq -e '
    any(
      .. | objects | .priority?;
      (type == "string" and length > 0) or
      (type == "object" and
        ((.name // .id // "") | type == "string" and length > 0))
    )
  ' >/dev/null 2>&1
}

cursor_jira_has_assignee() {
  cursor_has_nonempty_field assignee ||
    cursor_has_nonempty_field owner ||
    cursor_has_nonempty_field assignee_account_id ||
    cursor_has_nonempty_field accountId
}

cursor_jira_has_parent_or_standalone() {
  cursor_has_nonempty_field parent ||
    cursor_has_nonempty_field parentKey ||
    cursor_has_nonempty_field standalone_reason
}

cursor_jira_has_github_link() {
  cursor_has_nonempty_field github && return 0
  # Accept explicit N/A or a GitHub URL/marker inside description/body text so
  # agents need not smuggle a github key into Atlassian MCP (additionalProperties
  # false on createJiraIssue).
  printf '%s\n' "$CURSOR_TOOL_INPUT" |
    jq -r '
      [
        .. | objects |
        (.github?, .description?, .body?, .content?, .summary?) |
        select(type == "string" and length > 0)
      ] | join("\n")
    ' 2>/dev/null |
    grep -Ei '(^|[^A-Za-z])N/A([^A-Za-z]|$)|github\.com|[[:space:]]GitHub:' >/dev/null
}

cursor_jira_has_assignee_like() {
  cursor_has_value assignee ||
    cursor_has_value owner ||
    cursor_has_value assignee_account_id ||
    cursor_has_value accountId
}

cursor_template_missing_push() {
  if [ -z "${CURSOR_TEMPLATE_MISSING:-}" ]; then
    CURSOR_TEMPLATE_MISSING=$1
  else
    CURSOR_TEMPLATE_MISSING="$CURSOR_TEMPLATE_MISSING, $1"
  fi
}

cursor_jira_operation() {
  cjo_project=$(cursor_extract_single_jira_project "$CURSOR_TOOL_INPUT") || cjo_project=
  [ -n "$cjo_project" ] || return 2
  if [ "$cjo_project" = "$ROUTE_JIRA_PROJECT_KEY" ]; then
    case "$CURSOR_TOOL_TEXT" in
      *update*|*edit*|*comment*)
        if cursor_jira_handoff_shaped; then
          printf '%s\n' jira-handoff-write
          return
        fi
        ;;
    esac
    printf '%s\n' jira-write
    return
  fi
  case "$CURSOR_TOOL_TEXT" in *create*) ;; *) return 1 ;; esac
  cjo_target=$(
    (
      resolve_intake_route
      printf '%s\n' "$INTAKE_TARGET_JIRA_PROJECT"
    ) 2>/dev/null
  ) || return 1
  [ "$cjo_project" = "$cjo_target" ] || return 1
  printf '%s\n' jira-intake-write
}

cursor_confluence_marker() {
  ccm_label=$1
  awk -v label="$ccm_label" '
    {
      sub(/\r$/, "")
      sub(/^[[:space:]]*-[[:space:]]+/, "")
      prefix=label ":"
      if (index($0, prefix) == 1) {
        value=substr($0, length(prefix) + 1)
        sub(/^[[:space:]]+/, "", value)
        if (value == "" || seen++) invalid=1
        result=value
      }
    }
    END { if (invalid || seen != 1) exit 1; print result }
  '
}

cursor_confluence_handoff_ok() {
  ccho_body=$1
  ccho_title=$2
  ccho_jira=$(printf '%s\n' "$ccho_body" | cursor_confluence_marker Jira) ||
    return 1
  case "$ccho_jira" in
    http://*|https://*) ;;
    *)
      printf '%s\n' "$ccho_jira" |
        grep -Eq '^[A-Z][A-Z0-9]+-[1-9][0-9]*$' || return 1
      ;;
  esac
  ccho_github=$(printf '%s\n' "$ccho_body" |
    cursor_confluence_marker GitHub) || return 1
  case "$ccho_github" in
    N/A|http://*|https://*|git@*) ;;
    *) return 1 ;;
  esac
  if printf '%s\n' "$ccho_body" | grep -Eq '^#+[[:space:]]+Handoff[[:space:]]+[—-]'
  then
    return 0
  fi
  ccho_form=$(printf '%s\n' "$ccho_body" |
    cursor_confluence_marker 'Handoff form') || return 1
  [ "$ccho_form" = child-page ] || return 1
  printf '%s\n' "$ccho_title" |
    grep -Eq '^Handoff[[:space:]]+[—-]' || return 1
  ccho_canonical=$(printf '%s\n' "$ccho_body" |
    cursor_confluence_marker Canonical) || return 1
  case "$ccho_canonical" in
    http://*|https://*) ;;
    *)
      printf '%s\n' "$ccho_canonical" | grep -Eq '^[1-9][0-9]*$' || return 1
      ;;
  esac
  return 0
}

cursor_confluence_preflight() {
  ccp_action=update
  case "$CURSOR_TOOL_TEXT" in
    *create*) ccp_action=create ;;
    *move*) ccp_action=move ;;
  esac
  if [ "$ccp_action" = create ]; then
    ccp_target=new
  else
    ccp_target=$(printf '%s\n' "$CURSOR_TOOL_INPUT" | jq -er '
      [.. | objects | (.pageId?, .contentId?) |
       select(type == "string")] | unique |
      if length == 1 then .[0] else error("target") end
    ' 2>/dev/null) || return 1
  fi
  ccp_parent=$(printf '%s\n' "$CURSOR_TOOL_INPUT" | jq -er '
    [.. | objects | .parentId? | select(type == "string")] | unique |
    if length == 0 then "" elif length == 1 then .[0] else error("parent") end
  ' 2>/dev/null) || return 1
  if [ "$ccp_action" = move ]; then
    printf '%s\n' "$ccp_parent" | grep -Eq '^[1-9][0-9]*$' || {
      printf '%s\n' \
        'Result: ROUTING_REQUIRED' \
        'Provide parentId as the numeric destination parent for Confluence moves.'
      return 1
    }
    set -- --confluence-action move --target-content-id "$ccp_target" \
      --expected-parent-id "$ccp_parent"
    cmd_preflight "$CURSOR_WORKSPACE" --client cursor \
      --operation confluence-write --non-interactive "$@"
    return $?
  fi
  ccp_body=$(printf '%s\n' "$CURSOR_TOOL_INPUT" | jq -er '
    [.. | objects | (.body?, .content?) | select(type == "string")] |
    unique | if length == 1 then .[0] else error("body") end
  ' 2>/dev/null) || return 1
  ccp_title=$(printf '%s\n' "$CURSOR_TOOL_INPUT" | jq -er '
    [.. | objects | .title? | select(type == "string")] | unique |
    if length == 0 then "" elif length == 1 then .[0] else error("title") end
  ' 2>/dev/null) || ccp_title=
  if printf '%s\n' "$ccp_body" | cursor_handoff_intent
  then
    cursor_stage_exact_body confluence || {
      printf '%s\n' \
        'Result: HANDOFF_BODY_REQUIRED' \
        'Provide exactly one non-empty Confluence body.'
      return 1
    }
    set -- --confluence-action "$ccp_action" --target-content-id "$ccp_target"
    if [ -n "$ccp_parent" ]; then
      set -- "$@" --expected-parent-id "$ccp_parent"
    fi
    CONFLUENCE_BODY_TRUSTED=1
    cursor_staged_preflight "$CURSOR_WORKSPACE" --client cursor \
      --operation confluence-handoff-write --non-interactive "$@" \
      --handoff-body-file "$CURSOR_EXACT_BODY_FILE"
    ccp_status=$?
    CONFLUENCE_BODY_TRUSTED=0
    return "$ccp_status"
  fi
  if ! cursor_confluence_handoff_ok "$ccp_body" "$ccp_title"; then
    printf '%s\n' \
      'Result: HANDOFF_DELTA_REQUIRED' \
      'Provide Jira: <KEY|URL>, GitHub: <URL|N/A>, and either a ## Handoff — <JiraKey> section or Handoff form: child-page with title Handoff — <JiraKey> — <slug> plus Canonical: <URL|content-id>.'
    return 1
  fi
  set -- --confluence-action "$ccp_action" --target-content-id "$ccp_target"
  if [ -n "$ccp_parent" ]; then
    set -- "$@" --expected-parent-id "$ccp_parent"
  fi
  CONFLUENCE_BODY_TRUSTED=1
  cmd_preflight "$CURSOR_WORKSPACE" --client cursor \
    --operation confluence-write --non-interactive "$@"
  ccp_status=$?
  CONFLUENCE_BODY_TRUSTED=0
  return "$ccp_status"
}

cursor_language_label() {
  case "$CURSOR_LANGUAGE" in en) printf '%s\n' English ;; vi) printf '%s\n' Vietnamese ;; *) printf '%s\n' "$CURSOR_LANGUAGE" ;; esac
}

cursor_validate_template() {
  CURSOR_TEMPLATE_MISSING=
  cursor_marker="Work-item language: $(cursor_language_label)"
  printf '%s\n' "$CURSOR_TOOL_INPUT" | grep -F "$cursor_marker" >/dev/null || return 3
  case "$CURSOR_TOOL_TEXT" in
    *transition*)
      cursor_has_nonempty_field status ||
        cursor_has_nonempty_field transition || {
          cursor_template_missing_push 'status|transition'
          return 1
        }
      return 0
      ;;
    *update*|*edit*|*comment*)
      cursor_has_nonempty_field body || cursor_has_nonempty_field content ||
        cursor_has_nonempty_field description || {
          cursor_template_missing_push 'body|content|description'
          return 1
        }
      return 0
      ;;
  esac
  case "$CURSOR_PROVIDER" in
    github)
      cursor_has_nonempty_field owner || cursor_has_nonempty_field assignee || {
        cursor_template_missing_push 'owner|assignee'
        return 1
      }
      cursor_labels=$(printf '%s\n' "$CURSOR_TOOL_INPUT" | jq -r '.. | objects | .labels? | arrays | .[]? | strings')
      printf '%s\n' "$cursor_labels" | grep -Eq '^area:' || {
        cursor_template_missing_push 'labels area:*'
        return 2
      }
      [ "$(printf '%s\n' "$cursor_labels" | grep -Ec '^priority:')" -eq 1 ] || {
        cursor_template_missing_push 'labels one priority:*'
        return 2
      }
      cursor_has_nonempty_field type || printf '%s\n' "$cursor_labels" | grep -Eq '^type:' || {
        cursor_template_missing_push 'type or labels type:*'
        return 2
      }
      cursor_has_nonempty_field jira || printf '%s\n' "$CURSOR_TOOL_INPUT" | grep -F 'N/A' >/dev/null || {
        cursor_template_missing_push 'jira or N/A'
        return 1
      }
      ;;
    jira)
      cursor_jira_has_project || cursor_template_missing_push 'projectKey|project'
      cursor_jira_has_issue_type ||
        cursor_template_missing_push 'issueTypeName|issue_type'
      cursor_jira_has_priority ||
        cursor_template_missing_push 'priority or additional_fields.priority.name'
      cursor_jira_has_github_link ||
        cursor_template_missing_push 'GitHub URL or GitHub: N/A in description'
      if [ "$cursor_operation" = jira-intake-write ]; then
        cursor_has_nonempty_field reporter ||
          cursor_has_nonempty_field requester ||
          cursor_template_missing_push 'reporter|requester'
        if cursor_jira_has_assignee_like ||
           cursor_has_value parent ||
           cursor_has_value parentKey ||
           cursor_has_value sprint
        then
          cursor_template_missing_push \
            'intake must omit assignee/owner/parent/sprint'
        fi
      else
        cursor_jira_has_assignee ||
          cursor_template_missing_push 'assignee_account_id|assignee|owner'
        cursor_jira_has_parent_or_standalone ||
          cursor_template_missing_push 'parent|standalone_reason'
      fi
      [ -z "${CURSOR_TEMPLATE_MISSING:-}" ] || return 1
      ;;
  esac
}

cmd_cursor_before_mcp_execution() {
  cursor_require_jq
  CURSOR_REQUEST=$(cat) || {
    cursor_deny GOVERNANCE_CONTEXT_REQUIRED 'Provide Cursor hook input.'
    return
  }
  if ! cursor_parse_request_fields; then
    cursor_deny GOVERNANCE_CONTEXT_REQUIRED \
      'Provide one recognized Git workspace and start a new governance session.'
    return
  fi
  if ! cursor_resolve_workspaces; then
    # Peek the tool before denying so browser and other non-governed MCP tools
    # are not blocked solely by an ambiguous FE+BE workspace shape.
    if cursor_tool_provider && {
         [ -z "$CURSOR_PROVIDER" ] || [ "$CURSOR_TOOL_WRITE" -eq 0 ]
       }
    then
      cursor_allow
      return
    fi
    cursor_deny GOVERNANCE_CONTEXT_REQUIRED \
      'Provide one recognized Git workspace or a FULL_STACK Backend+Frontend pair and start a new governance session.'
    return
  fi
  if [ "$CURSOR_GOVERNANCE_STATE" = NOT_GOVERNED ]; then
    cursor_allow
    return
  fi
  cursor_tool_provider || {
    cursor_deny WORK_ITEM_TEMPLATE_REQUIRED 'Provide structured tool input for the governed write.'
    return
  }
  if [ "$CURSOR_WORKSPACE_MODE" = be-fe ] &&
     [ -n "$CURSOR_PROVIDER" ] && [ "$CURSOR_TOOL_WRITE" -eq 1 ]
  then
    if ! cursor_select_be_fe_workspace; then
      cursor_deny TARGET_REQUIRED \
        'Name the exact Backend or Frontend target (BB/BF project, parent/epic key, or beroka-vn repository) for this governed write.'
      return
    fi
  fi
  cursor_context
  cursor_receipt_matches 1 || {
    cursor_deny GOVERNANCE_CONTEXT_REQUIRED 'Run cursor-hook sessionStart again for this generation and workspace.'
    return
  }
  [ -n "$CURSOR_PROVIDER" ] && [ "$CURSOR_TOOL_WRITE" -eq 1 ] || { cursor_allow; return; }
  if cursor_cross_team_private_link; then
    cursor_deny CROSS_TEAM_LINK_SCOPE_DENIED \
      'Use an accessible exact Confluence page for cross-team documentation.'
    return
  fi
  case "$CURSOR_PROVIDER" in
    github) cursor_operation=github-write ;;
    confluence)
      cursor_preflight_state=0
      cursor_preflight=$(cursor_confluence_preflight 2>&1) ||
        cursor_preflight_state=$?
      case "$cursor_preflight_state" in
        0)
          printf '%s\n' "$cursor_preflight" | grep -F 'Result: PASS' >/dev/null &&
            { cursor_allow; return; }
          ;;
        2)
          cursor_deny MAPPING_CONFLICT \
            'Confluence body and structured target IDs conflict.'
          return
          ;;
      esac
      cursor_result=$(printf '%s\n' "$cursor_preflight" |
        awk '/^Result: / { result=$0 } END { sub(/^Result: /, "", result); print result }')
      [ -n "$cursor_result" ] || cursor_result=ROUTING_REQUIRED
      cursor_deny "$cursor_result" \
        "${cursor_preflight:-Exact Confluence target metadata is required.}"
      return
      ;;
    jira)
      cursor_operation_state=0
      cursor_operation=$(cursor_jira_operation) ||
        cursor_operation_state=$?
      case "$cursor_operation_state" in
        0) ;;
        2)
          cursor_deny WORK_ITEM_TEMPLATE_REQUIRED \
            'Provide exactly one structured Jira project.'
          return
          ;;
        *)
          cursor_deny ROUTING_REQUIRED \
            'Use the current Jira project or its exact governed intake target.'
          return
          ;;
      esac
      ;;
  esac
  case "$cursor_operation" in
    jira-intake-write|jira-handoff-write)
      cursor_stage_exact_body jira || {
        cursor_deny HANDOFF_BODY_REQUIRED \
          'Provide exactly one non-empty Jira description, comment, or body.'
        return
      }
      if ! (reject_cross_team_repository_references \
        "$CURSOR_EXACT_BODY_FILE") >/dev/null 2>&1
      then
        cursor_cleanup_staged_body || :
        cursor_deny CROSS_TEAM_LINK_SCOPE_DENIED \
          'Use an accessible exact Confluence page for cross-team documentation.'
        return
      fi
      ;;
  esac
  cursor_template_state=0
  cursor_validate_template || cursor_template_state=$?
  case "$cursor_template_state" in
    0) ;;
    2)
      cursor_cleanup_staged_body || :
      cursor_deny LABEL_CONFIGURATION_REQUIRED \
        "Use one configured type label, one area label, and one priority label.${CURSOR_TEMPLATE_MISSING:+ Missing: $CURSOR_TEMPLATE_MISSING}"
      return
      ;;
    3)
      cursor_cleanup_staged_body || :
      cursor_deny WORK_ITEM_LANGUAGE_REQUIRED \
        'Put "Work-item language: English" (or Vietnamese) in the Jira description/body, then retry createJiraIssue.'
      return
      ;;
    *)
      cursor_cleanup_staged_body || :
      cursor_deny WORK_ITEM_TEMPLATE_REQUIRED \
        "Retry createJiraIssue with Atlassian MCP fields only: projectKey, issueTypeName, parent, assignee_account_id, additional_fields.priority={name}, and description containing Work-item language plus GitHub URL or GitHub: N/A.${CURSOR_TEMPLATE_MISSING:+ Missing: $CURSOR_TEMPLATE_MISSING}"
      return
      ;;
  esac
  set --
  case "$cursor_operation" in
    jira-intake-write|jira-handoff-write)
      set -- --handoff-body-file "$CURSOR_EXACT_BODY_FILE"
      ;;
  esac
  cursor_preflight_state=0
  cursor_preflight=$(cursor_staged_preflight "$CURSOR_WORKSPACE" --client cursor \
    --operation "$cursor_operation" --non-interactive "$@" 2>&1) ||
    cursor_preflight_state=$?
  cursor_cleanup_staged_body || {
    cursor_deny GOVERNANCE_NOT_READY 'Cannot clean up staged cross-team body.'
    return
  }
  if [ "$cursor_preflight_state" -eq 0 ] &&
     printf '%s\n' "$cursor_preflight" | grep -F 'Result: PASS' >/dev/null; then
    cursor_allow
  else
    cursor_result=$(printf '%s\n' "$cursor_preflight" | awk '/^Result: / { result=$0 } END { sub(/^Result: /, "", result); print result }')
    [ -n "$cursor_result" ] || cursor_result=GOVERNANCE_CONTEXT_REQUIRED
    cursor_deny "$cursor_result" "$cursor_preflight"
  fi
}

cursor_shell_governed_github_write() {
  # Allow templated gh issue/pr create when workspace roots resolve and the
  # command carries the language marker plus required GitHub labels. Keep
  # unstructured gh api mutates denied. Return 0 on preflight PASS, 2 when the
  # template matched but preflight denied, and 1 when the template is incomplete.
  csg_command=$1
  CURSOR_SHELL_PREFLIGHT_RESULT=
  CURSOR_SHELL_PREFLIGHT_DETAIL=
  case " $csg_command " in
    *gh\ issue\ create\ *|*gh\ pr\ create\ *) ;;
    *) return 1 ;;
  esac
  cursor_parse_request_fields >/dev/null 2>&1 || return 1
  cursor_resolve_workspaces || return 1
  # Prefer explicit --repo over incidental product names in the issue body
  # (governance bug reports often mention both Backend and Frontend).
  if [ "$CURSOR_WORKSPACE_MODE" = be-fe ]; then
    csg_be=0
    csg_fe=0
    case " $csg_command " in
      *--repo*beroka-vn/Beroka_Frontend*|*--repo*Beroka_Frontend*)
        csg_fe=1
        ;;
    esac
    case " $csg_command " in
      *--repo*beroka-vn/Beroka_Backend*|*--repo*Beroka_Backend*)
        csg_be=1
        ;;
    esac
    if [ "$csg_be" -eq 0 ] && [ "$csg_fe" -eq 0 ]; then
      case " $csg_command " in
        *beroka-vn/Beroka_Frontend*) csg_fe=1 ;;
      esac
      case " $csg_command " in
        *beroka-vn/Beroka_Backend*) csg_be=1 ;;
      esac
    fi
    if [ "$csg_be" -eq 1 ] && [ "$csg_fe" -eq 0 ]; then
      CURSOR_WORKSPACE=$CURSOR_BACKEND_WORKSPACE
    elif [ "$csg_fe" -eq 1 ] && [ "$csg_be" -eq 0 ]; then
      CURSOR_WORKSPACE=$CURSOR_FRONTEND_WORKSPACE
    fi
  fi
  printf '%s\n' "$csg_command" |
    grep -Eq 'Work-item language: (English|Vietnamese|[a-z][a-z0-9-]{1,31})' ||
    return 1
  printf '%s\n' "$csg_command" |
    grep -Eq -- '--label(=|[[:space:]]"?area:)' || return 1
  printf '%s\n' "$csg_command" |
    grep -Eq -- '--label(=|[[:space:]]"?priority:)' || return 1
  [ "$(printf '%s\n' "$csg_command" |
    grep -Eoc -- '--label(=|[[:space:]]"?priority:)' |
    tr -d ' ')" -eq 1 ] || return 1
  printf '%s\n' "$csg_command" |
    grep -Eq -- '--label(=|[[:space:]]"?type:)|--label(=|[[:space:]]"?)(Bug|Feature|Task)("|[[:space:]]|$)' ||
    return 1
  CURSOR_SHELL_PREFLIGHT_DETAIL=$(cmd_preflight "$CURSOR_WORKSPACE" --client cursor \
    --operation github-write --non-interactive 2>&1) || true
  if printf '%s\n' "$CURSOR_SHELL_PREFLIGHT_DETAIL" | grep -F 'Result: PASS' >/dev/null; then
    return 0
  fi
  CURSOR_SHELL_PREFLIGHT_RESULT=$(printf '%s\n' "$CURSOR_SHELL_PREFLIGHT_DETAIL" |
    awk '/^Result: / { result=$0 } END { sub(/^Result: /, "", result); print result }')
  [ -n "$CURSOR_SHELL_PREFLIGHT_RESULT" ] ||
    CURSOR_SHELL_PREFLIGHT_RESULT=GOVERNANCE_CONTEXT_REQUIRED
  return 2
}

cmd_cursor_before_shell_execution() {
  cursor_require_jq
  CURSOR_REQUEST=$(cat) || die GOVERNANCE_CONTEXT_REQUIRED
  cursor_command=$(printf '%s\n' "$CURSOR_REQUEST" | jq -er '.command | if type == "string" then . else error("command") end') || {
    cursor_deny GOVERNANCE_CONTEXT_REQUIRED 'Provide a shell command.'
    return
  }
  if cursor_parse_request_fields && cursor_resolve_workspaces &&
     [ "$CURSOR_GOVERNANCE_STATE" = NOT_GOVERNED ]
  then
    cursor_allow
    return
  fi
  case " $cursor_command " in
    *gh\ issue\ create\ *|*gh\ pr\ create\ *)
      cursor_shell_state=0
      cursor_shell_governed_github_write "$cursor_command" || cursor_shell_state=$?
      case "$cursor_shell_state" in
        0)
          cursor_allow
          return
          ;;
        2)
          cursor_deny "$CURSOR_SHELL_PREFLIGHT_RESULT" \
            "${CURSOR_SHELL_PREFLIGHT_DETAIL:-Governed GitHub create preflight failed.}"
          return
          ;;
      esac
      cursor_deny WORK_ITEM_TEMPLATE_REQUIRED \
        'Create GitHub work items through a governed MCP write or a templated gh issue/pr create with Work-item language, area, priority, and type labels after github-write preflight PASS.'
      return
      ;;
    *gh\ issue\ edit\ *|*gh\ pr\ edit\ *)
      cursor_deny WORK_ITEM_TEMPLATE_REQUIRED \
        'Edit GitHub work items through a governed MCP write.'
      return
      ;;
  esac
  cursor_upper=$(printf '%s' "$cursor_command" | tr '[:lower:]' '[:upper:]')
  case " $cursor_command " in
    *gh\ api\ *)
      if printf '%s\n' "$cursor_upper" | grep -Eq '(^|[[:space:]])(-X|--METHOD)([[:space:]]|=)(POST|PUT|PATCH|DELETE)' &&
         printf '%s\n' "$cursor_command" | grep -Eq '/(issues|pulls|comments)(/|[[:space:]]|$)'; then
        cursor_deny WORK_ITEM_TEMPLATE_REQUIRED \
          'Create or edit GitHub work items through a governed MCP write.'
        return
      fi
      ;;
  esac
  cursor_allow
}

cmd_cursor_hook() {
  cursor_ensure_user_path
  case "$1" in
    sessionStart) cmd_cursor_session_start ;;
    beforeSubmitPrompt) cmd_cursor_before_submit_prompt ;;
    preCompact) cmd_cursor_pre_compact ;;
    beforeMCPExecution) cmd_cursor_before_mcp_execution ;;
    beforeShellExecution) cmd_cursor_before_shell_execution ;;
    *) die GOVERNANCE_CONTEXT_REQUIRED 'Unknown Cursor hook event' ;;
  esac
}
