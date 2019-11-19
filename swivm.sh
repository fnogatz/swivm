# SWI-Prolog Version Manager
# Implemented as a POSIX-compliant function
# Should work on sh, dash, bash, ksh, zsh
# To use source this file from your bash profile
#
# Implemented by Falco Nogatz <fnogatz@gmail.com>.
# Based on the Node Version Manager (nvm), by Tim
# Caswell <tim@creationix.com> and Matthew Ranney

{ # this ensures the entire script is downloaded #

SWIVM_SCRIPT_SOURCE="$_"

swivm_is_zsh() {
  [ -n "${ZSH_VERSION-}" ]
}

swivm_echo() {
  command printf %s\\n "$*" 2>/dev/null
}

swivm_cd() {
  \cd "$@"
}

swivm_err() {
  >&2 swivm_echo "$@"
}

swivm_grep() {
  GREP_OPTIONS='' command grep "$@"
}

swivm_has() {
  type "${1-}" > /dev/null 2>&1
}

swivm_is_alias() {
  # this is intentionally not "command alias" so it works in zsh.
  \alias "$1" > /dev/null 2>&1
}

swivm_has_colors() {
  local SWIVM_COLORS
  if swivm_has tput; then
    SWIVM_COLORS="$(tput -T "${TERM:-vt100}" colors)"
  fi
  [ "${SWIVM_COLORS:--1}" -ge 8 ]
}

swivm_download() {
  if swivm_has "curl"; then
    curl -q $*
  elif swivm_has "wget"; then
    # Emulate curl with wget
    ARGS=$(echo "$*" | command sed -e 's/--progress-bar /--progress=bar /' \
                           -e 's/-L //' \
                           -e 's/-I /--server-response /' \
                           -e 's/-s /-q /' \
                           -e 's/-o /-O /' \
                           -e 's/-C - /-c /')
    eval wget $ARGS
  fi
}

swivm_has_system() {
  [ "$(swivm deactivate >/dev/null 2>&1 && command -v swipl)" != '' ]
}

swivm_is_version_installed() {
  [ -n "${1-}" ] && [ -x "$(swivm_version_path "$1" 2>/dev/null)"/bin/swipl ]
}

# Make zsh glob matching behave same as bash
# This fixes the "zsh: no matches found" errors
if swivm_has "unsetopt"; then
  unsetopt nomatch 2>/dev/null
  SWIVM_CD_FLAGS="-q"
fi

# Auto detect the SWIVM_DIR when not set
if [ -z "$SWIVM_DIR" ]; then
  if [ -n "$BASH_SOURCE" ]; then
    SWIVM_SCRIPT_SOURCE="${BASH_SOURCE[0]}"
  fi
  SWIVM_DIR="$(cd $SWIVM_CD_FLAGS "$(dirname "${SWIVM_SCRIPT_SOURCE:-$0}")" > /dev/null && \pwd)"
  export SWIVM_DIR
fi
unset SWIVM_SCRIPT_SOURCE 2> /dev/null


# Setup mirror location if not already set
if [ -z "$SWIVM_MIRROR" ]; then
  export SWIVM_MIRROR="https://www.swi-prolog.org/download"
fi
if [ -z "$GITHUB_MIRROR" ]; then
  export GITHUB_MIRROR="https://github.com/SWI-Prolog"
fi

swivm_tree_contains_path() {
  local tree
  tree="$1"
  local swi_path
  swi_path="$2"

  if [ "@$tree@" = "@@" ] || [ "@$swi_path@" = "@@" ]; then
    >&2 echo "both the tree and the SWI-Prolog path are required"
    return 2
  fi

  local pathdir
  pathdir=$(dirname "$swi_path")
  while [ "$pathdir" != "" ] && [ "$pathdir" != "." ] && [ "$pathdir" != "/" ] && [ "$pathdir" != "$tree" ]; do
    pathdir=$(dirname "$pathdir")
  done
  [ "$pathdir" = "$tree" ]
}

# Traverse up in directory tree to find containing folder
swivm_find_up() {
  local path
  path=$PWD
  while [ "$path" != "" ] && [ ! -f "$path/$1" ]; do
    path=${path%/*}
  done
  echo "$path"
}


swivm_find_swivmrc() {
  local dir
  dir="$(swivm_find_up '.swivmrc')"
  if [ -e "$dir/.swivmrc" ]; then
    echo "$dir/.swivmrc"
  fi
}

# Obtain swivm version from rc file
swivm_rc_version() {
  export SWIVM_RC_VERSION=''
  local SWIVMRC_PATH
  SWIVMRC_PATH="$(swivm_find_swivmrc)"
  if [ ! -e "${SWIVMRC_PATH}" ]; then
    swivm_err "No .swivmrc file found"
    return 1
  fi
  SWIVM_RC_VERSION="$(command head -n 1 "${SWIVMRC_PATH}" | command tr -d '\r')" || command printf ''
  if [ -z "${SWIVM_RC_VERSION}" ]; then
    swivm_err "Warning: empty .swivmrc file found at \"${SWIVMRC_PATH}\""
    return 2
  fi
  swivm_echo "Found '${SWIVMRC_PATH}' with version <${SWIVM_RC_VERSION}>"
}

swivm_version_greater() {
  local LHS
  LHS="$(swivm_normalize_version "$1")"
  local RHS
  RHS="$(swivm_normalize_version "$2")"
  [ "$LHS" -gt "$RHS" ];
}

swivm_version_greater_than_or_equal_to() {
  local LHS
  LHS="$(swivm_normalize_version "$1")"
  local RHS
  RHS="$(swivm_normalize_version "$2")"
  [ "$LHS" -ge "$RHS" ];
}

swivm_version_dir() {
  local SWIVM_WHICH_DIR
  SWIVM_WHICH_DIR="$1"
  echo "$SWIVM_DIR/versions"
}

swivm_alias_path() {
  echo "$SWIVM_DIR/alias"
}

swivm_version_path() {
  local VERSION
  VERSION="$1"
  if [ -z "$VERSION" ]; then
    echo "version is required" >&2
    return 3
  else
    echo "$(swivm_version_dir)/$VERSION"
  fi
}

swivm_ensure_version_installed() {
  local PROVIDED_VERSION
  PROVIDED_VERSION="$1"
  local LOCAL_VERSION
  local EXIT_CODE
  LOCAL_VERSION="$(swivm_version "$PROVIDED_VERSION")"
  EXIT_CODE="$?"
  local SWIVM_VERSION_DIR
  if [ "_$EXIT_CODE" = "_0" ]; then
    SWIVM_VERSION_DIR="$(swivm_version_path "$LOCAL_VERSION")"
  fi
  if [ "_$EXIT_CODE" != "_0" ] || [ ! -d "$SWIVM_VERSION_DIR" ]; then
    VERSION="$(swivm_resolve_alias "$PROVIDED_VERSION")"
    if [ $? -eq 0 ]; then
      echo "N/A: version \"$PROVIDED_VERSION -> $VERSION\" is not yet installed" >&2
    else
      echo "N/A: version \"$PROVIDED_VERSION\" is not yet installed" >&2
    fi
    return 1
  fi
}

# Expand a version using the version cache
swivm_version() {
  local PATTERN
  PATTERN="${1-}"
  local VERSION
  # The default version is the current one
  if [ -z "${PATTERN}" ]; then
    PATTERN='current'
  fi

  if [ "${PATTERN}" = "current" ]; then
    swivm_ls_current
    return $?
  fi

  VERSION="$(swivm_ls "${PATTERN}" | command tail -1)"
  if [ -z "${VERSION}" ] || [ "_${VERSION}" = "_N/A" ]; then
    swivm_echo "N/A"
    return 3
  fi
  swivm_echo "${VERSION}"
}

swivm_remote_version() {
  local PATTERN
  PATTERN="${1-}"
  local VERSION
  if swivm_validate_implicit_alias "${PATTERN}" 2>/dev/null; then
    case "${PATTERN}" in
      *)
        VERSION="$(swivm_ls_remote "${PATTERN}")" &&:
      ;;
    esac
  else
    VERSION="$(swivm_remote_versions "${PATTERN}" | command tail -1)"
  fi
  if [ -n "${SWIVM_VERSION_ONLY-}" ]; then
    command awk 'BEGIN {
      n = split(ARGV[1], a);
      print a[1]
    }' "${VERSION}"
  else
    swivm_echo "${VERSION}"
  fi
  if [ "${VERSION}" = 'N/A' ]; then
    return 3
  fi
}

swivm_remote_versions() {
  local PATTERN
  PATTERN="$1"

  if swivm_validate_implicit_alias "$PATTERN" 2> /dev/null ; then
    echo >&2 "Implicit aliases are not supported in swivm_remote_versions."
    return 1
  fi
  VERSIONS="$(echo "$(swivm_ls_remote "$PATTERN")" | command grep -v "N/A" | command sed '/^$/d')"

  if [ -z "$VERSIONS" ]; then
    echo "N/A"
    return 3
  else
    echo "$VERSIONS"
  fi
}

swivm_is_valid_version() {
  if swivm_validate_implicit_alias "${1-}" 2>/dev/null; then
    return 0
  fi
  case "${1-}" in
    *)
      local VERSION
      VERSION="${1-}"
      swivm_version_greater_than_or_equal_to "${VERSION}" 0
    ;;
  esac
}

swivm_normalize_version() {
  echo "${1#v}" | command awk -F. '{ printf("%d%06d%06d\n", $1,$2,$3); }'
}

swivm_ensure_version_prefix() {
  local SWIVM_VERSION
  SWIVM_VERSION="$(echo "${1-}" | command sed -e 's/^\([0-9]\)/v\1/g')"
  swivm_echo "${SWIVM_VERSION}"
}

swivm_format_version() {
  local VERSION
  VERSION="$(swivm_ensure_version_prefix "${1-}")"
  local NUM_GROUPS
  NUM_GROUPS="$(swivm_num_version_groups "${VERSION}")"
  if [ "${NUM_GROUPS}" -lt 3 ]; then
    swivm_format_version "${VERSION%.}.0"
  else
    swivm_echo "${VERSION}" | command cut -f1-3 -d.
  fi
}

swivm_num_version_groups() {
  local VERSION
  VERSION="$1"
  VERSION="${VERSION#v}"
  VERSION="${VERSION%.}"
  if [ -z "$VERSION" ]; then
    echo "0"
    return
  fi
  local SWIVM_NUM_DOTS
  SWIVM_NUM_DOTS=$(echo "$VERSION" | command sed -e 's/[^\.]//g')
  local SWIVM_NUM_GROUPS
  SWIVM_NUM_GROUPS=".$SWIVM_NUM_DOTS" # add extra dot, since it's (n - 1) dots at this point
  echo "${#SWIVM_NUM_GROUPS}"
}

swivm_strip_path() {
  echo "$1" | command sed \
    -e "s#$SWIVM_DIR/[^/]*$2[^:]*:##g" \
    -e "s#:$SWIVM_DIR/[^/]*$2[^:]*##g" \
    -e "s#$SWIVM_DIR/[^/]*$2[^:]*##g" \
    -e "s#$SWIVM_DIR/versions/[^/]*$2[^:]*:##g" \
    -e "s#:$SWIVM_DIR/versions/[^/]*$2[^:]*##g" \
    -e "s#$SWIVM_DIR/versions/[^/]*$2[^:]*##g"
}

swivm_prepend_path() {
  if [ -z "$1" ]; then
    echo "$2"
  else
    echo "$2:$1"
  fi
}

swivm_change_path() {
  # if there’s no initial path, just return the supplementary path
  if [ -z "${1-}" ]; then
    swivm_echo "${3-}${2-}"
  # if the initial path doesn’t contain an swivm path, prepend the supplementary
  # path
  elif ! swivm_echo "${1-}" | swivm_grep -q "${SWIVM_DIR}/[^/]*${2-}" \
    && ! swivm_echo "${1-}" | swivm_grep -q "${SWIVM_DIR}/versions/[^/]*/[^/]*${2-}"; then
    swivm_echo "${3-}${2-}:${1-}"
  # if the initial path contains BOTH an swivm path (checked for above) and
  # that swivm path is preceded by a system binary path, just prepend the
  # supplementary path instead of replacing it.
  # https://github.com/nvm-sh/nvm/issues/1652#issuecomment-342571223
  elif swivm_echo "${1-}" | swivm_grep -Eq "(^|:)(/usr(/local)?)?${2-}:.*${SWIVM_DIR}/[^/]*${2-}" \
    || swivm_echo "${1-}" | swivm_grep -Eq "(^|:)(/usr(/local)?)?${2-}:.*${SWIVM_DIR}/versions/[^/]*/[^/]*${2-}"; then
    swivm_echo "${3-}${2-}:${1-}"
  # use sed to replace the existing swivm path with the supplementary path. This
  # preserves the order of the path.
  else
    swivm_echo "${1-}" | command sed \
      -e "s#${SWIVM_DIR}/[^/]*${2-}[^:]*#${3-}${2-}#" \
      -e "s#${SWIVM_DIR}/versions/[^/]*/[^/]*${2-}[^:]*#${3-}${2-}#"
  fi
}

swivm_print_formatted_alias() {
  local ALIAS
  ALIAS="${1-}"
  local DEST
  DEST="${2-}"
  local VERSION
  VERSION="${3-}"
  if [ -z "${VERSION}" ]; then
    VERSION="$(swivm_version "${DEST}")" ||:
  fi
  local VERSION_FORMAT
  local ALIAS_FORMAT
  local DEST_FORMAT
  ALIAS_FORMAT='%s'
  DEST_FORMAT='%s'
  VERSION_FORMAT='%s'
  local NEWLINE
  NEWLINE='\n'
  if [ "_${DEFAULT}" = '_true' ]; then
    NEWLINE=' (default)\n'
  fi
  local ARROW
  ARROW='->'
  if [ -z "${SWIVM_NO_COLORS}" ] && swivm_has_colors; then
    ARROW='\033[0;90m->\033[0m'
    if [ "_${DEFAULT}" = '_true' ]; then
      NEWLINE=' \033[0;37m(default)\033[0m\n'
    fi
    if [ "_${VERSION}" = "_${SWIVM_CURRENT-}" ]; then
      ALIAS_FORMAT='\033[0;32m%s\033[0m'
      DEST_FORMAT='\033[0;32m%s\033[0m'
      VERSION_FORMAT='\033[0;32m%s\033[0m'
    elif swivm_is_version_installed "${VERSION}"; then
      ALIAS_FORMAT='\033[0;34m%s\033[0m'
      DEST_FORMAT='\033[0;34m%s\033[0m'
      VERSION_FORMAT='\033[0;34m%s\033[0m'
    elif [ "${VERSION}" = '∞' ] || [ "${VERSION}" = 'N/A' ]; then
      ALIAS_FORMAT='\033[1;31m%s\033[0m'
      DEST_FORMAT='\033[1;31m%s\033[0m'
      VERSION_FORMAT='\033[1;31m%s\033[0m'
    fi
  elif [ "_${VERSION}" != '_∞' ] && [ "_${VERSION}" != '_N/A' ]; then
    VERSION_FORMAT='%s *'
  fi
  if [ "${DEST}" = "${VERSION}" ]; then
    command printf -- "${ALIAS_FORMAT} ${ARROW} ${VERSION_FORMAT}${NEWLINE}" "${ALIAS}" "${DEST}"
  else
    command printf -- "${ALIAS_FORMAT} ${ARROW} ${DEST_FORMAT} (${ARROW} ${VERSION_FORMAT})${NEWLINE}" "${ALIAS}" "${DEST}" "${VERSION}"
  fi
}

swivm_print_alias_path() {
  local SWIVM_ALIAS_DIR
  SWIVM_ALIAS_DIR="${1-}"
  if [ -z "${SWIVM_ALIAS_DIR}" ]; then
    swivm_err 'An alias dir is required.'
    return 1
  fi
  local ALIAS_PATH
  ALIAS_PATH="${2-}"
  if [ -z "${ALIAS_PATH}" ]; then
    swivm_err 'An alias path is required.'
    return 2
  fi
  local ALIAS
  ALIAS="${ALIAS_PATH##${SWIVM_ALIAS_DIR}\/}"
  local DEST
  DEST="$(swivm_alias "${ALIAS}" 2>/dev/null)" ||:
  if [ -n "${DEST}" ]; then
    SWIVM_NO_COLORS="${SWIVM_NO_COLORS-}" DEFAULT=false swivm_print_formatted_alias "${ALIAS}" "${DEST}"
  fi
}

swivm_print_default_alias() {
  local ALIAS
  ALIAS="${1-}"
  if [ -z "${ALIAS}" ]; then
    swivm_err 'A default alias is required.'
    return 1
  fi
  local DEST
  DEST="$(swivm_print_implicit_alias local "${ALIAS}")"
  if [ -n "${DEST}" ]; then
    SWIVM_NO_COLORS="${SWIVM_NO_COLORS-}" DEFAULT=true swivm_print_formatted_alias "${ALIAS}" "${DEST}"
  fi
}

swivm_make_alias() {
  local ALIAS
  ALIAS="${1-}"
  if [ -z "${ALIAS}" ]; then
    swivm_err "an alias name is required"
    return 1
  fi
  local VERSION
  VERSION="${2-}"
  if [ -z "${VERSION}" ]; then
    swivm_err "an alias target version is required"
    return 2
  fi
  swivm_echo "${VERSION}" | tee "$(swivm_alias_path)/${ALIAS}" >/dev/null
}

swivm_list_aliases() {
  local ALIAS
  ALIAS="${1-}"

  local SWIVM_CURRENT
  SWIVM_CURRENT="$(swivm_ls_current)"
  local SWIVM_ALIAS_DIR
  SWIVM_ALIAS_DIR="$(swivm_alias_path)"
  command mkdir -p "${SWIVM_ALIAS_DIR}"

  (
    local ALIAS_PATH
    for ALIAS_PATH in "${SWIVM_ALIAS_DIR}/${ALIAS}"*; do
      SWIVM_NO_COLORS="${SWIVM_NO_COLORS-}" SWIVM_CURRENT="${SWIVM_CURRENT}" swivm_print_alias_path "${SWIVM_ALIAS_DIR}" "${ALIAS_PATH}" &
    done
    wait
  ) | sort

  (
    local ALIAS_NAME
    for ALIAS_NAME in "stable" "devel"; do
      {
        if [ ! -f "${SWIVM_ALIAS_DIR}/${ALIAS_NAME}" ] && { [ -z "${ALIAS}" ] || [ "${ALIAS_NAME}" = "${ALIAS}" ]; }; then
          SWIVM_NO_COLORS="${SWIVM_NO_COLORS-}" SWIVM_CURRENT="${SWIVM_CURRENT}" swivm_print_default_alias "${ALIAS_NAME}"
        fi
      } &
    done
    wait
  ) | sort
  return
}

swivm_alias() {
  local ALIAS
  ALIAS="$1"
  if [ -z "$ALIAS" ]; then
    echo >&2 'An alias is required.'
    return 1
  fi

  local SWIVM_ALIAS_PATH
  SWIVM_ALIAS_PATH="$(swivm_alias_path)/$ALIAS"
  if [ ! -f "$SWIVM_ALIAS_PATH" ]; then
    echo >&2 'Alias does not exist.'
    return 2
  fi

  command cat "$SWIVM_ALIAS_PATH"
}

swivm_ls_current() {
  local SWIVM_LS_CURRENT_PATH
  if ! SWIVM_LS_CURRENT_PATH="$(command which swipl 2>/dev/null)"; then
    swivm_echo 'none'
  elif swivm_tree_contains_path "${SWIVM_DIR}" "${SWIVM_LS_CURRENT_PATH}"; then
    local VERSION
    VERSION="$(swipl --version | sed -E "s/^.* ([0-9]+(\.[0-9]+)*) .*$/\1/g" 2>/dev/null)"
    swivm_echo "v${VERSION}"
  else
    swivm_echo 'system'
  fi
}

swivm_resolve_alias() {
  if [ -z "${1-}" ]; then
    return 1
  fi

  local PATTERN
  PATTERN="${1-}"

  local ALIAS
  ALIAS="${PATTERN}"
  local ALIAS_TEMP

  local SEEN_ALIASES
  SEEN_ALIASES="${ALIAS}"
  while true; do
    ALIAS_TEMP="$(swivm_alias "${ALIAS}" 2>/dev/null || swivm_echo)"

    if [ -z "${ALIAS_TEMP}" ]; then
      break
    fi

    if command printf "${SEEN_ALIASES}" | swivm_grep -q -e "^${ALIAS_TEMP}$"; then
      ALIAS="∞"
      break
    fi

    SEEN_ALIASES="${SEEN_ALIASES}\\n${ALIAS_TEMP}"
    ALIAS="${ALIAS_TEMP}"
  done

  if [ -n "${ALIAS}" ] && [ "_${ALIAS}" != "_${PATTERN}" ]; then
    case "${ALIAS}" in
      '∞')
        swivm_echo "${ALIAS}"
      ;;
      *)
        swivm_ensure_version_prefix "${ALIAS}"
      ;;
    esac
    return 0
  fi

  if swivm_validate_implicit_alias "${PATTERN}" 2>/dev/null; then
    local IMPLICIT
    IMPLICIT="$(swivm_print_implicit_alias local "${PATTERN}" 2>/dev/null)"
    if [ -n "${IMPLICIT}" ]; then
      swivm_ensure_version_prefix "${IMPLICIT}"
    fi
  fi

  return 2
}

swivm_resolve_local_alias() {
  if [ -z "$1" ]; then
    return 1
  fi

  local VERSION
  local EXIT_CODE
  VERSION="$(swivm_resolve_alias "$1")"
  EXIT_CODE=$?
  if [ -z "$VERSION" ]; then
    return $EXIT_CODE
  fi
  if [ "_$VERSION" != "_∞" ]; then
    swivm_version "$VERSION"
  else
    echo "$VERSION"
  fi
}

swivm_version_mode() {
  local VERSION
  VERSION="$1"
  local NORMALIZED_VERSION
  NORMALIZED_VERSION="$(swivm_normalize_version "$VERSION")"
  local MOD
  MOD=$(expr "$NORMALIZED_VERSION" \/ 1000000 \% 2)
  local MODE
  MODE='stable'
  if [ "$MOD" -eq 1 ]; then
    MODE='devel'
  fi
  echo "$MODE"
}

swivm_is_stable_version() {
  local VERSION
  VERSION="$1"
  local MODE
  MODE="$(swivm_version_mode "$VERSION")"
  if [ "_$MODE" = "_stable" ]; then
    return 0
  fi
  return 1
}

swivm_ls() {
  local PATTERN
  PATTERN="${1-}"
  local VERSIONS
  VERSIONS=''
  if [ "${PATTERN}" = 'current' ]; then
    swivm_ls_current
    return
  fi

  case "${PATTERN}" in
    *)
      if swivm_resolve_local_alias "${PATTERN}"; then
        return
      fi
      PATTERN="$(swivm_ensure_version_prefix "${PATTERN}")"
    ;;
  esac
  if [ "${PATTERN}" = 'N/A' ]; then
    return
  fi
  # If it looks like an explicit version, don't do anything funny
  local SWIVM_PATTERN_STARTS_WITH_V
  case $PATTERN in
    v*) SWIVM_PATTERN_STARTS_WITH_V=true ;;
    *) SWIVM_PATTERN_STARTS_WITH_V=false ;;
  esac
  if [ $SWIVM_PATTERN_STARTS_WITH_V = true ] && [ "_$(swivm_num_version_groups "${PATTERN}")" = "_3" ]; then
    if swivm_is_version_installed "${PATTERN}"; then
      VERSIONS="${PATTERN}"
    fi
  else
    case "${PATTERN}" in
      "system") ;;
      *)
        local NUM_VERSION_GROUPS
        NUM_VERSION_GROUPS="$(swivm_num_version_groups "${PATTERN}")"
        if [ "${NUM_VERSION_GROUPS}" = "2" ] || [ "${NUM_VERSION_GROUPS}" = "1" ]; then
          PATTERN="${PATTERN%.}."
        fi
      ;;
    esac

    swivm_is_zsh && setopt local_options shwordsplit

    local SWIVM_DIRS_TO_SEARCH1
    SWIVM_DIRS_TO_SEARCH1=''
    SWIVM_ADD_SYSTEM=false

    SWIVM_DIRS_TO_SEARCH="$(swivm_version_dir)"
    if swivm_has_system ; then
      SWIVM_ADD_SYSTEM=true
    fi

    if ! [ -d "${SWIVM_DIRS_TO_SEARCH}" ] || ! (command ls -1qA "${SWIVM_DIRS_TO_SEARCH}" | swivm_grep -q .); then
      SWIVM_DIRS_TO_SEARCH=''
    fi

    local SEARCH_PATTERN
    if [ -z "${PATTERN}" ]; then
      PATTERN='v'
      SEARCH_PATTERN='.*'
    else
      SEARCH_PATTERN="$(swivm_echo "${PATTERN}" | command sed 's#\.#\\\.#g;')"
    fi

    if [ -n "${SWIVM_DIRS_TO_SEARCH}" ]; then
      VERSIONS="$(command find "${SWIVM_DIRS_TO_SEARCH}"/* -name . -o -type d -prune -o -path "${PATTERN}*" \
        | command sed -e "
            s#^${SWIVM_DIR}/##;
            \\#^[^v]# d;
            \\#^versions\$# d;
            s#^versions/##;
            \\#${SEARCH_PATTERN}# !d;
          " \
          -e 's#^\([^/]\{1,\}\)/\(.*\)$#\2.\1#;' \
        | command sort -t. -u -k 1.2,1n -k 2,2n -k 3,3n \
      )"
    fi
  fi

  if [ "${SWIVM_ADD_SYSTEM-}" = true ]; then
    if [ -z "${PATTERN}" ] || [ "${PATTERN}" = 'v' ]; then
      VERSIONS="${VERSIONS}$(command printf '\n%s' 'system')"
    elif [ "${PATTERN}" = 'system' ]; then
      VERSIONS="$(command printf '%s' 'system')"
    fi
  fi

  if [ -z "${VERSIONS}" ]; then
    swivm_echo 'N/A'
    return 3
  fi

  swivm_echo "${VERSIONS}"
}

swivm_ls_remote() {
  local PATTERN
  PATTERN="${1-}"
  if swivm_validate_implicit_alias "${PATTERN}" 2>/dev/null ; then
    local IMPLICIT
    IMPLICIT="$(swivm_print_implicit_alias remote "${PATTERN}")"
    if [ -z "${IMPLICIT-}" ] || [ "${IMPLICIT}" = 'N/A' ]; then
      swivm_echo "N/A"
      return 3
    fi
    PATTERN="$(swivm_ls_remote "${IMPLICIT}" | command tail -1 | command awk '{ print $1 }')"
  elif [ -n "${PATTERN}" ]; then
    PATTERN="$(swivm_ensure_version_prefix "${PATTERN}")"
  else
    PATTERN=".*"
  fi

  swivm_ls_remote_index "$SWIVM_MIRROR" "${PATTERN}"
}

swivm_ls_remote_index() {
  if [ "$#" -lt 2 ]; then
    echo "not enough arguments" >&2
    return 5
  fi
  local PREFIX
  PREFIX=''
  local SORT_COMMAND
  SORT_COMMAND='sort -t. -u -k 1,1n -k 2,2n -k 3,3n'
  local MIRROR
  MIRROR="$1"
  local PATTERN
  PATTERN="$2"
  local VERSIONS
  if [ -z "$PATTERN" ]; then
    PATTERN=".*"
  fi
  ZHS_HAS_SHWORDSPLIT_UNSET=1
  if swivm_has "setopt"; then
    ZHS_HAS_SHWORDSPLIT_UNSET=$(setopt | command grep shwordsplit > /dev/null ; echo $?)
    setopt shwordsplit
  fi
  VERSIONS="$(swivm_download -L -s "$MIRROR/devel/src/" "$MIRROR/stable/src/" -o - \
    | command grep -E 'a href=\"(swi)?pl\-' \
    | command sed -E 's/^.*a href="(swi)?pl\-(.*)\.tar\.gz".*$/\2/' \
    | command sed -E 's/^/v/' \
    | command grep -w "^$PATTERN" \
    | command sed -E 's/^v//' \
    | $SORT_COMMAND \
    | command sed -E 's/^/v/')"
  if [ "$ZHS_HAS_SHWORDSPLIT_UNSET" -eq 1 ] && swivm_has "unsetopt"; then
    unsetopt shwordsplit
  fi
  if [ -z "$VERSIONS" ]; then
    echo "N/A"
    return 3
  fi
  echo "$VERSIONS"
}

swivm_print_versions() {
  local VERSION
  local FORMAT
  local SWIVM_CURRENT
  SWIVM_CURRENT=$(swivm_ls_current)
  local SWIVM_HAS_COLORS
  if [ -z "${SWIVM_NO_COLORS-}" ] && swivm_has_colors; then
    SWIVM_HAS_COLORS=1
  fi
  swivm_echo "${1-}" \
  | command sed '1!G;h;$!d' \
  | command sed '1!G;h;$!d' \
  | while read -r VERSION_LINE; do
    VERSION="${VERSION_LINE%% *}"
    FORMAT='%15s'
    if [ "_${VERSION}" = "_${SWIVM_CURRENT}" ]; then
      if [ "${SWIVM_HAS_COLORS-}" = '1' ]; then
        FORMAT='\033[0;32m-> %12s\033[0m'
      else
        FORMAT='-> %12s *'
      fi
    elif [ "${VERSION}" = "system" ]; then
      if [ "${SWIVM_HAS_COLORS-}" = '1' ]; then
        FORMAT='\033[0;33m%15s\033[0m'
      else
        FORMAT='%15s *'
      fi
    elif swivm_is_version_installed "${VERSION}"; then
      if [ "${SWIVM_HAS_COLORS-}" = '1' ]; then
        FORMAT='\033[0;34m%15s\033[0m'
      else
        FORMAT='%15s *'
      fi
    fi
    command printf -- "${FORMAT}\\n" "${VERSION}"
  done
}

swivm_validate_implicit_alias() {
  case "$1" in
    "stable" | "devel" )
      return
    ;;
    *)
      echo "Only implicit aliases 'stable' and 'devel' are supported." >&2
      return 1
    ;;
  esac
}

swivm_print_implicit_alias() {
  if [ "_$1" != "_local" ] && [ "_$1" != "_remote" ]; then
    echo "swivm_print_implicit_alias must be specified with local or remote as the first argument." >&2
    return 1
  fi

  local SWIVM_IMPLICIT
  SWIVM_IMPLICIT="$2"
  if ! swivm_validate_implicit_alias "$SWIVM_IMPLICIT"; then
    return 2
  fi

  local ZHS_HAS_SHWORDSPLIT_UNSET

  local SWIVM_COMMAND
  local SWIVM_ADD_PREFIX_COMMAND
  local LAST_TWO

  SWIVM_COMMAND="swivm_ls_remote"
  if [ "_$1" = "_local" ]; then
    SWIVM_COMMAND="swivm_ls"
  fi

  ZHS_HAS_SHWORDSPLIT_UNSET=1
  if swivm_has "setopt"; then
    ZHS_HAS_SHWORDSPLIT_UNSET=$(setopt | command grep shwordsplit > /dev/null ; echo $?)
    setopt shwordsplit
  fi

  LAST_TWO=$($SWIVM_COMMAND | command cut -d . -f 1,2 | uniq)

  if [ "$ZHS_HAS_SHWORDSPLIT_UNSET" -eq 1 ] && swivm_has "unsetopt"; then
    unsetopt shwordsplit
  fi

  local MINOR
  local STABLE
  local UNSTABLE
  local MOD

  ZHS_HAS_SHWORDSPLIT_UNSET=1
  if swivm_has "setopt"; then
    ZHS_HAS_SHWORDSPLIT_UNSET=$(setopt | command grep shwordsplit > /dev/null ; echo $?)
    setopt shwordsplit
  fi
  for MINOR in $LAST_TWO; do
    MOD="$(swivm_version_mode "$MINOR")"
# TODO
    NORMALIZED_VERSION="$(swivm_normalize_version "$MINOR")"
    MOD=$(expr "$NORMALIZED_VERSION" \/ 1000000 \% 2)
    if [ "$MOD" -eq 0 ]; then
      STABLE="$MINOR"
    elif [ "$MOD" -eq 1 ]; then
      UNSTABLE="$MINOR"
    fi
  done
  if [ "$ZHS_HAS_SHWORDSPLIT_UNSET" -eq 1 ] && swivm_has "unsetopt"; then
    unsetopt shwordsplit
  fi

  if [ "_$2" = '_stable' ]; then
    echo "${STABLE}"
  elif [ "_$2" = '_devel' ]; then
    echo "${UNSTABLE}"
  fi
}

swivm_get_os() {
  local SWIVM_UNAME
  SWIVM_UNAME="$(uname -a)"
  local SWIVM_OS
  case "$SWIVM_UNAME" in
    Linux\ *) SWIVM_OS=linux ;;
    Darwin\ *) SWIVM_OS=darwin ;;
    SunOS\ *) SWIVM_OS=sunos ;;
    FreeBSD\ *) SWIVM_OS=freebsd ;;
  esac
  echo "$SWIVM_OS"
}

swivm_get_arch() {
  local HOST_ARCH
  local SWIVM_OS
  local EXIT_CODE

  SWIVM_OS="$(swivm_get_os)"
  # If the OS is SunOS, first try to use pkgsrc to guess
  # the most appropriate arch. If it's not available, use
  # isainfo to get the instruction set supported by the
  # kernel.
  if [ "_$SWIVM_OS" = "_sunos" ]; then
    HOST_ARCH=$(pkg_info -Q MACHINE_ARCH pkg_install)
    EXIT_CODE=$?
    if [ $EXIT_CODE -ne 0 ]; then
      HOST_ARCH=$(isainfo -n)
    fi
  else
     HOST_ARCH="$(uname -m)"
  fi

  local SWIVM_ARCH
  case "$HOST_ARCH" in
    x86_64 | amd64) SWIVM_ARCH="x64" ;;
    i*86) SWIVM_ARCH="x86" ;;
    *) SWIVM_ARCH="$HOST_ARCH" ;;
  esac
  echo "$SWIVM_ARCH"
}

swivm_ensure_default_set() {
  local VERSION
  VERSION="$1"
  if [ -z "$VERSION" ]; then
    echo 'swivm_ensure_default_set: a version is required' >&2
    return 1
  fi
  if swivm_alias default >/dev/null 2>&1; then
    # default already set
    return 0
  fi
  local OUTPUT
  OUTPUT="$(swivm alias default "$VERSION")"
  local EXIT_CODE
  EXIT_CODE="$?"
  echo "Creating default alias: $OUTPUT"
  return $EXIT_CODE
}

swivm_get_make_jobs() {
  if swivm_is_natural_num "${1-}"; then
    SWIVM_MAKE_JOBS="$1"
    swivm_echo "number of \`make\` jobs: ${SWIVM_MAKE_JOBS}"
    return
  elif [ -n "${1-}" ]; then
    unset SWIVM_MAKE_JOBS
    swivm_err "$1 is invalid for number of \`make\` jobs, must be a natural number"
  fi
  local SWIVM_OS
  SWIVM_OS="$(swivm_get_os)"
  local SWIVM_CPU_CORES
  case "_${SWIVM_OS}" in
    "_linux")
      SWIVM_CPU_CORES="$(swivm_grep -c -E '^processor.+: [0-9]+' /proc/cpuinfo)"
    ;;
    "_freebsd" | "_darwin")
      SWIVM_CPU_CORES="$(sysctl -n hw.ncpu)"
    ;;
    "_sunos")
      SWIVM_CPU_CORES="$(psrinfo | wc -l)"
    ;;
    "_aix")
      SWIVM_CPU_CORES="$(pmcycles -m | wc -l)"
    ;;
  esac
  if ! swivm_is_natural_num "${SWIVM_CPU_CORES}"; then
    swivm_err 'Can not determine how many core(s) are available, running in single-threaded mode.'
    swivm_err 'Please report an issue on GitHub to help us make swivm run faster on your computer!'
    SWIVM_MAKE_JOBS=1
  else
    swivm_echo "Detected that you have ${SWIVM_CPU_CORES} CPU core(s)"
    if [ "${SWIVM_CPU_CORES}" -gt 2 ]; then
      SWIVM_MAKE_JOBS=$((SWIVM_CPU_CORES - 1))
      swivm_echo "Running with ${SWIVM_MAKE_JOBS} threads to speed up the build"
    else
      SWIVM_MAKE_JOBS=1
      swivm_echo 'Number of CPU core(s) less than or equal to 2, running in single-threaded mode'
    fi
  fi
}

swivm_install() {
  local VERSION
  VERSION="$1"

  local SWIVM_MAKE_JOBS
  SWIVM_MAKE_JOBS="${2-}"

  local ADDITIONAL_PARAMETERS
  ADDITIONAL_PARAMETERS="$3"

  if [ -n "$ADDITIONAL_PARAMETERS" ]; then
    echo "Additional options while compiling: $ADDITIONAL_PARAMETERS"
  fi

  local VERSION_PATH
  VERSION_PATH="$(swivm_version_path "$VERSION")"
  local SWIVM_OS
  SWIVM_OS="$(swivm_get_os)"
  local MODE
  MODE="$(swivm_version_mode "$VERSION")"

  local tarball
  tarball=''
  local make
  make='make'
  if [ "_$SWIVM_OS" = "_freebsd" ]; then
    make='gmake'
    MAKE_CXX="CXX=c++"
  fi
  local tmpdir
  tmpdir="$SWIVM_DIR/src"
  local tmptarball
  tmptarball="$tmpdir/swipl-$VERSION.tar.gz"

  local VERSION_WITHOUT_V
  VERSION_WITHOUT_V="${VERSION:1}"
  if [ "$(swivm_download -L -s -I "$SWIVM_MIRROR/$MODE/src/swipl-$VERSION_WITHOUT_V.tar.gz" -o - | command grep '200 OK\|HTTP/2 200')" != '' ]; then
    tarball="$SWIVM_MIRROR/$MODE/src/swipl-$VERSION_WITHOUT_V.tar.gz"
  elif [ "$(swivm_download -L -s -I "$SWIVM_MIRROR/$MODE/src/pl-$VERSION_WITHOUT_V.tar.gz" -o - | command grep '200 OK\|HTTP/2 200')" != '' ]; then
    tarball="$SWIVM_MIRROR/$MODE/src/pl-$VERSION_WITHOUT_V.tar.gz"
  elif [ "$(swivm_download -L -s -I "$GITHUB_MIRROR/swipl-devel/archive/V$VERSION_WITHOUT_V.tar.gz" -o - 2>&1 | command grep '200 OK\|HTTP/2 200')" != '' ]; then
    tarball="$GITHUB_MIRROR/swipl-devel/archive/V$VERSION_WITHOUT_V.tar.gz"
  fi

  local SRC_PATH
  if ! (
    [ -n "$tarball" ] && \
    command mkdir -p "$tmpdir" && \
    echo "Downloading $tarball..." && \
    swivm_download -L --progress-bar "$tarball" -o "$tmptarball" && \
    command tar -xzf "$tmptarball" -C "$tmpdir" && \
    command mkdir -p "$SWIVM_DIR/versions" && \
    ( mv "$tmpdir/swipl-$VERSION_WITHOUT_V" "$VERSION_PATH" >/dev/null 2>&1 || \
      mv "$tmpdir/pl-$VERSION_WITHOUT_V" "$VERSION_PATH" >/dev/null 2>&1 || \
      mv "$tmpdir/swipl-devel-$VERSION_WITHOUT_V" "$VERSION_PATH" >/dev/null 2>&1 \
    ) && \
    cd "$VERSION_PATH" && \
    ( ([ "$tarball" = "$GITHUB_MIRROR/swipl-devel/archive/V$VERSION.tar.gz" ] && \
      # downloaded from GitHub \
      echo "Downloading packages..." && \
      swivm_download_git_submodules "$VERSION" \
    ) || true) && \
    cd "$VERSION_PATH" && \
    ( ([[ -f CMakeLists.txt ]] && \
      export SWIPL_INSTALL_PREFIX="$VERSION_PATH" && \
      mkdir build && \
      cd build && \
      cmake .. && \
      make -j "${SWIVM_MAKE_JOBS}" && \
      make -j "${SWIVM_MAKE_JOBS}" install \
    ) || ( \
      echo "### [SWIVM] Prepare Installation Template ###" && \
      sed -e "s@PREFIX=\$HOME@PREFIX=$VERSION_PATH@g" build.templ > build.templ.2 && \
      sed -e "s@MAKE=make@MAKE=$make@g" build.templ.2 > build && \
      rm build.templ.2 && \
      chmod +x build && \
      echo "### [SWIVM] Prepare SWI-Prolog ###" && \
      ./prepare --yes --all && \
      echo "### [SWIVM] Build SWI-Prolog ###" && \
      ./build && \
      cd packages && \
      echo "### [SWIVM] Configure Packages ###" && \
      ./configure && \
      $MAKE && \
      echo "### [SWIVM] Install Packages ###" && \
      make install )) \
    )
  then
    echo "swivm: install $VERSION failed!" >&2
    return 1
  fi

  return $?
}

swivm_download_git_submodules() {
  local VERSION
  VERSION="$1"

  local VERSION_PATH
  VERSION_PATH="$(swivm_version_path "$VERSION")"

  local tmpdir
  tmpdir="$VERSION_PATH/packages/src"

  local tmptarball

  command mkdir -p "$tmpdir"

  command sed -e '/^\[submodule .*\]$/ {
    N; /\n.*path = .*$/ {
      N; /\n.*url = .*$/ {
        s/\[submodule "\(.*\)"\]\n.*path = \(.*\)\n.*url = \.\.\/\(.*\)\.git$/\1 \2 \3/
      }
    }
  }' "$VERSION_PATH/.gitmodules" | while read -r SUB_NAME SUB_PATH SUB_URL; do
    if [[ "$SUB_NAME" != packages* ]]; then
      # only packages
      continue
    fi

    # remove currently empty directory if exists
    if [ -d "$VERSION_PATH/$SUB_NAME" ]; then command rmdir "$VERSION_PATH/$SUB_NAME"; fi

    tmptarball="$tmpdir/$SUB_URL.tar.gz"

    echo "Downloading package $SUB_NAME..." && \
    swivm_download -L --progress-bar "$GITHUB_MIRROR/$SUB_URL/archive/V$VERSION.tar.gz" -o "$tmptarball"
    command tar -xzf "$tmptarball" -C "$VERSION_PATH/packages"
    command mv "$VERSION_PATH/packages/$SUB_URL-$VERSION" "$VERSION_PATH/$SUB_NAME"

  done

  return $?
}

swivm_match_version() {
  local PROVIDED_VERSION
  PROVIDED_VERSION="$1"
  case "_${PROVIDED_VERSION}" in
    '_system')
      swivm_echo 'system'
    ;;
    *)
      swivm_version "${PROVIDED_VERSION}"
    ;;
  esac
}

swivm_die_on_prefix() {
  local SWIVM_DELETE_PREFIX
  SWIVM_DELETE_PREFIX="$1"
  case "$SWIVM_DELETE_PREFIX" in
    0|1) ;;
    *)
      echo >&2 'First argument "delete the prefix" must be zero or one'
      return 1
    ;;
  esac
  local SWIVM_COMMAND
  SWIVM_COMMAND="$2"
  if [ -z "$SWIVM_COMMAND" ]; then
    echo >&2 'Second argument "swivm command" must be nonempty'
    return 2
  fi

  if [ -n "$PREFIX" ] && ! (swivm_tree_contains_path "$SWIVM_DIR" "$PREFIX" >/dev/null 2>&1); then
    swivm deactivate >/dev/null 2>&1
    echo >&2 "swivm is not compatible with the \"PREFIX\" environment variable: currently set to \"$PREFIX\""
    echo >&2 "Run \`unset PREFIX\` to unset it."
    return 3
  fi
}

swivm_is_natural_num() {
  if [ -z "$1" ]; then
    return 4
  fi
  case "$1" in
    0) return 1 ;;
    -*) return 3 ;; # some BSDs return false positives for double-negated args
    *)
      [ "$1" -eq "$1" ] 2>/dev/null # returns 2 if it doesn't match
    ;;
  esac
}

swivm_sanitize_path() {
  local SANITIZED_PATH
  SANITIZED_PATH="$1"
  if [ "_$1" != "_$SWIVM_DIR" ]; then
    SANITIZED_PATH="$(echo "$SANITIZED_PATH" | command sed "s#$SWIVM_DIR#\$SWIVM_DIR#g")"
  fi
  echo "$SANITIZED_PATH" | command sed "s#$HOME#\$HOME#g"
}

swivm() {
  if [ $# -lt 1 ]; then
    swivm --help
    return
  fi

  local DEFAULT_IFS
  DEFAULT_IFS=" $(swivm_echo t | command tr t \\t)
"
  if [ "${-#*e}" != "$-" ]; then
    set +e
    local EXIT_CODE
    IFS="${DEFAULT_IFS}" swivm "$@"
    EXIT_CODE=$?
    set -e
    return $EXIT_CODE
  elif [ "${IFS}" != "${DEFAULT_IFS}" ]; then
    IFS="${DEFAULT_IFS}" swivm "$@"
    return $?
  fi

  local COMMAND
  COMMAND="${1-}"
  shift

  # initialize local variables
  local VERSION
  local ADDITIONAL_PARAMETERS

  case $COMMAND in
    "help" )
      echo
      echo "SWI-Prolog Version Manager"
      echo
      echo 'Note: <version> refers to any version-like string swivm understands. This includes:'
      echo '  - full or partial version numbers, starting with an optional "v" (6.6, v7.2.3, v5)'
      echo "  - default (built-in) aliases: stable, devel, system"
      echo '  - custom aliases you define with `swivm alias foo`'
      echo
      echo 'Usage:'
      echo '  swivm help                                  Show this message'
      echo '  swivm --version                             Print out the latest released version of swivm'
      echo '  swivm install <version>                     Download and install a <version>. Uses .swivmrc if available'
      echo '  swivm uninstall <version>                   Uninstall a version'
      echo '  swivm use [--silent] <version>              Modify PATH to use <version>. Uses .swivmrc if available'
      echo '  swivm exec [--silent] <version> [<command>] Run <command> on <version>. Uses .swivmrc if available'
      echo '  swivm run [--silent] <version> [<args>]     Run `swipl` on <version> with <args> as arguments. Uses .swivmrc if available'
      echo '  swivm current                               Display currently activated version'
      echo '  swivm ls                                    List installed versions'
      echo '  swivm ls <version>                          List versions matching a given description'
      echo '  swivm ls-remote                             List remote versions available for install'
      echo '  swivm version <version>                     Resolve the given description to a single local version'
      echo '  swivm version-remote <version>              Resolve the given description to a single remote version'
      echo '  swivm deactivate                            Undo effects of `swivm` on current shell'
      echo '  swivm alias [<pattern>]                     Show all aliases beginning with <pattern>'
      echo '  swivm alias <name> <version>                Set an alias named <name> pointing to <version>'
      echo '  swivm unalias <name>                        Deletes the alias named <name>'
      echo '  swivm unload                                Unload `swivm` from shell'
      echo '  swivm which [<version>]                     Display path to installed SWI-Prolog version. Uses .swivmrc if available'
      echo
      echo 'Example:'
      echo '  swivm install v6.6.2                        Install a specific version number'
      echo '  swivm use 7                                 Use the latest available 7.x.x release'
      echo '  swivm run v8.0 example.pl                   Run example.pl using latest SWI-Prolog 8.0.x'
      echo '  swivm exec 6.6.2 swipl example.pl           Run `swipl example.pl` with the PATH pointing to SWI-Prolog v6.6.2'
      echo '  swivm alias default 6.6.2                   Set default SWI-Prolog version on a shell'
      echo
      echo 'Note:'
      echo '  to remove, delete, or uninstall swivm - just remove the `$SWIVM_DIR` folder (usually `~/.swivm`)'
      echo
    ;;

    "debug" )
      local ZHS_HAS_SHWORDSPLIT_UNSET
      if swivm_has "setopt"; then
        ZHS_HAS_SHWORDSPLIT_UNSET=$(setopt | command grep shwordsplit > /dev/null ; echo $?)
        setopt shwordsplit
      fi
      echo >&2 "swivm --version: v$(swivm --version)"
      echo >&2 "\$SHELL: $SHELL"
      echo >&2 "\$HOME: $HOME"
      echo >&2 "\$SWIVM_DIR: '$(swivm_sanitize_path "$SWIVM_DIR")'"
      echo >&2 "\$PREFIX: '$(swivm_sanitize_path "$PREFIX")'"
      local SWIVM_DEBUG_OUTPUT
      for SWIVM_DEBUG_COMMAND in 'swivm current' 'which swipl'
      do
        SWIVM_DEBUG_OUTPUT="$($SWIVM_DEBUG_COMMAND 2>&1)"
        echo >&2 "$SWIVM_DEBUG_COMMAND: $(swivm_sanitize_path "$SWIVM_DEBUG_OUTPUT")"
      done
      if [ "$ZHS_HAS_SHWORDSPLIT_UNSET" -eq 1 ] && swivm_has "unsetopt"; then
        unsetopt shwordsplit
      fi
      return 42
    ;;

    "install" | "i")
      local version_not_provided
      version_not_provided=0
      local SWIVM_OS
      SWIVM_OS="$(swivm_get_os)"

      if ! swivm_has "curl" && ! swivm_has "wget"; then
        swivm_err 'swivm needs curl or wget to proceed.'
        return 1
      fi

      if [ $# -lt 1 ]; then
        version_not_provided=1
      fi

      while [ $# -ne 0 ]; do
        case "$1" in
          ---*)
            swivm_err 'arguments with `---` are not supported - this is likely a typo'
            return 55;
          ;;
          -j)
            shift # consume "-j"
            swivm_get_make_jobs "$1"
            shift # consume job count
          ;;
          --no-progress)
            noprogress=1
            shift
          ;;
          *)
            break # stop parsing args
          ;;
        esac
      done

      local provided_version
      provided_version="${1-}"

      if [ -z "${provided_version}" ]; then
        swivm_rc_version
        if [ $version_not_provided -eq 1 ] && [ -z "${SWIVM_RC_VERSION}" ]; then
          unset SWIVM_RC_VERSION
          >&2 swivm --help
          return 127
        fi
        provided_version="${SWIVM_RC_VERSION}"
        unset SWIVM_RC_VERSION
      elif [ $# -gt 0 ]; then
        shift
      fi

      VERSION="$(SWIVM_VERSION_ONLY=true swivm_remote_version "${provided_version}")"

      if [ "${VERSION}" = 'N/A' ]; then
        swivm_err "Version '${provided_version}' not found - try \`swivm ls-remote\` to browse available versions."
        return 3
      fi

      ADDITIONAL_PARAMETERS=''

      while [ $# -ne 0 ]; do
        case "$1" in
          *)
            ADDITIONAL_PARAMETERS="${ADDITIONAL_PARAMETERS} $1"
          ;;
        esac
        shift
      done

      if swivm_is_version_installed "${VERSION}"; then
        swivm_err "${VERSION} is already installed."
        swivm_ensure_default_set "${provided_version}"
        return $?
      fi

      local EXIT_CODE
      EXIT_CODE=-1

      if [ -z "${SWIVM_MAKE_JOBS-}" ]; then
        swivm_get_make_jobs
      fi

      SWIVM_NO_PROGRESS="${SWIVM_NO_PROGRESS:-${noprogress}}" swivm_install "$VERSION" "${SWIVM_MAKE_JOBS}" "$ADDITIONAL_PARAMETERS"
      EXIT_CODE=$?

      return $EXIT_CODE
    ;;
    "uninstall" )
      if [ $# -ne 2 ]; then
        >&2 swivm help
        return 127
      fi

      local ALIAS
      local PATTERN
      PATTERN="$2"
      VERSION="$(swivm_version "$PATTERN")"
      if [ "_$VERSION" = "_$(swivm_ls_current)" ]; then
        echo "swivm: Cannot uninstall currently-active SWI-Prolog version, $VERSION (inferred from $PATTERN)." >&2
        return 1
      fi

      local VERSION_PATH
      VERSION_PATH="$(swivm_version_path "$VERSION")"
      if [ ! -d "$VERSION_PATH" ]; then
        echo "$VERSION version is not installed..." >&2
        return;
      fi

      t="$VERSION-$(swivm_get_os)-$(swivm_get_arch)"

      local SWIVM_SUCCESS_MSG

      SWIVM_SUCCESS_MSG="Uninstalled SWI-Prolog $VERSION"
      # Delete all files related to target version.
      command rm -rf "$SWIVM_DIR/src/swipl-$VERSION.tar.*" \
             "$VERSION_PATH" 2>/dev/null
      echo "$SWIVM_SUCCESS_MSG"

      # rm any aliases that point to uninstalled version.
      for ALIAS in $(command grep -l "$VERSION" "$(swivm_alias_path)/*" 2>/dev/null)
      do
        swivm unalias "$(command basename "$ALIAS")"
      done
    ;;
    "deactivate" )
      local NEWPATH
      NEWPATH="$(swivm_strip_path "$PATH" "/bin")"
      if [ "_$PATH" = "_$NEWPATH" ]; then
        echo "Could not find $(swivm_version_dir)/*/bin in \$PATH" >&2
      else
        export PATH="$NEWPATH"
        hash -r
        echo "$(swivm_version_dir)/*/bin removed from \$PATH"
      fi

      NEWPATH="$(swivm_strip_path "$MANPATH" "/share/man")"
      if [ "_$MANPATH" = "_$NEWPATH" ]; then
        echo "Could not find $SWIVM_DIR/*/share/man in \$MANPATH" >&2
      else
        export MANPATH="$NEWPATH"
        echo "$SWIVM_DIR/*/share/man removed from \$MANPATH"
      fi
    ;;
    "use" )
      local PROVIDED_VERSION
      local SWIVM_USE_SILENT
      SWIVM_USE_SILENT=0
      local SWIVM_DELETE_PREFIX
      SWIVM_DELETE_PREFIX=0

      while [ $# -ne 0 ]; do
        case "$1" in
          --silent) SWIVM_USE_SILENT=1 ;;
          --delete-prefix) SWIVM_DELETE_PREFIX=1 ;;
          --) ;;
          --*) ;;
          *)
            if [ -n "${1-}" ]; then
              PROVIDED_VERSION="$1"
            fi
          ;;
        esac
        shift
      done

      if [ -z "${PROVIDED_VERSION-}" ]; then
        swivm_rc_version
        if [ -n "${SWIVM_RC_VERSION-}" ]; then
          PROVIDED_VERSION="${SWIVM_RC_VERSION}"
          VERSION="$(swivm_version "${PROVIDED_VERSION}")"
        fi
        unset SWIVM_RC_VERSION
        if [ -z "${VERSION}" ]; then
          swivm_err 'Please see `swivm --help` or https://github.com/fnogatz/swivm#swivmrc for more information.'
          return 127
        fi
      else
        VERSION="$(swivm_match_version "${PROVIDED_VERSION}")"
      fi

      if [ -z "${VERSION}" ]; then
        >&2 swivm --help
        return 127
      fi

      if [ "_${VERSION}" = '_system' ]; then
        if swivm_has_system && swivm deactivate >/dev/null 2>&1; then
          if [ $SWIVM_USE_SILENT -ne 1 ]; then
            swivm_echo "Now using system version of SWI-Prolog: $(swipl --version 2>/dev/null)"
          fi
          return
        elif [ $SWIVM_USE_SILENT -ne 1 ]; then
          swivm_err 'System version of SWI-Prolog not found.'
        fi
        return 127
      elif [ "_${VERSION}" = "_∞" ]; then
        if [ $SWIVM_USE_SILENT -ne 1 ]; then
          swivm_err "The alias \"${PROVIDED_VERSION}\" leads to an infinite loop. Aborting."
        fi
        return 8
      fi
      if [ "${VERSION}" = 'N/A' ]; then
        swivm_err "N/A: version \"${PROVIDED_VERSION} -> ${VERSION}\" is not yet installed."
        swivm_err ""
        swivm_err "You need to run \"swivm install ${PROVIDED_VERSION}\" to install it before using it."
        return 3
      # This swivm_ensure_version_installed call can be a performance bottleneck
      # on shell startup. Perhaps we can optimize it away or make it faster.
      elif ! swivm_ensure_version_installed "${VERSION}"; then
        return $?
      fi

      local SWIVM_VERSION_DIR
      SWIVM_VERSION_DIR="$(swivm_version_path "${VERSION}")"

      # Change current version
      PATH="$(swivm_change_path "${PATH}" "/bin" "${SWIVM_VERSION_DIR}")"
      if swivm_has manpath; then
        if [ -z "${MANPATH-}" ]; then
          local MANPATH
          MANPATH=$(manpath)
        fi
        # Change current version
        MANPATH="$(swivm_change_path "${MANPATH}" "/share/man" "${SWIVM_VERSION_DIR}")"
        export MANPATH
      fi
      export PATH
      hash -r
      export SWIVM_BIN="${SWIVM_VERSION_DIR}/bin"
      if [ "${SWIVM_SYMLINK_CURRENT-}" = true ]; then
        command rm -f "${SWIVM_DIR}/current" && ln -s "${SWIVM_VERSION_DIR}" "${SWIVM_DIR}/current"
      fi
      local SWIVM_USE_OUTPUT
      SWIVM_USE_OUTPUT=''
      if [ $SWIVM_USE_SILENT -ne 1 ]; then
        SWIVM_USE_OUTPUT="Now using SWI-Prolog ${VERSION}"
      fi
      if [ "_${VERSION}" != "_system" ]; then
        local SWIVM_USE_CMD
        SWIVM_USE_CMD="swivm use --delete-prefix"
        if [ -n "${PROVIDED_VERSION}" ]; then
          SWIVM_USE_CMD="${SWIVM_USE_CMD} ${VERSION}"
        fi
        if [ $SWIVM_USE_SILENT -eq 1 ]; then
          SWIVM_USE_CMD="${SWIVM_USE_CMD} --silent"
        fi
        if ! swivm_die_on_prefix "${SWIVM_DELETE_PREFIX}" "${SWIVM_USE_CMD}"; then
          return 11
        fi
      fi
      if [ -n "${SWIVM_USE_OUTPUT-}" ]; then
        swivm_echo "${SWIVM_USE_OUTPUT}"
      fi
    ;;
    "run" )
      local provided_version
      local has_checked_swivmrc
      has_checked_swivmrc=0
      # run given version of SWI-Prolog
      shift

      local SWIVM_SILENT
      SWIVM_SILENT=0
      if [ "_$1" = "_--silent" ]; then
        SWIVM_SILENT=1
        shift
      fi

      if [ $# -lt 1 ]; then
        if [ "$SWIVM_SILENT" -eq 1 ]; then
          swivm_rc_version >/dev/null 2>&1 && has_checked_swivmrc=1
        else
          swivm_rc_version && has_checked_swivmrc=1
        fi
        if [ -n "$SWIVM_RC_VERSION" ]; then
          VERSION="$(swivm_version "$SWIVM_RC_VERSION")"
        else
          VERSION='N/A'
        fi
        if [ $VERSION = "N/A" ]; then
          >&2 swivm help
          return 127
        fi
      fi

      provided_version="$1"
      if [ -n "$provided_version" ]; then
        VERSION="$(swivm_version "$provided_version")"
        if [ "_$VERSION" = "_N/A" ] && ! swivm_is_valid_version "$provided_version"; then
          provided_version=''
          if [ $has_checked_swivmrc -ne 1 ]; then
            if [ "$SWIVM_SILENT" -eq 1 ]; then
              swivm_rc_version >/dev/null 2>&1 && has_checked_swivmrc=1
            else
              swivm_rc_version && has_checked_swivmrc=1
            fi
          fi
          VERSION="$(swivm_version "$SWIVM_RC_VERSION")"
        else
          shift
        fi
      fi

      local ARGS
      ARGS="$@"
      local OUTPUT
      local EXIT_CODE

      local ZHS_HAS_SHWORDSPLIT_UNSET
      ZHS_HAS_SHWORDSPLIT_UNSET=1
      if swivm_has "setopt"; then
        ZHS_HAS_SHWORDSPLIT_UNSET=$(setopt | command grep shwordsplit > /dev/null ; echo $?)
        setopt shwordsplit
      fi
      if [ "_$VERSION" = "_N/A" ]; then
        swivm_ensure_version_installed "$provided_version"
        EXIT_CODE=$?
      elif [ -z "$ARGS" ]; then
        swivm exec "$VERSION" swipl
        EXIT_CODE="$?"
      else
        [ $SWIVM_SILENT -eq 1 ] || echo "Running SWI-Prolog $VERSION$(swivm use --silent "$VERSION")"
        OUTPUT="$(swivm use "$VERSION" >/dev/null && swipl $ARGS)"
        EXIT_CODE="$?"
      fi
      if [ "$ZHS_HAS_SHWORDSPLIT_UNSET" -eq 1 ] && swivm_has "unsetopt"; then
        unsetopt shwordsplit
      fi
      if [ -n "$OUTPUT" ]; then
        echo "$OUTPUT"
      fi
      return $EXIT_CODE
    ;;
    "exec" )
      local SWIVM_SILENT
      while [ $# -gt 0 ]; do
        case "$1" in
          --silent) SWIVM_SILENT='--silent' ; shift ;;
          --) break ;;
          --*)
            swivm_err "Unsupported option \"$1\"."
            return 55
          ;;
          *)
            if [ -n "$1" ]; then
              break
            else
              shift
            fi
          ;; # stop processing arguments
        esac
      done

      local provided_version
      provided_version="$1"
      if [ -n "${provided_version}" ]; then
        VERSION="$(swivm_version "${provided_version}")" ||:
        if [ "_${VERSION}" = '_N/A' ] && ! swivm_is_valid_version "${provided_version}"; then
          if [ -n "${SWIVM_SILENT-}" ]; then
            swivm_rc_version >/dev/null 2>&1
          else
            swivm_rc_version
          fi
          provided_version="${SWIVM_RC_VERSION}"
          unset SWIVM_RC_VERSION
          VERSION="$(swivm_version "${provided_version}")" ||:
        else
          shift
        fi
      fi

      swivm_ensure_version_installed "${provided_version}"
      EXIT_CODE=$?
      if [ "${EXIT_CODE}" != "0" ]; then
        return $EXIT_CODE
      fi

      if [ -z "${SWIVM_SILENT-}" ]; then
        swivm_echo "Running SWI-Prolog ${VERSION}"
      fi
      SWI_VERSION="${VERSION}" "${SWIVM_DIR}/swivm-exec" "$@"
    ;;
    "ls" | "list" )
      local PATTERN
      local SWIVM_NO_COLORS
      local SWIVM_NO_ALIAS
      while [ $# -gt 0 ]; do
        case "${1}" in
          --) ;;
          --no-colors) SWIVM_NO_COLORS="${1}" ;;
          --no-alias) SWIVM_NO_ALIAS="${1}" ;;
          --*)
            swivm_err "Unsupported option \"${1}\"."
            return 55
          ;;
          *)
            PATTERN="${PATTERN:-$1}"
          ;;
        esac
        shift
      done
      if [ -n "${PATTERN-}" ] && [ -n "${SWIVM_NO_ALIAS-}" ]; then
        swivm_err '`--no-alias` is not supported when a pattern is provided.'
        return 55
      fi
      local SWIVM_LS_OUTPUT
      local SWIVM_LS_EXIT_CODE
      SWIVM_LS_OUTPUT=$(swivm_ls "${PATTERN-}")
      SWIVM_LS_EXIT_CODE=$?
      SWIVM_NO_COLORS="${SWIVM_NO_COLORS-}" swivm_print_versions "${SWIVM_LS_OUTPUT}"
      if [ -z "${SWIVM_NO_ALIAS-}" ] && [ -z "${PATTERN-}" ]; then
        if [ -n "${SWIVM_NO_COLORS-}" ]; then
          swivm alias --no-colors
        else
          swivm alias
        fi
      fi
      return $SWIVM_LS_EXIT_CODE
    ;;
    "ls-remote" | "list-remote")
      local PATTERN
      local SWIVM_NO_COLORS
      while [ $# -gt 0 ]; do
        case "${1-}" in
          --) ;;
          --no-colors) SWIVM_NO_COLORS="${1}" ;;
          --*)
            swivm_err "Unsupported option \"${1}\"."
            return 55
          ;;
          *)
            if [ -z "${PATTERN-}" ]; then
              PATTERN="${1-}"
            fi
          ;;
        esac
        shift
      done

      local SWIVM_OUTPUT
      local EXIT_CODE
      SWIVM_OUTPUT="$(swivm_remote_versions "${PATTERN}" &&:)"
      EXIT_CODE=$?
      if [ -n "${SWIVM_OUTPUT}" ]; then
        SWIVM_NO_COLORS="${SWIVM_NO_COLORS-}" swivm_print_versions "${SWIVM_OUTPUT}"
        return $EXIT_CODE
      fi
      SWIVM_NO_COLORS="${SWIVM_NO_COLORS-}" swivm_print_versions "N/A"
      return 3
    ;;
    "current" )
      swivm_version current
    ;;
    "which" )
      local provided_version
      provided_version="$2"
      if [ $# -eq 1 ]; then
        swivm_rc_version
        if [ -n "$SWIVM_RC_VERSION" ]; then
          provided_version="$SWIVM_RC_VERSION"
          VERSION=$(swivm_version "$SWIVM_RC_VERSION")
        fi
      elif [ "_$2" != '_system' ]; then
        VERSION="$(swivm_version "$provided_version")"
      else
        VERSION="$2"
      fi
      if [ -z "$VERSION" ]; then
        >&2 swivm help
        return 127
      fi

      if [ "_$VERSION" = '_system' ]; then
        if swivm_has_system >/dev/null 2>&1; then
          local SWIVM_BIN
          SWIVM_BIN="$(swivm use system >/dev/null 2>&1 && command which swipl)"
          if [ -n "$SWIVM_BIN" ]; then
            echo "$SWIVM_BIN"
            return
          else
            return 1
          fi
        else
          echo "System version of SWI-Prolog not found." >&2
          return 127
        fi
      elif [ "_$VERSION" = "_∞" ]; then
        echo "The alias \"$2\" leads to an infinite loop. Aborting." >&2
        return 8
      fi

      swivm_ensure_version_installed "$provided_version"
      EXIT_CODE=$?
      if [ "$EXIT_CODE" != "0" ]; then
        return $EXIT_CODE
      fi
      local SWIVM_VERSION_DIR
      SWIVM_VERSION_DIR="$(swivm_version_path "$VERSION")"
      echo "$SWIVM_VERSION_DIR/bin/swipl"
    ;;
    "alias" )
      local SWIVM_ALIAS_DIR
      SWIVM_ALIAS_DIR="$(swivm_alias_path)"
      local SWIVM_CURRENT
      SWIVM_CURRENT="$(swivm_ls_current)"

      local ALIAS
      local TARGET
      local SWIVM_NO_COLORS
      ALIAS='--'
      TARGET='--'
      while [ $# -gt 0 ]; do
        case "${1-}" in
          --) ;;
          --no-colors) SWIVM_NO_COLORS="${1}" ;;
          --*)
            swivm_err "Unsupported option \"${1}\"."
            return 55
          ;;
          *)
            if [ "${ALIAS}" = '--' ]; then
              ALIAS="${1-}"
            elif [ "${TARGET}" = '--' ]; then
              TARGET="${1-}"
            fi
          ;;
        esac
        shift
      done

      if [ -z "${TARGET}" ]; then
        # for some reason the empty string was explicitly passed as the target
        # so, unalias it.
        swivm unalias "${ALIAS}"
        return $?
      elif [ "${TARGET}" != '--' ]; then
        # a target was passed: create an alias
        if [ "${ALIAS#*\/}" != "${ALIAS}" ]; then
          swivm_err 'Aliases in subdirectories are not supported.'
          return 1
        fi
        VERSION="$(swivm_version "${TARGET}")" ||:
        if [ "${VERSION}" = 'N/A' ]; then
          swivm_err "! WARNING: Version '${TARGET}' does not exist."
        fi
        swivm_make_alias "${ALIAS}" "${TARGET}"
        SWIVM_NO_COLORS="${SWIVM_NO_COLORS-}" SWIVM_CURRENT="${SWIVM_CURRENT-}" DEFAULT=false swivm_print_formatted_alias "${ALIAS}" "${TARGET}" "${VERSION}"
      else
        if [ "${ALIAS-}" = '--' ]; then
          unset ALIAS
        fi

        swivm_list_aliases "${ALIAS-}"
      fi
    ;;
    "unalias" )
      local SWIVM_ALIAS_DIR
      SWIVM_ALIAS_DIR="$(swivm_alias_path)"
      command mkdir -p "${SWIVM_ALIAS_DIR}"
      if [ $# -ne 1 ]; then
        >&2 swivm --help
        return 127
      fi
      if [ "${1#*\/}" != "${1-}" ]; then
        swivm_err 'Aliases in subdirectories are not supported.'
        return 1
      fi

      local SWIVM_ALIAS_EXISTS
      SWIVM_ALIAS_EXISTS=0
      if [ -f "${SWIVM_ALIAS_DIR}/${1-}" ]; then
        SWIVM_ALIAS_EXISTS=1
      fi

      if [ $SWIVM_ALIAS_EXISTS -eq 0 ]; then
        case "$1" in
          "stable" | "devel" | "system")
            swivm_err "${1-} is a default (built-in) alias and cannot be deleted."
            return 1
          ;;
        esac

        swivm_err "Alias ${1-} doesn't exist!"
        return
      fi

      local SWIVM_ALIAS_ORIGINAL
      SWIVM_ALIAS_ORIGINAL="$(swivm_alias "${1}")"
      command rm -f "${SWIVM_ALIAS_DIR}/${1}"
      swivm_echo "Deleted alias ${1} - restore it with \`swivm alias \"${1}\" \"${SWIVM_ALIAS_ORIGINAL}\"\`"
    ;;
    "clear-cache" )
      command rm -f "$SWIVM_DIR/v*" "$(swivm_version_dir)" 2>/dev/null
      echo "Cache cleared."
    ;;
    "version" )
      swivm_version "$2"
    ;;
    "version-remote" )
      swivm_remote_version "$2"
    ;;
    "--version" )
      echo "0.6.0"
    ;;
    "unload")
      swivm deactivate >/dev/null 2>&1
      unset -f swivm \
        swivm_is_alias \
        swivm_ls_remote swivm_ls_remote_index \
        swivm_ls swivm_remote_version swivm_remote_versions \
        swivm_print_versions \
        swivm_version swivm_rc_version swivm_match_version \
        swivm_ensure_default_set swivm_get_arch swivm_get_os \
        swivm_print_implicit_alias swivm_validate_implicit_alias \
        swivm_resolve_alias swivm_ls_current swivm_alias \
        swivm_change_path swivm_strip_path \
        swivm_num_version_groups swivm_format_version swivm_ensure_version_prefix \
        swivm_normalize_version swivm_is_valid_version \
        swivm_ensure_version_installed \
        swivm_version_path swivm_alias_path swivm_version_dir \
        swivm_find_swivmrc swivm_find_up swivm_tree_contains_path \
        swivm_version_greater swivm_version_greater_than_or_equal_to \
        swivm_has_system \
        swivm_download swivm_has \
        swivm_supports_source_options swivm_auto \
        swivm_echo swivm_err swivm_grep swivm_cd \
        swivm_die_on_prefix swivm_get_make_jobs \
        swivm_is_natural_num swivm_is_version_installed \
        swivm_list_aliases swivm_make_alias swivm_print_alias_path \
        swivm_print_default_alias swivm_print_formatted_alias swivm_resolve_local_alias \
        swivm_sanitize_path swivm_has_colors swivm_process_parameters \
        swivm_is_zsh \
        >/dev/null 2>&1
      unset SWIVM_RC_VERSION SWIVM_MIRROR GITHUB_MIRROR SWIVM_DIR \
        SWIVM_CD_FLAGS SWIVM_BIN SWIVM_MAKE_JOBS \
        >/dev/null 2>&1
    ;;
    * )
      >&2 swivm help
      return 127
    ;;
  esac
}

swivm_supports_source_options() {
  [ "_$(echo '[ $# -gt 0 ] && echo $1' | . /dev/stdin yes 2> /dev/null)" = "_yes" ]
}

swivm_auto() {
  local SWIVM_CURRENT
  SWIVM_CURRENT="$(swivm_ls_current)"
  local SWIVM_MODE
  SWIVM_MODE="${1-}"
  local VERSION
  if [ "_${SWIVM_MODE}" = '_install' ]; then
    VERSION="$(swivm_alias default 2>/dev/null || swivm_echo)"
    if [ -n "${VERSION}" ]; then
      swivm install "${VERSION}" >/dev/null
    elif swivm_rc_version >/dev/null 2>&1; then
      swivm install >/dev/null
    fi
  elif [ "_$SWIVM_MODE" = '_use' ]; then
    if [ "_${SWIVM_CURRENT}" = '_none' ] || [ "_${SWIVM_CURRENT}" = '_system' ]; then
      VERSION="$(swivm_resolve_local_alias default 2>/dev/null || swivm_echo)"
      if [ -n "${VERSION}" ]; then
        swivm use --silent "${VERSION}" >/dev/null
      elif swivm_rc_version >/dev/null 2>&1; then
        swivm use --silent >/dev/null
      fi
    else
      swivm use --silent "${SWIVM_CURRENT}" >/dev/null
    fi
  elif [ "_${SWIVM_MODE}" != '_none' ]; then
    swivm_err 'Invalid auto mode supplied.'
    return 1
  fi
}

swivm_process_parameters() {
  local SWIVM_AUTO_MODE
  SWIVM_AUTO_MODE='use'
  if swivm_supports_source_options; then
    while [ $# -ne 0 ]; do
      case "$1" in
        --install) SWIVM_AUTO_MODE='install' ;;
        --no-use) SWIVM_AUTO_MODE='none' ;;
      esac
      shift
    done
  fi
  swivm_auto "${SWIVM_AUTO_MODE}"
}

swivm_process_parameters "$@"

} # this ensures the entire script is downloaded #
