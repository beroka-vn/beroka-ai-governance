# Verified release lifecycle, user-state transactions, and client enrollment.

assert_install_paths() {
  assert_safe_user_path "$DATA_ROOT" data
  assert_safe_user_path "$DATA_ROOT/releases" release
  assert_safe_user_path "$BIN_DIR" bin
  assert_safe_user_path "$BIN_DIR/$PROGRAM" CLI
  [ ! -e "$DATA_ROOT" ] || [ -d "$DATA_ROOT" ] || die GOVERNANCE_NOT_READY "Data root is not a directory: $DATA_ROOT"
  [ ! -e "$BIN_DIR" ] || [ -d "$BIN_DIR" ] || die GOVERNANCE_NOT_READY "Bin path is not a directory: $BIN_DIR"
  [ ! -e "$BIN_DIR/$PROGRAM" ] || [ -f "$BIN_DIR/$PROGRAM" ] || die GOVERNANCE_NOT_READY "CLI is not a regular file: $BIN_DIR/$PROGRAM"
}

assert_valid_template() {
  template=$1
  awk -v start="$START_MARKER" -v end="$END_MARKER" '
    $0 == start { if (started || ended) invalid=1; started=1; next }
    $0 == end { if (!started || ended) invalid=1; ended=1 }
    END { exit (invalid || !started || !ended) }
  ' "$template" >/dev/null || die ENTRYPOINT_DRIFT "Invalid managed block in $template"
}

strip_managed_block() {
  input=$1 output=$2 managed=${3:-}
  smb_range=$(LC_ALL=C awk \
    -v start="$START_MARKER" -v end="$END_MARKER" \
    -v boundary="$INSTRUCTION_BOUNDARY_MARKER" '
    index($0, boundary) {
      boundary_index=index($0, boundary)
      if (boundary_seen ||
          boundary_index == 1 ||
          boundary_index + length(boundary) - 1 != length($0)) {
        invalid=1
      }
      boundary_seen=1
      boundary_line=NR
      boundary_prefix=boundary_index - 1
    }
    $0 == start {
      if (inside || found) invalid=1
      inside=1
      found=1
      first=NR
      next
    }
    $0 == end {
      if (!inside) invalid=1
      inside=0
      last=NR
      next
    }
    END {
      if (boundary_seen && boundary_line != first - 1) invalid=1
      if (invalid || inside) exit 42
      print first + 0, last + 0, boundary_line + 0, boundary_prefix + 0
    }
  ' "$input") || return 1
  smb_start=${smb_range%% *}
  smb_rest=${smb_range#* }
  smb_end=${smb_rest%% *}
  smb_rest=${smb_rest#* }
  smb_boundary_line=${smb_rest%% *}
  smb_boundary_prefix=${smb_rest#* }

  if BEROKA_BOUNDARY=$INSTRUCTION_BOUNDARY_MARKER \
     BEROKA_START=$START_MARKER /usr/bin/perl -0777 -e '
      $data = <>;
      $index = index($data, $ENV{BEROKA_BOUNDARY});
      exit 1 if $index < 0;
      exit 42 if index($data, $ENV{BEROKA_BOUNDARY}, $index + 1) >= 0;
      $suffix = $ENV{BEROKA_BOUNDARY} . "\n" . $ENV{BEROKA_START} . "\n";
      exit 42 unless substr($data, $index, length($suffix)) eq $suffix;
    ' "$input"
  then
    smb_boundary_line=1
  else
    smb_boundary_status=$?
    [ "$smb_boundary_status" -eq 1 ] || return 1
  fi

  if [ "$smb_start" -eq 0 ]; then
    cp "$input" "$output" || return 1
    [ -z "$managed" ] || : >"$managed"
    return 0
  fi

  if [ -n "$managed" ]; then
    head -n "$smb_end" "$input" |
      tail -n +"$smb_start" >"$managed" || return 1
  fi
  : >"$output" || return 1
  if [ "$smb_boundary_line" -gt 0 ]; then
    BEROKA_BOUNDARY=$INSTRUCTION_BOUNDARY_MARKER /usr/bin/perl -0777 -e '
      $data = <>;
      $index = index($data, $ENV{BEROKA_BOUNDARY});
      exit 42 if $index < 0;
      print substr($data, 0, $index);
    ' "$input" >"$output" || return 1
  elif [ "$smb_start" -gt 1 ]; then
    head -n "$((smb_start - 1))" "$input" >"$output" || return 1
  fi
  tail -n +"$((smb_end + 1))" "$input" >>"$output" || return 1
}

tx_begin() {
  TX_DIR=$(mktemp -d "${TMPDIR:-/tmp}/beroka-governance-tx.XXXXXX") || die GOVERNANCE_NOT_READY 'Cannot create transaction directory'
  TX_COMMITTED=0 TX_RELEASE_NEW=0 TX_RELEASE_TARGET= TX_RELEASE_STAGE= TX_RELEASE_OWNED=0
  TX_CLI_PATH= TX_CLI_SNAPSHOT=0 TX_ACTIVE_RELEASE_SNAPSHOT=0
  trap 'tx_abort' EXIT
  trap 'tx_abort; exit 1' HUP INT TERM
  mkdir -p "$TX_DIR/backup" "$TX_DIR/work" ||
    die GOVERNANCE_NOT_READY 'Cannot initialize transaction directory'
}

tx_abort() {
  [ -n "$TX_DIR" ] || return 0
  set +e
  if [ "$TX_COMMITTED" -eq 0 ]; then
    if [ "$TX_ACTIVE_RELEASE_SNAPSHOT" -eq 1 ]; then tx_restore_user_file "$ACTIVE_RELEASE" active-release; fi
    if [ "$TX_CLI_SNAPSHOT" -eq 1 ]; then tx_restore_user_file "$TX_CLI_PATH" cli; fi
    if [ "$TX_RELEASE_OWNED" -eq 1 ] && [ -n "$TX_RELEASE_TARGET" ]; then rm -rf "$TX_RELEASE_TARGET"; fi
  fi
  if [ -n "$TX_RELEASE_STAGE" ]; then rm -rf "$TX_RELEASE_STAGE"; fi
  rm -rf "$TX_DIR"
  TX_DIR=
}

tx_commit() {
  TX_COMMITTED=1
  rm -rf "$TX_DIR" || die GOVERNANCE_NOT_READY 'Cannot finalize transaction'
  TX_DIR=
  trap - EXIT HUP INT TERM
}

tx_snapshot_user_file() {
  tsu_path=$1 tsu_name=$2
  if [ -e "$tsu_path" ]; then
    [ ! -L "$tsu_path" ] && [ -f "$tsu_path" ] || die GOVERNANCE_NOT_READY "Unsafe user file: $tsu_path"
    cp -p "$tsu_path" "$TX_DIR/backup/$tsu_name" || die GOVERNANCE_NOT_READY "Cannot snapshot user file: $tsu_path"
    printf 'E\n' >"$TX_DIR/backup/$tsu_name.state" || die GOVERNANCE_NOT_READY 'Cannot record user-file snapshot'
  else
    printf 'M\n' >"$TX_DIR/backup/$tsu_name.state" || die GOVERNANCE_NOT_READY 'Cannot record user-file snapshot'
  fi
}

tx_restore_user_file() {
  tru_path=$1 tru_name=$2
  [ -f "$TX_DIR/backup/$tru_name.state" ] || return 0
  tru_state=$(sed -n '1p' "$TX_DIR/backup/$tru_name.state")
  case "$tru_state" in
    E) mkdir -p "$(dirname -- "$tru_path")" && cp -p "$TX_DIR/backup/$tru_name" "$tru_path" ;;
    M) rm -f "$tru_path" ;;
  esac
}

apply_user_file() {
  auf_source=$1 auf_destination=$2 auf_label=$3
  auf_parent=$(dirname -- "$auf_destination")
  mkdir -p "$auf_parent" || die GOVERNANCE_NOT_READY "Cannot create $auf_label directory"
  auf_temp=$(mktemp "$auf_parent/.beroka-$auf_label.XXXXXX") || die GOVERNANCE_NOT_READY "Cannot create temporary $auf_label"
  if ! cp -p "$auf_source" "$auf_temp"; then
    rm -f "$auf_temp" || :
    die GOVERNANCE_NOT_READY "Cannot prepare $auf_label"
  fi
  if ! mv "$auf_temp" "$auf_destination"; then
    rm -f "$auf_temp" || :
    die GOVERNANCE_NOT_READY "Cannot replace $auf_label"
  fi
}

write_active_release() {
  war_file=$1 war_version=$2 war_commit=$3
  printf '%s\n' \
    "VERSION=$war_version" \
    "COMMIT=$war_commit" >"$war_file" ||
    die GOVERNANCE_NOT_READY 'Cannot stage active release'
}

load_active_release() {
  assert_safe_user_path "$ACTIVE_RELEASE" 'active release'
  [ -f "$ACTIVE_RELEASE" ] ||
    die GOVERNANCE_NOT_READY 'No active governance release is installed'
  ar_values=$(awk -F= '
    $1 == "VERSION" && $2 ~ /^v[0-9]+\.[0-9]+\.[0-9]+$/ && !version++ {
      value=$2
    }
    $1 == "COMMIT" && $2 ~ /^[0-9a-f]{40}$/ && !commit++ {
      hash=$2
    }
    END {
      if (NR != 2 || version != 1 || commit != 1) exit 1
      print value "\t" hash
    }
  ' "$ACTIVE_RELEASE") ||
    die VERSION_MISMATCH 'Invalid active release record'
  ACTIVE_VERSION=${ar_values%%	*}
  ACTIVE_COMMIT=${ar_values#*	}
  release_for_version "$ACTIVE_VERSION"
  [ "$RELEASE_COMMIT" = "$ACTIVE_COMMIT" ] ||
    die VERSION_MISMATCH 'Active release commit does not match installed tag'
}

active_release_present() {
  ar_version=
  ar_commit=
  [ -f "$ACTIVE_RELEASE" ] || return 1
  ar_version=$(sed -n 's/^VERSION=//p' "$ACTIVE_RELEASE" | head -n 1)
  ar_commit=$(sed -n 's/^COMMIT=//p' "$ACTIVE_RELEASE" | head -n 1)
  printf '%s\n' "$ar_version" |
    grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' || return 1
  printf '%s\n' "$ar_commit" |
    grep -Eq '^[0-9a-f]{40}$' || return 1
  [ -d "$DATA_ROOT/releases/$ar_version/.git" ] || return 1
}

assert_detached_release() {
  if git -C "$1" symbolic-ref -q HEAD >/dev/null 2>&1; then
    die VERSION_MISMATCH 'Installed release is not detached'
  fi
}

assert_release_file() {
  arf_root=$1 arf_relative=$2
  arf_current=$arf_root
  arf_rest=$arf_relative
  while [ -n "$arf_rest" ]; do
    arf_component=${arf_rest%%/*}
    if [ "$arf_component" = "$arf_rest" ]; then arf_rest=; else arf_rest=${arf_rest#*/}; fi
    arf_current=$arf_current/$arf_component
    [ ! -L "$arf_current" ] || die GOVERNANCE_NOT_READY "Release path is a symlink: $arf_relative"
    if [ -n "$arf_rest" ]; then
      [ -d "$arf_current" ] || die GOVERNANCE_NOT_READY "Missing release directory: $arf_relative"
    else
      [ -f "$arf_current" ] || die GOVERNANCE_NOT_READY "Missing release file: $arf_relative"
    fi
  done
  arf_parent=$(dirname -- "$arf_root/$arf_relative")
  arf_physical_parent=$(CDPATH= cd -- "$arf_parent" && pwd -P) || die GOVERNANCE_NOT_READY "Cannot resolve release path: $arf_relative"
  case "$arf_physical_parent" in
    "$RELEASE_PHYSICAL"|"$RELEASE_PHYSICAL"/*) ;;
    *) die GOVERNANCE_NOT_READY "Release path escapes checkout: $arf_relative" ;;
  esac
}

atlassian_compatibility_schema() {
  acs_file=$1
  case "$(sed -n '1p' "$acs_file" 2>/dev/null)" in
    '# schema=1') printf '%s\n' 1 ;;
    '# schema=2') printf '%s\n' 2 ;;
    *) return 1 ;;
  esac
}

validate_release_checkout() {
  vrc_checkout=$1 vrc_version=$2
  [ ! -L "$vrc_checkout" ] && [ -d "$vrc_checkout" ] || die GOVERNANCE_NOT_READY "Release is not a regular directory: $vrc_version"
  [ ! -L "$vrc_checkout/.git" ] && [ -d "$vrc_checkout/.git" ] || die GOVERNANCE_NOT_READY "Release Git metadata is unsafe: $vrc_version"
  RELEASE_PHYSICAL=$(CDPATH= cd -- "$vrc_checkout" && pwd -P) || die GOVERNANCE_NOT_READY "Cannot resolve release: $vrc_version"
  vrc_origin=$(git -C "$vrc_checkout" config --get remote.origin.url 2>/dev/null) || die VERSION_MISMATCH 'Installed release origin is missing'
  [ "$vrc_origin" = "$REMOTE_URL" ] || die VERSION_MISMATCH "Installed release origin is not trusted: $vrc_origin"
  for vrc_required in \
    VERSION bin/beroka-governance runtime/entrypoint.md governance.md handbook.md workflow.md \
    templates/agent-entrypoints/AGENTS.md templates/agent-entrypoints/CLAUDE.md \
    templates/agent-entrypoints/CURSOR-USER-RULE.txt \
    templates/ai-agent-assignment.md templates/github-issue.md \
    templates/jira-confluence.md templates/pull-request.md
  do
    assert_release_file "$vrc_checkout" "$vrc_required"
  done
  if [ -e "$vrc_checkout/runtime/routing-schema" ]; then
    assert_release_file "$vrc_checkout" runtime/routing-schema
    [ "$(sed -n '1p' "$vrc_checkout/runtime/routing-schema")" = 1 ] ||
      die VERSION_MISMATCH 'Unsupported routing schema in installed release'
    for vrc_routing_file in \
      runtime/rules/general.md \
      runtime/profiles/standalone.md runtime/profiles/backend.md \
      runtime/profiles/frontend.md runtime/integrations/beroka-be-fe.md \
      runtime/integrations/beroka-be-fe.repositories \
      runtime/compatibility/atlassian.tsv
    do
      assert_release_file "$vrc_checkout" "$vrc_routing_file"
    done
    if semver_not_older v1.0.2 "$vrc_version"; then
      assert_release_file "$vrc_checkout" runtime/rules/work-items.md
    fi
    if semver_not_older v1.0.5 "$vrc_version"; then
      assert_release_file "$vrc_checkout" \
        runtime/integrations/beroka-be-fe.intake
      validate_intake_inventory \
        "$vrc_checkout/runtime/integrations/beroka-be-fe.intake" \
        "$vrc_checkout/runtime/repositories" ||
        die VERSION_MISMATCH 'Invalid cross-team intake inventory'
    fi
    if semver_not_older v1.0.6 "$vrc_version"; then
      assert_release_file "$vrc_checkout" \
        runtime/integrations/beroka-be-fe.confluence-targets
      validate_confluence_target_inventory \
        "$vrc_checkout/runtime/integrations/beroka-be-fe.confluence-targets" \
        "$vrc_checkout/runtime/repositories" ||
        die VERSION_MISMATCH 'Invalid Confluence target inventory'
    fi
    atlassian_compatibility_schema \
      "$vrc_checkout/runtime/compatibility/atlassian.tsv" >/dev/null ||
      die VERSION_MISMATCH 'Unsupported Atlassian compatibility schema'
    validate_catalog_records "$vrc_checkout/runtime/repositories"
  fi
  [ "$(sed -n '1p' "$vrc_checkout/VERSION" 2>/dev/null)" = "$vrc_version" ] || die VERSION_MISMATCH 'Installed VERSION does not match requested version'
  [ "$(git -C "$vrc_checkout" cat-file -t "$vrc_version" 2>/dev/null)" = tag ] || die VERSION_MISMATCH 'Installed tag is not annotated'
  RELEASE_COMMIT=$(git -C "$vrc_checkout" rev-parse "$vrc_version^{commit}" 2>/dev/null) || die VERSION_MISMATCH "Installed tag is missing: $vrc_version"
  [ "$(git -C "$vrc_checkout" rev-parse HEAD 2>/dev/null)" = "$RELEASE_COMMIT" ] || die VERSION_MISMATCH 'Installed checkout is not at its tag commit'
  assert_detached_release "$vrc_checkout"
  vrc_status=$(git -C "$vrc_checkout" status --porcelain --untracked-files=all 2>/dev/null) || die VERSION_MISMATCH 'Cannot inspect installed release status'
  [ -z "$vrc_status" ] || die VERSION_MISMATCH 'Installed release contains local modifications'
}

validate_intake_inventory() {
  vii_file=$1 vii_catalog=$2
  [ -f "$vii_file" ] && [ ! -L "$vii_file" ] &&
    [ -d "$vii_catalog" ] && [ ! -L "$vii_catalog" ] || return 1
  awk -F '\t' '
    /^#/ || /^[[:space:]]*$/ { next }
    NF != 4 { invalid=1; next }
    $1 == "beroka-vn/Beroka_Frontend" &&
      $2 == "beroka-vn/Beroka_Backend" &&
      $3 == "backend" && $4 == "BB" { frontend++; count++; next }
    $1 == "beroka-vn/Beroka_Backend" &&
      $2 == "beroka-vn/Beroka_Frontend" &&
      $3 == "frontend" && $4 == "BF" { backend++; count++; next }
    { invalid=1 }
    END {
      exit invalid || count != 2 || frontend != 1 || backend != 1
    }
  ' "$vii_file" || return 1
  while IFS="$(printf '\t')" read -r vii_source vii_target \
    vii_profile vii_project
  do
    case "$vii_source" in ''|\#*) continue ;; esac
    vii_record=$vii_catalog/$vii_target.conf
    case "$vii_record" in "$vii_catalog/"*.conf) ;; *) return 1 ;; esac
    [ -f "$vii_record" ] && [ ! -L "$vii_record" ] || return 1
    awk -F= -v profile="$vii_profile" -v project="$vii_project" '
      $1 == "PROFILE" {
        if (seen_profile++) exit 1
        actual_profile=substr($0, length($1) + 2)
      }
      $1 == "JIRA_PROJECT_KEY" {
        if (seen_project++) exit 1
        actual_project=substr($0, length($1) + 2)
      }
      $1 == "INTEGRATION_PROFILE" {
        if (seen_integration++) exit 1
        integration=substr($0, length($1) + 2)
      }
      $1 == "CROSS_REPO_POLICY" {
        if (seen_policy++) exit 1
        policy=substr($0, length($1) + 2)
      }
      END {
        exit !(seen_profile == 1 && seen_project == 1 &&
          seen_integration == 1 && seen_policy == 1 &&
          actual_profile == profile && actual_project == project &&
          integration == "beroka-be-fe" && policy == "profile-controlled")
      }
    ' "$vii_record" || return 1
  done <"$vii_file"
}

validate_confluence_target_inventory() {
  vcti_file=$1 vcti_catalog=$2
  [ -f "$vcti_file" ] && [ ! -L "$vcti_file" ] &&
    [ -d "$vcti_catalog" ] && [ ! -L "$vcti_catalog" ] || return 1
  vcti_root_ids=$(
    find "$vcti_catalog" -type f -name '*.conf' -print |
      LC_ALL=C sort |
      while IFS= read -r vcti_record; do
        awk -F= '$1 == "CONFLUENCE_ROOT_CONTENT_ID" { print $2 }' \
          "$vcti_record"
      done |
      tr '\n' ' '
  ) || return 1
  awk -F '\t' -v catalog="$vcti_catalog" -v roots="$vcti_root_ids" '
    /^#/ || /^[[:space:]]*$/ { next }
    NF != 11 { invalid=1; next }
    $1 !~ /^beroka-vn\/Beroka_(Backend|Frontend)$/ ||
      $2 !~ /^(page|folder)$/ ||
      $3 !~ /^(ACTIVE|PLANNED|DRIFTED|LEGACY|UNACTIVATED)$/ ||
      $4 !~ /^([1-9][0-9]*|-)$/ || $5 == "" ||
      $6 !~ /^(Shared|Derivatives|Underlying|-)$/ ||
      $7 !~ /^(Market|User|-)$/ ||
      $8 !~ /^(API|WebSocket|API\+WebSocket)$/ ||
      $9 !~ /^([1-9][0-9]*|-)$/ ||
      $10 !~ /^([A-Z][A-Z0-9]*(-[A-Z0-9]+)*|-)$/ ||
      $11 !~ /^([1-9][0-9]*|-)$/ { invalid=1 }
    ($3 == "ACTIVE" || $3 == "PLANNED") &&
      $7 !~ /^(Market|User)$/ { invalid=1 }
    $3 == "ACTIVE" && $2 == "page" &&
      ($4 == "-" || $6 !~ /^(Shared|Derivatives|Underlying)$/ ||
       $9 == "-" || $10 == "-" || $11 == "-") { invalid=1 }
    $3 == "ACTIVE" && $2 == "folder" &&
      ($4 == "-" || $6 !~ /^(Shared|Derivatives|Underlying)$/ ||
       $9 == "-" || $10 != "-" || $11 != "-") { invalid=1 }
    $3 == "PLANNED" &&
      ($2 != "page" || $4 != "-" ||
       $6 !~ /^(Shared|Derivatives|Underlying)$/ ||
       $9 == "-" || $10 == "-" || $11 == "-") { invalid=1 }
    $3 == "DRIFTED" && ($2 != "page" || $4 == "-") { invalid=1 }
    $3 == "LEGACY" &&
      ($2 != "folder" || $4 == "-" || $10 != "-" || $11 != "-") { invalid=1 }
    $3 == "UNACTIVATED" &&
      ($4 == "-" || $10 != "-" || $11 != "-") { invalid=1 }
    $4 != "-" && ++content[$4] > 1 { invalid=1 }
    $10 != "-" && ++capability[$10] > 1 { invalid=1 }
    { rows++; state[NR]=$3; type[NR]=$2; repo[NR]=$1; id[NR]=$4; parent[NR]=$9;
      scope[NR]=$6; domain[NR]=$7; transport[NR]=$8 }
    END {
      root_count=split(roots, root_values, /[^0-9]+/)
      for (i=1; i<=root_count; i++) if (root_values[i] != "" &&
        ++content[root_values[i]] > 1) invalid=1
      for (i in state) if ((state[i] == "ACTIVE" || state[i] == "PLANNED") && type[i] == "page") {
        matches=0
        for (j in state) if (repo[j] == repo[i] && type[j] == "folder" &&
          state[j] == "ACTIVE" && id[j] == parent[i]) {
          matches++
          if (scope[i] != scope[j] || domain[i] != domain[j] ||
            transport[i] != transport[j]) invalid=1
        }
        if (matches != 1) invalid=1
      }
      for (i in state) if (state[i] == "ACTIVE" && type[i] == "folder") {
        root=""
        path=catalog "/" repo[i] ".conf"
        while ((getline line < path) > 0)
          if (line ~ /^CONFLUENCE_ROOT_CONTENT_ID=/)
            root=substr(line, index(line, "=") + 1)
        close(path)
        current=parent[i]
        for (key in visited) delete visited[key]
        reaches_root=0
        for (step=0; step <= rows && current != root; step++) {
          key=repo[i] SUBSEP current
          if (visited[key]++) break
          matches=0
          for (j in state) if (repo[j] == repo[i] && type[j] == "folder" &&
            state[j] == "ACTIVE" && id[j] == current) {
            current=parent[j]
            matches++
          }
          if (matches != 1) break
        }
        if (current == root && root ~ /^[1-9][0-9]*$/) reaches_root=1
        if (!reaches_root) invalid=1
      }
      exit invalid || rows == 0
    }
  ' "$vcti_file" || return 1
  cut -f1 "$vcti_file" | sed '/^#/d;/^[[:space:]]*$/d' | LC_ALL=C sort -u |
  while IFS= read -r vcti_repository; do
    vcti_record=$vcti_catalog/$vcti_repository.conf
    [ -f "$vcti_record" ] && [ ! -L "$vcti_record" ] || exit 1
    case "$vcti_repository" in
      beroka-vn/Beroka_Backend) vcti_profile=backend ;;
      beroka-vn/Beroka_Frontend) vcti_profile=frontend ;;
      *) exit 1 ;;
    esac
    awk -F= -v profile="$vcti_profile" '
      $1 == "PROFILE" {
        if (seen_profile++) exit 1
        actual_profile=substr($0, length($1) + 2)
      }
      $1 == "INTEGRATION_PROFILE" {
        if (seen_integration++) exit 1
        integration=substr($0, length($1) + 2)
      }
      $1 == "CROSS_REPO_POLICY" {
        if (seen_policy++) exit 1
        policy=substr($0, length($1) + 2)
      }
      END {
        exit !(seen_profile == 1 && seen_integration == 1 &&
          seen_policy == 1 && actual_profile == profile &&
          integration == "beroka-be-fe" && policy == "profile-controlled")
      }
    ' "$vcti_record" || exit 1
  done
}

validate_catalog_records() {
  vcr_root=$1
  [ ! -L "$vcr_root" ] && [ -d "$vcr_root" ] ||
    die VERSION_MISMATCH 'Repository catalog is not a regular directory'
  if find "$vcr_root" -type l -print | grep -q .; then
    die VERSION_MISMATCH 'Repository catalog contains a symlink'
  fi
  vcr_files=$(find "$vcr_root" -type f -name '*.conf' -print | LC_ALL=C sort)
  [ -n "$vcr_files" ] || return 0
  printf '%s\n' "$vcr_files" |
    awk -v root="$vcr_root/" '
      index($0, root) != 1 { exit 1 }
      {
        slug=substr($0, length(root) + 1)
        sub(/\.conf$/, "", slug)
        if (slug !~ /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/ || seen[slug]++) exit 1
      }
    ' >/dev/null || die VERSION_MISMATCH 'Invalid repository catalog path'
  vcr_saved_release=$RELEASE_DIR
  RELEASE_DIR=${vcr_root%/runtime/repositories}
  while IFS= read -r vcr_file; do
    vcr_slug=${vcr_file#"$vcr_root/"}
    vcr_slug=${vcr_slug%.conf}
    parse_routing "$vcr_file" "$vcr_slug" ||
      die VERSION_MISMATCH 'Invalid repository catalog record'
  done <<EOF
$vcr_files
EOF
  RELEASE_DIR=$vcr_saved_release
}

release_for_version() {
  rfv_version=$1
  printf '%s\n' "$rfv_version" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' || die GOVERNANCE_NOT_READY "Invalid version: $rfv_version"
  RELEASE_DIR=$DATA_ROOT/releases/$rfv_version
  [ -d "$RELEASE_DIR/.git" ] || die GOVERNANCE_NOT_READY "Release is not installed: $rfv_version"
  validate_release_checkout "$RELEASE_DIR" "$rfv_version"
}

prepare_release() {
  pr_version=$1
  assert_install_paths
  TX_RELEASE_TARGET=$DATA_ROOT/releases/$pr_version
  [ ! -L "$TX_RELEASE_TARGET" ] || die GOVERNANCE_NOT_READY "Release target is a symlink: $pr_version"
  if [ -e "$TX_RELEASE_TARGET" ]; then
    release_for_version "$pr_version"
    TX_RELEASE_NEW=0
  else
    mkdir -p "$DATA_ROOT/releases" || die GOVERNANCE_NOT_READY 'Cannot create releases directory'
    TX_RELEASE_STAGE=$(mktemp -d "$DATA_ROOT/releases/.install.$pr_version.XXXXXX") || die GOVERNANCE_NOT_READY 'Cannot create release stage'
    if ! pr_clone_output=$(git -c advice.detachedHead=false clone -q --depth 1 --single-branch --branch "$pr_version" "$REMOTE_URL" "$TX_RELEASE_STAGE" 2>&1); then
      [ -z "$pr_clone_output" ] || printf '%s\n' "$pr_clone_output" >&2
      die GOVERNANCE_ACCESS_DENIED "Cannot clone $SOURCE_SLUG at $pr_version"
    fi
    RELEASE_DIR=$TX_RELEASE_STAGE
    validate_release_checkout "$RELEASE_DIR" "$pr_version"
    TX_RELEASE_NEW=1
  fi
}

remote_release_commit() {
  rrc_version=$1
  rrc_output=$(git ls-remote --tags "$REMOTE_URL" \
    "refs/tags/$rrc_version" "refs/tags/$rrc_version^{}" 2>/dev/null) ||
    die RELEASE_RESOLUTION_REQUIRED "Cannot verify release: $rrc_version"
  REMOTE_RELEASE_COMMIT=$(printf '%s\n' "$rrc_output" |
    awk -v ref="refs/tags/$rrc_version^{}" '
      $2 == ref && $1 ~ /^[0-9a-f]{40}$/ { commit=$1; matches++ }
      END { if (matches == 1) print commit; else exit 1 }
    ') || die RELEASE_RESOLUTION_REQUIRED \
    "Release is not an exact stable annotated tag: $rrc_version"
}

resolve_latest_release() {
  rlr_output=$(git ls-remote --tags "$REMOTE_URL" 2>/dev/null) ||
    die RELEASE_RESOLUTION_REQUIRED 'Cannot resolve the latest governance release'
  rlr_selected=$(printf '%s\n' "$rlr_output" |
    awk '
      $1 ~ /^[0-9a-f]{40}$/ &&
      $2 ~ /^refs\/tags\/v[0-9]+\.[0-9]+\.[0-9]+\^\{\}$/ {
        version=$2
        sub(/^refs\/tags\/v/, "", version)
        sub(/\^\{\}$/, "", version)
        split(version, part, ".")
        if (!found ||
            part[1] + 0 > major ||
            (part[1] + 0 == major && part[2] + 0 > minor) ||
            (part[1] + 0 == major && part[2] + 0 == minor &&
             part[3] + 0 > patch)) {
          found=1
          major=part[1] + 0
          minor=part[2] + 0
          patch=part[3] + 0
          commit=$1
        }
      }
      END {
        if (!found) exit 1
        print "v" major "." minor "." patch "\t" commit
      }
    ') || die RELEASE_RESOLUTION_REQUIRED \
    'No stable annotated governance release is available'
  RESOLVED_VERSION=${rlr_selected%%	*}
  REMOTE_RELEASE_COMMIT=${rlr_selected#*	}
}

semver_not_older() {
  awk -v current="${1#v}" -v target="${2#v}" '
    function canonical(component) {
      sub(/^0+/, "", component)
      return component == "" ? "0" : component
    }
    BEGIN {
      split(current, c, ".")
      split(target, t, ".")
      for (i = 1; i <= 3; i++) {
        c[i] = canonical(c[i])
        t[i] = canonical(t[i])
        if (length(t[i]) != length(c[i]))
          exit length(t[i]) > length(c[i]) ? 0 : 1
        if (t[i] != c[i])
          exit ("x" t[i]) > ("x" c[i]) ? 0 : 1
      }
      exit 0
    }
  '
}

validate_release_transition() {
  vrt_current=$1 vrt_target=$2 vrt_allow_upgrade=$3
  vrt_client=$4 vrt_non_interactive=$5
  [ "$vrt_current" != "$vrt_target" ] || return 0

  vrt_current_major=${vrt_current#v}
  vrt_current_major=${vrt_current_major%%.*}
  vrt_target_major=${vrt_target#v}
  vrt_target_major=${vrt_target_major%%.*}
  [ "$vrt_current_major" = "$vrt_target_major" ] ||
    die VERSION_MISMATCH \
      'Upgrade target has a different major version'
  semver_not_older "$vrt_current" "$vrt_target" &&
    ! semver_not_older "$vrt_target" "$vrt_current" ||
    die VERSION_MISMATCH \
      'Upgrade target must be newer than the active release'
  [ "$vrt_allow_upgrade" -eq 0 ] || return 0

  vrt_remediation='Remediation: beroka-governance bootstrap'
  [ -z "$vrt_client" ] ||
    vrt_remediation="$vrt_remediation --client $vrt_client"
  vrt_remediation="$vrt_remediation --version $vrt_target --upgrade"
  [ "$vrt_non_interactive" -eq 0 ] ||
    vrt_remediation="$vrt_remediation --non-interactive"
  die GOVERNANCE_UPGRADE_REQUIRED "$vrt_remediation"
}

prepare_cli() {
  cp "$RELEASE_DIR/bin/beroka-governance" "$TX_DIR/work/cli" || die GOVERNANCE_NOT_READY 'Cannot stage the user CLI'
  chmod 755 "$TX_DIR/work/cli" || die GOVERNANCE_NOT_READY 'Cannot prepare the user CLI'
  TX_CLI_PATH=$BIN_DIR/$PROGRAM
  tx_snapshot_user_file "$TX_CLI_PATH" cli
  TX_CLI_SNAPSHOT=1
}

activate_release() {
  [ "$TX_RELEASE_NEW" -eq 1 ] || return 0
  assert_install_paths
  mkdir -p "$DATA_ROOT/releases" || die GOVERNANCE_NOT_READY 'Cannot create releases directory'
  [ ! -e "$TX_RELEASE_TARGET" ] && [ ! -L "$TX_RELEASE_TARGET" ] || die VERSION_MISMATCH 'Release target appeared during installation'
  TX_RELEASE_OWNED=1
  mv "$RELEASE_DIR" "$TX_RELEASE_TARGET" || die GOVERNANCE_NOT_READY 'Cannot install the release checkout'
  RELEASE_DIR=$TX_RELEASE_TARGET
}

activate_cli() {
  assert_install_paths
  apply_user_file "$TX_DIR/work/cli" "$TX_CLI_PATH" CLI
  chmod 755 "$TX_CLI_PATH" || die GOVERNANCE_NOT_READY 'Cannot make the user CLI executable'
}

cmd_install() {
  ci_version=$1 ci_expected_commit=${2:-}
  ci_allow_upgrade=${3:-0} ci_transition_client=${4:-}
  ci_non_interactive=${5:-0}
  printf '%s\n' "$ci_version" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' || die GOVERNANCE_NOT_READY "Invalid version: $ci_version"
  case "$ci_allow_upgrade:$ci_non_interactive" in
    0:0|0:1|1:0|1:1) ;;
    *) die GOVERNANCE_NOT_READY 'Invalid release transition options' ;;
  esac
  assert_safe_user_path "$ACTIVE_RELEASE" 'active release'
  [ ! -e "$ACTIVE_RELEASE" ] || [ -f "$ACTIVE_RELEASE" ] ||
    die GOVERNANCE_NOT_READY 'Active release is not a regular file'
  ci_has_active=0
  ci_previous_version=
  if [ -e "$ACTIVE_RELEASE" ] || [ -L "$ACTIVE_RELEASE" ]; then
    if active_release_present; then
      load_active_release
      ci_has_active=1
      ci_previous_version=$ACTIVE_VERSION
      if [ -z "$ci_transition_client" ]; then
        load_enabled_clients
        ci_transition_client=${ENABLED_CLIENTS%%,*}
      fi
      validate_release_transition "$ACTIVE_VERSION" "$ci_version" \
        "$ci_allow_upgrade" "$ci_transition_client" "$ci_non_interactive"
    else
      rm -f "$ACTIVE_RELEASE"
    fi
  fi
  [ "$ci_allow_upgrade" -eq 0 ] || [ "$ci_has_active" -eq 1 ] ||
    die VERSION_MISMATCH 'Bootstrap --upgrade requires an active release'
  if [ -z "$ci_expected_commit" ]; then
    remote_release_commit "$ci_version"
    ci_expected_commit=$REMOTE_RELEASE_COMMIT
  else
    printf '%s\n' "$ci_expected_commit" |
      grep -Eq '^[0-9a-f]{40}$' ||
      die RELEASE_VERIFICATION_FAILED 'Invalid expected release commit'
  fi
  tx_begin
  prepare_release "$ci_version"
  [ "$RELEASE_COMMIT" = "$ci_expected_commit" ] ||
    die VERSION_MISMATCH 'Release commit does not match the verified commit'
  prepare_cli
  write_active_release "$TX_DIR/work/active-release" "$ci_version" "$RELEASE_COMMIT"
  tx_snapshot_user_file "$ACTIVE_RELEASE" active-release
  TX_ACTIVE_RELEASE_SNAPSHOT=1
  activate_release
  activate_cli
  apply_user_file "$TX_DIR/work/active-release" "$ACTIVE_RELEASE" active-release
  tx_commit
  if [ -n "$ci_previous_version" ] && [ "$ci_previous_version" != "$ci_version" ]; then
    cursor_clear_receipts
  fi
  printf '%s\n' "Installed: $ci_version"
  pass_result
}

assert_client_files() {
  assert_safe_user_path "$CONFIG_ROOT" config
  assert_safe_user_path "$CLIENTS_FILE" 'client enrollment'
  assert_safe_user_path "$CURSOR_ACK_FILE" 'Cursor acknowledgement'
  assert_safe_user_path "$GITHUB_ROLE_FILE" 'GitHub role'
  [ ! -e "$CONFIG_ROOT" ] || [ -d "$CONFIG_ROOT" ] ||
    die GOVERNANCE_NOT_READY "Config root is not a directory: $CONFIG_ROOT"
  { [ ! -e "$CLIENTS_FILE" ] && [ ! -L "$CLIENTS_FILE" ]; } ||
    { [ -f "$CLIENTS_FILE" ] && [ ! -L "$CLIENTS_FILE" ]; } ||
    die GOVERNANCE_NOT_READY 'Unsafe client enrollment'
  { [ ! -e "$CURSOR_ACK_FILE" ] && [ ! -L "$CURSOR_ACK_FILE" ]; } ||
    { [ -f "$CURSOR_ACK_FILE" ] && [ ! -L "$CURSOR_ACK_FILE" ]; } ||
    die GOVERNANCE_NOT_READY 'Unsafe Cursor acknowledgement'
  { [ ! -e "$GITHUB_ROLE_FILE" ] && [ ! -L "$GITHUB_ROLE_FILE" ]; } ||
    { [ -f "$GITHUB_ROLE_FILE" ] && [ ! -L "$GITHUB_ROLE_FILE" ]; } ||
    die GOVERNANCE_NOT_READY 'Unsafe GitHub role'
}

client_list_contains() {
  clc_list=$1 clc_client=$2
  case ",$clc_list," in
    *",$clc_client,"*) return 0 ;;
    *) return 1 ;;
  esac
}

validate_clients() {
  case "$1" in
    codex|claude|cursor|codex,claude|codex,cursor|claude,cursor|codex,claude,cursor) ;;
    *) die GOVERNANCE_NOT_READY 'Invalid CLIENTS' ;;
  esac
}

canonical_clients() {
  cc_current=$1 cc_selected=$2 cc_result=
  for cc_client in codex claude cursor; do
    if client_list_contains "$cc_current" "$cc_client" ||
      [ "$cc_selected" = "$cc_client" ]
    then
      if [ -n "$cc_result" ]; then
        cc_result=$cc_result,$cc_client
      else
        cc_result=$cc_client
      fi
    fi
  done
  validate_clients "$cc_result"
  printf '%s\n' "$cc_result"
}

load_enabled_clients() {
  ENABLED_CLIENTS=
  assert_client_files
  [ ! -e "$CLIENTS_FILE" ] || {
    ENABLED_CLIENTS=$(sed -n '1p' "$CLIENTS_FILE")
    validate_clients "$ENABLED_CLIENTS"
    [ "$(wc -l <"$CLIENTS_FILE" | tr -d ' ')" -eq 1 ] ||
      die GOVERNANCE_NOT_READY 'Invalid client enrollment'
  }
}

require_enrolled_client() {
  rec_client=$1
  load_enabled_clients
  client_list_contains "$ENABLED_CLIENTS" "$rec_client" ||
    die CLIENT_INSTRUCTION_REQUIRED \
      "Remediation: beroka-governance bootstrap --client $rec_client"
}

enable_client() {
  enable_selected=$1
  load_enabled_clients
  enable_clients=$(canonical_clients "$ENABLED_CLIENTS" "$enable_selected")
  enable_stage=$(mktemp "${TMPDIR:-/tmp}/beroka-governance-clients.XXXXXX") ||
    die GOVERNANCE_NOT_READY 'Cannot stage client enrollment'
  printf '%s\n' "$enable_clients" >"$enable_stage" ||
    die GOVERNANCE_NOT_READY 'Cannot stage client enrollment'
  apply_user_file "$enable_stage" "$CLIENTS_FILE" 'client enrollment'
  rm -f "$enable_stage" || :
}

active_instruction_file() {
  case "$1" in
    codex)
      codex_home=${CODEX_HOME:-$HOME/.codex}
      if [ -s "$codex_home/AGENTS.override.md" ]; then
        printf '%s\n' "$codex_home/AGENTS.override.md"
      else
        printf '%s\n' "$codex_home/AGENTS.md"
      fi
      ;;
    claude) printf '%s\n' "$HOME/.claude/CLAUDE.md" ;;
    cursor) return 1 ;;
  esac
}

cursor_ack_matches() {
  cam_hash=$1
  cam_bytes=$((${#cam_hash} + 1))
  [ -f "$CURSOR_ACK_FILE" ] &&
    [ ! -L "$CURSOR_ACK_FILE" ] &&
    [ "$(wc -l <"$CURSOR_ACK_FILE" | tr -d ' ')" -eq 1 ] &&
    [ "$(wc -c <"$CURSOR_ACK_FILE" | tr -d ' ')" -eq "$cam_bytes" ] &&
    [ "$(sed -n '1p' "$CURSOR_ACK_FILE")" = "$cam_hash" ]
}

cursor_rule_identity() {
  git --git-dir=/dev/null hash-object --no-filters "$1"
}

cursor_hooks_expected() {
  case "$BIN_DIR" in
    /*) ;;
    *) die GOVERNANCE_NOT_READY 'Cursor hook CLI path is not absolute' ;;
  esac
  che_cli=$BIN_DIR/$PROGRAM
  jq -nc --arg cli "$che_cli" '[
    {event:"sessionStart",command:($cli + " cursor-hook sessionStart"),security:false},
    {event:"beforeSubmitPrompt",command:($cli + " cursor-hook beforeSubmitPrompt"),security:false},
    {event:"preCompact",command:($cli + " cursor-hook preCompact"),security:false},
    {event:"beforeMCPExecution",command:($cli + " cursor-hook beforeMCPExecution"),security:true},
    {event:"beforeShellExecution",command:($cli + " cursor-hook beforeShellExecution"),security:true,matcher:"gh"}
  ]' || die GOVERNANCE_NOT_READY 'Cannot define Cursor security hooks'
}

install_cursor_hooks() {
  ich_dir=$HOME/.cursor ich_file=$HOME/.cursor/hooks.json
  assert_safe_user_path "$ich_dir" 'Cursor hooks directory'
  assert_safe_user_path "$ich_file" 'Cursor hooks config'
  [ ! -e "$ich_file" ] || { [ -f "$ich_file" ] && [ ! -L "$ich_file" ]; } ||
    die GOVERNANCE_NOT_READY 'Unsafe Cursor hooks config'
  mkdir -p "$ich_dir" || die GOVERNANCE_NOT_READY 'Cannot create Cursor hooks directory'
  ich_expected=$(cursor_hooks_expected)
  ich_temp=$(mktemp "$ich_dir/.beroka-hooks.XXXXXX") ||
    die GOVERNANCE_NOT_READY 'Cannot stage Cursor hooks config'
  if [ -e "$ich_file" ]; then
    if ! jq -s --argjson managed "$ich_expected" '
      if length != 1 or (.[0] | type != "object") then error("invalid hooks") else
        .[0] | .version = (.version // 1) |
      if has("hooks") and (.hooks | type != "object") then error("invalid hooks") else
        .hooks = (.hooks // {}) |
        reduce $managed[] as $item (
          .;
          ($item | {command}
            + (if .security then {failClosed:true} else {} end)
            + (if .matcher then {matcher:.matcher} else {} end)) as $expected |
          ($expected | del(.matcher)) as $legacy |
          (.hooks[$item.event] // []) as $entries |
          if ((.hooks | has($item.event)) and (.hooks[$item.event] | type != "array")) then error("invalid hook event")
          else
            ([$entries[] | select((($expected.matcher != null) and (. == $legacy)) | not)]) as $kept |
            if any($kept[]; .command == $expected.command and . != $expected) then error("conflicting hook")
            elif any($kept[]; . == $expected) then .hooks[$item.event] = $kept
            else .hooks[$item.event] = $kept + [$expected]
            end
          end
        )
      end
      end
    ' "$ich_file" >"$ich_temp" 2>/dev/null
    then
      rm -f "$ich_temp" || :
      die GOVERNANCE_NOT_READY 'Cursor hooks config is invalid or conflicts with managed hooks'
    fi
  elif ! printf '%s\n' '{}' | jq -s --argjson managed "$ich_expected" '
      if length != 1 or (.[0] | type != "object") then error("invalid hooks") else
      .[0] | .version = 1 | .hooks = {} |
      reduce $managed[] as $item (
        .;
        ($item | {command}
          + (if .security then {failClosed:true} else {} end)
          + (if .matcher then {matcher:.matcher} else {} end)) as $expected |
        .hooks[$item.event] = [$expected]
      )
      end
    ' >"$ich_temp" 2>/dev/null
  then
    rm -f "$ich_temp" || :
    die GOVERNANCE_NOT_READY 'Cannot stage Cursor hooks config'
  fi
  chmod 600 "$ich_temp" || { rm -f "$ich_temp" || :; die GOVERNANCE_NOT_READY 'Cannot secure Cursor hooks config'; }
  mv "$ich_temp" "$ich_file" || { rm -f "$ich_temp" || :; die GOVERNANCE_NOT_READY 'Cannot replace Cursor hooks config'; }
}

verify_cursor_hooks() {
  vch_file=$HOME/.cursor/hooks.json
  [ -f "$vch_file" ] && [ ! -L "$vch_file" ] || return 1
  vch_expected=$(cursor_hooks_expected) || return 1
  jq -se --argjson managed "$vch_expected" '
    length == 1 and (.[0] | type == "object") and
    (.[0] | (.version | type == "number" and . == 1) and
    (.hooks | type == "object") and
    (. as $config |
    all($managed[];
      (. as $item |
       ($item | {command}
         + (if .security then {failClosed:true} else {} end)
         + (if .matcher then {matcher:.matcher} else {} end)) as $expected |
       ($config.hooks[$item.event] | type == "array") and
       ([$config.hooks[$item.event][] | select(. == $expected)] | length == 1)))))
  ' "$vch_file" >/dev/null 2>&1
}

verify_cursor_runtime() {
  vcr_output=$(printf '%s\n' '{}' | "$BIN_DIR/$PROGRAM" \
    cursor-hook beforeMCPExecution 2>&1) || return 1
  printf '%s\n' "$vcr_output" | jq -e \
    '.permission == "deny" and (.user_message | contains("GOVERNANCE_CONTEXT_REQUIRED"))' \
    >/dev/null 2>&1
}

verify_client_instruction() {
  verify_instruction_client=$1
  case "$verify_instruction_client" in
    codex)
      verify_instruction_template=$RELEASE_DIR/templates/agent-entrypoints/AGENTS.md
      ;;
    claude)
      verify_instruction_template=$RELEASE_DIR/templates/agent-entrypoints/CLAUDE.md
      ;;
    cursor)
      verify_instruction_template=$RELEASE_DIR/templates/agent-entrypoints/CURSOR-USER-RULE.txt
      assert_client_files
      verify_cursor_hash=$(cursor_rule_identity \
        "$verify_instruction_template") ||
        die GOVERNANCE_NOT_READY 'Cannot hash Cursor user rule'
      cursor_ack_matches "$verify_cursor_hash" ||
        die CURSOR_USER_RULE_REQUIRED \
          'Remediation: beroka-governance bootstrap --client cursor'
      printf '%s\n' 'Instruction: USER_CONFIRMED'
      return
      ;;
    *) usage >&2; exit 2 ;;
  esac

  assert_valid_template "$verify_instruction_template"
  verify_instruction_destination=$(
    active_instruction_file "$verify_instruction_client"
  ) || die GOVERNANCE_NOT_READY \
    "No instruction file for $verify_instruction_client"
  assert_safe_user_path "$verify_instruction_destination" \
    "$verify_instruction_client instruction"
  [ -f "$verify_instruction_destination" ] &&
    [ ! -L "$verify_instruction_destination" ] ||
    die CLIENT_INSTRUCTION_REQUIRED \
      "Remediation: beroka-governance bootstrap --client $verify_instruction_client"

  PERSONAL_STAGE_ROOT=$(mktemp -d \
    "${TMPDIR:-/tmp}/beroka-governance-instruction-check.XXXXXX") ||
    die GOVERNANCE_NOT_READY 'Cannot verify client instruction'
  verify_instruction_stage=$PERSONAL_STAGE_ROOT
  verify_instruction_personal=$(mktemp \
    "$verify_instruction_stage/personal.XXXXXX") ||
    die GOVERNANCE_NOT_READY 'Cannot verify client instruction'
  verify_instruction_managed=$(mktemp \
    "$verify_instruction_stage/managed.XXXXXX") ||
    die GOVERNANCE_NOT_READY 'Cannot verify client instruction'
  if ! strip_managed_block "$verify_instruction_destination" \
    "$verify_instruction_personal" \
    "$verify_instruction_managed"
  then
    die CLIENT_INSTRUCTION_CONFLICT \
      "Remediation: repair the managed block, then run: beroka-governance bootstrap --client $verify_instruction_client"
  fi
  if [ ! -s "$verify_instruction_managed" ] ||
    ! cmp -s "$verify_instruction_managed" \
      "$verify_instruction_template"
  then
    die CLIENT_INSTRUCTION_REQUIRED \
      "Remediation: beroka-governance bootstrap --client $verify_instruction_client"
  fi
  cleanup_personal_stage ||
    die GOVERNANCE_NOT_READY 'Cannot finish client instruction verification'
  printf '%s\n' 'Instruction: INSTALLED'
}

install_client_instruction() {
  instruction_client=$1 instruction_interactive=$2
  case "$instruction_client" in
    codex) instruction_template=$RELEASE_DIR/templates/agent-entrypoints/AGENTS.md ;;
    claude) instruction_template=$RELEASE_DIR/templates/agent-entrypoints/CLAUDE.md ;;
    cursor)
      instruction_template=$RELEASE_DIR/templates/agent-entrypoints/CURSOR-USER-RULE.txt
      [ -f "$instruction_template" ] ||
        die ENTRYPOINT_DRIFT "Missing Cursor user rule in $RELEASE_DIR"
      assert_client_files
      cursor_rule_hash=$(cursor_rule_identity "$instruction_template") ||
        die GOVERNANCE_NOT_READY 'Cannot hash Cursor user rule'
      if cursor_ack_matches "$cursor_rule_hash"; then
        printf '%s\n' 'Instruction: USER_CONFIRMED'
        return
      fi
      [ "$instruction_interactive" -eq 1 ] ||
        die CURSOR_USER_RULE_REQUIRED \
          'Remediation: beroka-governance bootstrap --client cursor'
      cat "$instruction_template" || die GOVERNANCE_NOT_READY 'Cannot print Cursor user rule'
      printf 'User Rule added in Cursor Settings > Rules? [y/N] '
      IFS= read -r cursor_answer || cursor_answer=
      case "$cursor_answer" in y|Y|yes|YES) ;; *) die CURSOR_USER_RULE_REQUIRED 'Cursor User Rule was not confirmed' ;; esac
      cursor_stage=$(mktemp "${TMPDIR:-/tmp}/beroka-governance-cursor-rule.XXXXXX") ||
        die GOVERNANCE_NOT_READY 'Cannot stage Cursor acknowledgement'
      printf '%s\n' "$cursor_rule_hash" >"$cursor_stage" ||
        die GOVERNANCE_NOT_READY 'Cannot stage Cursor acknowledgement'
      apply_user_file "$cursor_stage" "$CURSOR_ACK_FILE" 'Cursor acknowledgement'
      rm -f "$cursor_stage" || :
      printf '%s\n' 'Instruction: USER_CONFIRMED'
      return
      ;;
    *) usage >&2; exit 2 ;;
  esac

  assert_valid_template "$instruction_template"
  instruction_destination=$(active_instruction_file "$instruction_client") ||
    die GOVERNANCE_NOT_READY "No instruction file for $instruction_client"
  assert_safe_user_path "$instruction_destination" "$instruction_client instruction"
  [ ! -e "$instruction_destination" ] || { [ -f "$instruction_destination" ] && [ ! -L "$instruction_destination" ]; } ||
    die GOVERNANCE_NOT_READY "Unsafe $instruction_client instruction"
  PERSONAL_STAGE_ROOT=$(mktemp -d \
    "${TMPDIR:-/tmp}/beroka-governance-instruction.XXXXXX") ||
    die GOVERNANCE_NOT_READY "Cannot stage $instruction_client instruction"
  instruction_stage=$(mktemp "$PERSONAL_STAGE_ROOT/personal.XXXXXX") ||
    die GOVERNANCE_NOT_READY "Cannot stage $instruction_client instruction"
  instruction_last_byte_file=$(mktemp \
    "$PERSONAL_STAGE_ROOT/last-byte.XXXXXX") ||
    die GOVERNANCE_NOT_READY "Cannot stage $instruction_client instruction"
  instruction_lf_file=$(mktemp "$PERSONAL_STAGE_ROOT/lf.XXXXXX") ||
    die GOVERNANCE_NOT_READY "Cannot stage $instruction_client instruction"
  instruction_merged_file=$(mktemp "$PERSONAL_STAGE_ROOT/merged.XXXXXX") ||
    die GOVERNANCE_NOT_READY "Cannot stage $instruction_client instruction"
  if [ -e "$instruction_destination" ]; then
    strip_managed_block "$instruction_destination" "$instruction_stage" || {
      die CLIENT_INSTRUCTION_CONFLICT \
        "Remediation: repair the managed block, then run: beroka-governance bootstrap --client $instruction_client"
    }
  else
    : >"$instruction_stage" || die GOVERNANCE_NOT_READY "Cannot stage $instruction_client instruction"
  fi
  instruction_needs_boundary=0
  if [ -s "$instruction_stage" ]; then
    tail -c 1 "$instruction_stage" >"$instruction_last_byte_file" ||
      die GOVERNANCE_NOT_READY \
        "Cannot inspect $instruction_client instruction boundary"
    [ -s "$instruction_last_byte_file" ] ||
      die GOVERNANCE_NOT_READY \
        "Cannot inspect $instruction_client instruction boundary"
    printf '\n' >"$instruction_lf_file" ||
      die GOVERNANCE_NOT_READY \
        "Cannot inspect $instruction_client instruction boundary"
    instruction_newline_status=0
    cmp -s "$instruction_last_byte_file" "$instruction_lf_file" ||
      instruction_newline_status=$?
    case "$instruction_newline_status" in
      0) ;;
      1) instruction_needs_boundary=1 ;;
      *)
        die GOVERNANCE_NOT_READY \
          "Cannot inspect $instruction_client instruction boundary"
        ;;
    esac
  fi
  cat "$instruction_stage" >"$instruction_merged_file" ||
    die GOVERNANCE_NOT_READY "Cannot stage $instruction_client instruction"
  if [ "$instruction_needs_boundary" -eq 1 ]; then
    printf '%s\n' "$INSTRUCTION_BOUNDARY_MARKER" \
      >>"$instruction_merged_file" ||
      die GOVERNANCE_NOT_READY "Cannot stage $instruction_client instruction"
  fi
  cat "$instruction_template" >>"$instruction_merged_file" ||
    die GOVERNANCE_NOT_READY "Cannot stage $instruction_client instruction"
  apply_user_file "$instruction_merged_file" "$instruction_destination" \
    "$instruction_client instruction"
  cleanup_personal_stage ||
    die GOVERNANCE_NOT_READY \
      "Cannot finish $instruction_client instruction staging"
  printf '%s\n' 'Instruction: INSTALLED'
}

cmd_bootstrap() {
  bs_requested=
  if [ "$#" -gt 0 ]; then
    case "$1" in --*) ;; *) bs_requested=$1; shift ;; esac
  fi
  bs_client= bs_version= bs_expected_commit=
  bs_non_interactive=0 bs_upgrade=0 bs_ready=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --client)
        [ -z "$bs_client" ] && [ "$#" -ge 2 ] ||
          { usage >&2; exit 2; }
        case "$2" in
          codex|claude|cursor) bs_client=$2 ;;
          *) usage >&2; exit 2 ;;
        esac
        shift 2
        ;;
      --version)
        [ -z "$bs_version" ] && [ "$#" -ge 2 ] ||
          { usage >&2; exit 2; }
        printf '%s\n' "$2" |
          grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' ||
          { usage >&2; exit 2; }
        bs_version=$2
        shift 2
        ;;
      --expected-commit)
        [ -z "$bs_expected_commit" ] && [ "$#" -ge 2 ] ||
          { usage >&2; exit 2; }
        printf '%s\n' "$2" |
          grep -Eq '^[0-9a-f]{40}$' ||
          { usage >&2; exit 2; }
        bs_expected_commit=$2
        shift 2
        ;;
      --non-interactive)
        [ "$bs_non_interactive" -eq 0 ] ||
          { usage >&2; exit 2; }
        bs_non_interactive=1
        shift
        ;;
      --upgrade)
        [ "$bs_upgrade" -eq 0 ] || { usage >&2; exit 2; }
        bs_upgrade=1
        shift
        ;;
      --ready)
        bs_ready=1
        shift
        ;;
      *) usage >&2; exit 2 ;;
    esac
  done

  if [ "$bs_ready" -eq 1 ] && [ -z "$bs_requested" ] && [ "$bs_non_interactive" -eq 1 ]; then
    usage >&2
    exit 2
  fi
  if [ "$bs_ready" -eq 1 ] && [ -z "$bs_requested" ]; then
    bs_requested=$(canonical_repo '.')
  fi

  bs_interactive=0
  if [ "$bs_non_interactive" -eq 0 ] && [ -t 0 ] && [ -t 1 ]; then
    bs_interactive=1
  fi
  if [ -z "$bs_client" ]; then
    [ "$bs_interactive" -eq 1 ] || { usage >&2; exit 2; }
    bs_client=$(detect_client)
  fi
  require_client "$bs_client"

  if [ -z "$bs_version" ]; then
    [ "$bs_interactive" -eq 1 ] ||
      die RELEASE_RESOLUTION_REQUIRED \
        'Non-interactive bootstrap requires --version vX.Y.Z'
    resolve_latest_release
    bs_version=$RESOLVED_VERSION
    [ -n "$bs_expected_commit" ] ||
      bs_expected_commit=$REMOTE_RELEASE_COMMIT
  fi

  SUPPRESS_PASS_RESULT=1
  cmd_install "$bs_version" "$bs_expected_commit" "$bs_upgrade" \
    "$bs_client" "$bs_non_interactive"
  load_active_release
  bs_selected_instruction_installed=0
  if [ "$bs_upgrade" -eq 1 ]; then
    load_enabled_clients
    for bs_enabled_client in codex claude cursor; do
      client_list_contains "$ENABLED_CLIENTS" "$bs_enabled_client" ||
        continue
      install_client_instruction "$bs_enabled_client" "$bs_interactive"
      install_documentation_hooks "$bs_enabled_client"
      [ "$bs_enabled_client" != "$bs_client" ] ||
        bs_selected_instruction_installed=1
    done
  fi
  [ "$bs_selected_instruction_installed" -eq 1 ] ||
    install_client_instruction "$bs_client" "$bs_interactive"
  if [ "$bs_client" = cursor ]; then
    install_cursor_hooks
    verify_cursor_hooks || die GOVERNANCE_NOT_READY 'Cursor hooks installation verification failed'
    printf '%s\n' 'Runtime hook: INSTALLED'
  fi
  install_documentation_hooks "$bs_client"
  enable_client "$bs_client"
  printf '%s\n' \
    'Release: PASS' \
    "Version: $bs_version" \
    "Selected client: $bs_client"

  if [ "$bs_interactive" -eq 1 ]; then
    cmd_setup_connectors --client "$bs_client"
  else
    cmd_setup_connectors --client "$bs_client" --non-interactive
  fi
  configure_github_role "$bs_client" "$bs_interactive"

  if [ "$bs_ready" -eq 1 ]; then
    cmd_doctor "$bs_requested" --client "$bs_client"
  elif [ -n "$bs_requested" ]; then
    cmd_context "$bs_requested"
  fi
  [ "$bs_ready" -eq 1 ] || printf '%s\n' 'Result: PASS'
}

cmd_uninstall() {
  force=${1:-}
  [ -z "$force" ] || [ "$force" = --force ] || { usage >&2; exit 2; }
  assert_install_paths
  assert_client_files
  PERSONAL_STAGE_ROOT=$(mktemp -d \
    "${TMPDIR:-/tmp}/beroka-governance-uninstall.XXXXXX") ||
    die GOVERNANCE_NOT_READY 'Cannot stage instruction removal'
  uninstall_stage=$PERSONAL_STAGE_ROOT
  codex_home=${CODEX_HOME:-$HOME/.codex}
  for uninstall_spec in \
    "codex-agents	$codex_home/AGENTS.md" \
    "codex-override	$codex_home/AGENTS.override.md" \
    "claude	$HOME/.claude/CLAUDE.md"
  do
    uninstall_name=${uninstall_spec%%	*}
    uninstall_path=${uninstall_spec#*	}
    assert_safe_user_path "$uninstall_path" "$uninstall_name instruction"
    [ ! -e "$uninstall_path" ] || {
      [ -f "$uninstall_path" ] && [ ! -L "$uninstall_path" ]
    } || {
      die GOVERNANCE_NOT_READY "Unsafe instruction file: $uninstall_path"
    }
    if [ -e "$uninstall_path" ]; then
      : >"$uninstall_stage/$uninstall_name" ||
        die GOVERNANCE_NOT_READY 'Cannot stage instruction removal'
      chmod 600 "$uninstall_stage/$uninstall_name" ||
        die GOVERNANCE_NOT_READY 'Cannot secure instruction removal stage'
      strip_managed_block "$uninstall_path" \
        "$uninstall_stage/$uninstall_name" ||
        die CLIENT_INSTRUCTION_CONFLICT \
          "Malformed managed block in $uninstall_path"
    fi
  done

  for uninstall_spec in \
    "codex-agents	$codex_home/AGENTS.md" \
    "codex-override	$codex_home/AGENTS.override.md" \
    "claude	$HOME/.claude/CLAUDE.md"
  do
    uninstall_name=${uninstall_spec%%	*}
    uninstall_path=${uninstall_spec#*	}
    [ -f "$uninstall_stage/$uninstall_name" ] || continue
    if [ -s "$uninstall_stage/$uninstall_name" ]; then
      apply_user_file "$uninstall_stage/$uninstall_name" \
        "$uninstall_path" "$uninstall_name instruction"
    else
      rm -f "$uninstall_path" ||
        die GOVERNANCE_NOT_READY "Cannot remove $uninstall_name instruction"
    fi
  done
  cleanup_personal_stage ||
    die GOVERNANCE_NOT_READY 'Cannot remove uninstall stage'
  remove_documentation_hooks
  rm -f "$BIN_DIR/$PROGRAM" || die GOVERNANCE_NOT_READY 'Cannot remove the user CLI'
  rm -rf "$DATA_ROOT" || die GOVERNANCE_NOT_READY 'Cannot remove package data'
  rm -f "$ACTIVE_RELEASE" "$CLIENTS_FILE" "$CURSOR_ACK_FILE" \
    "$GITHUB_ROLE_FILE" ||
    die GOVERNANCE_NOT_READY 'Cannot remove package configuration'
  rmdir "$CONFIG_ROOT" 2>/dev/null || :
  printf '%s\n' 'Result: PASS'
}
