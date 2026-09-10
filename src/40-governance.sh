# Governance policy, handoff, Confluence, context, and preflight commands.

require_trusted_confluence_body_gate() {
  rtcbg_client=$1 rtcbg_action=$2
  [ "$rtcbg_action" = move ] && return 0
  [ -n "$CONFLUENCE_HOOK_CLIENT" ] &&
    [ "$CONFLUENCE_HOOK_CLIENT" = "$rtcbg_client" ] && return 0
  [ "$rtcbg_client" = cursor ] &&
    [ "$CONFLUENCE_BODY_TRUSTED" -eq 1 ] && return 0
  die CLIENT_BODY_GATE_REQUIRED \
    "Use native Confluence tool hooks: beroka-governance setup-documentation-hooks --client $rtcbg_client; restart the client with hooks enabled. Standalone preflight and body files cannot prove a tool call."
}

handoff_body_is_safe() {
  hbs_file=$1
  [ -n "$hbs_file" ] && [ "${hbs_file#/}" != "$hbs_file" ] || return 1
  [ -f "$hbs_file" ] && [ ! -L "$hbs_file" ] && [ -s "$hbs_file" ] || return 1
  hbs_tmp=${TMPDIR:-/tmp}
  hbs_home=$(CDPATH= cd -- "$HOME" && pwd -P) || return 1
  hbs_tmp_physical=$(CDPATH= cd -- "$hbs_tmp" && pwd -P) || return 1
  case "$hbs_file" in
    "$HOME"/*) hbs_current=$HOME; hbs_rest=${hbs_file#"$HOME"/} ;;
    "$hbs_tmp"/*) hbs_current=$hbs_tmp; hbs_rest=${hbs_file#"$hbs_tmp"/} ;;
    *) return 1 ;;
  esac
  while [ -n "$hbs_rest" ]; do
    hbs_component=${hbs_rest%%/*}
    if [ "$hbs_component" = "$hbs_rest" ]; then hbs_rest=; else hbs_rest=${hbs_rest#*/}; fi
    case "$hbs_component" in ''|.|..) return 1 ;; esac
    hbs_current=$hbs_current/$hbs_component
    [ ! -L "$hbs_current" ] || return 1
  done
  hbs_parent=$(CDPATH= cd -- "$(dirname -- "$hbs_file")" && pwd -P) || return 1
  case "$hbs_parent" in
    "$hbs_home"|"$hbs_home"/*|"$hbs_tmp_physical"|"$hbs_tmp_physical"/*) ;;
    *) return 1 ;;
  esac
}

handoff_header_value() {
  hhv_file=$1 hhv_label=$2
  awk -v label="$hhv_label" '
    BEGIN {
      count=split("Handoff schema|Handoff state|Provider Jira|Consumer Jira|Scope|Domain|Confluence content ID|Confluence page version|Owner account ID|Effective date|Supersedes|Superseded by|API impact|WebSocket impact|Missing sections", headers, "|")
    }
    NR <= count {
      if (index($0, headers[NR] ": ") != 1) invalid=1
      else values[headers[NR]]=substr($0, length(headers[NR]) + 3)
      next
    }
    {
      for (i = 1; i <= count; i++)
        if (index($0, headers[i] ": ") == 1) invalid=1
    }
    END {
      if (NR < count || invalid || values[label] == "") exit 1
      print values[label]
    }
  ' "$hhv_file"
}

handoff_section_is_complete() {
  hsic_file=$1 hsic_heading=$2
  awk -v heading="$hsic_heading" '
    $0 == heading { matches++; active=1; next }
    active && /^#/ { active=0 }
    active && $0 !~ /^[[:space:]]*$/ { content=1 }
    END { exit !(matches == 1 && content) }
  ' "$hsic_file"
}

handoff_section_exists() {
  hse_file=$1 hse_heading=$2
  awk -v heading="$hse_heading" '$0 == heading { matches++ } END { exit matches != 1 }' "$hse_file"
}

handoff_missing_section_listed() {
  hmsl_missing=$1 hmsl_section=$2
  printf '%s\n' "$hmsl_missing" | awk -v section="$hmsl_section" '
    {
      count=split($0, values, ",")
      for (i = 1; i <= count; i++) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", values[i])
        if (values[i] == section) found=1
      }
    }
    END { exit !found }
  '
}

handoff_section_contains() {
  hsc_file=$1 hsc_heading=$2 hsc_text=$3
  awk -v heading="$hsc_heading" -v text="$hsc_text" '
    $0 == heading { matches++; active=1; next }
    active && /^#/ { active=0 }
    active && index($0, text) { found=1 }
    END { exit !(matches == 1 && found) }
  ' "$hsc_file"
}

handoff_require_section() {
  hrs_file=$1 hrs_section=$2 hrs_state=$3 hrs_missing=$4
  handoff_section_is_complete "$hrs_file" "## $hrs_section" && return 0
  if [ "$hrs_state" = DRAFT ] &&
     ! handoff_section_exists "$hrs_file" "## $hrs_section" &&
     handoff_missing_section_listed "$hrs_missing" "$hrs_section"
  then
    return 0
  fi
  die HANDOFF_BODY_INVALID 'Handoff body has an incomplete required section'
}

reject_cross_team_repository_references() {
  rctrr_file=$1
  if LC_ALL=C grep -Eiq \
    'github[.]com|git@github|[[:alnum:]_./-]+[.]git([^[:alnum:]_./-]|$)|canonical:[[:space:]]*[^[:space:]]|(^|[^[:alnum:]_])((beroka-vn/)?beroka_(backend|frontend)|repository|branch|pull request|pr|commit)([^[:alnum:]_]|$)' \
    "$rctrr_file"
  then
    die CROSS_TEAM_LINK_SCOPE_DENIED \
      'Cross-team handoff content cannot depend on repository references'
  fi
}

validate_cross_team_body() {
  vctb_file=$1
  handoff_body_is_safe "$vctb_file" ||
    die HANDOFF_BODY_REQUIRED 'A non-empty regular cross-team body file inside HOME or TMPDIR is required'
  reject_cross_team_repository_references "$vctb_file"
}

handoff_validate_api_operations() {
  hvao_file=$1
  awk '
    function complete(    i) {
      if (!operation) return 0
      for (i = 1; i <= required_count; i++)
        if (!seen[required[i]] || !content[required[i]]) return 0
      return 1
    }
    function finish_operation() {
      if (operation && !complete()) invalid=1
      operation=0; current=""
    }
    BEGIN {
      split("Permissions|Headers|Path parameters|Query parameters|Request payload|Success status and payload|Stable public errors|Pagination|Idempotency|Retry|Cache|Timestamp semantics|Sanitized request/response examples", required, "|")
      required_count=13
    }
    $0 == "## Affected API inventory" {
      finish_operation(); inventory_section=1; next
    }
    inventory_section && /^## / { inventory_section=0 }
    inventory_section && $0 !~ /^[[:space:]]*$/ {
      if ($0 !~ /^[A-Z]+ \/[^[:space:]]+$/) invalid=1
      inventory[$0]++; inventory_count++
      next
    }
    /^## API operation: [A-Z]+ \/[^[:space:]]+$/ {
      finish_operation()
      operation=1; operations++
      key=substr($0, length("## API operation: ") + 1)
      contracts[key]++
      delete seen; delete content; current=""
      next
    }
    /^## / {
      finish_operation()
      next
    }
    operation && /^### / {
      current=substr($0, 5)
      for (i = 1; i <= required_count; i++)
        if (current == required[i]) seen[current]++
      next
    }
    operation && current != "" && $0 !~ /^[[:space:]]*$/ { content[current]=1 }
    END {
      finish_operation()
      if (inventory_count < 1 || operations != inventory_count) invalid=1
      for (key in inventory)
        if (inventory[key] != 1 || contracts[key] != 1) invalid=1
      for (key in contracts)
        if (contracts[key] != 1 || inventory[key] != 1) invalid=1
      exit invalid
    }
  ' "$hvao_file"
}

handoff_require_api() {
  hra_file=$1 hra_state=$2 hra_missing=$3
  handoff_require_section "$hra_file" 'Affected API inventory' "$hra_state" "$hra_missing"
  if ! handoff_validate_api_operations "$hra_file"; then
    [ "$hra_state" = DRAFT ] &&
      handoff_missing_section_listed "$hra_missing" 'API operation' ||
      die HANDOFF_BODY_INVALID 'Handoff body has an incomplete API operation'
  fi
  handoff_require_section "$hra_file" 'Unaffected API inventory' "$hra_state" "$hra_missing"
}

handoff_validate_websocket_contracts() {
  hvwc_file=$1
  awk '
    function complete(    i) {
      if (!contract) return 0
      for (i = 1; i <= required_count; i++)
        if (!seen[required[i]] || !content[required[i]]) return 0
      return 1
    }
    function finish_contract() {
      if (contract && !complete()) invalid=1
      contract=0; current=""
    }
    BEGIN {
      split("Public connection URL and authentication|Subscribe and unsubscribe requests|Event envelope and affected message payloads|Ordering|Deduplication|Replay/resume|Reconnect|Heartbeat|Timeout|Backpressure|Error events|Close codes|Sanitized message examples", required, "|")
      required_count=13
    }
    $0 == "## Affected WebSocket inventory" {
      finish_contract(); inventory_section=1; next
    }
    inventory_section && /^## / { inventory_section=0 }
    inventory_section && $0 !~ /^[[:space:]]*$/ {
      if ($0 !~ /^wss:\/\/[^[:space:]]+$/) invalid=1
      inventory[$0]++; inventory_count++
      next
    }
    /^## WebSocket contract: wss:\/\/[^[:space:]]+$/ {
      finish_contract()
      contract=1; contracts_count++
      key=substr($0, length("## WebSocket contract: ") + 1)
      contracts[key]++
      delete seen; delete content; current=""
      next
    }
    /^## / { finish_contract(); next }
    contract && /^### / {
      current=substr($0, 5)
      for (i = 1; i <= required_count; i++)
        if (current == required[i]) seen[current]++
      next
    }
    contract && current != "" && $0 !~ /^[[:space:]]*$/ { content[current]=1 }
    END {
      finish_contract()
      if (inventory_count < 1 || contracts_count != inventory_count) invalid=1
      for (key in inventory)
        if (inventory[key] != 1 || contracts[key] != 1) invalid=1
      for (key in contracts)
        if (contracts[key] != 1 || inventory[key] != 1) invalid=1
      exit invalid
    }
  ' "$hvwc_file"
}

handoff_require_websocket() {
  hrw_file=$1 hrw_state=$2 hrw_missing=$3
  handoff_require_section "$hrw_file" 'Affected WebSocket inventory' \
    "$hrw_state" "$hrw_missing"
  if ! handoff_validate_websocket_contracts "$hrw_file"; then
    [ "$hrw_state" = DRAFT ] &&
      handoff_missing_section_listed "$hrw_missing" 'WebSocket contract' ||
      die HANDOFF_BODY_INVALID 'Handoff body has an incomplete WebSocket contract'
  fi
  handoff_require_section "$hrw_file" 'Unaffected WebSocket inventory' \
    "$hrw_state" "$hrw_missing"
}

validate_handoff_body() {
  vhb_file=$1 vhb_action=$2 vhb_target=$3
  validate_cross_team_body "$vhb_file"
  if [ -z "$PERSONAL_STAGE_ROOT" ]; then
    PERSONAL_STAGE_ROOT=$(umask 077; mktemp -d \
      "${TMPDIR:-/tmp}/beroka-governance-handoff.XXXXXX") ||
      die GOVERNANCE_NOT_READY 'Cannot create handoff validation stage'
    trap 'cleanup_personal_stage || :' EXIT
    trap 'cleanup_personal_stage || :; exit 1' HUP INT TERM
  fi
  vhb_normalized=$PERSONAL_STAGE_ROOT/handoff-lf
  (umask 077; awk '{ sub(/\r$/, ""); print }' "$vhb_file" >"$vhb_normalized") ||
    die GOVERNANCE_NOT_READY 'Cannot normalize handoff body'
  vhb_file=$vhb_normalized

  vhb_schema=$(handoff_header_value "$vhb_file" 'Handoff schema') ||
    die HANDOFF_BODY_INVALID 'Handoff body has an invalid header'
  [ "$vhb_schema" = 1 ] || die HANDOFF_BODY_INVALID 'Handoff body has an invalid header'
  vhb_state=$(handoff_header_value "$vhb_file" 'Handoff state') ||
    die HANDOFF_BODY_INVALID 'Handoff body has an invalid header'
  vhb_provider=$(handoff_header_value "$vhb_file" 'Provider Jira') ||
    die HANDOFF_BODY_INVALID 'Handoff body has an invalid header'
  vhb_consumer=$(handoff_header_value "$vhb_file" 'Consumer Jira') ||
    die HANDOFF_BODY_INVALID 'Handoff body has an invalid header'
  vhb_scope=$(handoff_header_value "$vhb_file" Scope) ||
    die HANDOFF_BODY_INVALID 'Handoff body has an invalid header'
  vhb_domain=$(handoff_header_value "$vhb_file" Domain) ||
    die HANDOFF_BODY_INVALID 'Handoff body has an invalid header'
  vhb_content=$(handoff_header_value "$vhb_file" 'Confluence content ID') ||
    die HANDOFF_BODY_INVALID 'Handoff body has an invalid header'
  vhb_version=$(handoff_header_value "$vhb_file" 'Confluence page version') ||
    die HANDOFF_BODY_INVALID 'Handoff body has an invalid header'
  vhb_owner=$(handoff_header_value "$vhb_file" 'Owner account ID') ||
    die HANDOFF_BODY_INVALID 'Handoff body has an invalid header'
  vhb_date=$(handoff_header_value "$vhb_file" 'Effective date') ||
    die HANDOFF_BODY_INVALID 'Handoff body has an invalid header'
  vhb_supersedes=$(handoff_header_value "$vhb_file" Supersedes) ||
    die HANDOFF_BODY_INVALID 'Handoff body has an invalid header'
  vhb_superseded=$(handoff_header_value "$vhb_file" 'Superseded by') ||
    die HANDOFF_BODY_INVALID 'Handoff body has an invalid header'
  vhb_api=$(handoff_header_value "$vhb_file" 'API impact') ||
    die HANDOFF_BODY_INVALID 'Handoff body has an invalid header'
  vhb_websocket=$(handoff_header_value "$vhb_file" 'WebSocket impact') ||
    die HANDOFF_BODY_INVALID 'Handoff body has an invalid header'
  vhb_missing=$(handoff_header_value "$vhb_file" 'Missing sections') ||
    die HANDOFF_BODY_INVALID 'Handoff body has an invalid header'

  case "$vhb_state" in DRAFT|READY_FOR_FE) ;; *) die HANDOFF_BODY_INVALID 'Handoff body has an invalid state' ;; esac
  case "$vhb_provider:$vhb_consumer" in
    BB-[1-9]*:BF-[1-9]*|BF-[1-9]*:BB-[1-9]*) ;;
    *) die HANDOFF_BODY_INVALID 'Handoff body must name opposite Jira projects' ;;
  esac
  printf '%s\n' "$vhb_provider" | grep -Eq '^(BB|BF)-[1-9][0-9]*$' ||
    die HANDOFF_BODY_INVALID 'Handoff body has an invalid Jira header'
  printf '%s\n' "$vhb_consumer" | grep -Eq '^(BB|BF)-[1-9][0-9]*$' ||
    die HANDOFF_BODY_INVALID 'Handoff body has an invalid Jira header'
  [ "${vhb_provider%%-*}" = "$ROUTE_JIRA_PROJECT_KEY" ] ||
    die HANDOFF_BODY_INVALID 'Handoff provider Jira does not match the routed team'
  [ -n "$vhb_owner" ] &&
    printf '%s\n' "$vhb_date" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' ||
    die HANDOFF_BODY_INVALID 'Handoff body has an invalid header'
  for vhb_revision in "$vhb_supersedes" "$vhb_superseded"; do
    [ "$vhb_revision" = N/A ] ||
      printf '%s\n' "$vhb_revision" | grep -Eq '^[1-9][0-9]* [1-9][0-9]*$' ||
      die HANDOFF_BODY_INVALID 'Handoff body has an invalid header'
  done
  case "$vhb_api" in affected|none) ;; *) die HANDOFF_BODY_INVALID 'Handoff body has an invalid impact' ;; esac
  case "$vhb_websocket" in affected|none) ;; *) die HANDOFF_BODY_INVALID 'Handoff body has an invalid impact' ;; esac

  case "$vhb_state:$vhb_action" in
    DRAFT:create)
      [ "$vhb_content" = new ] && [ "$vhb_version" = pending ] &&
        [ "$vhb_missing" != None ] ||
        die HANDOFF_BODY_INVALID 'Draft handoff state conflicts with its target'
      awk '
        NR == 2 { next }
        {
          readiness=tolower($0)
          gsub(/[^[:alnum:]]+/, " ", readiness)
          if (readiness ~ /(^| )ready +for +fe( |$)/ ||
              readiness ~ /(^| )readyforfe( |$)/) exit 1
        }
      ' "$vhb_file" ||
        die HANDOFF_BODY_INVALID 'Draft handoff cannot claim recipient readiness'
      ;;
    READY_FOR_FE:update)
      [ "$vhb_content" = "$vhb_target" ] && [ "$vhb_missing" = None ] &&
        printf '%s\n' "$vhb_content" | grep -Eq '^[1-9][0-9]*$' &&
        printf '%s\n' "$vhb_version" | grep -Eq '^[1-9][0-9]*$' ||
        die HANDOFF_BODY_INVALID 'Ready handoff state conflicts with its target'
      ;;
    *) die HANDOFF_BODY_INVALID 'Handoff state conflicts with its action' ;;
  esac

  for vhb_section in \
    'Purpose and delivered behavior' \
    'Affected user flows, assumptions, and non-goals' \
    'Authentication and authorization' \
    'Public data types and compatibility' \
    'State and delivery semantics' \
    'Errors and edge cases' \
    'Frontend implementation guidance' \
    'Sanitized examples and validation evidence' \
    'Known limitations and unverified items' \
    'FE acknowledgment'
  do
    handoff_require_section "$vhb_file" "$vhb_section" "$vhb_state" "$vhb_missing"
  done
  case "$vhb_api" in
    affected) handoff_require_api "$vhb_file" "$vhb_state" "$vhb_missing" ;;
    none)
      handoff_require_section "$vhb_file" 'API impact rationale' "$vhb_state" "$vhb_missing"
      handoff_section_contains "$vhb_file" '## API impact rationale' \
        'No public API operation changes' ||
        die HANDOFF_BODY_INVALID 'API no-impact rationale is incomplete'
      ;;
  esac
  case "$vhb_websocket" in
    affected) handoff_require_websocket "$vhb_file" "$vhb_state" "$vhb_missing" ;;
    none)
      handoff_require_section "$vhb_file" 'WebSocket impact rationale' "$vhb_state" "$vhb_missing"
      handoff_section_contains "$vhb_file" '## WebSocket impact rationale' \
        'No public WebSocket contract changes' ||
        die HANDOFF_BODY_INVALID 'WebSocket no-impact rationale is incomplete'
      ;;
  esac
  if LC_ALL=C grep -Eiq '(^|[^[:alnum:]])(tbd|todo)([^[:alnum:]]|$)|<[^>]+>|fill later|(api[ _-]?key|client[ _-]?secret|password|access[ _-]?token|refresh[ _-]?token|private[ _-]?key)[[:space:]"*`_]*[:=]|authorization[[:space:]"*`_]*:[[:space:]"*`_]*(basic|bearer)|(^|[^[:alnum:]])(kafka[ _-]*)?topic[[:space:]"*`_]*[:=]|(^|[^[:alnum:]])topology[[:space:]"*`_]*[:=]|(^|[^[:alnum:]])adapter[[:space:]"*`_]*[:=]|provider[ _-]+(credential|secret|token|adapter|implementation)[[:space:]"*`_]*[:=]|internal (topic|topology|adapter|provider)|raw upstream payload|upstream payload' "$vhb_file"; then
    die HANDOFF_BODY_INVALID 'Handoff body contains placeholders or publication leakage'
  fi
}

require_confluence_route() {
  [ -n "$ROUTE_CONFLUENCE_SPACE_KEY" ] &&
    [ -n "$ROUTE_CONFLUENCE_ROOT_CONTENT_ID" ] &&
    [ -n "$ROUTE_CONFLUENCE_ROOT_CONTENT_TYPE" ] ||
    die ROUTING_REQUIRED \
      'Confluence space, root content ID, and root type are required'
}

confluence_parent_is_legacy() {
  cpl_file=$1
  awk -F '\t' \
    -v repository="$REPOSITORY_SLUG" \
    -v parent="$CONFLUENCE_TARGET_PARENT_ID" '
      /^#/ || /^[[:space:]]*$/ { next }
      $1 == repository && $2 == "folder" && $3 == "LEGACY" &&
        $4 == parent { found=1 }
      END { exit !found }
    ' "$cpl_file"
}

confluence_targets_path() {
  printf '%s\n' "$RELEASE_DIR/runtime/integrations/beroka-be-fe.confluence-targets"
}

require_active_handoff_folder() {
  rahf_file=$1
  [ -n "$CONFLUENCE_TARGET_PARENT_ID" ] ||
    die_folder_creation_required \
      'Confluence handoffs require an exact reviewed ACTIVE Folder parent'
  [ "$CONFLUENCE_TARGET_PARENT_ID" != "$ROUTE_CONFLUENCE_ROOT_CONTENT_ID" ] ||
    die_folder_creation_required \
      'The routed Confluence root cannot be the parent of a handoff page'
  rahf_record=$(
    awk -F '\t' \
      -v repository="$REPOSITORY_SLUG" \
      -v parent="$CONFLUENCE_TARGET_PARENT_ID" '
        /^#/ || /^[[:space:]]*$/ { next }
        $1 == repository && $4 == parent { matches++; record=$0 }
        END {
          if (matches != 1) exit 1
          print record
        }
      ' "$rahf_file"
  ) || die_folder_creation_required \
    'Confluence handoffs require one exact reviewed ACTIVE Folder parent'
  validate_confluence_target_inventory "$rahf_file" \
    "$RELEASE_DIR/runtime/repositories" ||
    die ROUTING_REQUIRED 'Reviewed Confluence target inventory is unavailable'
  IFS="$(printf '\t')" read -r rahf_repository rahf_type rahf_state \
    rahf_content rahf_title rahf_scope rahf_domain rahf_transport rahf_parent \
    rahf_capability rahf_registry <<EOF
$rahf_record
EOF
  [ "$rahf_type" = folder ] && [ "$rahf_state" = ACTIVE ] &&
    [ "$rahf_parent" = "$ROUTE_CONFLUENCE_ROOT_CONTENT_ID" ] ||
    die_folder_creation_required \
      'Confluence handoffs require an exact reviewed ACTIVE Folder below the routed root'
  require_confluence_triple "$rahf_scope" "$rahf_domain" "$rahf_transport"
  [ "$rahf_scope" = "$vhb_scope" ] ||
    die_folder_creation_required \
      'The handoff body scope does not match the ACTIVE Folder'
  [ "$rahf_domain" = "$vhb_domain" ] ||
    die_folder_creation_required \
      'The handoff body domain does not match the ACTIVE Folder'
  [ -z "$CONFLUENCE_TARGET_SCOPE" ] ||
    [ "$vhb_scope" = "$CONFLUENCE_TARGET_SCOPE" ] ||
    die_folder_creation_required 'The requested handoff scope does not match the ACTIVE Folder'
  [ -z "$CONFLUENCE_TARGET_DOMAIN" ] ||
    [ "$vhb_domain" = "$CONFLUENCE_TARGET_DOMAIN" ] ||
    die_folder_creation_required 'The requested handoff domain does not match the ACTIVE Folder'
  [ -z "$CONFLUENCE_TARGET_TRANSPORT" ] ||
    [ "$rahf_transport" = "$CONFLUENCE_TARGET_TRANSPORT" ] ||
    die_folder_creation_required 'The requested handoff transport does not match the ACTIVE Folder'
  case "$vhb_api:$vhb_websocket" in
    affected:none) rahf_required_transport=API ;;
    none:affected) rahf_required_transport=WebSocket ;;
    affected:affected) rahf_required_transport=API+WebSocket ;;
    none:none) rahf_required_transport=$rahf_transport ;;
    *) die HANDOFF_BODY_INVALID 'Handoff body has an invalid impact' ;;
  esac
  [ "$rahf_transport" = "$rahf_required_transport" ] ||
    die_folder_creation_required \
      'The ACTIVE Folder transport does not match the handoff contract impact'
  CONFLUENCE_TARGET_SCOPE=$rahf_scope
  CONFLUENCE_TARGET_DOMAIN=$rahf_domain
  CONFLUENCE_TARGET_TRANSPORT=$rahf_transport
}

require_handoff_target_parent() {
  [ "$CONFLUENCE_TARGET_ACTION" != update ] || {
    [ "$rct_state" != UNTRACKED ] &&
      [ "$rct_parent" != - ] &&
      [ "$rct_parent" = "$CONFLUENCE_TARGET_PARENT_ID" ]
  } ||
    die MAPPING_CONFLICT \
      'Handoff target parent conflicts with the reviewed target ancestry'
}

die_folder_creation_required() {
  dfc_message=$1
  dfc_repo=${REPO:-$REPOSITORY_SLUG}
  [ -n "$dfc_repo" ] || dfc_repo=REPO
  printf '%s\n' "Result: FOLDER_CREATION_REQUIRED" >&2
  printf '%s\n' "$dfc_message" >&2
  printf '%s\n' \
    "Guidance: beroka-governance confluence-discover $dfc_repo" \
    'Hierarchy bootstrap is optional guidance, not a write gate.' \
    'Ordinary confluence-write is allow-by-default unless the target is UNACTIVATED in the governance release.' \
    >&2
  cleanup_personal_stage || :
  exit 1
}

die_docs_unactivated() {
  ddu_message=$1
  printf '%s\n' "Result: DOCS_UNACTIVATED" >&2
  printf '%s\n' "$ddu_message" >&2
  printf '%s\n' \
    'Remediation: open a reviewed governance release PR that removes or replaces the UNACTIVATED row in runtime/integrations/beroka-be-fe.confluence-targets.' \
    'Agents and user sessions cannot unactivate or reactivate docs locally.' \
    >&2
  cleanup_personal_stage || :
  exit 1
}

confluence_content_is_unactivated() {
  cciu_file=$1
  cciu_content=$2
  [ -n "$cciu_content" ] && [ "$cciu_content" != new ] || return 1
  awk -F '\t' \
    -v repository="$REPOSITORY_SLUG" \
    -v content="$cciu_content" '
      /^#/ || /^[[:space:]]*$/ { next }
      $1 == repository && $3 == "UNACTIVATED" && $4 == content { found=1 }
      END { exit !found }
    ' "$cciu_file"
}

require_confluence_triple() {
  case "$1" in
    Shared|Derivatives|Underlying) ;;
    *) die ROUTING_REQUIRED 'A reviewed Confluence scope is required' ;;
  esac
  case "$2" in
    Market|User) ;;
    *) die ROUTING_REQUIRED 'A reviewed Confluence domain is required' ;;
  esac
  case "$3" in
    API|WebSocket|API+WebSocket) ;;
    *) die ROUTING_REQUIRED 'API, WebSocket, or API+WebSocket transport is required' ;;
  esac
}

confluence_folder_title() {
  printf '%s — %s — %s\n' "$1" "$2" "$3"
}

confluence_bootstrap_state_file() {
  cbs_slug=$1
  printf '%s\n' "$cbs_slug" |
    grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' ||
    die GOVERNANCE_NOT_READY 'Invalid repository slug for bootstrap state'
  cbs_safe=$(printf '%s' "$cbs_slug" | tr '/' '-')
  printf '%s\n' "$CONFLUENCE_BOOTSTRAP_STATE_ROOT/$cbs_safe.json"
}

confluence_inventory_has_active_folder() {
  cih_file=$1 cih_scope=$2 cih_domain=$3 cih_transport=$4
  awk -F '\t' \
    -v repository="$REPOSITORY_SLUG" \
    -v scope="$cih_scope" \
    -v domain="$cih_domain" \
    -v transport="$cih_transport" '
      /^#/ || /^[[:space:]]*$/ { next }
      $1 == repository && $2 == "folder" && $3 == "ACTIVE" &&
        $6 == scope && $7 == domain && $8 == transport { found=1 }
      END { exit !found }
    ' "$cih_file"
}

confluence_inventory_has_active_registry() {
  cir_file=$1
  awk -F '\t' \
    -v repository="$REPOSITORY_SLUG" '
      /^#/ || /^[[:space:]]*$/ { next }
      $1 == repository && $2 == "page" &&
        ($3 == "ACTIVE" || $3 == "PLANNED") &&
        ($5 == "Backend Capability Registry" || $11 != "-") {
          found=1
        }
      END { exit !found }
    ' "$cir_file"
}

confluence_inventory_content_state() {
  # Print STATE for an exact content id in the current repository, or empty.
  cic_file=$1 cic_id=$2
  awk -F '\t' \
    -v repository="$REPOSITORY_SLUG" \
    -v content="$cic_id" '
      /^#/ || /^[[:space:]]*$/ { next }
      $1 == repository && $4 == content { print $3; found=1; exit }
      END { if (!found) exit 0 }
    ' "$cic_file"
}

prepare_confluence_bootstrap_repo() {
  load_active_release
  resolve_repository_context "$1"
  require_confluence_route
  case "$ROUTE_PROFILE" in
    backend) ;;
    *)
      die ROUTING_REQUIRED \
        'Confluence target bootstrap is supported for Backend profile repositories only'
      ;;
  esac
  CONFLUENCE_TARGETS_FILE=$(confluence_targets_path)
  validate_confluence_target_inventory "$CONFLUENCE_TARGETS_FILE" \
    "$RELEASE_DIR/runtime/repositories" ||
    die ROUTING_REQUIRED 'Reviewed Confluence target inventory is unavailable'
}

cmd_confluence_discover() {
  ccd_repo=$1
  shift
  ccd_scope= ccd_domain= ccd_transport=
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --scope)
        [ "$#" -ge 2 ] || { usage >&2; exit 2; }
        ccd_scope=$2
        shift 2
        ;;
      --domain)
        [ "$#" -ge 2 ] || { usage >&2; exit 2; }
        ccd_domain=$2
        shift 2
        ;;
      --transport)
        [ "$#" -ge 2 ] || { usage >&2; exit 2; }
        ccd_transport=$2
        shift 2
        ;;
      *) usage >&2; exit 2 ;;
    esac
  done
  if [ -n "$ccd_scope$ccd_domain$ccd_transport" ]; then
    [ -n "$ccd_scope" ] && [ -n "$ccd_domain" ] && [ -n "$ccd_transport" ] ||
      { usage >&2; exit 2; }
    require_confluence_triple "$ccd_scope" "$ccd_domain" "$ccd_transport"
  fi
  prepare_confluence_bootstrap_repo "$ccd_repo"
  ccd_legacy=0 ccd_drifted=0 ccd_active_folders=0 ccd_active_pages=0
  ccd_planned=0 ccd_registry=0
  while IFS="$(printf '\t')" read -r \
    ccd_r ccd_type ccd_state ccd_id ccd_title ccd_sc ccd_dom ccd_tr \
    ccd_parent ccd_cap ccd_reg
  do
    case "$ccd_r" in \#*|'') continue ;; esac
    [ "$ccd_r" = "$REPOSITORY_SLUG" ] || continue
    case "$ccd_state:$ccd_type" in
      LEGACY:folder) ccd_legacy=$((ccd_legacy + 1)) ;;
      DRIFTED:page) ccd_drifted=$((ccd_drifted + 1)) ;;
      ACTIVE:folder) ccd_active_folders=$((ccd_active_folders + 1)) ;;
      ACTIVE:page)
        ccd_active_pages=$((ccd_active_pages + 1))
        [ "$ccd_title" = 'Backend Capability Registry' ] && ccd_registry=1
        ;;
      PLANNED:page) ccd_planned=$((ccd_planned + 1)) ;;
    esac
  done <"$CONFLUENCE_TARGETS_FILE"
  printf '%s\n' \
    "Repository: $REPOSITORY_SLUG" \
    "Confluence space: $ROUTE_CONFLUENCE_SPACE_KEY" \
    "Confluence root content ID: $ROUTE_CONFLUENCE_ROOT_CONTENT_ID" \
    "Legacy folders: $ccd_legacy" \
    "Drifted pages: $ccd_drifted" \
    "Active folders: $ccd_active_folders" \
    "Active pages: $ccd_active_pages" \
    "Planned pages: $ccd_planned" \
    "Active Backend Capability Registry: $ccd_registry"
  if [ -n "$ccd_scope" ]; then
    ccd_title=$(confluence_folder_title "$ccd_scope" "$ccd_domain" "$ccd_transport")
    if confluence_inventory_has_active_folder "$CONFLUENCE_TARGETS_FILE" \
         "$ccd_scope" "$ccd_domain" "$ccd_transport"
    then
      printf '%s\n' "Requested folder ($ccd_title): ACTIVE"
    else
      printf '%s\n' "Requested folder ($ccd_title): MISSING"
    fi
  fi
  if [ "$ccd_registry" -eq 1 ] &&
     { [ -z "$ccd_scope" ] || confluence_inventory_has_active_folder \
         "$CONFLUENCE_TARGETS_FILE" "$ccd_scope" "$ccd_domain" "$ccd_transport"; }
  then
    printf '%s\n' \
      'Next: ordinary allow-by-default confluence-write with Jira/GitHub handoff delta' \
      'Phase: ordinary documentation update (UNACTIVATED targets remain release-locked)' \
      'Result: DISCOVERY_COMPLETE'
    return 0
  fi
  if [ -n "$ccd_scope" ]; then
    printf '%s\n' \
      "Optional hierarchy guidance: beroka-governance confluence-bootstrap-plan $REPO --scope $ccd_scope --domain $ccd_domain --transport $ccd_transport"
  else
    printf '%s\n' \
      "Optional hierarchy guidance: beroka-governance confluence-bootstrap-plan $REPO --scope SCOPE --domain DOMAIN --transport API|WebSocket|API+WebSocket"
  fi
  printf '%s\n' \
    'Phase: hierarchy bootstrap is optional guidance, not a write gate' \
    'Ordinary confluence-write is allow-by-default unless the target is UNACTIVATED in the governance release' \
    'Result: DISCOVERY_COMPLETE'
}

cmd_confluence_bootstrap_plan() {
  cbp_repo=$1
  shift
  cbp_scope= cbp_domain= cbp_transport=
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --scope)
        [ "$#" -ge 2 ] || { usage >&2; exit 2; }
        cbp_scope=$2
        shift 2
        ;;
      --domain)
        [ "$#" -ge 2 ] || { usage >&2; exit 2; }
        cbp_domain=$2
        shift 2
        ;;
      --transport)
        [ "$#" -ge 2 ] || { usage >&2; exit 2; }
        cbp_transport=$2
        shift 2
        ;;
      *) usage >&2; exit 2 ;;
    esac
  done
  [ -n "$cbp_scope" ] && [ -n "$cbp_domain" ] && [ -n "$cbp_transport" ] ||
    { usage >&2; exit 2; }
  require_confluence_triple "$cbp_scope" "$cbp_domain" "$cbp_transport"
  prepare_confluence_bootstrap_repo "$cbp_repo"
  cbp_title=$(confluence_folder_title "$cbp_scope" "$cbp_domain" "$cbp_transport")
  if confluence_inventory_has_active_folder "$CONFLUENCE_TARGETS_FILE" \
       "$cbp_scope" "$cbp_domain" "$cbp_transport"
  then
    die ROUTING_REQUIRED \
      "An ACTIVE folder already exists for $cbp_title"
  fi
  if confluence_inventory_has_active_registry "$CONFLUENCE_TARGETS_FILE"
  then
    die ROUTING_REQUIRED \
      'An ACTIVE Backend Capability Registry already exists'
  fi
  printf '%s\n' \
    'Phase: authorized bootstrap' \
    'Authorization: obtain explicit human confirmation before any Confluence create' \
    "Repository: $REPOSITORY_SLUG" \
    "Confluence space: $ROUTE_CONFLUENCE_SPACE_KEY" \
    "Catalog root parent ID: $ROUTE_CONFLUENCE_ROOT_CONTENT_ID" \
    "Catalog root parent type: $ROUTE_CONFLUENCE_ROOT_CONTENT_TYPE" \
    'Create 1 — canonical folder:' \
    "  title: $cbp_title" \
    '  record-type: folder' \
    "  parentId: $ROUTE_CONFLUENCE_ROOT_CONTENT_ID" \
    "  scope: $cbp_scope" \
    "  domain: $cbp_domain" \
    "  transport: $cbp_transport" \
    'Create 2 — Backend Capability Registry page:' \
    '  title: Backend Capability Registry' \
    '  record-type: page' \
    "  parentId: $ROUTE_CONFLUENCE_ROOT_CONTENT_ID" \
    '  body: use Backend Capability Registry Template from jira-confluence template' \
    'After MCP create, capture exact returned content IDs:' \
    "  beroka-governance confluence-bootstrap-capture $REPO --folder-id FOLDER_ID --registry-id REGISTRY_ID --scope $cbp_scope --domain $cbp_domain --transport $cbp_transport" \
    'Then verify with MCP read-back parent IDs before any ACTIVE inventory PR.' \
    'Result: BOOTSTRAP_PLAN'
}

cmd_confluence_bootstrap_capture() {
  cbc_repo=$1
  shift
  cbc_folder= cbc_registry= cbc_scope= cbc_domain= cbc_transport=
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --folder-id)
        [ "$#" -ge 2 ] || { usage >&2; exit 2; }
        cbc_folder=$2
        shift 2
        ;;
      --registry-id)
        [ "$#" -ge 2 ] || { usage >&2; exit 2; }
        cbc_registry=$2
        shift 2
        ;;
      --scope)
        [ "$#" -ge 2 ] || { usage >&2; exit 2; }
        cbc_scope=$2
        shift 2
        ;;
      --domain)
        [ "$#" -ge 2 ] || { usage >&2; exit 2; }
        cbc_domain=$2
        shift 2
        ;;
      --transport)
        [ "$#" -ge 2 ] || { usage >&2; exit 2; }
        cbc_transport=$2
        shift 2
        ;;
      *) usage >&2; exit 2 ;;
    esac
  done
  [ -n "$cbc_folder" ] && [ -n "$cbc_registry" ] &&
    [ -n "$cbc_scope" ] && [ -n "$cbc_domain" ] && [ -n "$cbc_transport" ] ||
    { usage >&2; exit 2; }
  require_confluence_triple "$cbc_scope" "$cbc_domain" "$cbc_transport"
  printf '%s\n' "$cbc_folder" | grep -Eq '^[1-9][0-9]*$' ||
    die ROUTING_REQUIRED 'A numeric folder content ID is required'
  printf '%s\n' "$cbc_registry" | grep -Eq '^[1-9][0-9]*$' ||
    die ROUTING_REQUIRED 'A numeric Registry content ID is required'
  [ "$cbc_folder" != "$cbc_registry" ] ||
    die MAPPING_CONFLICT 'Folder and Registry content IDs must differ'
  prepare_confluence_bootstrap_repo "$cbc_repo"
  cbc_title=$(confluence_folder_title "$cbc_scope" "$cbc_domain" "$cbc_transport")
  for cbc_id in "$cbc_folder" "$cbc_registry"; do
    cbc_state=$(confluence_inventory_content_state "$CONFLUENCE_TARGETS_FILE" "$cbc_id") ||
      cbc_state=
    case "$cbc_state" in
      LEGACY|DRIFTED)
        die MAPPING_CONFLICT \
          "Content ID $cbc_id is already recorded as $cbc_state"
        ;;
      ACTIVE)
        die MAPPING_CONFLICT \
          "Content ID $cbc_id is already ACTIVE in the reviewed inventory"
        ;;
    esac
  done
  assert_safe_user_path "$CONFLUENCE_BOOTSTRAP_STATE_ROOT" 'Confluence bootstrap state'
  mkdir -p "$CONFLUENCE_BOOTSTRAP_STATE_ROOT" ||
    die GOVERNANCE_NOT_READY 'Cannot create Confluence bootstrap state directory'
  chmod 700 "$CONFLUENCE_BOOTSTRAP_STATE_ROOT" ||
    die GOVERNANCE_NOT_READY 'Cannot secure Confluence bootstrap state directory'
  cbc_file=$(confluence_bootstrap_state_file "$REPOSITORY_SLUG") ||
    die GOVERNANCE_NOT_READY 'Cannot derive Confluence bootstrap state path'
  assert_safe_user_path "$cbc_file" 'Confluence bootstrap receipt'
  cbc_tmp=$(umask 077; mktemp "$CONFLUENCE_BOOTSTRAP_STATE_ROOT/.capture.XXXXXX") ||
    die GOVERNANCE_NOT_READY 'Cannot stage Confluence bootstrap capture'
  if ! jq -nc \
    --arg repository "$REPOSITORY_SLUG" \
    --arg folder "$cbc_folder" \
    --arg registry "$cbc_registry" \
    --arg scope "$cbc_scope" \
    --arg domain "$cbc_domain" \
    --arg transport "$cbc_transport" \
    --arg folder_title "$cbc_title" \
    --arg registry_title 'Backend Capability Registry' \
    --arg root "$ROUTE_CONFLUENCE_ROOT_CONTENT_ID" \
    '{
       repository:$repository,
       folder_id:$folder,
       registry_id:$registry,
       scope:$scope,
       domain:$domain,
       transport:$transport,
       folder_title:$folder_title,
       registry_title:$registry_title,
       catalog_root_id:$root
     }' >"$cbc_tmp" || ! chmod 600 "$cbc_tmp" || ! mv "$cbc_tmp" "$cbc_file"
  then
    rm -f "$cbc_tmp" || :
    die GOVERNANCE_NOT_READY 'Cannot write Confluence bootstrap capture'
  fi
  printf '%s\n' \
    'Phase: authorized bootstrap' \
    "Staged capture: $cbc_file" \
    "Captured folder ID: $cbc_folder" \
    "Captured Registry ID: $cbc_registry" \
    "Folder title: $cbc_title" \
    "Registry title: Backend Capability Registry" \
    "Next: beroka-governance confluence-bootstrap-verify $REPO --folder-id $cbc_folder --registry-id $cbc_registry --folder-parent-id $ROUTE_CONFLUENCE_ROOT_CONTENT_ID --registry-parent-id $ROUTE_CONFLUENCE_ROOT_CONTENT_ID" \
    'Result: BOOTSTRAP_CAPTURED'
}

cmd_confluence_bootstrap_verify() {
  cbv_repo=$1
  shift
  cbv_folder= cbv_registry= cbv_folder_parent= cbv_registry_parent=
  cbv_folder_title= cbv_registry_title=
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --folder-id)
        [ "$#" -ge 2 ] || { usage >&2; exit 2; }
        cbv_folder=$2
        shift 2
        ;;
      --registry-id)
        [ "$#" -ge 2 ] || { usage >&2; exit 2; }
        cbv_registry=$2
        shift 2
        ;;
      --folder-parent-id)
        [ "$#" -ge 2 ] || { usage >&2; exit 2; }
        cbv_folder_parent=$2
        shift 2
        ;;
      --registry-parent-id)
        [ "$#" -ge 2 ] || { usage >&2; exit 2; }
        cbv_registry_parent=$2
        shift 2
        ;;
      --folder-title)
        [ "$#" -ge 2 ] || { usage >&2; exit 2; }
        cbv_folder_title=$2
        shift 2
        ;;
      --registry-title)
        [ "$#" -ge 2 ] || { usage >&2; exit 2; }
        cbv_registry_title=$2
        shift 2
        ;;
      *) usage >&2; exit 2 ;;
    esac
  done
  [ -n "$cbv_folder" ] && [ -n "$cbv_registry" ] &&
    [ -n "$cbv_folder_parent" ] && [ -n "$cbv_registry_parent" ] ||
    { usage >&2; exit 2; }
  for cbv_id in "$cbv_folder" "$cbv_registry" "$cbv_folder_parent" \
    "$cbv_registry_parent"
  do
    printf '%s\n' "$cbv_id" | grep -Eq '^[1-9][0-9]*$' ||
      die ROUTING_REQUIRED 'Numeric Confluence content IDs are required'
  done
  prepare_confluence_bootstrap_repo "$cbv_repo"
  cbv_file=$(confluence_bootstrap_state_file "$REPOSITORY_SLUG") ||
    die GOVERNANCE_NOT_READY 'Cannot derive Confluence bootstrap state path'
  [ -f "$cbv_file" ] && [ ! -L "$cbv_file" ] ||
    die ROUTING_REQUIRED 'Run confluence-bootstrap-capture before verify'
  cbv_cap_folder=$(jq -r .folder_id "$cbv_file") ||
    die GOVERNANCE_NOT_READY 'Corrupt Confluence bootstrap capture'
  cbv_cap_registry=$(jq -r .registry_id "$cbv_file") ||
    die GOVERNANCE_NOT_READY 'Corrupt Confluence bootstrap capture'
  cbv_scope=$(jq -r .scope "$cbv_file") ||
    die GOVERNANCE_NOT_READY 'Corrupt Confluence bootstrap capture'
  cbv_domain=$(jq -r .domain "$cbv_file") ||
    die GOVERNANCE_NOT_READY 'Corrupt Confluence bootstrap capture'
  cbv_transport=$(jq -r .transport "$cbv_file") ||
    die GOVERNANCE_NOT_READY 'Corrupt Confluence bootstrap capture'
  cbv_expected_folder_title=$(jq -r .folder_title "$cbv_file") ||
    die GOVERNANCE_NOT_READY 'Corrupt Confluence bootstrap capture'
  cbv_expected_registry_title=$(jq -r .registry_title "$cbv_file") ||
    die GOVERNANCE_NOT_READY 'Corrupt Confluence bootstrap capture'
  cbv_root=$(jq -r .catalog_root_id "$cbv_file") ||
    die GOVERNANCE_NOT_READY 'Corrupt Confluence bootstrap capture'
  [ "$cbv_folder" = "$cbv_cap_folder" ] &&
    [ "$cbv_registry" = "$cbv_cap_registry" ] ||
    die MAPPING_CONFLICT 'Verify IDs do not match the staged bootstrap capture'
  [ "$cbv_root" = "$ROUTE_CONFLUENCE_ROOT_CONTENT_ID" ] ||
    die MAPPING_CONFLICT 'Staged catalog root no longer matches active routing'
  [ "$cbv_folder_parent" = "$ROUTE_CONFLUENCE_ROOT_CONTENT_ID" ] ||
    die DOC_HIERARCHY_FAILED \
      'Folder parent read-back must equal the catalog Confluence root'
  [ "$cbv_registry_parent" = "$ROUTE_CONFLUENCE_ROOT_CONTENT_ID" ] ||
    die DOC_HIERARCHY_FAILED \
      'Registry parent read-back must equal the catalog Confluence root'
  [ -z "$cbv_folder_title" ] ||
    [ "$cbv_folder_title" = "$cbv_expected_folder_title" ] ||
    die MAPPING_CONFLICT 'Folder title read-back does not match the bootstrap plan'
  [ -z "$cbv_registry_title" ] ||
    [ "$cbv_registry_title" = "$cbv_expected_registry_title" ] ||
    die MAPPING_CONFLICT 'Registry title read-back does not match the bootstrap plan'
  printf '%s\n' \
    'Phase: authorized bootstrap' \
    'Inventory update required: open a reviewed governance PR that appends this ACTIVE folder row to runtime/integrations/beroka-be-fe.confluence-targets' \
    "ACTIVE folder:	$REPOSITORY_SLUG	folder	ACTIVE	$cbv_folder	$cbv_expected_folder_title	$cbv_scope	$cbv_domain	$cbv_transport	$ROUTE_CONFLUENCE_ROOT_CONTENT_ID	-	-" \
    "Reviewed Registry content ID: $cbv_registry" \
    'Use that Registry content ID as registry-content-id on later ACTIVE/PLANNED capability pages.' \
    'Do not guess IDs. Do not write ACTIVE rows into a local installed release.' \
    'After the inventory release is active, use ordinary target-bound confluence-write.' \
    'Result: BOOTSTRAP_VERIFIED' \
    'Result: INVENTORY_UPDATE_REQUIRED'
}

resolve_confluence_target() {
  case "$CONFLUENCE_TARGET_ACTION:$CONFLUENCE_TARGET_CONTENT_ID" in
    create:new) ;;
    update:[1-9]*|move:[1-9]*)
      printf '%s\n' "$CONFLUENCE_TARGET_CONTENT_ID" |
        grep -Eq '^[1-9][0-9]*$' ||
        die ROUTING_REQUIRED \
          'A numeric Confluence target content ID is required'
      ;;
    *)
      die ROUTING_REQUIRED \
        'Confluence action and target content ID conflict'
      ;;
  esac
  # Moves need a numeric destination parent on every route, including
  # standalone none:explicit-only which returns before inventory checks.
  if [ "$CONFLUENCE_TARGET_ACTION" = move ]; then
    printf '%s\n' "$CONFLUENCE_TARGET_PARENT_ID" |
      grep -Eq '^[1-9][0-9]*$' ||
      die ROUTING_REQUIRED \
        'A numeric destination parent ID is required for Confluence moves'
  fi
  case "$ROUTE_INTEGRATION_PROFILE:$ROUTE_CROSS_REPO_POLICY" in
    none:explicit-only) return 0 ;;
    beroka-be-fe:profile-controlled) ;;
    *) die ROUTING_REQUIRED 'Exact Confluence target routing is required' ;;
  esac
  rct_file=$RELEASE_DIR/runtime/integrations/beroka-be-fe.confluence-targets
  validate_confluence_target_inventory "$rct_file" \
    "$RELEASE_DIR/runtime/repositories" ||
    die ROUTING_REQUIRED 'Reviewed Confluence target inventory is unavailable'

  # Allow-by-default: only UNACTIVATED rows hard-deny writes. Inventory
  # ACTIVE/PLANNED/LEGACY/DRIFTED rows remain discoverability guidance.
  if [ "$CONFLUENCE_TARGET_CONTENT_ID" != new ] &&
     confluence_content_is_unactivated "$rct_file" \
       "$CONFLUENCE_TARGET_CONTENT_ID"
  then
    die_docs_unactivated \
      "Confluence content $CONFLUENCE_TARGET_CONTENT_ID is UNACTIVATED in the governance release"
  fi
  if [ -n "$CONFLUENCE_TARGET_PARENT_ID" ] &&
     confluence_content_is_unactivated "$rct_file" \
       "$CONFLUENCE_TARGET_PARENT_ID"
  then
    die_docs_unactivated \
      "Confluence parent $CONFLUENCE_TARGET_PARENT_ID is UNACTIVATED in the governance release"
  fi

  rct_record=$(
    awk -F '\t' \
      -v repository="$REPOSITORY_SLUG" \
      -v action="$CONFLUENCE_TARGET_ACTION" \
      -v content="$CONFLUENCE_TARGET_CONTENT_ID" \
      -v capability="$CONFLUENCE_TARGET_CAPABILITY_ID" '
        /^#/ || /^[[:space:]]*$/ { next }
        $1 == repository &&
          ((action == "create" && $3 == "PLANNED" && $4 == "-" &&
            capability != "" && $10 == capability) ||
           (action != "create" && $4 == content)) {
            matches++
            row=$0
        }
        END {
          if (matches != 1) exit 1
          print row
        }
      ' "$rct_file"
  ) || rct_record=
  if [ -z "$rct_record" ]; then
    rct_state=UNTRACKED
    rct_repository=$REPOSITORY_SLUG
    rct_type=page
    rct_content=$CONFLUENCE_TARGET_CONTENT_ID
    rct_title='(allow-by-default writable target)'
    rct_scope=${CONFLUENCE_TARGET_SCOPE:--}
    rct_domain=${CONFLUENCE_TARGET_DOMAIN:--}
    rct_transport=${CONFLUENCE_TARGET_TRANSPORT:--}
    rct_parent=${CONFLUENCE_TARGET_PARENT_ID:--}
    rct_capability=${CONFLUENCE_TARGET_CAPABILITY_ID:--}
    rct_registry=${CONFLUENCE_TARGET_REGISTRY_CONTENT_ID:--}
    return 0
  fi

  IFS="$(printf '\t')" read -r rct_repository rct_type rct_state \
    rct_content rct_title rct_scope rct_domain rct_transport rct_parent \
    rct_capability rct_registry <<EOF
$rct_record
EOF

  case "$rct_state" in
    UNACTIVATED)
      die_docs_unactivated \
        "Confluence content $CONFLUENCE_TARGET_CONTENT_ID is UNACTIVATED in the governance release"
      ;;
    DRIFTED)
      if [ -n "$CONFLUENCE_TARGET_TRANSPORT" ] &&
         [ "$CONFLUENCE_TARGET_TRANSPORT" != "$rct_transport" ]
      then
        printf '%s\n' \
          "Target content ID: $CONFLUENCE_TARGET_CONTENT_ID" \
          "Intended transport: $CONFLUENCE_TARGET_TRANSPORT" \
          "Target transport: $rct_transport"
        die MAPPING_CONFLICT
      fi
      ;;
  esac

  # When callers still supply full reviewed metadata, keep consistency checks.
  if [ -n "$CONFLUENCE_TARGET_SCOPE" ] &&
     [ -n "$CONFLUENCE_TARGET_DOMAIN" ] &&
     [ -n "$CONFLUENCE_TARGET_TRANSPORT" ] &&
     [ -n "$CONFLUENCE_TARGET_PARENT_ID" ] &&
     [ -n "$CONFLUENCE_TARGET_CAPABILITY_ID" ] &&
     [ -n "$CONFLUENCE_TARGET_REGISTRY_CONTENT_ID" ]
  then
    [ "$rct_scope" = - ] && rct_scope=$CONFLUENCE_TARGET_SCOPE
    [ "$rct_domain" = - ] && rct_domain=$CONFLUENCE_TARGET_DOMAIN
    [ "$rct_transport" = - ] && rct_transport=$CONFLUENCE_TARGET_TRANSPORT
    [ "$rct_parent" = - ] && rct_parent=$CONFLUENCE_TARGET_PARENT_ID
    [ "$rct_capability" = - ] && rct_capability=$CONFLUENCE_TARGET_CAPABILITY_ID
    [ "$rct_registry" = - ] && rct_registry=$CONFLUENCE_TARGET_REGISTRY_CONTENT_ID
    [ "$rct_scope" = "$CONFLUENCE_TARGET_SCOPE" ] &&
      [ "$rct_domain" = "$CONFLUENCE_TARGET_DOMAIN" ] &&
      [ "$rct_transport" = "$CONFLUENCE_TARGET_TRANSPORT" ] &&
      [ "$rct_parent" = "$CONFLUENCE_TARGET_PARENT_ID" ] &&
      [ "$rct_capability" = "$CONFLUENCE_TARGET_CAPABILITY_ID" ] &&
      [ "$rct_registry" = "$CONFLUENCE_TARGET_REGISTRY_CONTENT_ID" ] ||
      die MAPPING_CONFLICT \
        'Requested Confluence metadata conflicts with the reviewed target'
  fi
}

require_operation_routing() {
  ror_operation=$1 ror_client=${2:-}
  case "$ror_operation" in
    jira-write|jira-handoff-write)
      [ -n "$ROUTE_JIRA_PROJECT_KEY" ] ||
        die ROUTING_REQUIRED "JIRA_PROJECT_KEY is required for $ror_operation"
      if [ "$ror_operation" = jira-handoff-write ]; then
        [ "$ROUTE_INTEGRATION_PROFILE" = beroka-be-fe ] &&
          [ "$ROUTE_CROSS_REPO_POLICY" = profile-controlled ] ||
          die ROUTING_REQUIRED \
            'Cross-team Jira handoff updates require an exact integration target'
        validate_cross_team_body "$CONFLUENCE_HANDOFF_BODY_FILE"
      fi
      PREFLIGHT_CAPABILITY=jira-issue-write
      ;;
    jira-board-verify)
      [ -n "$ROUTE_JIRA_PROJECT_KEY" ] ||
        die ROUTING_REQUIRED 'JIRA_PROJECT_KEY is required for jira-board-verify'
      [ -n "$ROUTE_JIRA_BOARD_ID" ] ||
        die ROUTING_REQUIRED 'JIRA_BOARD_ID is required for jira-board-verify'
      PREFLIGHT_CAPABILITY=jira-board-verification
      ;;
    jira-intake-write)
      resolve_intake_route
      validate_cross_team_body "$CONFLUENCE_HANDOFF_BODY_FILE"
      PREFLIGHT_CAPABILITY=jira-issue-write
      ;;
    confluence-write)
      require_confluence_route
      case "$CONFLUENCE_TARGET_ACTION" in
        '')
          die ROUTING_REQUIRED 'Confluence content target details are required'
          ;;
        update) PREFLIGHT_CAPABILITY=confluence-page-update ;;
        create|move) PREFLIGHT_CAPABILITY=confluence-page-parent-write ;;
        *) die ROUTING_REQUIRED 'Confluence action is invalid' ;;
      esac
      if [ -n "$CONFLUENCE_TARGET_ACTION" ]; then
        resolve_confluence_target
      fi
      require_trusted_confluence_body_gate "$ror_client" \
        "$CONFLUENCE_TARGET_ACTION"
      ;;
    confluence-handoff-write)
      require_confluence_route
      case "$CONFLUENCE_TARGET_ACTION" in
        create) PREFLIGHT_CAPABILITY=confluence-page-parent-write ;;
        update) PREFLIGHT_CAPABILITY=confluence-page-update ;;
        *) die ROUTING_REQUIRED 'Confluence handoff write requires create or update' ;;
      esac
      validate_handoff_body "$CONFLUENCE_HANDOFF_BODY_FILE" \
        "$CONFLUENCE_TARGET_ACTION" "$CONFLUENCE_TARGET_CONTENT_ID"
      require_active_handoff_folder "$(confluence_targets_path)"
      resolve_confluence_target
      require_handoff_target_parent
      require_trusted_confluence_body_gate "$ror_client" \
        "$CONFLUENCE_TARGET_ACTION"
      ;;
    confluence-handoff-verify)
      require_confluence_route
      [ "$ROUTE_INTEGRATION_PROFILE" = beroka-be-fe ] &&
        [ "$ROUTE_CROSS_REPO_POLICY" = profile-controlled ] ||
        die ROUTING_REQUIRED \
          'Confluence handoff verification requires an exact integration target'
      case "$CONFLUENCE_TARGET_ACTION:$CONFLUENCE_TARGET_CONTENT_ID" in
        update:[1-9]*)
          printf '%s\n' "$CONFLUENCE_TARGET_CONTENT_ID" | grep -Eq '^[1-9][0-9]*$' ||
            die HANDOFF_READBACK_REQUIRED \
              'Handoff readback requires an exact numeric target content ID'
          ;;
        *) die HANDOFF_READBACK_REQUIRED \
          'Handoff readback requires an existing target page' ;;
      esac
      validate_handoff_body "$CONFLUENCE_HANDOFF_BODY_FILE" \
        "$CONFLUENCE_TARGET_ACTION" "$CONFLUENCE_TARGET_CONTENT_ID"
      require_active_handoff_folder "$(confluence_targets_path)"
      resolve_confluence_target
      require_handoff_target_parent
      [ "$rct_state" = ACTIVE ] ||
        die ROUTING_REQUIRED \
          'Confluence handoff verification requires an ACTIVE target page'
      PREFLIGHT_CAPABILITY=confluence-page-read
      ;;
    cross-repo-write)
      die ROUTING_REQUIRED \
        'Centrally reviewed exact counterpart and workflow mapping are required for cross-repo-write'
      ;;
    *) usage >&2; exit 2 ;;
  esac
}

resolve_intake_route() {
  INTAKE_TARGET_REPOSITORY=
  INTAKE_TARGET_PROFILE=
  INTAKE_TARGET_JIRA_PROJECT=
  [ "$ROUTE_INTEGRATION_PROFILE" = beroka-be-fe ] &&
    [ "$ROUTE_CROSS_REPO_POLICY" = profile-controlled ] ||
    die ROUTING_REQUIRED \
      'Exact profile-controlled intake mapping is required for jira-intake-write'

  rir_file=$RELEASE_DIR/runtime/integrations/beroka-be-fe.intake
  validate_intake_inventory \
    "$rir_file" "$RELEASE_DIR/runtime/repositories" ||
    die ROUTING_REQUIRED \
      'Exact profile-controlled intake mapping is required for jira-intake-write'
  rir_record=$(
    awk -F '\t' -v source="$REPOSITORY_SLUG" '
      /^#/ || /^[[:space:]]*$/ { next }
      $1 == source { matches++; record=$0 }
      END {
        if (matches != 1) exit 1
        print record
      }
    ' "$rir_file"
  ) || die ROUTING_REQUIRED \
    'Exact profile-controlled intake mapping is required for jira-intake-write'
  while IFS="$(printf '\t')" read -r rir_source rir_target_repository \
    rir_target_profile rir_target_project
  do
    [ "$rir_source" = "$REPOSITORY_SLUG" ] || die ROUTING_REQUIRED
    INTAKE_TARGET_REPOSITORY=$rir_target_repository
    INTAKE_TARGET_PROFILE=$rir_target_profile
    INTAKE_TARGET_JIRA_PROJECT=$rir_target_project
  done <<EOF
$rir_record
EOF

  case "$ROUTE_PROFILE:$INTAKE_TARGET_PROFILE" in
    frontend:backend|backend:frontend) ;;
    *)
      die ROUTING_REQUIRED \
        "Cross-team intake requires the opposite profile: $ROUTE_PROFILE -> ${INTAKE_TARGET_PROFILE:-missing}"
      ;;
  esac
}

print_preflight_result() {
  ppr_client=$1 ppr_operation=$2
  printf '%s\n' \
    "Client: $ppr_client" \
    'Routing source: central catalog' \
    "Profile: $ROUTE_PROFILE" \
    "Integration profile: $ROUTE_INTEGRATION_PROFILE" \
    "Cross-repository policy: $ROUTE_CROSS_REPO_POLICY" \
    "Operation: $ppr_operation"
  case "$ppr_operation" in
    jira-write|jira-handoff-write)
      printf '%s\n' "Jira project: $ROUTE_JIRA_PROJECT_KEY"
      ;;
    jira-intake-write)
      printf '%s\n' \
        "Intake target profile: $INTAKE_TARGET_PROFILE" \
        "Intake Jira project: $INTAKE_TARGET_JIRA_PROJECT"
      ;;
    jira-board-verify)
      printf '%s\n' \
        "Jira project: $ROUTE_JIRA_PROJECT_KEY" \
        "Jira board: $ROUTE_JIRA_BOARD_ID"
      ;;
    confluence-write|confluence-handoff-write|confluence-handoff-verify)
      printf '%s\n' \
        "Confluence space: $ROUTE_CONFLUENCE_SPACE_KEY" \
        "Confluence root content: $ROUTE_CONFLUENCE_ROOT_CONTENT_ID" \
        "Confluence root type: $ROUTE_CONFLUENCE_ROOT_CONTENT_TYPE" \
        "Target action: $CONFLUENCE_TARGET_ACTION" \
        "Target content ID: $CONFLUENCE_TARGET_CONTENT_ID" \
        "Capability ID: $CONFLUENCE_TARGET_CAPABILITY_ID" \
        "Target scope: $CONFLUENCE_TARGET_SCOPE" \
        "Target domain: $CONFLUENCE_TARGET_DOMAIN" \
        "Target transport: $CONFLUENCE_TARGET_TRANSPORT" \
        "Expected parent ID: $CONFLUENCE_TARGET_PARENT_ID" \
        "Registry content ID: $CONFLUENCE_TARGET_REGISTRY_CONTENT_ID"
      if [ "$ppr_operation" = confluence-handoff-verify ]; then
        printf '%s\n' 'Readback: CAPABILITY_ONLY'
      fi
      ;;
  esac
  printf '%s\n' \
    "Capability: $PREFLIGHT_CAPABILITY" \
    "Capability state: $CAPABILITY_STATE" \
    "Capability evidence: $CAPABILITY_EVIDENCE_SOURCE" \
    "Runtime inventory: $CAPABILITY_INVENTORY_STATE" \
    'Result: PASS'
}

cmd_preflight() {
  pf_repo=$1
  shift
  pf_client= pf_operation= pf_non_interactive=0
  pf_has_confluence_target=0
  pf_seen_action=0 pf_seen_content=0 pf_seen_capability=0 pf_seen_scope=0
  pf_seen_domain=0 pf_seen_transport=0 pf_seen_parent=0 pf_seen_registry=0
  pf_seen_handoff_body=0
  pf_seen_readback_parent=0 pf_seen_readback_space=0 pf_seen_readback_title=0
  pf_seen_readback_version=0 pf_seen_readback_owner=0
  CONFLUENCE_TARGET_ACTION= CONFLUENCE_TARGET_CONTENT_ID=
  CONFLUENCE_TARGET_CAPABILITY_ID= CONFLUENCE_TARGET_SCOPE=
  CONFLUENCE_TARGET_DOMAIN= CONFLUENCE_TARGET_TRANSPORT=
  CONFLUENCE_TARGET_PARENT_ID= CONFLUENCE_TARGET_REGISTRY_CONTENT_ID=
  CONFLUENCE_HANDOFF_BODY_FILE=
  CONFLUENCE_READBACK_PARENT_ID= CONFLUENCE_READBACK_SPACE_KEY=
  CONFLUENCE_READBACK_TITLE= CONFLUENCE_READBACK_VERSION=
  CONFLUENCE_READBACK_OWNER_ACCOUNT_ID=
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --client)
        [ -z "$pf_client" ] && [ "$#" -ge 2 ] ||
          { usage >&2; exit 2; }
        case "$2" in
          codex|claude|cursor) pf_client=$2 ;;
          *) usage >&2; exit 2 ;;
        esac
        shift 2
        ;;
      --operation)
        [ -z "$pf_operation" ] && [ "$#" -ge 2 ] ||
          { usage >&2; exit 2; }
        pf_operation=$2
        shift 2
        ;;
      --non-interactive)
        [ "$pf_non_interactive" -eq 0 ] || { usage >&2; exit 2; }
        pf_non_interactive=1
        shift
        ;;
      --handoff-body-file)
        [ "$pf_seen_handoff_body" -eq 0 ] && [ "$#" -ge 2 ] ||
          { usage >&2; exit 2; }
        case "$2" in --*) usage >&2; exit 2 ;; esac
        pf_seen_handoff_body=1
        CONFLUENCE_HANDOFF_BODY_FILE=$2
        shift 2
        ;;
      --readback-parent-id|--readback-space-key|--readback-title|\
      --readback-version|--readback-owner-account-id)
        pf_readback_option=$1
        [ "$#" -ge 2 ] || { usage >&2; exit 2; }
        case "$2" in --*) usage >&2; exit 2 ;; esac
        case "$pf_readback_option" in
          --readback-parent-id)
            [ "$pf_seen_readback_parent" -eq 0 ] || { usage >&2; exit 2; }
            pf_seen_readback_parent=1
            CONFLUENCE_READBACK_PARENT_ID=$2
            ;;
          --readback-space-key)
            [ "$pf_seen_readback_space" -eq 0 ] || { usage >&2; exit 2; }
            pf_seen_readback_space=1
            CONFLUENCE_READBACK_SPACE_KEY=$2
            ;;
          --readback-title)
            [ "$pf_seen_readback_title" -eq 0 ] || { usage >&2; exit 2; }
            pf_seen_readback_title=1
            CONFLUENCE_READBACK_TITLE=$2
            ;;
          --readback-version)
            [ "$pf_seen_readback_version" -eq 0 ] || { usage >&2; exit 2; }
            pf_seen_readback_version=1
            CONFLUENCE_READBACK_VERSION=$2
            ;;
          --readback-owner-account-id)
            [ "$pf_seen_readback_owner" -eq 0 ] || { usage >&2; exit 2; }
            pf_seen_readback_owner=1
            CONFLUENCE_READBACK_OWNER_ACCOUNT_ID=$2
            ;;
        esac
        shift 2
        ;;
      --confluence-action|--target-content-id|--capability-id|--scope|\
      --domain|--transport|--expected-parent-id|--registry-content-id)
        pf_target_option=$1
        pf_target_value=
        pf_has_confluence_target=1
        shift
        if [ "$#" -gt 0 ]; then
          case "$1" in
            --*) ;;
            *) pf_target_value=$1; shift ;;
          esac
        fi
        case "$pf_target_option" in
          --confluence-action)
            [ "$pf_seen_action" -eq 0 ] || { usage >&2; exit 2; }
            pf_seen_action=1
            CONFLUENCE_TARGET_ACTION=$pf_target_value
            ;;
          --target-content-id)
            [ "$pf_seen_content" -eq 0 ] || { usage >&2; exit 2; }
            pf_seen_content=1
            CONFLUENCE_TARGET_CONTENT_ID=$pf_target_value
            ;;
          --capability-id)
            [ "$pf_seen_capability" -eq 0 ] || { usage >&2; exit 2; }
            pf_seen_capability=1
            CONFLUENCE_TARGET_CAPABILITY_ID=$pf_target_value
            ;;
          --scope)
            [ "$pf_seen_scope" -eq 0 ] || { usage >&2; exit 2; }
            pf_seen_scope=1
            CONFLUENCE_TARGET_SCOPE=$pf_target_value
            ;;
          --domain)
            [ "$pf_seen_domain" -eq 0 ] || { usage >&2; exit 2; }
            pf_seen_domain=1
            CONFLUENCE_TARGET_DOMAIN=$pf_target_value
            ;;
          --transport)
            [ "$pf_seen_transport" -eq 0 ] || { usage >&2; exit 2; }
            pf_seen_transport=1
            CONFLUENCE_TARGET_TRANSPORT=$pf_target_value
            ;;
          --expected-parent-id)
            [ "$pf_seen_parent" -eq 0 ] || { usage >&2; exit 2; }
            pf_seen_parent=1
            CONFLUENCE_TARGET_PARENT_ID=$pf_target_value
            ;;
          --registry-content-id)
            [ "$pf_seen_registry" -eq 0 ] || { usage >&2; exit 2; }
            pf_seen_registry=1
            CONFLUENCE_TARGET_REGISTRY_CONTENT_ID=$pf_target_value
            ;;
        esac
        ;;
      *) usage >&2; exit 2 ;;
    esac
  done
  [ -n "$pf_client" ] && [ -n "$pf_operation" ] ||
    { usage >&2; exit 2; }
  case "$pf_operation" in
    confluence-write|confluence-handoff-write|confluence-handoff-verify) ;;
    *)
      [ "$pf_has_confluence_target" -eq 0 ] ||
        { usage >&2; exit 2; }
      ;;
  esac
  if [ "$pf_seen_handoff_body" -eq 1 ]; then
    case "$pf_operation" in
      jira-intake-write|jira-handoff-write|confluence-handoff-write|confluence-handoff-verify) ;;
      *) usage >&2; exit 2 ;;
    esac
  fi
  if [ "$pf_seen_readback_parent" -eq 1 ] || [ "$pf_seen_readback_space" -eq 1 ] ||
     [ "$pf_seen_readback_title" -eq 1 ] || [ "$pf_seen_readback_version" -eq 1 ] ||
     [ "$pf_seen_readback_owner" -eq 1 ]
  then
    [ "$pf_operation" = confluence-handoff-verify ] || { usage >&2; exit 2; }
  fi
  load_active_release
  resolve_repository_context "$pf_repo" defer-role
  if ! repository_is_governed; then
    print_not_governed
    return
  fi
  [ "$pf_operation" != cross-repo-write ] ||
    require_operation_routing "$pf_operation"
  require_role_scope
  require_enrolled_client "$pf_client"
  # Instruction verification has its own temporary staging lifecycle.
  (verify_client_instruction "$pf_client")
  if [ "$pf_operation" = github-write ]; then
    github_preflight "$pf_client" "$pf_non_interactive"
    return
  fi
  [ -f "$RELEASE_DIR/runtime/routing-schema" ] &&
    [ "$(sed -n '1p' "$RELEASE_DIR/runtime/routing-schema")" = 1 ] ||
    die GOVERNANCE_NOT_READY \
      'Update the repository to a release with runtime/routing-schema=1 before preflight'
  case "$ROUTING_STATE" in
    ROUTING_ACTIVE) ;;
    ROUTING_REQUIRED) die ROUTING_REQUIRED ;;
    *) die ROUTING_INVALID ;;
  esac
  if [ "$pf_operation" = confluence-handoff-verify ] && {
       [ "$pf_seen_readback_parent" -eq 1 ] ||
       [ "$pf_seen_readback_space" -eq 1 ] ||
       [ "$pf_seen_readback_title" -eq 1 ] ||
       [ "$pf_seen_readback_version" -eq 1 ] ||
       [ "$pf_seen_readback_owner" -eq 1 ]
     }
  then
    die HANDOFF_READBACK_REQUIRED \
      'Caller-supplied assertions cannot prove an actual Confluence write and subsequent read'
  fi
  require_operation_routing "$pf_operation" "$pf_client"
  verify_github_role "$pf_client"

  require_client "$pf_client"
  pf_connector=0
  connector_state "$pf_client" || pf_connector=$?
  [ "$pf_connector" -eq 0 ] || {
    die CONNECTOR_MISSING \
      "Missing compatible Atlassian connector for $pf_client"
  }
  pf_health=0
  connector_health "$pf_client" || pf_health=$?
  if [ "$pf_health" -eq 1 ]; then
    pf_interactive=0
    if [ "$pf_non_interactive" -eq 0 ] && [ -t 0 ] && [ -t 1 ]; then
      pf_interactive=1
    fi
    [ "$pf_interactive" -eq 1 ] ||
      auth_required "$pf_client"
    printf '%s\n' \
      "Client: $pf_client" \
      'Provider: atlassian' \
      'Authentication: AUTH_REQUIRED'
    run_oauth "$pf_client" || auth_required "$pf_client"
    pf_health=0
    connector_health "$pf_client" || pf_health=$?
    case "$pf_health" in
      0) ;;
      1) auth_required "$pf_client" ;;
      *) connector_health_unavailable "$pf_client" ;;
    esac
  elif [ "$pf_health" -ne 0 ]; then
    connector_health_unavailable "$pf_client"
  fi

  if [ -n "$PREFLIGHT_CAPABILITY" ]; then
    resolve_capability "$pf_client" "$PREFLIGHT_CAPABILITY"
    if [ "$CAPABILITY_STATE" != SUPPORTED ]; then
      printf '%s\n' \
        "Operation: $pf_operation" \
        "Capability: $PREFLIGHT_CAPABILITY" \
        "Capability state: $CAPABILITY_STATE" \
        "Capability evidence: $CAPABILITY_EVIDENCE_SOURCE" \
        "Runtime inventory: $CAPABILITY_INVENTORY_STATE"
      die CONNECTOR_CAPABILITY_REQUIRED
    fi
  fi
  print_preflight_result "$pf_client" "$pf_operation"
}

cmd_setup_connectors() {
  setup_client= setup_non_interactive=0 setup_cursor_first_run=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --client)
        [ -z "$setup_client" ] && [ "$#" -ge 2 ] || { usage >&2; exit 2; }
        setup_client=$(client_executable "$2")
        case "$setup_client" in
          cursor-agent) setup_client=cursor ;;
        esac
        shift 2
        ;;
      --non-interactive)
        [ "$setup_non_interactive" -eq 0 ] || { usage >&2; exit 2; }
        setup_non_interactive=1
        shift
        ;;
      *) usage >&2; exit 2 ;;
    esac
  done
  setup_interactive=0
  if [ "$setup_non_interactive" -eq 0 ] && [ -t 0 ] && [ -t 1 ]; then
    setup_interactive=1
  fi
  if [ -z "$setup_client" ]; then
    [ "$setup_interactive" -eq 1 ] || { usage >&2; exit 2; }
    setup_client=$(detect_client)
  fi
  require_client "$setup_client"
  setup_state=0
  connector_state "$setup_client" || setup_state=$?
  case "$setup_state" in
    0) ;;
    1)
      if [ "$setup_client" = cursor ]; then
        setup_cursor_first_run=1
        cursor_first_run_setup "$setup_interactive"
      else
        configure_connector "$setup_client"
      fi
      ;;
    2) die CONNECTOR_MISSING "Existing atlassian connector has an unexpected URL for $setup_client" ;;
    *) die GOVERNANCE_NOT_READY "Cannot inspect $setup_client Atlassian connector" ;;
  esac
  setup_health=0
  connector_health "$setup_client" || setup_health=$?
  case "$setup_health" in
    0)
      printf '%s\n' \
        "Client: $setup_client" \
        'Connector: PASS' \
        'Authentication: PASS'
      pass_result
      return
      ;;
    1)
      [ "$setup_cursor_first_run" -eq 0 ] ||
        auth_pending "$setup_client"
      ;;
    *) connector_health_unavailable "$setup_client" ;;
  esac
  [ "$setup_interactive" -eq 1 ] ||
    auth_required "$setup_client"
  printf '%s\n' \
    "Client: $setup_client" \
    'Provider: atlassian' \
    'Authentication: AUTH_REQUIRED'
  run_oauth "$setup_client" || auth_pending "$setup_client"
  setup_health=0
  connector_health "$setup_client" || setup_health=$?
  case "$setup_health" in
    0) ;;
    1) auth_pending "$setup_client" ;;
    *) connector_health_unavailable "$setup_client" ;;
  esac
  printf '%s\n' \
    "Client: $setup_client" \
    'Connector: PASS' \
    'Authentication: PASS'
  pass_result
}

cmd_doctor() {
  requested=$1 doctor_flag=${2:-} doctor_client=${3:-}
  if [ -n "$doctor_flag" ]; then
    [ "$doctor_flag" = --client ] && [ -n "$doctor_client" ] ||
      { usage >&2; exit 2; }
    case "$doctor_client" in
      codex|claude|cursor) ;;
      *) usage >&2; exit 2 ;;
    esac
  fi
  load_active_release
  resolve_repository_context "$requested"
  if [ -n "$doctor_client" ]; then
    require_enrolled_client "$doctor_client"
    verify_client_instruction "$doctor_client"
    if [ "$doctor_client" = cursor ]; then
      verify_cursor_hooks || die GOVERNANCE_NOT_READY \
        'Remediation: beroka-governance bootstrap --client cursor'
      printf '%s\n' 'Runtime hook: INSTALLED'
      verify_cursor_runtime || die GOVERNANCE_NOT_READY \
        'Cursor runtime enforcement canary failed'
      printf '%s\n' 'Runtime enforcement: PASS'
    fi
    require_client "$doctor_client"
    doctor_state=0
    connector_state "$doctor_client" || doctor_state=$?
    [ "$doctor_state" -eq 0 ] ||
      die CONNECTOR_MISSING "Missing compatible Atlassian connector for $doctor_client"
    doctor_health=0
    connector_health "$doctor_client" || doctor_health=$?
    case "$doctor_health" in
      0) ;;
      1)
        doctor_interactive=0
        [ -t 0 ] && [ -t 1 ] && doctor_interactive=1
        [ "$doctor_interactive" -eq 1 ] ||
          auth_required "$doctor_client"
        printf '%s\n' \
          "Client: $doctor_client" \
          'Provider: atlassian' \
          'Authentication: AUTH_REQUIRED'
        run_oauth "$doctor_client" || auth_required "$doctor_client"
        doctor_health=0
        connector_health "$doctor_client" || doctor_health=$?
        case "$doctor_health" in
          0) ;;
          1) auth_required "$doctor_client" ;;
          *) connector_health_unavailable "$doctor_client" ;;
        esac
        ;;
      *) connector_health_unavailable "$doctor_client" ;;
    esac
    printf '%s\n' "Client: $doctor_client" 'Connector: PASS' 'Authentication: PASS'
  fi
  printf '%s\n' \
    "Repository: $REPOSITORY_SLUG" \
    "Version: $ACTIVE_VERSION" \
    "Commit: $ACTIVE_COMMIT" \
    'Routing source: central catalog' \
    "Routing: $ROUTING_STATE" \
    "Legacy repository metadata: $(legacy_repository_state "$REPO")"
  pass_result
}

cmd_context() {
  load_active_release
  resolve_repository_context "$1"
  if ! repository_is_governed; then
    print_not_governed
    return
  fi
  cat "$RELEASE_DIR/runtime/entrypoint.md" || die GOVERNANCE_NOT_READY 'Cannot read runtime entrypoint'
  printf '%s\n' \
    "Repository: $REPOSITORY_SLUG" \
    "Version: $ACTIVE_VERSION" \
    "Commit: $ACTIVE_COMMIT" \
    'Routing source: central catalog' \
    "Routing: $ROUTING_STATE"
  if [ ! -e "$RELEASE_DIR/runtime/routing-schema" ]; then
    printf '%s\n' 'External routing-dependent writes: BLOCKED'
    return
  fi
  render_routing_context
  case "$ROUTING_STATE" in
    ROUTING_ACTIVE) printf '%s\n' 'External routing-dependent writes: PREFLIGHT_REQUIRED' ;;
    *) printf '%s\n' 'External routing-dependent writes: BLOCKED' ;;
  esac
}

render_routing_context() {
  cat "$RELEASE_DIR/runtime/rules/general.md" ||
    die GOVERNANCE_NOT_READY 'Cannot read general runtime rules'
  case "$ROUTING_STATE" in
    ROUTING_ACTIVE|ROUTING_REQUIRED) ;;
    *) return 0 ;;
  esac
  printf '%s\n' \
    "Profile: $ROUTE_PROFILE" \
    "Dependency state: $DEPENDENCY_STATE" \
    "Jira project: ${ROUTE_JIRA_PROJECT_KEY:-ROUTING_REQUIRED}" \
    "Jira board: ${ROUTE_JIRA_BOARD_ID:-NOT_DECLARED}" \
    "Confluence space: ${ROUTE_CONFLUENCE_SPACE_KEY:-ROUTING_REQUIRED}" \
    "Confluence root content: ${ROUTE_CONFLUENCE_ROOT_CONTENT_ID:-ROUTING_REQUIRED}" \
    "Confluence root type: ${ROUTE_CONFLUENCE_ROOT_CONTENT_TYPE:-ROUTING_REQUIRED}" \
    "Integration profile: $ROUTE_INTEGRATION_PROFILE" \
    "Cross-repository policy: $ROUTE_CROSS_REPO_POLICY"
  cat "$RELEASE_DIR/runtime/profiles/$ROUTE_PROFILE.md" ||
    die GOVERNANCE_NOT_READY 'Cannot read repository profile'
  if [ "$ROUTE_INTEGRATION_PROFILE" = beroka-be-fe ]; then
    cat "$RELEASE_DIR/runtime/rules/work-items.md" ||
      die GOVERNANCE_NOT_READY 'Cannot read BE/FE work-item rules'
  fi
  if [ "$ROUTE_INTEGRATION_PROFILE" != none ]; then
    cat "$RELEASE_DIR/runtime/integrations/$ROUTE_INTEGRATION_PROFILE.md" ||
      die GOVERNANCE_NOT_READY 'Cannot read integration profile'
  fi
}

cmd_show() {
  repo=$1 kind=$2 name=${3:-}
  load_active_release
  resolve_repository_context "$repo"
  if ! repository_is_governed; then
    print_not_governed
    return
  fi
  case "$kind:$name" in
    governance:) file=governance.md ;;
    handbook:) file=handbook.md ;;
    workflow:) file=workflow.md ;;
    template:ai-agent-assignment) file=templates/ai-agent-assignment.md ;;
    template:github-issue) file=templates/github-issue.md ;;
    template:jira-confluence) file=templates/jira-confluence.md ;;
    template:pull-request) file=templates/pull-request.md ;;
    *) die GOVERNANCE_NOT_READY "Unknown document selection: $kind ${name}" ;;
  esac
  [ -f "$RELEASE_DIR/$file" ] || die GOVERNANCE_NOT_READY "Missing package file: $file"
  cat "$RELEASE_DIR/$file" || die GOVERNANCE_NOT_READY "Cannot read package file: $file"
}
