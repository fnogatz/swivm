# SWI-Prolog Version Manager

swivm, the SWI-Prolog Version Manager, is a bash script to manage multiple active SWI-Prolog versions. It provides a uniform command line interface to install and execute SWI-Prolog since version 5. Being an adapted fork of the [Node Version Manager nvm](https://github.com/nvm-sh/nvm) it has a very similar interface.

## Installation

swivm does not support Windows. Make sure your system has the requirements for a manual SWI-Prolog installation from source.

Typically, the following libraries are required:

```sh
sudo apt-get install \
        build-essential autoconf curl chrpath pkg-config \
        ncurses-dev libreadline-dev libedit-dev \
        libunwind-dev \
        libgmp-dev \
        libssl-dev \
        unixodbc-dev \
        zlib1g-dev libarchive-dev \
        libossp-uuid-dev \
        libxext-dev libice-dev libjpeg-dev libxinerama-dev libxft-dev \
        libxpm-dev libxt-dev \
        libdb-dev \
        libpcre3-dev \
        libyaml-dev \
        openjdk-8-jdk junit \
        make ninja-build \
        cmake
```

If you want to reduce resources, the following packages are optional:

- `openjdk-8-jdk junit`: Without, you do not have Java connectivity (JPL).
- `unixodbc-dev`: Without, you have no ODBC database connectivity (e.g., MySQL)
- `libssl-dev`: Without, you have no SSL (and HTTPS) support.
- `libgmp-dev`: Without, you lack unbounded integer support, rational numbers, good random number generators, etc.
- `libarchive-dev`: Without, you can not unpack and install add-ons.
- `libpcre3-dev`: Without, you have no regular expression support ([library(pcre)](http://www.swi-prolog.org/pldoc/doc/_SWI_/library/pcre.pl)).
- `libyaml-dev`: Without, you have no YAML support ([library(yaml)](http://www.swi-prolog.org/pldoc/doc/_SWI_/library/yaml.pl)).

Additionally a Java compiler is required, so make sure `javac -version` is possible.

Building SWI-Prolog v7.7.20+ requires cmake version 3.5 or later.

### Install script

To install or update swivm, you can use the [install script](https://github.com/fnogatz/swivm/blob/v1.3.2/install.sh) using cURL:

```sh
curl -o- https://raw.githubusercontent.com/fnogatz/swivm/v1.3.2/install.sh | bash
```

or Wget:

```sh
wget -qO- https://raw.githubusercontent.com/fnogatz/swivm/v1.3.2/install.sh | bash
```

<sub>The script clones the swivm repository to `~/.swivm/` and adds the source line to your profile (`~/.bash_profile`, `~/.zshrc` or `~/.profile`).</sub>

You can customize the install source, directory and profile using the `SWIVM_SOURCE`, `SWIVM_DIR`, and `PROFILE` variables.
Eg: `curl ... | SWIVM_DIR=/usr/local/swivm bash` for a global install.

<sub>_NB. The installer can use `git`, `curl`, or `wget` to download swivm, whatever is available._</sub>

### Manual install

For manual install create a folder somewhere in your filesystem with the `swivm.sh` file inside it. I put mine in `~/.swivm/`.

Or if you have `git` installed, then just clone it, and check out the latest version:

```sh
git clone https://github.com/fnogatz/swivm.git ~/.swivm && cd ~/.swivm && git checkout `git describe --abbrev=0 --tags`
```

To activate swivm, you need to source it from your shell:

```sh
. ~/.swivm/swivm.sh
```

Add these lines to your `~/.bashrc`, `~/.profile`, or `~/.zshrc` file to have it automatically sourced upon login:

```sh
export SWIVM_DIR="$HOME/.swivm"
[ -s "$SWIVM_DIR/swivm.sh" ] && . "$SWIVM_DIR/swivm.sh" # This loads swivm
```

## Usage

You can create an `.swivmrc` file containing version number in the project root directory (or any parent directory).
`swivm use`, `swivm install`, `swivm exec`, `swivm run`, and `swivm which` will all respect an `.swivmrc` file when a version is not supplied.

To download, compile, and install the latest v8.2.x release of SWI-Prolog, do this:

```sh
swivm install 8.2
```

And then in any new shell just use the installed version:

```sh
swivm use 8.2
```

Or you can just run it:

```sh
swivm run 8.2 --version
```

Or, you can run any arbitrary command in a subshell with the desired version of SWI-Prolog:

```sh
swivm exec 8.2 swipl --version
```

You can also get the path to the executable to where it was installed:

```sh
swivm which 8.2
```

In place of a version pointer like "6.2" or "v7.3" or "6.6.8", you can use the following special aliases with `swivm install`, `swivm use`, `swivm run`, `swivm exec`, `swivm which`, etc.:

- `stable`: this alias points to the most recent SWI-Prolog version with an even minor version number.
- `devel`: this alias points to the most recent SWI-Prolog version with an odd minor version number.

If you want to use the system-installed version of SWI-Prolog, you can use the special default alias "system". The system version is this one not installed by swivm. If you have installed SWI-Prolog by, e.g., `apt-get install swi-prolog` or system-wide self-compiled, this will be the system version.

```sh
swivm use system
swivm run system --version
```

If you want to see what versions are installed:

```sh
swivm ls
```

If you want to see what versions are available to install:

```sh
swivm ls-remote
```

To restore your PATH, you can deactivate swivm:

```sh
swivm deactivate
```

To set a default SWI-Prolog version to be used in any new shell, use the alias 'default':

```sh
swivm alias default 8.2
```

## Usage with GitHub Actions

swivm provides two workflows for usage with [GitHub Actions](https://docs.github.com/en/actions/learn-github-actions):

- `fnogatz/swivm/actions/install@main` just installs the latest version of swivm into `~/.swivm/`, so it can be used after `. ~/.swivm/swivm.sh`.
- `fnogatz/swivm/actions/load@main` installs swivm as well as SWI-Prolog. Its version can be specified by the `swi-prolog-version` input value (default: `devel`). swivm and SWI-Prolog are available after `. ~/.swivm/swivm.sh`.

Here is a non-exhaustive list of projects that use the GitHub Actions provided by swivm:

- [tap](https://github.com/fnogatz/tap)

Please open an issue if you want to have your project listed here.

## Known Problems

If you try to install a SWI-Prolog version and the installation fails, be sure to delete the SWI-Prolog downloads from src (`~/.swivm/src/`) and versions (`~/.swivm/versions/`) or you might get an error when trying to reinstall them again.
