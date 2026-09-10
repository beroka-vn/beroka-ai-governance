#!/bin/sh
set -eu

# Shared process state, errors, and path-safety helpers.

PROGRAM=beroka-governance
SOURCE_SLUG=beroka-vn/beroka-ai-governance
DATA_ROOT=${XDG_DATA_HOME:-$HOME/.local/share}/beroka-ai-governance
CONFIG_ROOT=${XDG_CONFIG_HOME:-$HOME/.config}/beroka-ai-governance
STATE_ROOT=${XDG_STATE_HOME:-$HOME/.local/state}/beroka-ai-governance
CURSOR_STATE_ROOT=$STATE_ROOT/cursor
CONFLUENCE_BOOTSTRAP_STATE_ROOT=$STATE_ROOT/confluence-bootstrap
BIN_DIR=${BEROKA_GOV_BIN_DIR:-$HOME/.local/bin}
REMOTE_URL=https://github.com/beroka-vn/beroka-ai-governance.git
ATLASSIAN_MCP_URL=https://mcp.atlassian.com/v1/mcp/authv2
START_MARKER='<!-- BEROKA-GOVERNANCE:START -->'
END_MARKER='<!-- BEROKA-GOVERNANCE:END -->'
INSTRUCTION_BOUNDARY_MARKER='<!-- BEROKA-GOVERNANCE:BOUNDARY -->'
ACTIVE_RELEASE=$CONFIG_ROOT/active-release
CLIENTS_FILE=$CONFIG_ROOT/clients
CURSOR_ACK_FILE=$CONFIG_ROOT/cursor-user-rule.sha256
GITHUB_ROLE_FILE=$CONFIG_ROOT/github-role
TX_DIR= TX_COMMITTED=0 TX_RELEASE_NEW=0 TX_RELEASE_TARGET=
TX_RELEASE_STAGE= TX_RELEASE_OWNED=0
TX_CLI_PATH= TX_CLI_SNAPSHOT=0 TX_ACTIVE_RELEASE_SNAPSHOT=0
ROUTING_STATE= REPOSITORY_SLUG= CATALOG_RECORD=
ROUTE_SCHEMA_VERSION= ROUTE_PROFILE= ROUTE_JIRA_PROJECT_KEY=
ROUTE_JIRA_BOARD_ID= ROUTE_CONFLUENCE_SPACE_KEY=
ROUTE_CONFLUENCE_ROOT_CONTENT_ID= ROUTE_CONFLUENCE_ROOT_CONTENT_TYPE=
ROUTE_INTEGRATION_PROFILE= ROUTE_CROSS_REPO_POLICY= DEPENDENCY_STATE=
INTAKE_TARGET_REPOSITORY= INTAKE_TARGET_PROFILE= INTAKE_TARGET_JIRA_PROJECT=
CONFLUENCE_TARGET_ACTION= CONFLUENCE_TARGET_CONTENT_ID=
CONFLUENCE_TARGET_CAPABILITY_ID= CONFLUENCE_TARGET_SCOPE=
CONFLUENCE_TARGET_DOMAIN= CONFLUENCE_TARGET_TRANSPORT=
CONFLUENCE_TARGET_PARENT_ID= CONFLUENCE_TARGET_REGISTRY_CONTENT_ID=
CONFLUENCE_HANDOFF_BODY_FILE=
CONFLUENCE_READBACK_PARENT_ID= CONFLUENCE_READBACK_SPACE_KEY=
CONFLUENCE_READBACK_TITLE= CONFLUENCE_READBACK_VERSION=
CONFLUENCE_READBACK_OWNER_ACCOUNT_ID=
GITHUB_ROLE=
GITHUB_FRONTEND_MEMBER=0 GITHUB_BACKEND_MEMBER=0
CONNECTOR_PROBE_CLIENT= CONNECTOR_PROBE_OUTPUT= CONNECTOR_PROBE_STATUS=
CONNECTOR_PROBE_STATE=
CONNECTOR_PROBE_TOOLS=
CONNECTOR_PROBE_TOOLS_OK=0
CAPABILITY_INVENTORY= CAPABILITY_INVENTORY_COMPLETE=0
CAPABILITY_INVENTORY_FORMAT= CAPABILITY_TOOLSET=UNAVAILABLE
CAPABILITY_STATE= PREFLIGHT_CAPABILITY=
SUPPRESS_PASS_RESULT=0
PERSONAL_STAGE_ROOT=
CONFLUENCE_BODY_TRUSTED=0
CONFLUENCE_HOOK_CLIENT=

cleanup_personal_stage() {
  CONFLUENCE_BODY_TRUSTED=0
  cleanup_stage_root=$PERSONAL_STAGE_ROOT
  PERSONAL_STAGE_ROOT=
  [ -z "$cleanup_stage_root" ] || rm -rf "$cleanup_stage_root"
}

die() {
  code=$1
  shift
  cleanup_personal_stage || :
  printf '%s\n' "Result: $code" >&2
  if [ "$#" -gt 0 ]; then printf '%s\n' "$*" >&2; fi
  exit 1
}

pass_result() {
  [ "$SUPPRESS_PASS_RESULT" -eq 1 ] ||
    printf '%s\n' 'Result: PASS'
}

assert_safe_user_path() {
  # ponytail: POSIX cannot lock path topology; use dirfd/openat if hostile concurrent local mutation enters scope.
  candidate=$1 label=$2
  case "$candidate" in
    /*) ;;
    *) die GOVERNANCE_NOT_READY "Unsafe $label path: $candidate" ;;
  esac

  physical_home=$(CDPATH= cd -- "$HOME" && pwd -P) || die GOVERNANCE_NOT_READY 'Cannot resolve HOME'
  tmp_root=${TMPDIR:-/tmp}
  physical_tmp=$(CDPATH= cd -- "$tmp_root" && pwd -P) || die GOVERNANCE_NOT_READY 'Cannot resolve TMPDIR'
  [ "$physical_home" != / ] || die GOVERNANCE_NOT_READY 'HOME cannot be the filesystem root'
  [ "$physical_tmp" != / ] || die GOVERNANCE_NOT_READY 'TMPDIR cannot be the filesystem root'
  case "$candidate" in
    "$HOME"/*) current=$HOME; rest=${candidate#"$HOME"/} ;;
    "$tmp_root"/*) current=$tmp_root; rest=${candidate#"$tmp_root"/} ;;
    "$HOME"|"$tmp_root") die GOVERNANCE_NOT_READY "Unsafe $label path: $candidate" ;;
    *) current=; rest=${candidate#/} ;;
  esac
  while [ -n "$rest" ]; do
    component=${rest%%/*}
    if [ "$component" = "$rest" ]; then rest=; else rest=${rest#*/}; fi
    case "$component" in
      ''|.|..) die GOVERNANCE_NOT_READY "Unsafe $label path: $candidate" ;;
    esac
    current=${current:-}/$component
    [ ! -L "$current" ] || die GOVERNANCE_NOT_READY "Symlinked $label path: $current"
    if [ -n "$rest" ] && [ -e "$current" ] && [ ! -d "$current" ]; then
      die GOVERNANCE_NOT_READY "Non-directory $label path component: $current"
    fi
  done

  ancestor=$candidate
  while [ ! -e "$ancestor" ]; do ancestor=$(dirname -- "$ancestor"); done
  if [ -d "$ancestor" ]; then
    physical_ancestor=$(CDPATH= cd -- "$ancestor" && pwd -P) || die GOVERNANCE_NOT_READY "Cannot resolve $label path"
  else
    ancestor_parent=$(dirname -- "$ancestor")
    physical_ancestor=$(CDPATH= cd -- "$ancestor_parent" && pwd -P) || die GOVERNANCE_NOT_READY "Cannot resolve $label path parent"
  fi
  # Explicit Codex configuration may live outside HOME/TMPDIR. The component
  # walk above still rejects traversal and symlinks; allow only managed files.
  case "${CODEX_HOME:-}" in
    /*)
      [ "$CODEX_HOME" != / ] || die GOVERNANCE_NOT_READY 'CODEX_HOME cannot be the filesystem root'
      case "$candidate" in
        "$CODEX_HOME/hooks.json"|"$CODEX_HOME/AGENTS.md"|"$CODEX_HOME/AGENTS.override.md") return 0 ;;
      esac ;;
  esac
  case "$physical_ancestor" in
    "$physical_home"|"$physical_home"/*|"$physical_tmp"|"$physical_tmp"/*) ;;
    *) die GOVERNANCE_NOT_READY "$label path is outside HOME and TMPDIR: $candidate" ;;
  esac
}
