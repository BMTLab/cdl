#!/usr/bin/env bash

# Name: tools/ci/install-tools.sh
# Author: Nikita Neverov (BMTLab)
# License: MIT
#
# Description:
#   Install the tools a CI job needs, at pinned versions,
#   and put them on the PATH of the steps that follow.
#   Every download is checked against a pinned SHA-256 digest
#   before it reaches the PATH,
#   and bats-core is checked out at a pinned commit,
#   so a moved tag or a swapped asset cannot slip into a build.
#
#   The cache directory, which actions/cache keeps between runs,
#   spares the network: a pinned download found there is used
#   while it still matches its digest, the .deb files there install
#   without apt-get update, and Homebrew keeps its bottles there,
#   checked against the digests of its formulae.
#
# Usage:
#   tools/ci/install-tools.sh TOOL...
#
#   Tools with pinned versions:
#     - shellcheck: the ShellCheck release binary (Linux x86_64 or arm64);
#     - shfmt: the shfmt release binary (Linux x86_64 or arm64);
#     - actionlint: the actionlint release binary (Linux x86_64 or arm64);
#     - bats: bats-core at a pinned commit.
#   Any other name is a system package:
#   apt-get installs it on Linux, Homebrew on macOS.
#
# Environment:
#   GITHUB_PATH: set by GitHub Actions (and by nektos/act);
#   without it, the tools still land in the tools directory,
#   which the caller puts on PATH.
#   CI_CACHE_DIR: the cache directory (default: ~/.cache/cdl-ci).
#
# Exit Codes:
#   0: Success.
#   10: INSTALL_ERR_USAGE
#      No tool was named.
#   11: INSTALL_ERR_DOWNLOAD
#      A download failed or did not match its pinned digest,
#      or apt-get could not reach its mirrors.
#   12: INSTALL_ERR_PLATFORM
#      There is no pinned binary for this machine.

set -o errexit -o nounset -o pipefail

readonly INSTALL_ERR_USAGE=10
readonly INSTALL_ERR_DOWNLOAD=11
readonly INSTALL_ERR_PLATFORM=12

readonly CI_SCRIPT_NAME='install-tools'
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# region Pinned versions

# The versions of ShellCheck and shfmt match what the maintainer runs,
# so CI and a local `make check` judge the code alike.
# To move one: change the version, then take the new digests
# from `gh release view TAG --repo OWNER/REPO --json assets`.
readonly SHELLCHECK_VERSION='0.11.0'
readonly SHELLCHECK_SHA256_X86_64='8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198'
readonly SHELLCHECK_SHA256_AARCH64='12b331c1d2db6b9eb13cfca64306b1b157a86eb69db83023e261eaa7e7c14588'

readonly SHFMT_VERSION='3.14.1'
readonly SHFMT_SHA256_AMD64='76e77641faa025814b77f153b29796b8e6fa2fca03e0c76a691608b86c7ea7bf'
readonly SHFMT_SHA256_ARM64='5f2db09dae91fca848f7adbdd014632e921a383863a2ad7e0450ad3aba0c6489'

readonly ACTIONLINT_VERSION='1.7.12'
readonly ACTIONLINT_SHA256_AMD64='8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8'
readonly ACTIONLINT_SHA256_ARM64='325e971b6ba9bfa504672e29be93c24981eeb1c07576d730e9f7c8805afff0c6'

readonly BATS_VERSION='1.14.0'
readonly BATS_COMMIT='eb7f42f8d608ac693d7a4b67474f6714ea68cfc5'

# endregion

# region Limits

# apt-get update reaches the mirrors only on a cache miss,
# and one that stalls, as it does at times on Ubuntu 22.04,
# gets two minutes an attempt instead of the whole job.
readonly APT_UPDATE_TIMEOUT_SECONDS=120
readonly APT_UPDATE_ATTEMPTS=3

# endregion

TOOLS_PREFIX="${RUNNER_TEMP:-${HOME}/.local}/cdl-tools"
readonly TOOLS_PREFIX
readonly TOOLS_BIN="${TOOLS_PREFIX}/bin"

CACHE_DIR="${CI_CACHE_DIR:-${HOME}/.cache/cdl-ci}"
readonly CACHE_DIR

DOWNLOADS="$(mktemp -d)"
readonly DOWNLOADS
trap 'rm -rf -- "${DOWNLOADS}"' EXIT

# region Helpers

#######################################
# Download a file, or take it from the cache,
# and check it against its SHA-256 digest.
#
# Only a file that matches its digest is handed on;
# a cached file that does not is fetched again.
#
# Arguments:
#   1: URL.
#   2: Expected SHA-256, in hex.
#
# Outputs:
#   The path of the checked file to stdout.
#
# Returns:
#   0 on success; INSTALL_ERR_DOWNLOAD otherwise.
#######################################
function download_verified() {
  local -r url="$1"
  local -r expected="$2"
  local -r file="${CACHE_DIR}/downloads/${url##*/}"

  if [[ -f ${file} && $(sha256_of "${file}") == "${expected}" ]]; then
    printf '%s\n' "${file}"
    return 0
  fi

  mkdir -p "${file%/*}"
  if ! curl --fail --silent --show-error --location --retry 3 \
    --output "${file}" "${url}"; then
    ci_error "download failed: ${url}" "${INSTALL_ERR_DOWNLOAD}" || return
  fi

  local actual
  actual="$(sha256_of "${file}")"
  if [[ ${actual} != "${expected}" ]]; then
    rm -f "${file}"
    ci_error "digest mismatch for ${url}: got ${actual}" "${INSTALL_ERR_DOWNLOAD}" || return
  fi

  printf '%s\n' "${file}"
}

#######################################
# Print the machine name a release asset uses.
#
# Arguments:
#   1: Name for x86_64.
#   2: Name for 64-bit ARM.
#
# Returns:
#   0 on success; INSTALL_ERR_PLATFORM on another OS or CPU.
#######################################
function asset_arch() {
  local -r x86_64_name="$1"
  local -r arm64_name="$2"

  if [[ $(uname -s) != 'Linux' ]]; then
    ci_error 'pinned binaries are for Linux only' "${INSTALL_ERR_PLATFORM}" || return
  fi

  case $(uname -m) in
    x86_64) printf '%s\n' "${x86_64_name}" ;;
    aarch64 | arm64) printf '%s\n' "${arm64_name}" ;;
    *) ci_error "no pinned binary for $(uname -m)" "${INSTALL_ERR_PLATFORM}" ;;
  esac
}

#######################################
# Pick the digest of the asset for this machine.
#
# Arguments:
#   1: The machine name asset_arch printed.
#   2: The x86_64 name.
#   3: Digest of the x86_64 asset.
#   4: Digest of the 64-bit ARM asset.
#######################################
function digest_for() {
  local -r arch="$1"
  local -r x86_64_name="$2"
  local -r x86_64_digest="$3"
  local -r arm64_digest="$4"

  if [[ ${arch} == "${x86_64_name}" ]]; then
    printf '%s\n' "${x86_64_digest}"
  else
    printf '%s\n' "${arm64_digest}"
  fi
}

# endregion

# region Installers

#######################################
# Install the pinned ShellCheck.
#######################################
function install_shellcheck() {
  local arch digest archive
  arch="$(asset_arch 'x86_64' 'aarch64')"
  digest="$(digest_for "${arch}" 'x86_64' \
    "${SHELLCHECK_SHA256_X86_64}" "${SHELLCHECK_SHA256_AARCH64}")"

  local -r name="shellcheck-v${SHELLCHECK_VERSION}"
  archive="$(download_verified \
    "https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/${name}.linux.${arch}.tar.xz" \
    "${digest}")"

  tar -xJf "${archive}" -C "${DOWNLOADS}"
  install -m 0755 "${DOWNLOADS}/${name}/shellcheck" "${TOOLS_BIN}/shellcheck"
}

#######################################
# Install the pinned shfmt.
#######################################
function install_shfmt() {
  local arch digest binary
  arch="$(asset_arch 'amd64' 'arm64')"
  digest="$(digest_for "${arch}" 'amd64' "${SHFMT_SHA256_AMD64}" "${SHFMT_SHA256_ARM64}")"

  binary="$(download_verified \
    "https://github.com/mvdan/sh/releases/download/v${SHFMT_VERSION}/shfmt_v${SHFMT_VERSION}_linux_${arch}" \
    "${digest}")"

  install -m 0755 "${binary}" "${TOOLS_BIN}/shfmt"
}

#######################################
# Install the pinned actionlint.
#######################################
function install_actionlint() {
  local arch digest archive
  arch="$(asset_arch 'amd64' 'arm64')"
  digest="$(digest_for "${arch}" 'amd64' \
    "${ACTIONLINT_SHA256_AMD64}" "${ACTIONLINT_SHA256_ARM64}")"

  archive="$(download_verified \
    "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_${arch}.tar.gz" \
    "${digest}")"

  tar -xzf "${archive}" -C "${DOWNLOADS}" actionlint
  install -m 0755 "${DOWNLOADS}/actionlint" "${TOOLS_BIN}/actionlint"
}

#######################################
# Install bats-core from its pinned commit.
#
# Returns:
#   0 on success; INSTALL_ERR_DOWNLOAD if the tag points elsewhere.
#######################################
function install_bats() {
  local -r checkout="${DOWNLOADS}/bats-core"

  git clone --quiet --depth 1 --branch "v${BATS_VERSION}" \
    https://github.com/bats-core/bats-core.git "${checkout}"

  local commit
  commit="$(git -C "${checkout}" rev-parse HEAD)"
  if [[ ${commit} != "${BATS_COMMIT}" ]]; then
    ci_error "bats v${BATS_VERSION} is ${commit}, not ${BATS_COMMIT}" \
      "${INSTALL_ERR_DOWNLOAD}" || return
  fi

  "${checkout}/install.sh" "${TOOLS_PREFIX}" >/dev/null
}

#######################################
# Install system packages with the package manager of the runner.
#
# Arguments:
#   $@: Package names.
#######################################
function install_packages() {
  if (($# == 0)); then
    return 0
  fi

  if [[ $(uname -s) == 'Darwin' ]]; then
    install_brew_packages "$@"
  else
    install_apt_packages "$@"
  fi
}

#######################################
# Install packages with Homebrew, which keeps its bottles in the cache
# and checks each against the digest of its formula.
#
# Arguments:
#   $@: Package names.
#######################################
function install_brew_packages() {
  HOMEBREW_CACHE="${CACHE_DIR}/homebrew" HOMEBREW_NO_AUTO_UPDATE=1 \
    brew install --quiet "$@"
}

#######################################
# Install the packages the runner lacks, from the cache if it can.
#
# A package whose command is on the PATH already is left alone.
# The .deb files of the others come from the cache;
# only on a miss, or when they no longer install,
# apt-get reaches the mirrors and fills the cache again.
# The log names each step, so a stall shows where it is.
#
# Arguments:
#   $@: Package names, each also the name of its command.
#
# Returns:
#   0 on success; INSTALL_ERR_DOWNLOAD if the mirrors cannot be reached.
#######################################
function install_apt_packages() {
  local -r debs="${CACHE_DIR}/apt"
  local package
  local -a missing=()

  for package in "$@"; do
    if ! command -v "${package}" >/dev/null; then
      missing+=("${package}")
    fi
  done
  if ((${#missing[@]} == 0)); then
    printf 'apt: %s already installed\n' "$*"
    return 0
  fi

  # apt rebuilds the index of the man pages after an install,
  # which can take minutes on the Ubuntu images of GitHub;
  # CI reads no man pages.
  sudo rm -f /var/lib/man-db/auto-update

  if install_debs "${debs}"; then
    printf 'apt: %s installed from the cache\n' "${missing[*]}"
    return 0
  fi

  rm -rf "${debs}"
  update_package_lists || return
  download_debs "${debs}" "${missing[@]}" || return
  if ! install_debs "${debs}"; then
    ci_error "the .deb files of ${missing[*]} did not install" "${INSTALL_ERR_DOWNLOAD}" || return
  fi
}

#######################################
# Install the .deb files of a directory, if there are any.
#
# A cached file older than the version a newer runner image ships
# is skipped rather than installed over it (--refuse-downgrade).
#
# Arguments:
#   1: Directory of .deb files.
#
# Returns:
#   0 once they are installed; 1 if there are none, or dpkg fails.
#######################################
function install_debs() {
  local -r debs="$1"
  local -a files=("${debs}"/*.deb)

  if [[ ! -f ${files[0]} ]]; then
    return 1
  fi

  printf 'dpkg -i %s\n' "${files[*]##*/}"
  sudo DEBIAN_FRONTEND=noninteractive dpkg -i --refuse-downgrade "${files[@]}" >/dev/null
}

#######################################
# Refresh the package lists of apt, in bounded attempts.
#
# Globals:
#   APT_UPDATE_TIMEOUT_SECONDS, APT_UPDATE_ATTEMPTS (read).
#
# Returns:
#   0 on success; INSTALL_ERR_DOWNLOAD after the last failed attempt.
#######################################
function update_package_lists() {
  local -i attempt

  for ((attempt = 1; attempt <= APT_UPDATE_ATTEMPTS; attempt++)); do
    printf 'apt-get update, attempt %d of %d\n' "${attempt}" "${APT_UPDATE_ATTEMPTS}"
    if timeout "${APT_UPDATE_TIMEOUT_SECONDS}" \
      sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq; then
      return 0
    fi
  done

  ci_error "apt-get update failed ${APT_UPDATE_ATTEMPTS} times" "${INSTALL_ERR_DOWNLOAD}"
}

#######################################
# Download the .deb files of packages and of the dependencies they lack.
#
# apt writes them as root;
# actions/cache saves them as the runner, after the job.
#
# Arguments:
#   1: Directory for the .deb files.
#   $@: Package names.
#
# Returns:
#   0 on success; INSTALL_ERR_DOWNLOAD otherwise.
#######################################
function download_debs() {
  local -r debs="$1"
  shift

  mkdir -p "${debs}/partial"
  printf 'apt-get install --download-only %s\n' "$*"
  if ! sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
    --download-only -o Dir::Cache::archives="${debs}" "$@" >/dev/null; then
    ci_error "apt-get could not download $*" "${INSTALL_ERR_DOWNLOAD}" || return
  fi
  sudo rm -rf "${debs}/partial" "${debs}/lock"
  sudo chown -R "$(id -u):$(id -g)" "${debs}"
}

# endregion

# region Entry point

#######################################
# Install every tool named on the command line.
#
# Arguments:
#   $@: Tool names, see the usage.
#######################################
function main() {
  if (($# == 0)); then
    ci_error 'name at least one tool' "${INSTALL_ERR_USAGE}" || return
  fi

  mkdir -p "${TOOLS_BIN}"
  if [[ -n ${GITHUB_PATH-} ]]; then
    printf '%s\n' "${TOOLS_BIN}" >>"${GITHUB_PATH}"
  fi

  local tool
  local -a packages=()
  for tool in "$@"; do
    case ${tool} in
      shellcheck) install_shellcheck ;;
      shfmt) install_shfmt ;;
      actionlint) install_actionlint ;;
      bats) install_bats ;;
      *) packages+=("${tool}") ;;
    esac
  done

  # The +-expansion keeps an empty list working under set -u in bash 3.2.
  install_packages ${packages[@]+"${packages[@]}"}
}

# endregion

main "$@"

### End
