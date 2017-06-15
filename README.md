# SWI-Prolog Version Manager

SWIVM, the SWI-Prolog Version Manager, is a bash script to manage multiple active SWI-Prolog versions. It provides a uniform command line interface to install and execute SWI-Prolog since version 5. Being an adapted fork of the [Node Version Manager nvm](https://github.com/creationix/nvm) it has a very similar interface.

## Installation

`swivm` does not support Windows so far. Make sure your system has the requirements for a manual SWI-Prolog installation from source.

Typically, the following libraries are required:

```
sudo apt-get install autoconf make libgmp-dev libxt-dev libjpeg-dev libxpm-dev libxft-dev libdb-dev libssl-dev unixodbc-dev libarchive-dev
```

If you want to reduce resources, the following packages are optional:

- `unixodbc-dev`: Without, you have no ODBC database connectivity (e.g., MySQL)
- `libssl-dev`: Without, you have no SSL (and HTTPS) support.
- `libgmp-dev`: Without, you lack unbounded integer support, rational numbers, good random number generators, etc.
- `libarchive-dev`: Without, you can not unpack and install add-ons.

Additionally a Java compiler is required, so make sure `javac -version` is possible.

### Install script

To install or update swivm, you can use the [install script](https://github.com/fnogatz/swivm/blob/v0.3.1/install.sh) using cURL:

    curl -o- https://raw.githubusercontent.com/fnogatz/swivm/v0.3.1/install.sh | bash

or Wget:

    wget -qO- https://raw.githubusercontent.com/fnogatz/swivm/v0.3.1/install.sh | bash

<sub>The script clones the swivm repository to `~/.swivm` and adds the source line to your profile (`~/.bash_profile`, `~/.zshrc` or `~/.profile`).</sub>

You can customize the install source, directory and profile using the `SWIVM_SOURCE`, `SWIVM_DIR`, and `PROFILE` variables.
Eg: `curl ... | SWIVM_DIR=/usr/local/swivm bash` for a global install.

<sub>*NB. The installer can use `git`, `curl`, or `wget` to download `swivm`, whatever is available.*</sub>

### Manual install

For manual install create a folder somewhere in your filesystem with the `swivm.sh` file inside it. I put mine in `~/.swivm`.

Or if you have `git` installed, then just clone it, and check out the latest version:

    git clone https://github.com/fnogatz/swivm.git ~/.swivm && cd ~/.swivm && git checkout `git describe --abbrev=0 --tags`

To activate swivm, you need to source it from your shell:

    . ~/.swivm/swivm.sh

Add these lines to your `~/.bashrc`, `~/.profile`, or `~/.zshrc` file to have it automatically sourced upon login:

    export SWIVM_DIR="$HOME/.swivm"
    [ -s "$SWIVM_DIR/swivm.sh" ] && . "$SWIVM_DIR/swivm.sh" # This loads swivm

## Usage

You can create an `.swivmrc` file containing version number in the project root directory (or any parent directory).
`swivm use`, `swivm install`, `swivm exec`, `swivm run`, and `swivm which` will all respect an `.swivmrc` file when a version is not supplied.

To download, compile, and install the latest v7.2.x release of SWI-Prolog, do this:

    swivm install 7.2

And then in any new shell just use the installed version:

    swivm use 7.2

Or you can just run it:

    swivm run 7.2 --version

Or, you can run any arbitrary command in a subshell with the desired version of SWI-Prolog:

    swivm exec 7.2 swipl --version

You can also get the path to the executable to where it was installed:

    swivm which 7.2

In place of a version pointer like "6.2" or "v7.3" or "6.6.8", you can use the following special aliases with `swivm install`, `swivm use`, `swivm run`, `swivm exec`, `swivm which`, etc:

 - `stable`: this alias points to the most recent SWI-Prolog version with an even minor version number.
 - `devel`: this alias points to the most recent SWI-Prolog version with an odd minor version number.

If you want to use the system-installed version of SWI-Prolog, you can use the special default alias "system":

    swivm use system
    swivm run system --version

If you want to see what versions are installed:

    swivm ls

If you want to see what versions are available to install:

    swivm ls-remote

To restore your PATH, you can deactivate swivm:

    swivm deactivate

To set a default SWI-Prolog version to be used in any new shell, use the alias 'default':

    swivm alias default 7.2

## Problems

If you try to install a SWI-Prolog version and the installation fails, be sure to delete the SWI-Prolog downloads from src (\~/.swivm/src/) and versions (\~/.swivm/versions/) or you might get an error when trying to reinstall them again.

## License

swivm is released under the MIT license, like the original [nvm](https://github.com/creationix/nvm).
