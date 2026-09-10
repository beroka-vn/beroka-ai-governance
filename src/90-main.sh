# Public usage and the single top-level command dispatcher.

usage() {
  printf '%s\n' \
    'Usage:' \
    '  beroka-governance bootstrap [REPO] --client codex|claude|cursor [--version vX.Y.Z] [--upgrade] [--ready] [--non-interactive]' \
    '  beroka-governance install VERSION' \
    '  beroka-governance uninstall [--force]' \
    '  beroka-governance setup-connectors [--client codex|claude|cursor] [--non-interactive]' \
    '  beroka-governance setup-documentation-hooks --client codex|claude|cursor' \
    '  beroka-governance confluence-hook codex|claude|cursor pre|post|stop' \
    '  beroka-governance doctor REPO [--client codex|claude|cursor]' \
    '  beroka-governance preflight REPO --client codex|claude|cursor --operation OPERATION [--non-interactive] [CONFLUENCE-TARGET-OPTIONS]' \
    '  Handoff operations: confluence-handoff-write | confluence-handoff-verify | jira-handoff-write' \
    '  Confluence target options: --confluence-action create|update|move --target-content-id ID|new --capability-id ID --scope SCOPE --domain DOMAIN --transport API|WebSocket|API+WebSocket --expected-parent-id ID --registry-content-id ID' \
    '  Cross-team body option: --handoff-body-file PATH' \
    '  Legacy caller readback assertion options are rejected with HANDOFF_READBACK_REQUIRED' \
    '  beroka-governance context REPO' \
    '  beroka-governance confluence-discover REPO [--scope SCOPE --domain DOMAIN --transport API|WebSocket|API+WebSocket]' \
    '  beroka-governance confluence-bootstrap-plan REPO --scope SCOPE --domain DOMAIN --transport API|WebSocket|API+WebSocket' \
    '  beroka-governance confluence-bootstrap-capture REPO --folder-id ID --registry-id ID --scope SCOPE --domain DOMAIN --transport API|WebSocket|API+WebSocket' \
    '  beroka-governance confluence-bootstrap-verify REPO --folder-id ID --registry-id ID --folder-parent-id ID --registry-parent-id ID [--folder-title TITLE] [--registry-title TITLE]' \
    '  beroka-governance cursor-hook sessionStart|beforeSubmitPrompt|preCompact|beforeMCPExecution|beforeShellExecution' \
    '  beroka-governance show REPO governance|handbook|workflow' \
    '  beroka-governance show REPO template ai-agent-assignment|github-issue|jira-confluence|pull-request' \
    'Retired commands: register, update, rollback, unregister'
}

retired_command() {
  die COMMAND_RETIRED \
    'Repository routing is managed in the Central catalog; bootstrap and upgrade never modify application repositories'
}

main() {
  command=${1:-}
  case "$command" in
    bootstrap) shift; cmd_bootstrap "$@" ;;
    install) [ "$#" -eq 2 ] || { usage >&2; exit 2; }; cmd_install "$2" ;;
    register|update|rollback|unregister) retired_command "$command" ;;
    uninstall) [ "$#" -le 2 ] || { usage >&2; exit 2; }; cmd_uninstall "${2:-}" ;;
    setup-connectors) shift; cmd_setup_connectors "$@" ;;
    setup-documentation-hooks)
      [ "$#" -eq 3 ] && [ "$2" = --client ] || { usage >&2; exit 2; }
      install_documentation_hooks "$3"
      ;;
    confluence-hook)
      [ "$#" -eq 3 ] || { usage >&2; exit 2; }
      cmd_confluence_hook "$2" "$3"
      ;;
    doctor)
      { [ "$#" -eq 2 ] || [ "$#" -eq 4 ]; } || { usage >&2; exit 2; }
      cmd_doctor "$2" "${3:-}" "${4:-}"
      ;;
    preflight)
      [ "$#" -ge 6 ] || { usage >&2; exit 2; }
      shift
      pf_repo=$1
      shift
      cmd_preflight "$pf_repo" "$@"
      ;;
    context) [ "$#" -eq 2 ] || { usage >&2; exit 2; }; cmd_context "$2" ;;
    confluence-discover)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      shift
      cmd_confluence_discover "$@"
      ;;
    confluence-bootstrap-plan)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      shift
      cmd_confluence_bootstrap_plan "$@"
      ;;
    confluence-bootstrap-capture)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      shift
      cmd_confluence_bootstrap_capture "$@"
      ;;
    confluence-bootstrap-verify)
      [ "$#" -ge 2 ] || { usage >&2; exit 2; }
      shift
      cmd_confluence_bootstrap_verify "$@"
      ;;
    cursor-hook) [ "$#" -eq 2 ] || { usage >&2; exit 2; }; cmd_cursor_hook "$2" ;;
    show) [ "$#" -ge 3 ] && [ "$#" -le 4 ] || { usage >&2; exit 2; }; cmd_show "$2" "$3" "${4:-}" ;;
    *) usage >&2; exit 2 ;;
  esac
}

main "$@"
