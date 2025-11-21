# cdl

A small Bash helper that combines `cd` and a compact, colored `ls` into a single interactive command.

> It changes the current directory and immediately prints a clear, compact overview of its contents - showing names, sizes, timestamps and symlink targets, with directories first and a layout that adapts to your terminal width and the amount of content.

---

## Features

1. **`cd` + `ls` in one step**

   * `cdl /path/to/dir` → change into `/path/to/dir` and show a listing.
   * `cdl` with no arguments → go to `$HOME` and list it.

2. **Argument, stdin, or fallback**

   * Uses an explicit argument when provided.
   * Otherwise, if stdin is not a TTY, reads the **first non-empty line** as the directory.
   * If both are missing, falls back to `$HOME`.

3. **Adaptive, compact listing**

   * On systems with **GNU `ls`** (or `gls` on macOS):

     * uses `--group-directories-first`, `-Alh`, human‑readable sizes, and a fixed timestamp format,
     * computes visible width (stripping ANSI sequences) and tries to render the output in **two columns** if it fits,
     * falls back to a single column if the terminal is narrow or entry names are too long.
   * On systems without GNU flags (BSD/macOS default):

     * falls back to `ls -AlhG` without parsing, avoiding portability issues.

4. **Safe to source repeatedly**

   * Defines a `cdl` function and a few internal helpers under `__cdl_*`.
   * Error codes (`CDL_ERR_*`) are `readonly` and safe to override only once.

> [!TIP]
> Think of `cdl` as "`cd` with a built‑in, nicer `ls`" for interactive work.

---

## Requirements

* **Bash** (uses `[[ ... ]]`, `local`, and other Bash features)
* Standard `ls` (GNU or BSD)

Optional:

* **GNU `ls`** or `gls` (Homebrew coreutils on macOS) - enables the adaptive two‑column listing.

The script is otherwise self‑contained and does not depend on external utilities.

---

## Installation

`cdl.sh` is intended to be **sourced**, not executed.

### 1. Put the script somewhere permanent

For example:

```bash
ln -s <path-to-cdl.sh>/cdl.sh <path-to-home>/.cdl.sh
```

### 2. Source it from your shell profile

In `~/.bashrc` (or `~/.bash_profile` / `~/.profile` depending on your setup):

```bash
if [[ -f "${HOME}/.cdl.sh" ]]; then
  source "${HOME}/.cdl.sh"
fi
```

Reload your shell configuration or open a new terminal.

After that, `cdl` is available as a shell function.

> [!IMPORTANT]
> If you run `./cdl.sh` directly, it will print an error and exit with `CDL_ERR_NOT_SOURCED`. 
> The script must be **sourced**, because only a sourced function can change the parent shell's current directory.

---

## Quick start

### Basic usage

```bash
cdl                 # cd to $HOME and list it
cdl /tmp            # cd to /tmp and list it
cdl ~/Documents     # cd to ~/Documents and list it
cdl .               # list the current directory
cdl ..              # cd to the parent directory and list it
cdl ~               # cd to the previous directory ($OLD_PWD) and list it
```

<img width="1717" height="788" alt="image" src="https://github.com/user-attachments/assets/6e5dcd7e-c66d-4374-ba90-0393c7c6a7e3" />

### Use command output as a target directory

Since pipelines run in subshells, use **command substitution** to let `cdl` actually change your current directory:

```bash
cdl "$(xclip -o)"               # cd to path currently in clipboard (Linux + xclip)
cdl "$(pwd | sed 's/old/new/')" # cd to a transformed path
```

### Peek into a directory without changing the current shell directory

You can pipe a path into `cdl` to just show its listing:

```bash
echo '/var/log' | cdl
```

In this mode, `cdl` changes directory only inside the subshell created by the pipeline; your interactive shell stays where it was.

> [!NOTE]
> **Pipe limitation:** `echo ... | cdl` will never change the parent shell's working directory, only display the contents of the target directory.
> To actually move, use `cdl "$(command)"`.

---

## Behavior details

1. **Target directory resolution**

   * If an explicit argument is given, it is used.
   * Else, if stdin is not a TTY, the first non‑empty line from stdin is used (with leading/trailing whitespace trimmed).
   * Else, `$HOME` is used (or `/` if `$HOME` is unset).

2. **Error handling**

   * If `cd` fails (directory does not exist or is not accessible), `cdl` prints an error and returns `CDL_ERR_CHDIR`.
   * All errors are printed to stderr.

3. **Listing format**

   * Skips the `total N` line from `ls` output.
   * Shows size, timestamp, and name (including symlink targets) in aligned columns.
   * On GNU systems, the script tries to use two columns when `tput cols` reports enough width and all entries fit side by side.

---

## Exit / return codes

When used as a function, `cdl` **returns** one of the following codes:

* `0` – success
* `1` (`CDL_ERR_GENERAL`) – generic error
* `2` (`CDL_ERR_CHDIR`) – target directory does not exist or cannot be accessed
* `3` (`CDL_ERR_NOT_SOURCED`) – script was executed instead of sourced

These constants are also available as shell variables if you want to check for specific conditions in your scripts.

---

## Examples for shell customization

### Make `cdl` your default `cd`

If you like the behavior, you can wrap `cd` to always list after changing:

```bash
cd() {
  builtin cd "$@" && __cdl_print_listing
}
```

Or simply train your fingers to use `cdl` when you want an immediate listing and `cd` for minimal changes.

---

## License & disclaimer

This project is licensed under the [MIT License](./LICENSE).

> [!IMPORTANT]
> This helper is meant for interactive use. It does not attempt to be a fully portable listing tool across all Unix variants.
> Always verify the resolved target path and behavior in your environment before relying on it in automation or critical workflows.
