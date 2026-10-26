#!/usr/bin/env bash

# Prepare the shell that docs/demo/demo.tape records.
#
# Usage: sourced by docs/demo/demo.tape, from the root of the repository:
#   source docs/demo/setup.bash
# Effects: makes a scratch HOME in ${TMPDIR:-/tmp}/cdl-demo,
#   in place of the one an earlier recording left,
#   and exports HOME and CDL_LINKS=never;
#   then it sources cdl.sh, enters HOME and sets a short prompt.
# Dependencies: git, awk, and the GNU truncate and touch: record on Linux.
# See: make demo, docs/demo/demo.tape.
#
# How it works:
#   The scratch HOME holds a small project, a folder of photos
#   and a folder that may not be entered, each file with a size
#   and a date of its own, so the recording shows the same listings
#   on every machine. The tape sources this file out of sight.
#   Links stay off: the terminal of the recorder underlines them all.
#
# Version: 1.0.0

# region Fixtures

#######################################
# Make an empty scratch HOME,
# removing the one an earlier recording left behind.
#
# Arguments:
#   1: Directory.
#######################################
function demo_make_home() {
  local -r home="$1"

  # The folder that may not be entered has to open up before it can go.
  if [[ -d "${home}" ]]; then
    command chmod -R u+rwx "${home}"
    command rm -rf -- "${home}"
  fi

  command mkdir -p -- "${home}"
}

#######################################
# Print the bytes of a size in IEC units, rounded down,
# so that `ls -h`, which rounds up, prints the size as it was written.
#
# Arguments:
#   1: Size, e.g. 760, 4.2K, 1.4M.
# Outputs:
#   The number of bytes.
#######################################
function demo_bytes() {
  command awk -v size="$1" 'BEGIN {
    unit["K"] = 1024
    unit["M"] = 1024 * 1024
    unit["G"] = 1024 * 1024 * 1024
    suffix = size
    sub(/^[0-9.]+/, "", suffix)
    printf "%d", size * (suffix in unit ? unit[suffix] : 1)
  }'
}

#######################################
# Create a file of a given size and date.
#
# Arguments:
#   1: Path.
#   2: Size in IEC units, as `ls -h` prints them (e.g. 760, 4.2K, 1.4M).
#   3: Date, as touch -d reads it.
#######################################
function demo_file() {
  local -r path="$1"
  local -r size="$2"
  local -r date="$3"

  command mkdir -p -- "${path%/*}"
  command truncate -s "$(demo_bytes "${size}")" -- "${path}"
  command touch -d "${date}" -- "${path}"
}

#######################################
# Build the project the demo walks through, a git repository.
#
# Arguments:
#   1: Directory of the project.
#######################################
function demo_make_project() {
  local -r project="$1"

  demo_file "${project}/README.md" 4.2K '2026-10-02 18:40'
  demo_file "${project}/CHANGELOG.md" 9.6K '2026-10-03 11:05'
  demo_file "${project}/LICENSE" 1.1K '2026-01-14 09:00'
  demo_file "${project}/Makefile" 2.3K '2026-09-28 21:17'
  demo_file "${project}/deploy.sh" 760 '2026-09-30 16:42'
  command chmod +x "${project}/deploy.sh"
  demo_file "${project}/Отчёт за квартал.pdf" 1.4M '2026-09-29 10:12'
  demo_file "${project}/日本語メモ.txt" 380 '2026-09-25 08:31'
  demo_file "${project}/.gitignore" 120 '2026-01-14 09:00'
  demo_file "${project}/src/main.go" 12K '2026-10-04 22:03'
  demo_file "${project}/tests/main_test.go" 8.1K '2026-10-04 22:10'
  demo_file "${project}/docs/guide.md" 15K '2026-10-01 14:55'
  demo_file "${project}/docs/api.md" 22K '2026-09-27 19:30'
  demo_file "${project}/docs/faq.md" 3.9K '2026-09-21 12:00'
  demo_file "${project}/docs/images/flow.svg" 6.4K '2026-09-21 12:00'
  demo_file "${project}/assets/logo.svg" 2.8K '2026-08-11 15:20'
  demo_file "${project}/assets/banner.png" 310K '2026-08-11 15:24'
  demo_file "${project}/assets/favicon.ico" 15K '2026-08-11 15:26'
  demo_file "${project}/assets/screenshot.webp" 184K '2026-09-30 17:05'
  demo_file "${project}/assets/fonts/Inter.woff2" 98K '2026-08-02 10:00'
  demo_file "${project}/assets/icons/menu.svg" 640 '2026-08-02 10:00'

  command ln -s docs/guide.md "${project}/latest"
  command git init --quiet --initial-branch=main "${project}"

  command touch -h -d '2026-10-01 14:56' -- "${project}/latest"
  command touch -d '2026-10-05 09:00' -- \
    "${project}"/{.git,src,tests,docs,assets,docs/images,assets/fonts,assets/icons}
}

#######################################
# Fill a folder with photos, more than a screen can show.
#
# Arguments:
#   1: Directory of the photos.
#######################################
function demo_make_photos() {
  local -r photos="$1"
  local -i number

  for ((number = 1; number <= 240; number++)); do
    demo_file "${photos}/IMG_$((2000 + number)).jpg" \
      "$((2 + number % 5)).$((number % 10))M" \
      "2026-07-$((1 + number % 28)) 1$((number % 10)):$((10 + number % 50))"
  done
}

#######################################
# Make a folder that may not be entered, with another inside it.
#
# Arguments:
#   1: Directory.
#######################################
function demo_make_locked() {
  local -r locked="$1"

  command mkdir -p -- "${locked}/inner"
  command chmod 000 "${locked}"
}

# endregion Fixtures

# region Shell

#######################################
# Build the scratch HOME, source cdl and set a short prompt.
#
# Globals:
#   TMPDIR (read); HOME, PS1, CDL_LINKS (write).
#######################################
function demo_setup() {
  local -r cdl_script="${PWD}/cdl.sh"
  local -r home="${TMPDIR:-/tmp}/cdl-demo"

  demo_make_home "${home}"
  export HOME="${home}"
  demo_make_project "${HOME}/projects/aurora"
  demo_make_photos "${HOME}/photos"
  demo_make_locked "${HOME}/vault"

  export CDL_LINKS='never'
  # shellcheck source=../../cdl.sh
  source "${cdl_script}"

  builtin cd -- "${HOME}" || return
  PS1='\[\e[1;36m\]\W\[\e[0m\] \[\e[1;35m\]❯\[\e[0m\] '
}

demo_setup

# endregion Shell

### End
