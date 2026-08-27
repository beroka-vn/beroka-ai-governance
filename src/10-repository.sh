# Repository identity, catalog routing, and role scope.

canonical_repo() {
  requested=$1
  root=$(git -C "$requested" rev-parse --show-toplevel 2>/dev/null) ||
    die REPOSITORY_INVALID "Not a Git repository: $requested"
  (CDPATH= cd -- "$root" && pwd -P) ||
    die REPOSITORY_INVALID "Cannot resolve Git repository: $requested"
}

normalize_github_url() {
  ngu_url=$1
  case "$ngu_url" in
    https://github.com/*) ngu_slug=${ngu_url#https://github.com/} ;;
    git@github.com:*) ngu_slug=${ngu_url#git@github.com:} ;;
    ssh://git@github.com/*) ngu_slug=${ngu_url#ssh://git@github.com/} ;;
    git@*:*|ssh://git@*/*)
      case "$ngu_url" in
        git@*)
          ngu_host=${ngu_url#git@}
          ngu_host=${ngu_host%%:*}
          ngu_slug=${ngu_url#*:}
          ;;
        ssh://git@*)
          ngu_host=${ngu_url#ssh://git@}
          ngu_host=${ngu_host%%/*}
          ngu_slug=${ngu_url#ssh://git@*/}
          ;;
      esac
      ssh -G "$ngu_host" 2>/dev/null |
        awk '$1 == "hostname" && $2 == "github.com" { found++ } END { exit found != 1 }' ||
        return 1
      ;;
    *) return 1 ;;
  esac
  while [ "${ngu_slug%/}" != "$ngu_slug" ]; do ngu_slug=${ngu_slug%/}; done
  ngu_slug=${ngu_slug%.git}
  printf '%s\n' "$ngu_slug" |
    grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' || return 1
  printf '%s\n' "$ngu_slug"
}

resolve_canonical_remote() {
  rcr_repo=$1 rcr_expected=${2:-}
  CANONICAL_REMOTE_NAME= CANONICAL_REMOTE_URL=
  rcr_matches=0
  if [ -n "$rcr_expected" ]; then
    for rcr_name in $(git -C "$rcr_repo" remote); do
      rcr_url=$(git -C "$rcr_repo" config --get "remote.$rcr_name.url" 2>/dev/null) ||
        continue
      rcr_slug=$(normalize_github_url "$rcr_url") || continue
      [ "$rcr_slug" = "$rcr_expected" ] || continue
      rcr_matches=$((rcr_matches + 1))
      CANONICAL_REMOTE_NAME=$rcr_name
      CANONICAL_REMOTE_URL=$rcr_url
    done
    [ "$rcr_matches" -eq 1 ] ||
      die REMOTE_MISMATCH "Cannot resolve expected remote $rcr_expected"
    return
  fi

  # Prefer an exact Central catalog remote even when origin is a fork
  # (for example origin=hungnx77/... and beroka=beroka-vn/Beroka_Backend).
  # Multiple remotes that normalize to the same catalog slug are fine; prefer
  # origin among them. Distinct catalog slugs stay fail-closed. Unknown remotes
  # stay standalone; never invent BE/FE routing.
  if [ -n "${RELEASE_DIR:-}" ]; then
    rcr_seen_slugs=
    rcr_unique_slugs=0
    rcr_pick_name= rcr_pick_url=
    rcr_origin_name= rcr_origin_url=
    for rcr_name in $(git -C "$rcr_repo" remote); do
      rcr_url=$(git -C "$rcr_repo" config --get "remote.$rcr_name.url" 2>/dev/null) ||
        continue
      rcr_slug=$(normalize_github_url "$rcr_url") || continue
      catalog_record_for_slug "$rcr_slug" || continue
      [ -f "$CATALOG_RECORD" ] || continue
      case "$rcr_seen_slugs" in
        *"|$rcr_slug|"*) ;;
        *)
          rcr_seen_slugs="$rcr_seen_slugs|$rcr_slug|"
          rcr_unique_slugs=$((rcr_unique_slugs + 1))
          ;;
      esac
      if [ "$rcr_name" = origin ]; then
        rcr_origin_name=$rcr_name
        rcr_origin_url=$rcr_url
      elif [ -z "$rcr_pick_name" ]; then
        rcr_pick_name=$rcr_name
        rcr_pick_url=$rcr_url
      fi
    done
    if [ "$rcr_unique_slugs" -eq 1 ]; then
      if [ -n "$rcr_origin_name" ]; then
        CANONICAL_REMOTE_NAME=$rcr_origin_name
        CANONICAL_REMOTE_URL=$rcr_origin_url
      else
        CANONICAL_REMOTE_NAME=$rcr_pick_name
        CANONICAL_REMOTE_URL=$rcr_pick_url
      fi
      return
    fi
    if [ "$rcr_unique_slugs" -gt 1 ]; then
      die REMOTE_MISMATCH \
        'Multiple distinct catalog remotes found; keep remotes for exactly one beroka-vn catalog repository'
    fi
  fi

  for rcr_name in $(git -C "$rcr_repo" remote); do
    rcr_url=$(git -C "$rcr_repo" config --get "remote.$rcr_name.url" 2>/dev/null) ||
      continue
    rcr_slug=$(normalize_github_url "$rcr_url") || continue
    [ "$rcr_name" = origin ] || continue
    rcr_matches=$((rcr_matches + 1))
    CANONICAL_REMOTE_NAME=$rcr_name
    CANONICAL_REMOTE_URL=$rcr_url
  done
  if [ "$rcr_matches" -eq 0 ]; then
    for rcr_name in $(git -C "$rcr_repo" remote); do
      rcr_url=$(git -C "$rcr_repo" config --get "remote.$rcr_name.url" 2>/dev/null) ||
        continue
      normalize_github_url "$rcr_url" >/dev/null 2>&1 || continue
      rcr_matches=$((rcr_matches + 1))
      CANONICAL_REMOTE_NAME=$rcr_name
      CANONICAL_REMOTE_URL=$rcr_url
    done
  fi
  [ "$rcr_matches" -eq 1 ] ||
    die REMOTE_MISMATCH 'Cannot resolve exactly one canonical GitHub remote'
}

catalog_record_for_slug() {
  crs_slug=$1
  printf '%s\n' "$crs_slug" |
    grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' || return 1
  CATALOG_RECORD=$RELEASE_DIR/runtime/repositories/$crs_slug.conf
  case "$CATALOG_RECORD" in
    "$RELEASE_DIR/runtime/repositories/"*) ;;
    *) return 1 ;;
  esac
}

resolve_repository_context() {
  rrc_role=${2:-require-role}
  REPO=$(canonical_repo "$1")
  resolve_canonical_remote "$REPO"
  REPOSITORY_SLUG=$(normalize_github_url "$CANONICAL_REMOTE_URL") ||
    die REMOTE_MISMATCH 'Canonical remote is not GitHub'
  catalog_record_for_slug "$REPOSITORY_SLUG" ||
    die REMOTE_MISMATCH 'Invalid canonical repository slug'
  if [ -f "$CATALOG_RECORD" ]; then
    parse_routing "$CATALOG_RECORD" "$REPOSITORY_SLUG" ||
      die ROUTING_INVALID
    ROUTING_STATE=ROUTING_ACTIVE
  else
    clear_routing_values
    ROUTING_STATE=NOT_GOVERNED
    return 0
  fi
  [ "$rrc_role" = defer-role ] || require_role_scope
}

repository_is_governed() {
  [ "$ROUTING_STATE" = ROUTING_ACTIVE ]
}

print_not_governed() {
  printf '%s\n' \
    'Result: NOT_GOVERNED' \
    "Repository: $REPOSITORY_SLUG"
}

clear_routing_values() {
  ROUTE_SCHEMA_VERSION= ROUTE_PROFILE= ROUTE_JIRA_PROJECT_KEY=
  ROUTE_JIRA_BOARD_ID= ROUTE_CONFLUENCE_SPACE_KEY=
  ROUTE_CONFLUENCE_ROOT_CONTENT_ID=
  ROUTE_CONFLUENCE_ROOT_CONTENT_TYPE=
  ROUTE_INTEGRATION_PROFILE= ROUTE_CROSS_REPO_POLICY=
  DEPENDENCY_STATE=
}

parse_routing() {
  pr_file=$1 pr_slug=$2
  printf '%s\n' "$pr_slug" |
    grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' || return 1
  clear_routing_values
  [ ! -L "$pr_file" ] && [ -f "$pr_file" ] || return 1
  pr_parsed=$(
    awk -F= '
      /^[[:space:]]*$/ { next }
      index($0, "=") == 0 { exit 42 }
      {
        key=$1
        value=substr($0, length(key) + 2)
        if (key !~ /^[A-Z][A-Z0-9_]*$/ || value == "" || seen[key]++) exit 42
        if (key != "SCHEMA_VERSION" &&
            key != "PROFILE" &&
            key != "JIRA_PROJECT_KEY" &&
            key != "JIRA_BOARD_ID" &&
            key != "CONFLUENCE_SPACE_KEY" &&
            key != "CONFLUENCE_ROOT_CONTENT_ID" &&
            key != "CONFLUENCE_ROOT_CONTENT_TYPE" &&
            key != "INTEGRATION_PROFILE" &&
            key != "CROSS_REPO_POLICY") exit 42
        print key "\t" value
      }
    ' "$pr_file"
  ) || return 1
  while IFS="$(printf '\t')" read -r pr_key pr_value; do
    case "$pr_key" in
      SCHEMA_VERSION) ROUTE_SCHEMA_VERSION=$pr_value ;;
      PROFILE) ROUTE_PROFILE=$pr_value ;;
      JIRA_PROJECT_KEY) ROUTE_JIRA_PROJECT_KEY=$pr_value ;;
      JIRA_BOARD_ID) ROUTE_JIRA_BOARD_ID=$pr_value ;;
      CONFLUENCE_SPACE_KEY) ROUTE_CONFLUENCE_SPACE_KEY=$pr_value ;;
      CONFLUENCE_ROOT_CONTENT_ID) ROUTE_CONFLUENCE_ROOT_CONTENT_ID=$pr_value ;;
      CONFLUENCE_ROOT_CONTENT_TYPE) ROUTE_CONFLUENCE_ROOT_CONTENT_TYPE=$pr_value ;;
      INTEGRATION_PROFILE) ROUTE_INTEGRATION_PROFILE=$pr_value ;;
      CROSS_REPO_POLICY) ROUTE_CROSS_REPO_POLICY=$pr_value ;;
    esac
  done <<EOF
$pr_parsed
EOF

  [ "$ROUTE_SCHEMA_VERSION" = 1 ] || return 1
  case "$ROUTE_PROFILE" in standalone|backend|frontend) ;; *) return 1 ;; esac
  case "$ROUTE_INTEGRATION_PROFILE" in none|beroka-be-fe) ;; *) return 1 ;; esac
  case "$ROUTE_CROSS_REPO_POLICY" in explicit-only|profile-controlled) ;; *) return 1 ;; esac
  [ -z "$ROUTE_JIRA_PROJECT_KEY" ] ||
    printf '%s\n' "$ROUTE_JIRA_PROJECT_KEY" |
      grep -Eq '^[A-Z][A-Z0-9_]*$' || return 1
  [ -z "$ROUTE_JIRA_BOARD_ID" ] ||
    printf '%s\n' "$ROUTE_JIRA_BOARD_ID" |
      grep -Eq '^[1-9][0-9]*$' || return 1
  [ -z "$ROUTE_CONFLUENCE_SPACE_KEY" ] ||
    printf '%s\n' "$ROUTE_CONFLUENCE_SPACE_KEY" |
      grep -Eq '^[A-Za-z0-9._~-]+$' || return 1
  [ -z "$ROUTE_CONFLUENCE_ROOT_CONTENT_ID" ] ||
    printf '%s\n' "$ROUTE_CONFLUENCE_ROOT_CONTENT_ID" |
      grep -Eq '^[1-9][0-9]*$' || return 1
  case "$ROUTE_CONFLUENCE_ROOT_CONTENT_TYPE" in ''|page|folder) ;; *) return 1 ;; esac

  [ "$ROUTE_INTEGRATION_PROFILE" != none ] ||
    [ "$ROUTE_CROSS_REPO_POLICY" = explicit-only ] || return 1
  [ "$ROUTE_PROFILE" != standalone ] ||
    [ "$ROUTE_INTEGRATION_PROFILE:$ROUTE_CROSS_REPO_POLICY" = none:explicit-only ] ||
    return 1
  [ "$ROUTE_INTEGRATION_PROFILE" != beroka-be-fe ] ||
    [ "$ROUTE_PROFILE" = backend ] || [ "$ROUTE_PROFILE" = frontend ] ||
    return 1
  if [ "$ROUTE_INTEGRATION_PROFILE" = beroka-be-fe ]; then
    awk -F '\t' \
      -v repository="$pr_slug" \
      -v profile="$ROUTE_PROFILE" '
        $0 !~ /^#/ && $1 == repository && $2 == profile { found=1 }
        END { exit !found }
      ' "$RELEASE_DIR/runtime/integrations/beroka-be-fe.repositories" ||
      return 1
  fi

  if [ "$ROUTE_INTEGRATION_PROFILE" = none ]; then
    DEPENDENCY_STATE=NO_DEPENDENCY_DECLARED
  else
    DEPENDENCY_STATE=MAPPING_VERIFICATION_REQUIRED
  fi
}

read_github_role() {
  GITHUB_ROLE=
  assert_client_files
  [ -f "$GITHUB_ROLE_FILE" ] && [ ! -L "$GITHUB_ROLE_FILE" ] ||
    return 1
  GITHUB_ROLE=$(
    awk '
      NR == 1 { value=$0 }
      NR > 1 { invalid=1 }
      END {
        if (NR != 1 || invalid) exit 1
        print value
      }
    ' "$GITHUB_ROLE_FILE"
  ) || return 1
  case "$GITHUB_ROLE" in
    FE|BE|FULL_STACK) return 0 ;;
    *) return 1 ;;
  esac
}

load_github_role() {
  read_github_role ||
    die GITHUB_ROLE_REQUIRED \
      'Remediation: rerun beroka-governance bootstrap with an enrolled client'
}

require_role_scope() {
  case "$ROUTE_PROFILE" in
    backend)
      load_github_role
      case "$GITHUB_ROLE" in
        BE|FULL_STACK) ;;
        *) die ROLE_SCOPE_DENIED 'GitHub role cannot govern Backend routing' ;;
      esac
      ;;
    frontend)
      load_github_role
      case "$GITHUB_ROLE" in
        FE|FULL_STACK) ;;
        *) die ROLE_SCOPE_DENIED 'GitHub role cannot govern Frontend routing' ;;
      esac
      ;;
  esac
}

legacy_repository_state() {
  lrs_repo=$1
  for lrs_path in \
    .beroka-governance.lock \
    AGENTS.md CLAUDE.md \
    .cursor/rules/beroka-governance.mdc
  do
    [ -e "$lrs_repo/$lrs_path" ] || [ -L "$lrs_repo/$lrs_path" ] ||
      continue
    printf '%s\n' PRESENT_IGNORED
    return
  done
  printf '%s\n' ABSENT
}
