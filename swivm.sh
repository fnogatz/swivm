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

swivm_has() {
  type "$1" > /dev/null 2>&1
}

swivm_is_alias() {
  # this is intentionally not "command alias" so it works in zsh.
  \alias "$1" > /dev/null 2>&1
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

swivm_has_system_swi() {
  [ "$(swivm deactivate >/dev/null 2>&1 && command -v swipl)" != '' ]
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
  export SWIVM_MIRROR="http://www.swi-prolog.org/download"
fi
if [ -z "$GITHUB_MIRROR" ]; then
  export GITHUB_MIRROR="https://github.com/SWI-Prolog/swipl-devel/archive"
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
  if [ -e "$SWIVMRC_PATH" ]; then
    read -r SWIVM_RC_VERSION < "$SWIVMRC_PATH"
    echo "Found '$SWIVMRC_PATH' with version <$SWIVM_RC_VERSION>"
  else
    >&2 echo "No .swivmrc file found"
    return 1
  fi
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
  PATTERN="$1"
  local VERSION
  # The default version is the current one
  if [ -z "$PATTERN" ]; then
    PATTERN='current'
  fi

  if [ "$PATTERN" = "current" ]; then
    swivm_ls_current
    return $?
  fi

  VERSION="$(swivm_ls "$PATTERN" | command tail -n1)"
  if [ -z "$VERSION" ] || [ "_$VERSION" = "_N/A" ]; then
    echo "N/A"
    return 3;
  else
    echo "$VERSION"
  fi
}

swivm_remote_version() {
  local PATTERN
  PATTERN="$1"
  local VERSION
  if swivm_validate_implicit_alias "$PATTERN" 2> /dev/null ; then
    VERSION="$(swivm_ls_remote "$PATTERN")"
  else
    VERSION="$(swivm_remote_versions "$PATTERN" | command tail -n1)"
  fi
  echo "$VERSION"
  if [ "_$VERSION" = '_N/A' ]; then
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
  if swivm_validate_implicit_alias "$1" 2> /dev/null; then
    return 0
  fi

  local VERSION
  swivm_version_greater "$VERSION"
}

swivm_normalize_version() {
  echo "${1#v}" | command awk -F. '{ printf("%d%06d%06d\n", $1,$2,$3); }'
}

swivm_format_version() {
  local VERSION
  VERSION="$1"
  if [ "_$(swivm_num_version_groups "$VERSION")" != "_3" ]; then
    swivm_format_version "${VERSION%.}.0"
  else
    echo "$VERSION"
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
  local SWIVM_LS_CURRENT_SWIPL_PATH
  SWIVM_LS_CURRENT_SWIPL_PATH="$(command which swipl 2> /dev/null)"
  if [ $? -ne 0 ]; then
    echo 'none'
  elif swivm_tree_contains_path "$SWIVM_DIR" "$SWIVM_LS_CURRENT_SWIPL_PATH"; then
    local VERSION
    VERSION="$(swipl --version 2>/dev/null | sed -r "s/^.* ([0-9](\.[0-9])*) .*$/\1/g")"
    echo "$VERSION"
  else
    echo 'system'
  fi
}

swivm_resolve_alias() {
  if [ -z "$1" ]; then
    return 1
  fi

  local PATTERN
  PATTERN="$1"

  local ALIAS
  ALIAS="$PATTERN"
  local ALIAS_TEMP

  local SEEN_ALIASES
  SEEN_ALIASES="$ALIAS"
  while true; do
    ALIAS_TEMP="$(swivm_alias "$ALIAS" 2> /dev/null)"

    if [ -z "$ALIAS_TEMP" ]; then
      break
    fi

    if [ -n "$ALIAS_TEMP" ] \
      && command printf "$SEEN_ALIASES" | command grep -e "^$ALIAS_TEMP$" > /dev/null; then
      ALIAS="∞"
      break
    fi

    SEEN_ALIASES="$SEEN_ALIASES\n$ALIAS_TEMP"
    ALIAS="$ALIAS_TEMP"
  done

  if [ -n "$ALIAS" ] && [ "_$ALIAS" != "_$PATTERN" ]; then
    case "_$ALIAS" in
      "_∞" )
        echo "$ALIAS"
      ;;
    esac
    return 0
  fi

  if swivm_validate_implicit_alias "$PATTERN" 2> /dev/null ; then
    local IMPLICIT
    IMPLICIT="$(swivm_print_implicit_alias local "$PATTERN" 2> /dev/null)"
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
  PATTERN="$1"
  local VERSIONS
  VERSIONS=''
  if [ "$PATTERN" = 'current' ]; then
    swivm_ls_current
    return
  fi

  if swivm_resolve_local_alias "$PATTERN"; then
    return
  fi
  if [ "_$PATTERN" = "_N/A" ]; then
    return
  fi
  # If it looks like an explicit version, don't do anything funny
  local SWIVM_PATTERN_STARTS_WITH_V
  case $PATTERN in
    v*) SWIVM_PATTERN_STARTS_WITH_V=true ;;
    *) SWIVM_PATTERN_STARTS_WITH_V=false ;;
  esac
  if [ $SWIVM_PATTERN_STARTS_WITH_V = true ] && [ "_$(swivm_num_version_groups "$PATTERN")" = "_3" ]; then
    if [ -d "$(swivm_version_path "$PATTERN")" ]; then
      VERSIONS="$PATTERN"
    fi
  else
    case "$PATTERN" in
      "system") ;;
      *)
        local NUM_VERSION_GROUPS
        NUM_VERSION_GROUPS="$(swivm_num_version_groups "$PATTERN")"
        if [ "_$NUM_VERSION_GROUPS" = "_2" ] || [ "_$NUM_VERSION_GROUPS" = "_1" ]; then
          PATTERN="${PATTERN%.}."
        fi
      ;;
    esac

    local ZHS_HAS_SHWORDSPLIT_UNSET
    ZHS_HAS_SHWORDSPLIT_UNSET=1
    if swivm_has "setopt"; then
      ZHS_HAS_SHWORDSPLIT_UNSET=$(setopt | command grep shwordsplit > /dev/null ; echo $?)
      setopt shwordsplit
    fi

    local SWIVM_DIRS_TO_SEARCH
    SWIVM_DIRS_TO_SEARCH="$(swivm_version_dir)"
    local SWIVM_ADD_SYSTEM
    SWIVM_ADD_SYSTEM=false

    if swivm_has_system_swi || swivm_has_system_swi; then
      SWIVM_ADD_SYSTEM=true
    fi

    if ! [ -d "$SWIVM_DIRS_TO_SEARCH" ]; then
      SWIVM_DIRS_TO_SEARCH=''
    fi

    if [ -z "$PATTERN" ]; then
      PATTERN=''
    fi
    if [ -n "$SWIVM_DIRS_TO_SEARCH" ]; then
      VERSIONS="$(command find "$SWIVM_DIRS_TO_SEARCH" -maxdepth 1 -type d -name "$PATTERN*" \
        | command sed "
            s#^$SWIVM_DIR/##;
            \#^versions\$# d;
            s#^versions/##" \
        | command sort -t. -u -k 2.2,2n -k 3,3n -k 4,4n \
      )"
    fi

    if [ "$ZHS_HAS_SHWORDSPLIT_UNSET" -eq 1 ] && swivm_has "unsetopt"; then
      unsetopt shwordsplit
    fi
  fi

  if [ "$SWIVM_ADD_SYSTEM" = true ]; then
    if [ -z "$PATTERN" ] || [ "_$PATTERN" = "_v" ]; then
      VERSIONS="$VERSIONS$(command printf '\n%s' 'system')"
    elif [ "$PATTERN" = 'system' ]; then
      VERSIONS="$(command printf '%s' 'system')"
    fi
  fi

  if [ -z "$VERSIONS" ]; then
    echo "N/A"
    return 3
  fi

  echo "$VERSIONS"
}

swivm_ls_remote() {
  local PATTERN
  PATTERN="$1"
  if swivm_validate_implicit_alias "$PATTERN" 2> /dev/null ; then
    PATTERN="$(swivm_ls_remote "$(swivm_print_implicit_alias remote "$PATTERN")" | command tail -n1)"
  elif [ -z "$PATTERN" ]; then
    PATTERN=".*"
  fi
  swivm_ls_remote_index "$SWIVM_MIRROR" "$PATTERN"
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
    | command sed -r 's/^.*a href="(swi)?pl\-(.*)\.tar\.gz".*$/\2/' \
    | command grep -w "^$PATTERN" \
    | $SORT_COMMAND)"
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
  echo "$1" | while read -r VERSION; do
    if [ "_$VERSION" = "_$SWIVM_CURRENT" ]; then
      FORMAT='\033[0;32m-> %12s\033[0m'
    elif [ "$VERSION" = "system" ]; then
      FORMAT='\033[0;33m%15s\033[0m'
    elif [ -d "$(swivm_version_path "$VERSION" 2> /dev/null)" ]; then
      FORMAT='\033[0;34m%15s\033[0m'
    else
      FORMAT='%15s'
    fi
    command printf "$FORMAT\n" "$VERSION"
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

swivm_install() {
  local VERSION
  VERSION="$1"
  local ADDITIONAL_PARAMETERS
  ADDITIONAL_PARAMETERS="$2"

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

  if [ "$(swivm_download -L -s -I "$SWIVM_MIRROR/$MODE/src/swipl-$VERSION.tar.gz" -o - | command grep '200 OK')" != '' ]; then
    tarball="$SWIVM_MIRROR/$MODE/src/swipl-$VERSION.tar.gz"
  elif [ "$(swivm_download -L -s -I "$SWIVM_MIRROR/$MODE/src/pl-$VERSION.tar.gz" -o - | command grep '200 OK')" != '' ]; then
    tarball="$SWIVM_MIRROR/$MODE/src/pl-$VERSION.tar.gz"
  elif [ "$(swivm_download -L -s -I "$GITHUB_MIRROR/V$VERSION.tar.gz" -o - 2>&1 | command grep '200 OK')" != '' ]; then
    tarball="$GITHUB_MIRROR/V$VERSION.tar.gz"
  fi

  local SRC_PATH
  if ! (
    [ -n "$tarball" ] && \
    command mkdir -p "$tmpdir" && \
    echo "Downloading $tarball..." && \
    swivm_download -L --progress-bar "$tarball" -o "$tmptarball" && \
    command tar -xzf "$tmptarball" -C "$tmpdir" && \
    command mkdir -p "$SWIVM_DIR/versions" && \
    (mv "$tmpdir/swipl-$VERSION" "$VERSION_PATH" 2>&1 || mv "$tmpdir/pl-$VERSION" "$VERSION_PATH") && \
    cd "$VERSION_PATH" && \
    echo "### [SWIVM] Prepare Installation Template ###" && \
    cp build.templ build && \
    sed -i "s@PREFIX=\$HOME@PREFIX=$VERSION_PATH@g" build && \
    sed -i "s@MAKE=make@MAKE=$make@g" build && \
    echo "### [SWIVM] Prepare SWI-Prolog ###" && \
    ./prepare --yes --all && \
    echo "### [SWIVM] Build SWI-Prolog ###" && \
    ./build && \
    cd packages && \
    echo "### [SWIVM] Configure Packages ###" && \
    ./configure && \
    $MAKE && \
    echo "### [SWIVM] Install Packages ###" && \
    make install
    )
  then
    echo "swivm: install $VERSION failed!" >&2
    return 1
  fi

  return $?
}

swivm_match_version() {
  local PROVIDED_VERSION
  PROVIDED_VERSION="$1"
  case "_$PROVIDED_VERSION" in
    "_system")
      echo "system"
    ;;
    *)
      swivm_version "$PROVIDED_VERSION"
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
    swivm help
    return
  fi

  local GREP_OPTIONS
  GREP_OPTIONS=''

  # initialize local variables
  local VERSION
  local ADDITIONAL_PARAMETERS
  local ALIAS

  case $1 in
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
      echo '  swivm run 6.6.2 example.pl                  Run example.pl using SWI-Prolog v6.6.2'
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

    "install" | "i" )
      local version_not_provided
      version_not_provided=0
      local provided_version
      local SWIVM_OS
      SWIVM_OS="$(swivm_get_os)"

      if ! swivm_has "curl" && ! swivm_has "wget"; then
        echo 'swivm needs curl or wget to proceed.' >&2;
        return 1
      fi

      if [ $# -lt 2 ]; then
        version_not_provided=1
        swivm_rc_version
        if [ -z "$SWIVM_RC_VERSION" ]; then
          >&2 swivm help
          return 127
        fi
      fi

      shift

      provided_version="$1"

      if [ -z "$provided_version" ]; then
        if [ $version_not_provided -ne 1 ]; then
          swivm_rc_version
        fi
        provided_version="$SWIVM_RC_VERSION"
      else
        shift
      fi

      VERSION="$(swivm_remote_version "$provided_version")"

      if [ "_$VERSION" = "_N/A" ]; then
        echo "Version '$provided_version' not found - try \`swivm ls-remote\` to browse available versions." >&2
        return 3
      fi

      ADDITIONAL_PARAMETERS=''
      local PROVIDED_REINSTALL_PACKAGES_FROM
      local REINSTALL_PACKAGES_FROM

      while [ $# -ne 0 ]
      do
        case "$1" in
          *)
            ADDITIONAL_PARAMETERS="$ADDITIONAL_PARAMETERS $1"
          ;;
        esac
        shift
      done

      local VERSION_PATH
      VERSION_PATH="$(swivm_version_path "$VERSION")"
      if [ -d "$VERSION_PATH" ]; then
        echo "$VERSION is already installed." >&2
        return $?
      fi

      swivm_install "$VERSION" "$ADDITIONAL_PARAMETERS"
    ;;
    "uninstall" )
      if [ $# -ne 2 ]; then
        >&2 swivm help
        return 127
      fi

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

      shift # remove "use"
      while [ $# -ne 0 ]
      do
        case "$1" in
          --silent) SWIVM_USE_SILENT=1 ;;
          --delete-prefix) SWIVM_DELETE_PREFIX=1 ;;
          *)
            if [ -n "$1" ]; then
              PROVIDED_VERSION="$1"
            fi
          ;;
        esac
        shift
      done

      if [ -z "$PROVIDED_VERSION" ]; then
        swivm_rc_version
        if [ -n "$SWIVM_RC_VERSION" ]; then
          PROVIDED_VERSION="$SWIVM_RC_VERSION"
          VERSION="$(swivm_version "$PROVIDED_VERSION")"
        fi
      else
        VERSION="$(swivm_match_version "$PROVIDED_VERSION")"
      fi

      if [ -z "$VERSION" ]; then
        >&2 swivm help
        return 127
      fi

      if [ "_$VERSION" = '_system' ]; then
        if swivm_has_system_swi && swivm deactivate >/dev/null 2>&1; then
          if [ $SWIVM_USE_SILENT -ne 1 ]; then
            echo "Now using system version of SWI-Prolog: $(swipl --version 2>/dev/null | sed -r "s/^.* ([0-9](\.[0-9])*) .*$/\1/g")"
          fi
          return
        else
          if [ $SWIVM_USE_SILENT -ne 1 ]; then
            echo "System version of SWI-Prolog not found." >&2
          fi
          return 127
        fi
      elif [ "_$VERSION" = "_∞" ]; then
        if [ $SWIVM_USE_SILENT -ne 1 ]; then
          echo "The alias \"$PROVIDED_VERSION\" leads to an infinite loop. Aborting." >&2
        fi
        return 8
      fi

      # This swivm_ensure_version_installed call can be a performance bottleneck
      # on shell startup. Perhaps we can optimize it away or make it faster.
      swivm_ensure_version_installed "$PROVIDED_VERSION"
      EXIT_CODE=$?
      if [ "$EXIT_CODE" != "0" ]; then
        return $EXIT_CODE
      fi

      local SWIVM_VERSION_DIR
      SWIVM_VERSION_DIR="$(swivm_version_path "$VERSION")"

      # Strip other version from PATH
      PATH="$(swivm_strip_path "$PATH" "/bin")"
      # Prepend current version
      PATH="$(swivm_prepend_path "$PATH" "$SWIVM_VERSION_DIR/bin")"
      if swivm_has manpath; then
        if [ -z "$MANPATH" ]; then
          MANPATH=$(manpath)
        fi
        # Strip other version from MANPATH
        MANPATH="$(swivm_strip_path "$MANPATH" "/share/man")"
        # Prepend current version
        MANPATH="$(swivm_prepend_path "$MANPATH" "$SWIVM_VERSION_DIR/share/man")"
        export MANPATH
      fi
      export PATH
      hash -r
      export SWIVM_BIN="$SWIVM_VERSION_DIR/bin"
      if [ "$SWIVM_SYMLINK_CURRENT" = true ]; then
        command rm -f "$SWIVM_DIR/current" && ln -s "$SWIVM_VERSION_DIR" "$SWIVM_DIR/current"
      fi
      local SWIVM_USE_OUTPUT

      if [ $SWIVM_USE_SILENT -ne 1 ]; then
        SWIVM_USE_OUTPUT="Now using SWI-Prolog $VERSION"
      fi
      if [ "_$VERSION" != "_system" ]; then
        local SWIVM_USE_CMD
        SWIVM_USE_CMD="swivm use --delete-prefix"
        if [ -n "$PROVIDED_VERSION" ]; then
          SWIVM_USE_CMD="$SWIVM_USE_CMD $VERSION"
        fi
        if [ $SWIVM_USE_SILENT -eq 1 ]; then
          SWIVM_USE_CMD="$SWIVM_USE_CMD --silent"
        fi
        if ! swivm_die_on_prefix "$SWIVM_DELETE_PREFIX" "$SWIVM_USE_CMD"; then
          return 11
        fi
      fi
      if [ -n "$SWIVM_USE_OUTPUT" ]; then
        echo "$SWIVM_USE_OUTPUT"
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
      shift

      local SWIVM_SILENT
      SWIVM_SILENT=0
      if [ "_$1" = "_--silent" ]; then
        SWIVM_SILENT=1
        shift
      fi

      local provided_version
      provided_version="$1"
      if [ -n "$provided_version" ]; then
        VERSION="$(swivm_version "$provided_version")"
        if [ "_$VERSION" = "_N/A" ] && ! swivm_is_valid_version "$provided_version"; then
          if [ "$SWIVM_SILENT" -eq 1 ]; then
            swivm_rc_version >/dev/null 2>&1
          else
            swivm_rc_version
          fi
          provided_version="$SWIVM_RC_VERSION"
          VERSION="$(swivm_version "$provided_version")"
        else
          shift
        fi
      fi

      swivm_ensure_version_installed "$provided_version"
      EXIT_CODE=$?
      if [ "$EXIT_CODE" != "0" ]; then
        return $EXIT_CODE
      fi

      [ $SWIVM_SILENT -eq 1 ] || echo "Running SWI-Prolog $VERSION$(swivm use --silent "$VERSION")"
      SWI_VERSION="$VERSION" "$SWIVM_DIR/swivm-exec" "$@"
    ;;
    "ls" | "list" )
      local SWIVM_LS_OUTPUT
      local SWIVM_LS_EXIT_CODE
      SWIVM_LS_OUTPUT=$(swivm_ls "$2")
      SWIVM_LS_EXIT_CODE=$?
      swivm_print_versions "$SWIVM_LS_OUTPUT"
      if [ $# -eq 1 ]; then
        swivm alias
      fi
      return $SWIVM_LS_EXIT_CODE
    ;;
    "ls-remote" | "list-remote" )
      local PATTERN
      PATTERN="$2"

      local SWIVM_OUTPUT
      SWIVM_OUTPUT=$(swivm_ls_remote "$PATTERN")

      if [ -n "$SWIVM_OUTPUT" ]; then
        swivm_print_versions "$SWIVM_OUTPUT"
        return
      else
        swivm_print_versions "N/A"
        return 3
      fi
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
        if swivm_has_system_swi >/dev/null 2>&1; then
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
      command mkdir -p "$SWIVM_ALIAS_DIR"
      if [ $# -le 2 ]; then
        local DEST
        for ALIAS_PATH in "$SWIVM_ALIAS_DIR"/"$2"*; do
          ALIAS="$(command basename "$ALIAS_PATH")"
          DEST="$(swivm_alias "$ALIAS" 2> /dev/null)"
          if [ -n "$DEST" ]; then
            VERSION="$(swivm_version "$DEST")"
            if [ "_$DEST" = "_$VERSION" ]; then
              echo "$ALIAS -> $DEST"
            else
              echo "$ALIAS -> $DEST (-> $VERSION)"
            fi
          fi
        done

        for ALIAS in "stable" "devel"; do
          if [ ! -f "$SWIVM_ALIAS_DIR/$ALIAS" ]; then
            if [ $# -lt 2 ] || [ "~$ALIAS" = "~$2" ]; then
              DEST="$(swivm_print_implicit_alias local "$ALIAS")"
              if [ "_$DEST" != "_" ]; then
                VERSION="$(swivm_version "$DEST")"
                if [ "_$DEST" = "_$VERSION" ]; then
                  echo "$ALIAS -> $DEST (default)"
                else
                  echo "$ALIAS -> $DEST (-> $VERSION) (default)"
                fi
              fi
            fi
          fi
        done
        return
      fi
      if [ -z "$3" ]; then
        command rm -f "$SWIVM_ALIAS_DIR/$2"
        echo "$2 -> *poof*"
        return
      fi
      VERSION="$(swivm_version "$3")"
      if [ $? -ne 0 ]; then
        echo "! WARNING: Version '$3' does not exist." >&2
      fi
      echo "$3" | tee "$SWIVM_ALIAS_DIR/$2" >/dev/null
      if [ ! "_$3" = "_$VERSION" ]; then
        echo "$2 -> $3 (-> $VERSION)"
      else
        echo "$2 -> $3"
      fi
    ;;
    "unalias" )
      local SWIVM_ALIAS_DIR
      SWIVM_ALIAS_DIR="$(swivm_alias_path)"
      command mkdir -p "$SWIVM_ALIAS_DIR"
      if [ $# -ne 2 ]; then
        >&2 swivm help
        return 127
      fi
      [ ! -f "$SWIVM_ALIAS_DIR/$2" ] && echo "Alias $2 doesn't exist!" >&2 && return
      command rm -f "$SWIVM_ALIAS_DIR/$2"
      echo "Deleted alias $2"
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
      echo "0.2.3"
    ;;
    "unload" )
      unset -f swivm swivm_print_versions \
        swivm_is_stable_version swivm_is_devel_version \
        swivm_ls_remote swivm_ls_remote_index \
        swivm_ls swivm_remote_version swivm_remote_versions \
        swivm_install \
        swivm_version swivm_rc_version swivm_match_version \
        swivm_ensure_default_set swivm_get_arch swivm_get_os \
        swivm_print_implicit_alias swivm_validate_implicit_alias \
        swivm_resolve_alias swivm_ls_current swivm_alias \
        swivm_prepend_path swivm_strip_path \
        swivm_num_version_groups swivm_format_version \
        swivm_normalize_version swivm_is_valid_version \
        swivm_ensure_version_installed \
        swivm_version_path swivm_alias_path swivm_version_dir \
        swivm_find_swivmrc swivm_find_up swivm_tree_contains_path \
        swivm_version_greater swivm_version_greater_than_or_equal_to \
        swivm_has_system_swi \
        swivm_download swivm_has \
        swivm_supports_source_options swivm_supports_xz > /dev/null 2>&1
      unset RC_VERSION SWIVM_DIR SWIVM_CD_FLAGS > /dev/null 2>&1
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

swivm_supports_xz() {
  command which xz >/dev/null 2>&1 && swivm_version_greater_than_or_equal_to "$1" "2.3.2"
}

SWIVM_VERSION="$(swivm_alias default 2>/dev/null || echo)"
if swivm_supports_source_options && [ "$#" -gt 0 ] && [ "_$1" = "_--install" ]; then
  if [ -n "$SWIVM_VERSION" ]; then
    swivm install "$SWIVM_VERSION" >/dev/null
  elif swivm_rc_version >/dev/null 2>&1; then
    swivm install >/dev/null
  fi
elif [ -n "$SWIVM_VERSION" ]; then
  swivm use --silent "$SWIVM_VERSION" >/dev/null
elif swivm_rc_version >/dev/null 2>&1; then
  swivm use --silent >/dev/null
fi

} # this ensures the entire script is downloaded #
