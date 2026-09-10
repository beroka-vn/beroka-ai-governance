# Native Confluence tool boundaries. No credentials or page bodies in receipts.

documentation_hooks_file() {
  case "$1" in
    codex) printf '%s\n' "${CODEX_HOME:-$HOME/.codex}/hooks.json" ;;
    claude) printf '%s\n' "$HOME/.claude/settings.json" ;;
    cursor) printf '%s\n' "$HOME/.cursor/hooks.json" ;;
    *) die CLIENT_BODY_GATE_REQUIRED 'Supported documentation clients: codex, claude, cursor' ;;
  esac
}

documentation_hooks_expected() {
  dhe_client=$1
  jq -nc --arg client "$dhe_client" --arg cli "$BIN_DIR/$PROGRAM" '
    ($cli | @sh) as $cli |
    [{phase:"pre",event:(if $client == "cursor" then "preToolUse" else "PreToolUse" end)},
     {phase:"post",event:(if $client == "cursor" then "postToolUse" else "PostToolUse" end)},
     {phase:"stop",event:(if $client == "cursor" then "stop" else "Stop" end)}] |
    map(. + {entry:(($cli + " confluence-hook " + $client + " " + .phase) as $cmd |
      if $client == "cursor" then
        {command:$cmd,failClosed:true}
      else {hooks:[{type:"command",command:$cmd,timeout:120}]} end)})'
}

install_documentation_hooks() {
  idh_client=$1
  command -v jq >/dev/null 2>&1 || die DEPENDENCY_MISSING 'Missing dependency: jq'
  idh_file=$(documentation_hooks_file "$idh_client")
  assert_safe_user_path "$idh_file" 'documentation hooks'
  [ ! -e "$idh_file" ] || [ -f "$idh_file" ] || die GOVERNANCE_NOT_READY 'Invalid documentation hook config'
  mkdir -p "$(dirname -- "$idh_file")"
  idh_managed=$(documentation_hooks_expected "$idh_client")
  idh_temp=$(mktemp "$(dirname -- "$idh_file")/.beroka-doc-hooks.XXXXXX") || die GOVERNANCE_NOT_READY
  if ! { if [ -f "$idh_file" ]; then cat "$idh_file"; else printf '{}\n'; fi; } |
    jq -s --arg client "$idh_client" --argjson managed "$idh_managed" '
      if length != 1 or (.[0]|type) != "object" then error("config") else .[0] end |
      if $client == "cursor" then .version = (.version // 1) else . end |
      .hooks = (.hooks // {}) |
      if (.hooks|type) != "object" then error("hooks") else . end |
      reduce $managed[] as $item (.;
        (.hooks[$item.event] // []) as $entries |
        if ($entries|type) != "array" then error("event") else . end |
        if any($entries[]; . == $item.entry) then .
        elif any($entries[]; tostring | contains(" confluence-hook " + $client + " "))
        then error("conflicting managed hook")
        else .hooks[$item.event] = $entries + [$item.entry] end)
    ' >"$idh_temp" 2>/dev/null
  then
    rm -f "$idh_temp"
    die GOVERNANCE_NOT_READY 'Invalid or conflicting documentation hooks; existing config was preserved'
  fi
  chmod 600 "$idh_temp"
  mv "$idh_temp" "$idh_file"
  printf '%s\n' 'Documentation hooks: INSTALLED' 'Restart the client with native tool hooks enabled; configuration alone is not execution proof.'
}

verify_documentation_hooks() {
  vdh_file=$(documentation_hooks_file "$1")
  assert_safe_user_path "$vdh_file" 'documentation hooks'
  [ -f "$vdh_file" ] && [ ! -L "$vdh_file" ] || return 1
  vdh_expected=$(documentation_hooks_expected "$1")
  jq -se --argjson expected "$vdh_expected" '
    length == 1 and (.[0].disableAllHooks != true) and (.[0] as $config |
      all($expected[]; . as $item |
        [$config.hooks[$item.event][]? | select(. == $item.entry)] | length == 1))
  ' "$vdh_file" >/dev/null 2>&1
}

remove_documentation_hooks() {
  for rdh_client in codex claude cursor; do
    rdh_file=$(documentation_hooks_file "$rdh_client")
    assert_safe_user_path "$rdh_file" 'documentation hooks'
    [ -f "$rdh_file" ] || continue
    rdh_expected=$(documentation_hooks_expected "$rdh_client")
    rdh_temp=$(mktemp "$(dirname -- "$rdh_file")/.beroka-doc-hooks.XXXXXX") || die GOVERNANCE_NOT_READY
    if ! jq -s --argjson expected "$rdh_expected" '
      if length != 1 or (.[0]|type) != "object" then error("config") else .[0] end |
      reduce $expected[] as $item (.;
        if .hooks[$item.event] == null then . else
          .hooks[$item.event] |= map(select(. != $item.entry)) end)
    ' "$rdh_file" >"$rdh_temp" 2>/dev/null; then
      rm -f "$rdh_temp"
      die GOVERNANCE_NOT_READY 'Cannot remove documentation hooks from invalid config'
    fi
    chmod 600 "$rdh_temp"
    mv "$rdh_temp" "$rdh_file"
  done
}

confluence_hook_message() {
  if [ "$dh_client" = cursor ]; then
    case "$dh_event" in
      pre) jq -nc --arg message "$1" '{permission:"allow",agent_message:$message}' ;;
      post) jq -nc --arg message "$1" '{additional_context:$message}' ;;
      stop) printf '{}\n' ;;
    esac
  else
    case "$dh_event" in
      pre) dh_native_event=PreToolUse ;;
      post) dh_native_event=PostToolUse ;;
      stop) printf '{}\n'; return ;;
    esac
    # Abstain on permission: governance must never override the client's approval.
    jq -nc --arg event "$dh_native_event" --arg message "$1" \
      '{hookSpecificOutput:{hookEventName:$event,additionalContext:$message}}'
  fi
}

confluence_hook_hash() { git --git-dir=/dev/null hash-object --stdin; }

# Only documented structured MCP result wrappers are decoded. Never search
# arbitrary nested objects for a plausible success ID.
confluence_hook_result() {
  printf '%s\n' "$dh_request" | jq -ce '
    def decode: if type == "string" then fromjson else . end;
    (.tool_response // .tool_output) | decode |
    if .isError == true or .error != null then error("tool failed") else . end |
    if .structuredContent != null then .structuredContent
    elif (.content|type) == "array" then
      [.content[] | select(.type == "text") | .text | fromjson] |
      if length == 1 then .[0] else error("ambiguous result") end
    else . end |
    if type != "object" or .isError == true or .error != null then error("result") else . end
  ' 2>/dev/null
}

confluence_hook_save() {
  dh_save_path=$1 dh_save_json=$2
  assert_safe_user_path "$dh_save_path" 'Confluence receipt'
  dh_save_temp=$(umask 077; mktemp "$dh_dir/.receipt.XXXXXX") || die GOVERNANCE_NOT_READY
  printf '%s\n' "$dh_save_json" >"$dh_save_temp"
  mv "$dh_save_temp" "$dh_save_path"
}

confluence_hook_run() {
  dh_request=$(cat)
  printf '%s\n' "$dh_request" | jq -se 'length == 1 and (.[0]|type == "object")' >/dev/null 2>&1 ||
    die CLIENT_BODY_GATE_REQUIRED 'Malformed native hook event'
  dh_tool=$(printf '%s\n' "$dh_request" | jq -r '.tool_name // ""')
  dh_action= dh_unsupported=0
  case "$dh_tool" in
    mcp__atlassian__*|mcp__codex_apps__atlassian_rovo_*|MCP:*)
      case "$dh_tool" in
        mcp__atlassian__*) dh_name=${dh_tool#mcp__atlassian__} ;;
        mcp__codex_apps__atlassian_rovo_*) dh_name=${dh_tool#mcp__codex_apps__atlassian_rovo_} ;;
        MCP:*) dh_name=${dh_tool#MCP:} ;;
      esac
      dh_name=$(printf '%s' "$dh_name" | tr '[:upper:]' '[:lower:]')
      case "$dh_name" in
        createconfluencepage) dh_action=create ;;
        updateconfluencepage) dh_action=update ;;
        getconfluencepage) dh_action=read ;;
        getconfluencespaces) dh_action=spaces ;;
        *confluence*)
          case "$dh_name" in *create*|*update*) dh_unsupported=1 ;; esac ;;
      esac ;;
  esac
  dh_lower_tool=$(printf '%s' "$dh_tool" | tr '[:upper:]' '[:lower:]')
  case "$dh_lower_tool" in
    *confluence*) case "$dh_lower_tool" in *create*|*update*) [ -n "$dh_action" ] || dh_unsupported=1 ;; esac ;;
  esac
  if [ -z "$dh_action" ] && [ "$dh_unsupported" -eq 0 ] && [ "$dh_event" != stop ]; then
    confluence_hook_message ''; return
  fi
  if [ "$dh_event" = stop ]; then
    # Native Stop retries must be allowed to report a blocked operation rather
    # than trapping the entire conversation in an endless continuation loop.
    if printf '%s\n' "$dh_request" | jq -e '.stop_hook_active == true or (.loop_count // 0) > 0' >/dev/null; then
      confluence_hook_message ''; return
    fi
    dh_stop_session=$(printf '%s\n' "$dh_request" | jq -r '.session_id // .conversation_id // ""')
    while IFS= read -r dh_stop_root; do
      dh_stop_repo=$(git -C "$dh_stop_root" rev-parse --show-toplevel 2>/dev/null) || continue
      dh_stop_key=$(printf '%s\n' "$dh_client" "$dh_stop_repo" "$dh_stop_session" | confluence_hook_hash)
      dh_stop_dir=$STATE_ROOT/confluence-hooks/$dh_stop_key/write
      assert_safe_user_path "$dh_stop_dir" 'Confluence receipt'
      [ ! -d "$dh_stop_dir" ] || die HANDOFF_READBACK_REQUIRED 'Confluence write remains unverified. Read the exact written page; do not retry creation or report READY_FOR_FE.'
    done <<CONFLUENCE_STOP_ROOTS
$(printf '%s\n' "$dh_request" | jq -r '[.cwd?, .workspace_roots[]?] | map(select(type == "string" and length > 0)) | unique[]')
CONFLUENCE_STOP_ROOTS
    confluence_hook_message ''; return
  fi
  load_active_release
  if [ "$dh_client" = cursor ]; then
    CURSOR_REQUEST=$dh_request
    cursor_parse_request_fields && cursor_resolve_workspaces ||
      die CLIENT_BODY_GATE_REQUIRED 'Native Cursor hooks require unambiguous workspace_roots'
    if [ "$CURSOR_WORKSPACE_MODE" = be-fe ]; then
      CURSOR_TOOL_INPUT=$(printf '%s\n' "$dh_request" | jq -c '.tool_input')
      cursor_select_be_fe_workspace || die ROUTING_REQUIRED 'Select an exact repository in the BE/FE workspace'
    fi
    dh_cwd=$CURSOR_WORKSPACE
  else
    dh_cwd=$(printf '%s\n' "$dh_request" | jq -er '.cwd | strings | select(length > 0)') ||
      die CLIENT_BODY_GATE_REQUIRED 'Native hooks must supply the exact working repository'
  fi
  resolve_repository_context "$dh_cwd" defer-role
  if ! repository_is_governed; then confluence_hook_message 'Result: NOT_GOVERNED'; return; fi
  [ "$dh_unsupported" -eq 0 ] || die CLIENT_BODY_GATE_REQUIRED 'Unsupported Confluence tool boundary; use the configured Atlassian createConfluencePage/updateConfluencePage native tool'
  dh_repo=$(git -C "$dh_cwd" rev-parse --show-toplevel)
  dh_session=$(printf '%s\n' "$dh_request" | jq -er '.session_id // .conversation_id | strings | select(length > 0)') || die CLIENT_BODY_GATE_REQUIRED
  dh_key=$(printf '%s\n' "$dh_client" "$dh_repo" "$dh_session" | confluence_hook_hash)
  dh_dir=$STATE_ROOT/confluence-hooks/$dh_key
  assert_safe_user_path "$dh_dir" 'Confluence hook state'
  (umask 077; mkdir -p "$dh_dir")
  dh_pending=$dh_dir/write/pending.json
  assert_safe_user_path "$dh_pending" 'Confluence receipt'
  dh_call=$(printf '%s\n' "$dh_request" | jq -er '.tool_use_id | strings | select(length > 0)') ||
    die CLIENT_BODY_GATE_REQUIRED 'This client host must provide native tool-use IDs; enable supported native hooks'
  dh_args=$(printf '%s\n' "$dh_request" | jq -ce '.tool_input | if type == "string" then fromjson else . end | select(type == "object")') || die CLIENT_BODY_GATE_REQUIRED
  dh_fingerprint=$(printf '%s\n' "$dh_args" | jq -Sc . | confluence_hook_hash)
  dh_cloud=$(printf '%s\n' "$dh_args" | jq -er '.cloudId | strings | select(length > 0)') || die ROUTING_REQUIRED 'Explicit cloudId is required'
  dh_cloud_key=$(printf '%s' "$dh_cloud" | confluence_hook_hash)
  dh_space_file=$dh_dir/space-$dh_cloud_key.json
  assert_safe_user_path "$dh_space_file" 'Confluence space receipt'

  dh_page_key=$(printf '%s\n' "$dh_cloud" "$(printf '%s\n' "$dh_args" | jq -r '.pageId // ""')" | confluence_hook_hash)
  dh_page_file=$dh_dir/page-$dh_page_key.json
  assert_safe_user_path "$dh_page_file" 'Confluence page metadata'

  if [ "$dh_event" = pre ]; then
    case "$dh_action" in
      spaces|read)
        # A read that began before the write cannot later prove its readback.
        if [ "$dh_action" = read ] && [ -f "$dh_pending" ] &&
          jq -e '.phase == "written"' "$dh_pending" >/dev/null
        then
          dh_read_key=$(printf '%s' "$dh_call" | confluence_hook_hash)
          confluence_hook_save "$dh_dir/read-$dh_read_key.json" \
            "$(jq -nc --arg tool "$dh_tool" --arg fingerprint "$dh_fingerprint" --argjson pending "$(cat "$dh_pending")" '{tool:$tool,fingerprint:$fingerprint,pending:$pending}')"
        fi
        confluence_hook_message ''; return ;;
    esac
    verify_documentation_hooks "$dh_client" || die CLIENT_BODY_GATE_REQUIRED \
      "Run beroka-governance setup-documentation-hooks --client $dh_client and restart with hooks enabled"
    [ ! -d "$dh_dir/write" ] || die HANDOFF_READBACK_REQUIRED 'Resolve the previous write and readback before another write'
    printf '%s\n' "$dh_args" | jq -e --arg action "$dh_action" '
      def id: type == "string" and test("^[1-9][0-9]*$");
      (if $action == "create" then (.parentId|id) and (.spaceId|id)
       else (if has("parentId") then (.parentId|id) else true end) and
            (if has("spaceId") then (.spaceId|id) else true end) end) and
      (.body|type == "string" and length > 0 and (contains("\u0000")|not)) and
      ((.contentFormat // "markdown") == "markdown") and
      ((.title // "")|type == "string") and
      ((keys - ["cloudId","spaceId","parentId","pageId","title","body","contentFormat","includeBody","status","versionMessage","isPrivate"])|length == 0)
    ' >/dev/null 2>&1 || die CLIENT_BODY_GATE_REQUIRED 'Use one Markdown body; create requires numeric spaceId/parentId and update permits their omission'
    dh_space=$(printf '%s\n' "$dh_args" | jq -r '.spaceId // ""')
    dh_parent=$(printf '%s\n' "$dh_args" | jq -r '.parentId // ""')
    if [ "$dh_action" = update ] && { [ -z "$dh_space" ] || [ -z "$dh_parent" ]; }; then
      [ -f "$dh_page_file" ] || die ROUTING_REQUIRED 'First read the exact page with getConfluencePage to observe its space and parent'
      [ -n "$dh_space" ] || dh_space=$(jq -r .space "$dh_page_file")
      [ -n "$dh_parent" ] || dh_parent=$(jq -r .parent "$dh_page_file")
    fi
    [ -f "$dh_space_file" ] && jq -e --arg space "$dh_space" --arg key "$ROUTE_CONFLUENCE_SPACE_KEY" \
      '.id == $space and .key == $key' "$dh_space_file" >/dev/null ||
      die ROUTING_REQUIRED 'First call getConfluenceSpaces for the routed space key in this cloud; the hook must observe its real result'
    dh_target=new
    if [ "$dh_action" = update ]; then
      dh_target=$(printf '%s\n' "$dh_args" | jq -er '.pageId | strings | select(test("^[1-9][0-9]*$"))') || die ROUTING_REQUIRED
    elif printf '%s\n' "$dh_args" | jq -e 'has("pageId")' >/dev/null; then
      die ROUTING_REQUIRED 'Create cannot supply an existing pageId'
    fi
    CURSOR_WORKSPACE=$dh_repo CURSOR_TOOL_TEXT=$dh_action
    # Validation-only parent from native read metadata; fingerprint/body still
    # bind the original outbound arguments, without synthesizing a tool request.
    CURSOR_TOOL_INPUT=$(printf '%s\n' "$dh_args" | jq -c --arg parent "$dh_parent" '.parentId=$parent')
    # Internal state only: initialized empty at process startup, never a CLI flag.
    CONFLUENCE_HOOK_CLIENT=$dh_client
    CURSOR_REQUEST=$dh_request
    if cursor_cross_team_private_link; then
      die CROSS_TEAM_LINK_SCOPE_DENIED 'Use accessible Confluence references instead of opposite-team repository links'
    fi
    set +e
    dh_validation=$(set -e; cursor_confluence_preflight "$dh_client" 2>&1)
    dh_validation_status=$?
    set -e
    if [ "$dh_validation_status" -ne 0 ]; then
      printf '%s\n' "$dh_validation" >&2
      return 1
    fi
    printf '%s\n' "$dh_validation" | grep -Fx 'Result: PASS' >/dev/null || die CLIENT_BODY_GATE_REQUIRED 'Native preflight did not pass'
    CONFLUENCE_HOOK_CLIENT=
    dh_body_hash=$(printf '%s\n' "$dh_args" | jq -j .body | confluence_hook_hash)
    dh_handoff_state=$(printf '%s\n' "$dh_args" | jq -r .body | awk '{sub(/\r$/, ""); if (sub(/^Handoff state: /, "")) print}')
    dh_declared_version=$(printf '%s\n' "$dh_args" | jq -r .body | awk '{sub(/\r$/, ""); if (sub(/^Confluence page version: /, "")) print}')
    if [ "$dh_handoff_state" = READY_FOR_FE ]; then
      printf '%s\n' "$dh_args" | jq -e '(.status // "current") == "current" and .isPrivate != true' >/dev/null ||
        die HANDOFF_BODY_INVALID 'READY_FOR_FE cannot use draft status or private publication'
    fi
    # ponytail: one outstanding write per client/repo/session; per-page queues if concurrent publication is needed.
    (umask 077; mkdir "$dh_dir/write") || die HANDOFF_READBACK_REQUIRED 'Another write is pending'
    confluence_hook_save "$dh_pending" "$(jq -nc --arg call "$dh_call" --arg fingerprint "$dh_fingerprint" \
      --arg body "$dh_body_hash" --arg cloud "$dh_cloud" --arg space "$dh_space" --arg parent "$dh_parent" \
      --arg tool "$dh_tool" --arg target "$dh_target" --arg state "$dh_handoff_state" --arg declaredVersion "$dh_declared_version" \
      '{phase:"prepared",tool:$tool,call:$call,fingerprint:$fingerprint,body:$body,cloud:$cloud,space:$space,parent:$parent,target:$target,state:$state,declaredVersion:$declaredVersion}')"
    confluence_hook_message 'WRITE_VALIDATED: After the tool returns, call getConfluencePage for the returned ID with contentFormat markdown. Do not report completion before READBACK_VERIFIED.'
    return
  fi

  # Only an explicit structured HTTP rejection proves there was no write.
  # Text errors and timeouts remain indeterminate and must not unlock retry.
  if { [ "$dh_action" = create ] || [ "$dh_action" = update ]; } &&
    [ -f "$dh_pending" ] && printf '%s\n' "$dh_request" | jq -e '
      (.tool_response // .tool_output) | if type == "string" then fromjson else . end |
      .isError == true
    ' >/dev/null 2>&1
  then
    dh_rejection=$(printf '%s\n' "$dh_request" | jq -r '
      (.tool_response // .tool_output) | if type == "string" then fromjson else . end |
      .statusCode // .structuredContent.statusCode // 0')
    case "$dh_rejection" in
      400|401|403|404|409|422)
        if jq -e --arg tool "$dh_tool" --arg call "$dh_call" --arg fingerprint "$dh_fingerprint" \
          '.phase == "prepared" and .tool == $tool and .call == $call and .fingerprint == $fingerprint' "$dh_pending" >/dev/null; then
          rm -f "$dh_pending"
          rmdir "$dh_dir/write"
          die CONFLUENCE_WRITE_REJECTED 'Server rejected the write. Correct the reported prerequisite before any new attempt; no completion is proven.'
        fi ;;
    esac
  fi
  dh_result=$(confluence_hook_result) || die CONFLUENCE_RESULT_UNVERIFIED 'Tool failed or returned an unsupported result. No write/readback success is proven; do not automatically retry creation.'
  if [ "$dh_action" = spaces ]; then
    dh_space_record=$(printf '%s\n' "$dh_result" | jq -ce --arg key "$ROUTE_CONFLUENCE_SPACE_KEY" '
      [.results[]? | select(.key == $key and (.id|type == "string" and test("^[1-9][0-9]*$"))) | {id,key}] |
      if length == 1 then .[0] else error("space") end') || die ROUTING_REQUIRED 'No exact routed space in native tool result'
    confluence_hook_save "$dh_space_file" "$dh_space_record"
    confluence_hook_message 'Confluence space identity observed'; return
  fi
  if [ "$dh_action" = read ]; then
    if dh_page_record=$(printf '%s\n' "$dh_result" | jq -ce --argjson args "$dh_args" '
      def id: type == "string" and test("^[1-9][0-9]*$");
      select(.id == $args.pageId and (.id|id)) |
      {space:(.spaceId // .space.id),parent:(.parentId // .ancestors[-1].id)} |
      select((.space|id) and (.parent|id))'); then
      confluence_hook_save "$dh_page_file" "$dh_page_record"
    else
      rm -f "$dh_page_file"
    fi
  fi
  if [ ! -f "$dh_pending" ]; then
    case "$dh_action" in create|update) die CLIENT_BODY_GATE_REQUIRED 'No matching native pre-tool receipt for the executed write' ;; esac
    confluence_hook_message ''; return
  fi
  if [ "$dh_action" = create ] || [ "$dh_action" = update ]; then
    jq -e --arg tool "$dh_tool" --arg call "$dh_call" --arg fingerprint "$dh_fingerprint" \
      '.phase == "prepared" and .tool == $tool and .call == $call and .fingerprint == $fingerprint' "$dh_pending" >/dev/null ||
      die CONFLUENCE_BODY_MISMATCH 'Actual executed arguments differ from the validated request or tool-call identity'
    dh_written=$(printf '%s\n' "$dh_result" | jq -ce --argjson expected "$(cat "$dh_pending")" '
      select((.id|type == "string" and test("^[1-9][0-9]*$")) and
        ($expected.target == "new" or .id == $expected.target) and
        ($expected.state != "READY_FOR_FE" or (.version.number|tostring) == $expected.declaredVersion) and
        (.version.number|type == "number" and . >= 1 and floor == .)) |
      $expected + {phase:"written",target:.id,version:.version.number}') ||
      die CREATION_STATUS_UNKNOWN 'Write did not return an exact content ID and version; reconcile without retrying creation'
    confluence_hook_save "$dh_pending" "$dh_written"
    confluence_hook_message "WRITE_RECORDED: Read getConfluencePage ID $(printf '%s\n' "$dh_written" | jq -r .target), same cloud, contentFormat markdown. Readback remains unverified."
    return
  fi
  dh_read_key=$(printf '%s' "$dh_call" | confluence_hook_hash)
  dh_read_file=$dh_dir/read-$dh_read_key.json
  assert_safe_user_path "$dh_read_file" 'Confluence read receipt'
  [ -f "$dh_read_file" ] && jq -e --arg tool "$dh_tool" --arg fingerprint "$dh_fingerprint" --argjson pending "$(cat "$dh_pending")" \
    '.tool == $tool and .fingerprint == $fingerprint and .pending == $pending' "$dh_read_file" >/dev/null ||
    die HANDOFF_READBACK_REQUIRED 'Read must start after the observed write and use the same native tool-call arguments'
  dh_read_body_json=$(printf '%s\n' "$dh_result" | jq -ce '
    if (.body|type) == "string" then .body
    elif (.body.markdown.value|type) == "string" then .body.markdown.value
    elif .body.representation == "markdown" and (.body.value|type) == "string" then .body.value
    else error("Markdown body required") end') || die HANDOFF_READBACK_REQUIRED 'Readback must include the full Markdown body'
  dh_read_body=$(printf '%s\n' "$dh_read_body_json" | jq -j . | confluence_hook_hash)
  printf '%s\n' "$dh_result" | jq -e --argjson pending "$(cat "$dh_pending")" --argjson args "$dh_args" \
    --arg hash "$dh_read_body" '
      .id == $pending.target and $args.pageId == $pending.target and
      $args.cloudId == $pending.cloud and (.parentId // .ancestors[-1].id) == $pending.parent and
      (.spaceId // .space.id) == $pending.space and .version.number == $pending.version and
      ($pending.state != "READY_FOR_FE" or .status == "current") and
      $hash == $pending.body
    ' >/dev/null || die HANDOFF_READBACK_REQUIRED 'Readback ID, parent, space, version or exact Markdown body does not match the observed write'
  dh_verified_state=$(jq -r .state "$dh_pending")
  rm -f "$dh_pending" "$dh_read_file"
  rmdir "$dh_dir/write"
  confluence_hook_message "READBACK_VERIFIED${dh_verified_state:+: $dh_verified_state}"
}

cmd_confluence_hook() {
  dh_client=$1 dh_event=$2
  case "$dh_client:$dh_event" in
    codex:pre|codex:post|codex:stop|claude:pre|claude:post|claude:stop|cursor:pre|cursor:post|cursor:stop) ;;
    *) die CLIENT_BODY_GATE_REQUIRED 'Unsupported native hook client/event' ;;
  esac
  # Native clients interpret exit 2 as blocking. Preserve set -e inside the
  # child (do not invoke the validator in an if/|| shell condition).
  set +e
  dh_output=$(set -e; confluence_hook_run 2>&1)
  dh_status=$?
  set -e
  if [ "$dh_status" -eq 0 ]; then printf '%s\n' "$dh_output"; return; fi
  if [ "$dh_client" = cursor ]; then
    case "$dh_event" in
      pre) jq -nc --arg message "$dh_output" '{permission:"deny",user_message:$message,agent_message:$message}' ;;
      post) jq -nc --arg message "$dh_output" '{additional_context:$message,updated_mcp_tool_output:{isError:true,content:[{type:"text",text:$message}]}}' ;;
      stop) jq -nc --arg message "$dh_output" '{followup_message:$message}' ;;
    esac
  else
    printf '%s\n' "$dh_output" >&2
    return 2
  fi
}
