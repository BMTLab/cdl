<h1 align="center">cdl</h1>

<div align="center">

**`cd` and a compact, colored `ls` in one step, for bash and zsh.**

[![CI][ci-badge]][ci]
[![Release][release-badge]][releases]
[![License: MIT][license-badge]](./LICENSE)

![cdl in a terminal: a project in columns under a header with its git branch,
a file marked in its folder, Tab completion, a long folder cut around
a marked photo, and an error with its code][demo]

</div>

## Features

- 📂 **One step.** `cdl DIR` enters `DIR` and lists it:
  size, date and name, directories first, in as many columns as fit.
- 🧭 **A header line** names the folder, its git branch and what it holds:
  `~/projects/app · main · 3 dirs, 12 files, 1.4M`.
- 📄 **Files too.** `cdl notes/todo.md` enters `notes` and marks `todo.md`.
- ✂️ **Long folders stay on screen.** The listing is cut at the window height,
  around the file you asked for; `cdl -a` shows everything.
- 🌏 **Aligned in any language.** Widths are counted in screen cells,
  so Cyrillic, CJK and emoji names stay in their columns.
- 📋 **Pasted paths work:** a `file://` URI, or a `~` that no shell expanded.
- 🔁 **It can replace `cd`,** options and Tab completion included:
  see [Replacing `cd`](#replacing-cd).
- ⌨️ **Tab completion** in bash and zsh,
  and **clickable names** in terminals that show hyperlinks.
- 🚦 **Clear errors,** each with a return code of its own.
- ⚡ **Fast.** One `ls` and one `awk` per call, about 5 ms;
  the branch is read without running `git`.

## Install

Download cdl, and load it from the startup file of your shell:

```bash
curl -fsSLo ~/.cdl.sh https://github.com/BMTLab/cdl/releases/latest/download/cdl.sh
echo '[[ -f ~/.cdl.sh ]] && source ~/.cdl.sh' >>~/.bashrc   # or ~/.zshrc
```

Then open a new terminal and try `cdl ~`.

cdl needs bash 3.2+ or zsh 5.0+, and any POSIX awk.
GNU `ls`, uutils `ls` or Homebrew's `gls` give the compact listing;
with the BSD `ls` of macOS, cdl prints a plain `ls -Alh`
(`brew install coreutils` brings `gls`).

<details>
<summary><b>From a clone, or with a zsh plugin manager</b></summary>

From a clone, `make install` links `~/.cdl.sh` to it,
so a `git pull` updates cdl:

```bash
git clone https://github.com/BMTLab/cdl.git
cd cdl
make install                     # links ~/.cdl.sh to this clone
make install INSTALL_MODE=copy   # or copies the file instead
```

A zsh plugin manager loads `cdl.plugin.zsh`, which sources `cdl.sh`:

```bash
zinit light BMTLab/cdl                    # zinit
echo 'BMTLab/cdl' >>~/.zsh_plugins.txt    # antidote
# oh-my-zsh: clone into its custom plugins, then add cdl to plugins=(...)
git clone https://github.com/BMTLab/cdl.git "${ZSH_CUSTOM}/plugins/cdl"
```

</details>

### Replacing `cd`

cdl can take the place of `cd`:
`cd` then lists every folder, takes files,
and offers the options of cdl on <kbd>Tab</kbd>.

Open `~/.bashrc` or `~/.zshrc`,
find the line that loads cdl (`source ~/.cdl.sh`),
and add this line just above it:

```bash
export CDL_REPLACE_CD=1
```

Then open a new terminal.
Where `cd` writes to no terminal, as in `$(cd dir && pwd)`,
it stays the shell's own, so scripts and other tools keep working.

## Usage

```text
cdl [-a] [-1] [-L | -P] [DIRECTORY | FILE]
```

`cdl DIR` enters `DIR` and lists it.
`cdl FILE` enters the folder of `FILE` and marks the file.
Without an argument, cdl goes home, and `cdl -` goes back, as `cd` does.
`-a` shows every entry, `-1` one entry per row,
and `-L` and `-P` treat symlinks as `cd` does.
`cdl -h` prints the full help.

### Ways to use it

```bash
cdl ~/Downloads/report.pdf              # land next to a file, marked
cdl /usr/bin/zsh                        # thousands of files, cut around zsh
cdl "$(command -v git)"                 # where a command lives
cdl "$(git rev-parse --show-toplevel)"  # the root of this repository
cdl "$(fzf)"                            # pick any file with fzf, land next to it
cdl "$(wl-paste)"                       # a path or a file:// URI from the clipboard
CDL_COLOR=always cdl -a /usr/bin | less -R   # page through a big folder, in color
```

<details>
<summary><b>Settings</b></summary>

cdl reads these environment variables.
An empty value counts as unset,
and an invalid one fails with `CDL_ERR_SETTING` before cdl moves.
`CDL_REPLACE_CD` acts when cdl is loaded,
so it goes above the line that loads it.

| Variable          | Values                    | Default | Effect                                              |
|-------------------|---------------------------|---------|-----------------------------------------------------|
| `CDL_COLOR`       | `auto`, `always`, `never` | `auto`  | Colors; `auto` colors a terminal                    |
| `CDL_HIDDEN`      | `1`, `0`                  | `1`     | `0` leaves hidden entries out                       |
| `CDL_WIDTH`       | a positive number         | empty   | Width of the terminal                               |
| `CDL_MAX_ROWS`    | a number                  | empty   | Rows before a listing is cut; `0` never cuts        |
| `CDL_MAX_COLUMNS` | a number                  | empty   | Most columns side by side                           |
| `CDL_HEADER`      | `auto`, `always`, `never` | `auto`  | The header line; `auto` shows it on a terminal      |
| `CDL_GIT`         | `1`, `0`                  | `1`     | `0` leaves the git branch out of the header         |
| `CDL_LINKS`       | `auto`, `always`, `never` | `auto`  | Names as hyperlinks to their files                  |
| `CDL_REPLACE_CD`  | `1`, `0`                  | `0`     | `cd` runs cdl, with its options and completion      |

`cdl -h` tells more about each of them.

</details>

<details>
<summary><b>Return codes</b></summary>

cdl returns these codes, which are also read-only shell variables.
The tens digit names what failed, and the units digit why,
so `(( $? / 10 == 3 ))` holds whenever a directory could not be entered.

| Code | Name                    | When                                                   |
|------|-------------------------|--------------------------------------------------------|
| `0`  |                         | Success                                                |
| `10` | `CDL_ERR_USAGE`         | A wrong option, or a wrong directory argument          |
| `20` | `CDL_ERR_SETTING`       | A `CDL_*` setting with an invalid value                |
| `30` | `CDL_ERR_CHDIR`         | The directory could not be entered, for another reason |
| `31` | `CDL_ERR_NOT_FOUND`     | No such directory, or no previous one for `cdl -`      |
| `32` | `CDL_ERR_DENIED`        | No permission to enter it, or a directory on the way   |
| `33` | `CDL_ERR_NOT_DIRECTORY` | A file where the path needs a directory                |
| `40` | `CDL_ERR_LIST`          | Entered, but `ls` could not list it in full            |
| `50` | `CDL_ERR_NOT_SOURCED`   | `cdl.sh` was run, not sourced into bash or zsh         |

</details>

## License

cdl is free software under the [MIT License](./LICENSE).
Bug reports and pull requests are welcome:
see [CONTRIBUTING.md](./CONTRIBUTING.md).

> [!WARNING]
> cdl comes with no warranty of any kind, and you use it at your own risk.
> The author takes no responsibility for any damage or loss it may cause.
> See the [LICENSE](./LICENSE) for the full terms.

[ci]: https://github.com/BMTLab/cdl/actions/workflows/ci-main.yml
[ci-badge]: https://github.com/BMTLab/cdl/actions/workflows/ci-main.yml/badge.svg
[releases]: https://github.com/BMTLab/cdl/releases
[release-badge]: https://img.shields.io/github/v/release/BMTLab/cdl?sort=semver
[license-badge]: https://img.shields.io/badge/License-MIT-blue.svg
[demo]: docs/demo/demo.gif
