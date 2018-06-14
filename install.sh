#!/bin/bash

{ # this ensures the entire script is downloaded #

swivm_has() {
  type "$1" > /dev/null 2>&1
}

if [ -z "$SWIVM_DIR" ]; then
  SWIVM_DIR="$HOME/.swivm"
fi

swivm_latest_version() {
  echo "v0.3.3"
}

#
# Outputs the location to SWIVM depending on:
# * The availability of $SWIVM_SOURCE
# * The method used ("script" or "git" in the script, defaults to "git")
# SWIVM_SOURCE always takes precedence unless the method is "script-swivm-exec"
#
swivm_source() {
  local SWIVM_METHOD
  SWIVM_METHOD="$1"
  local SWIVM_SOURCE_URL
  SWIVM_SOURCE_URL="$SWIVM_SOURCE"
  if [ "_$SWIVM_METHOD" = "_script-swivm-exec" ]; then
    SWIVM_SOURCE_URL="https://raw.githubusercontent.com/fnogatz/swivm/$(swivm_latest_version)/swivm-exec"
  elif [ -z "$SWIVM_SOURCE_URL" ]; then
    if [ "_$SWIVM_METHOD" = "_script" ]; then
      SWIVM_SOURCE_URL="https://raw.githubusercontent.com/fnogatz/swivm/$(swivm_latest_version)/swivm.sh"
    elif [ "_$SWIVM_METHOD" = "_git" ] || [ -z "$SWIVM_METHOD" ]; then
      SWIVM_SOURCE_URL="https://github.com/fnogatz/swivm.git"
    else
      echo >&2 "Unexpected value \"$SWIVM_METHOD\" for \$SWIVM_METHOD"
      return 1
    fi
  fi
  echo "$SWIVM_SOURCE_URL"
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
    wget $ARGS
  fi
}

install_swivm_from_git() {
  if [ -d "$SWIVM_DIR/.git" ]; then
    echo "=> swivm is already installed in $SWIVM_DIR, trying to update using git"
    printf "\r=> "
    cd "$SWIVM_DIR" && (command git fetch 2> /dev/null || {
      echo >&2 "Failed to update swivm, run 'git fetch' in $SWIVM_DIR yourself." && exit 1
    })
  else
    # Cloning to $SWIVM_DIR
    echo "=> Downloading swivm from git to '$SWIVM_DIR'"
    printf "\r=> "
    mkdir -p "$SWIVM_DIR"
    command git clone "$(swivm_source git)" "$SWIVM_DIR"
  fi
  cd "$SWIVM_DIR" && command git checkout --quiet $(swivm_latest_version)
  if [ ! -z "$(cd "$SWIVM_DIR" && git show-ref refs/heads/master)" ]; then
    if git branch --quiet 2>/dev/null; then
      cd "$SWIVM_DIR" && command git branch --quiet -D master >/dev/null 2>&1
    else
      echo >&2 "Your version of git is out of date. Please update it!"
      cd "$SWIVM_DIR" && command git branch -D master >/dev/null 2>&1
    fi
  fi
  return
}

install_swivm_as_script() {
  local SWIVM_SOURCE_LOCAL
  SWIVM_SOURCE_LOCAL=$(swivm_source script)
  local SWIVM_EXEC_SOURCE
  SWIVM_EXEC_SOURCE=$(swivm_source script-swivm-exec)

  # Downloading to $SWIVM_DIR
  mkdir -p "$SWIVM_DIR"
  if [ -d "$SWIVM_DIR/swivm.sh" ]; then
    echo "=> swivm is already installed in $SWIVM_DIR, trying to update the script"
  else
    echo "=> Downloading swivm as script to '$SWIVM_DIR'"
  fi
  swivm_download -s "$SWIVM_SOURCE_LOCAL" -o "$SWIVM_DIR/swivm.sh" || {
    echo >&2 "Failed to download '$SWIVM_SOURCE_LOCAL'"
    return 1
  }
  swivm_download -s "$SWIVM_EXEC_SOURCE" -o "$SWIVM_DIR/swivm-exec" || {
    echo >&2 "Failed to download '$SWIVM_EXEC_SOURCE'"
    return 2
  }
  chmod a+x "$SWIVM_DIR/swivm-exec" || {
    echo >&2 "Failed to mark '$SWIVM_DIR/swivm-exec' as executable"
    return 3
  }
}

#
# Detect profile file if not specified as environment variable
# (eg: PROFILE=~/.myprofile)
# The echo'ed path is guaranteed to be an existing file
# Otherwise, an empty string is returned
#
swivm_detect_profile() {

  local DETECTED_PROFILE
  DETECTED_PROFILE=''
  local SHELLTYPE
  SHELLTYPE="$(basename /$SHELL)"

  if [ $SHELLTYPE = "bash" ]; then
    if [ -f "$HOME/.bashrc" ]; then
      DETECTED_PROFILE="$HOME/.bashrc"
    elif [ -f "$HOME/.bash_profile" ]; then
      DETECTED_PROFILE="$HOME/.bash_profile"
    fi
  elif [ $SHELLTYPE = "zsh" ]; then
    DETECTED_PROFILE="$HOME/.zshrc"
  fi

  if [ -z $DETECTED_PROFILE ]; then
    if [ -f "$PROFILE" ]; then
      DETECTED_PROFILE="$PROFILE"
    elif [ -f "$HOME/.profile" ]; then
      DETECTED_PROFILE="$HOME/.profile"
    elif [ -f "$HOME/.bashrc" ]; then
      DETECTED_PROFILE="$HOME/.bashrc"
    elif [ -f "$HOME/.bash_profile" ]; then
      DETECTED_PROFILE="$HOME/.bash_profile"
    elif [ -f "$HOME/.zshrc" ]; then
      DETECTED_PROFILE="$HOME/.zshrc"
    fi
  fi

  if [ ! -z $DETECTED_PROFILE ]; then
    echo "$DETECTED_PROFILE"
  fi
}

swivm_do_install() {
  if [ -z "$METHOD" ]; then
    # Autodetect install method
    if swivm_has "git"; then
      install_swivm_from_git
    elif swivm_has "swivm_download"; then
      install_swivm_as_script
    else
      echo >&2 "You need git, curl, or wget to install swivm"
      exit 1
    fi
  elif [ "~$METHOD" = "~git" ]; then
    if ! swivm_has "git"; then
      echo >&2 "You need git to install swivm"
      exit 1
    fi
    install_swivm_from_git
  elif [ "~$METHOD" = "~script" ]; then
    if ! swivm_has "swivm_download"; then
      echo >&2 "You need curl or wget to install swivm"
      exit 1
    fi
    install_swivm_as_script
  fi

  echo

  local SWIVM_PROFILE
  SWIVM_PROFILE=$(swivm_detect_profile)

  SOURCE_STR="\nexport SWIVM_DIR=\"$SWIVM_DIR\"\n[ -s \"\$SWIVM_DIR/swivm.sh\" ] && . \"\$SWIVM_DIR/swivm.sh\"  # This loads swivm"

  if [ -z "$SWIVM_PROFILE" ] ; then
    echo "=> Profile not found. Tried $SWIVM_PROFILE (as defined in \$PROFILE), ~/.bashrc, ~/.bash_profile, ~/.zshrc, and ~/.profile."
    echo "=> Create one of them and run this script again"
    echo "=> Create it (touch $SWIVM_PROFILE) and run this script again"
    echo "   OR"
    echo "=> Append the following lines to the correct file yourself:"
    printf "$SOURCE_STR"
    echo
  else
    if ! command grep -qc '/swivm.sh' "$SWIVM_PROFILE"; then
      echo "=> Appending source string to $SWIVM_PROFILE"
      printf "$SOURCE_STR\n" >> "$SWIVM_PROFILE"
    else
      echo "=> Source string already in $SWIVM_PROFILE"
    fi
  fi

  echo "=> Close and reopen your terminal to start using swivm"
  swivm_reset
}

#
# Unsets the various functions defined
# during the execution of the install script
#
swivm_reset() {
  unset -f swivm_reset swivm_has swivm_latest_version \
    swivm_source swivm_download install_swivm_as_script install_swivm_from_git \
    swivm_detect_profile swivm_do_install
}

[ "_$SWIVM_ENV" = "_testing" ] || swivm_do_install

} # this ensures the entire script is downloaded #
