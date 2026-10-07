#!/usr/bin/env python3

# ruff: file-ignore[commented-out-code]
# The header below follows the shell files of this repository;
# ruff's "commented-out code" heuristic mistakes its `Key: value` lines for code.

# Name: tools/gen-width-table.py
# Author: Nikita Neverov (BMTLab)
# License: MIT
#
# Description:
#   Generate the screen-width table
#   that the awk formatter in cdl.sh uses to align names in two columns.
#   The table comes from the Unicode database bundled with Python
#   (the unicodedata module), so nothing is downloaded,
#   and the Unicode version is the one the local Python ships.
#
#   Width rules, in screen cells per code point:
#     0  nonspacing and enclosing marks (Mn, Me), format characters (Cf),
#        and the Hangul Jamo medial vowels and final consonants
#        (U+1160..U+11FF), which combine with the syllable before them;
#        U+00AD SOFT HYPHEN stays at 1, as in glibc wcwidth.
#     2  East Asian Wide (W) and Fullwidth (F) characters,
#        which include emoji with default emoji presentation.
#     1  everything else, which therefore stays out of the table.
#   Neighbouring code points of the same width form one range;
#   unassigned code points join a range
#   when unicodedata reports the same width for them.
#   The scan covers U+00A0..U+10FFFF without the surrogates.
#
#   In cdl.sh the block lives between the `# region Width table` marker
#   and the next `# endregion` marker, as one blank line, the block,
#   and one blank line.
#
# Usage:
#   tools/gen-width-table.py                 Print the block to stdout.
#   tools/gen-width-table.py --write cdl.sh  Replace the block in place.
#   tools/gen-width-table.py --check cdl.sh  Compare the block with the file.
#
# Exit codes (the block 50-59 of this repository):
#   0   Success; with --check, the block in the file is up to date.
#   50  Wrong command line.
#   51  With --check, the block differs (a unified diff goes to stderr);
#       otherwise the file could not be read or written.
#   52  With --check, the Unicode version recorded in the file
#       differs from the local Python's, so the comparison is skipped
#       (a test can skip instead of failing on an older Python).
#   53  The file has no `# region Width table` ... `# endregion` block.

"""Generate the Unicode width table of the cdl.sh awk formatter."""

import argparse
import difflib
import re
import sys
import unicodedata
from collections.abc import Iterable, Sequence
from dataclasses import dataclass, replace
from pathlib import Path
from typing import NoReturn

# region Constants

FIRST_CODE_POINT = 0xA0
LAST_CODE_POINT = 0x10FFFF
SURROGATES = range(0xD800, 0xE000)
SOFT_HYPHEN = 0xAD
HANGUL_JAMO_COMBINING = range(0x1160, 0x1200)
ZERO_WIDTH_CATEGORIES = frozenset({"Mn", "Me", "Cf"})
WIDE_EAST_ASIAN_WIDTHS = frozenset({"W", "F"})
NARROW_CELLS = 1

GENERATOR_NAME = "tools/gen-width-table.py"
REGION_START = "# region Width table"
REGION_END = "# endregion"
UNICODE_VERSION_PATTERN = re.compile(r"# Unicode (\d+(?:\.\d+)*)")
MAX_LINE_LENGTH = 100
FUNCTION_INDENT = " " * 4
BODY_INDENT = " " * 6
BLOCK_FOOTER = (f"{BODY_INDENT}return t", f"{FUNCTION_INDENT}}}")

EXIT_OK = 0
EXIT_USAGE = 50
EXIT_FAILURE = 51
EXIT_UNICODE_MISMATCH = 52
EXIT_NO_REGION = 53

# endregion


# region Width rules


def cell_width(code_point: int) -> int:
    """Return the screen cells that one code point takes.

    Parameters
    ----------
    code_point : int
        The code point to measure.

    Returns
    -------
    int
        0 for combining and format characters, 2 for wide ones,
        and 1 for everything else, surrogates included.
    """
    if code_point == SOFT_HYPHEN or code_point in SURROGATES:
        return NARROW_CELLS
    if code_point in HANGUL_JAMO_COMBINING:
        return 0

    character = chr(code_point)
    if unicodedata.category(character) in ZERO_WIDTH_CATEGORIES:
        return 0
    if unicodedata.east_asian_width(character) in WIDE_EAST_ASIAN_WIDTHS:
        return 2

    return NARROW_CELLS


# endregion


# region Ranges


@dataclass(frozen=True, slots=True)
class WidthRange:
    """A run of code points that all take the same number of cells.

    Attributes
    ----------
    first : int
        The first code point of the run.
    last : int
        The last code point of the run, inclusive.
    cells : int
        The screen cells each code point takes.
    """

    first: int
    last: int
    cells: int

    def continues_with(self, code_point: int, cells: int) -> bool:
        """Tell whether a code point extends the run.

        Parameters
        ----------
        code_point : int
            The next code point in ascending order.
        cells : int
            The screen cells it takes.

        Returns
        -------
        bool
            True when the code point follows the run and has its width.
        """
        return code_point == self.last + 1 and cells == self.cells

    def token(self) -> str:
        """Render the run as a table token.

        Returns
        -------
        str
            ``FIRST-LAST:CELLS`` with uppercase hex of at least four digits,
            or ``FIRST:CELLS`` when the run holds one code point.
        """
        first = f"{self.first:04X}"
        if self.first == self.last:
            return f"{first}:{self.cells}"

        return f"{first}-{self.last:04X}:{self.cells}"


def merge_adjacent(measured: Iterable[tuple[int, int]]) -> list[WidthRange]:
    """Fold ascending (code point, cells) pairs into ranges.

    Parameters
    ----------
    measured : Iterable[tuple[int, int]]
        Code points in ascending order with the cells each takes.

    Returns
    -------
    list[WidthRange]
        Ascending, non-overlapping runs of equal width.
    """
    ranges: list[WidthRange] = []

    for code_point, cells in measured:
        if ranges and ranges[-1].continues_with(code_point, cells):
            ranges[-1] = replace(ranges[-1], last=code_point)
        else:
            ranges.append(WidthRange(code_point, code_point, cells))

    return ranges


def width_ranges() -> list[WidthRange]:
    """Collect every code point whose width is not one cell.

    Returns
    -------
    list[WidthRange]
        Ascending, non-overlapping ranges of zero-width and wide code points.
    """
    measured = (
        (code_point, cells)
        for code_point in range(FIRST_CODE_POINT, LAST_CODE_POINT + 1)
        if (cells := cell_width(code_point)) != NARROW_CELLS
    )

    return merge_adjacent(measured)


# endregion


# region Block rendering


def literal_line(tokens: Sequence[str]) -> str:
    """Render one awk line that appends tokens to the table string.

    Parameters
    ----------
    tokens : Sequence[str]
        The tokens the line carries.

    Returns
    -------
    str
        ``t = t "TOKEN TOKEN "``: every literal ends with a space,
        so the lines concatenate into one space-separated list.
    """
    body = " ".join(tokens)

    return f'{BODY_INDENT}t = t "{body} "'


def pack_tokens(tokens: Sequence[str]) -> list[str]:
    """Spread tokens over literal lines no longer than MAX_LINE_LENGTH.

    Parameters
    ----------
    tokens : Sequence[str]
        The tokens in table order.

    Returns
    -------
    list[str]
        The literal lines, each holding as many tokens as fit.
    """
    lines: list[str] = []
    pending: list[str] = []

    for token in tokens:
        if pending and len(literal_line([*pending, token])) > MAX_LINE_LENGTH:
            lines.append(literal_line(pending))
            pending = []
        pending.append(token)

    if pending:
        lines.append(literal_line(pending))

    return lines


def block_header(unicode_version: str) -> list[str]:
    """Render the comment lines and the function line that open the block.

    Parameters
    ----------
    unicode_version : str
        The Unicode version the table was derived from.

    Returns
    -------
    list[str]
        The three opening lines of the block.
    """
    return [
        (
            f"{FUNCTION_INDENT}# Unicode {unicode_version}, "
            f"generated by {GENERATOR_NAME}: do not edit by hand."
        ),
        f"{FUNCTION_INDENT}# Tokens: FIRST[-LAST]:CELLS, hex code points in ascending order.",
        f"{FUNCTION_INDENT}function width_table(    t) {{",
    ]


def render_block(ranges: Sequence[WidthRange], unicode_version: str) -> list[str]:
    """Render the awk function that returns the table.

    Parameters
    ----------
    ranges : Sequence[WidthRange]
        The table rows in ascending order.
    unicode_version : str
        The Unicode version the rows were derived from.

    Returns
    -------
    list[str]
        The block lines without line terminators.
    """
    tokens = [width_range.token() for width_range in ranges]

    return [*block_header(unicode_version), *pack_tokens(tokens), *BLOCK_FOOTER]


def region_content(block: Sequence[str]) -> list[str]:
    """Wrap the block the way it sits between the region markers.

    Parameters
    ----------
    block : Sequence[str]
        The rendered block lines.

    Returns
    -------
    list[str]
        One blank line, the block, one blank line.
    """
    return ["", *block, ""]


# endregion


# region Region in the file


class RegionNotFoundError(ValueError):
    """The file has no width-table region to replace."""

    def __init__(self, path: Path) -> None:
        message = f"{path}: no '{REGION_START}' ... '{REGION_END}' block"
        super().__init__(message)


@dataclass(frozen=True, slots=True)
class FileRegion:
    """The lines of a file together with the position of its region.

    Attributes
    ----------
    lines : list[str]
        The whole file as lines.
    start : int
        The index of the line holding the start marker.
    end : int
        The index of the line holding the end marker.
    """

    lines: list[str]
    start: int
    end: int

    @property
    def content(self) -> list[str]:
        """The lines between the markers."""
        return self.lines[self.start + 1 : self.end]

    def replaced_with(self, content: Sequence[str]) -> list[str]:
        """Return the file lines with new content between the markers.

        Parameters
        ----------
        content : Sequence[str]
            The lines to put between the markers.

        Returns
        -------
        list[str]
            The whole file as lines, markers kept.
        """
        return [*self.lines[: self.start + 1], *content, *self.lines[self.end :]]


def find_marker(lines: Sequence[str], marker: str, start: int = 0) -> int | None:
    """Find the first line, from start on, that is the marker once stripped.

    Parameters
    ----------
    lines : Sequence[str]
        The file content split into lines.
    marker : str
        The exact marker text.
    start : int
        The index to begin the search at.

    Returns
    -------
    int | None
        The index of the marker line, or None when there is none.
    """
    return next(
        (index for index in range(start, len(lines)) if lines[index].strip() == marker), None
    )


def load_region(path: Path) -> FileRegion:
    """Read a file and locate its width-table region.

    Parameters
    ----------
    path : Path
        The file holding the region.

    Returns
    -------
    FileRegion
        The file lines with the marker positions.

    Raises
    ------
    RegionNotFoundError
        If either marker is missing.
    """
    lines = path.read_text(encoding="utf-8").split("\n")

    start = find_marker(lines, REGION_START)
    if start is None:
        raise RegionNotFoundError(path)

    end = find_marker(lines, REGION_END, start + 1)
    if end is None:
        raise RegionNotFoundError(path)

    return FileRegion(lines, start, end)


def recorded_unicode_version(region: Iterable[str]) -> str | None:
    """Read the Unicode version the block in the file was generated from.

    Parameters
    ----------
    region : Iterable[str]
        The lines between the region markers.

    Returns
    -------
    str | None
        The version from the ``# Unicode X.Y.Z`` comment, or None without one.
    """
    for line in region:
        match = UNICODE_VERSION_PATTERN.search(line)
        if match:
            return match.group(1)

    return None


# endregion


# region Commands


def print_block(block: Sequence[str]) -> int:
    """Print the block to stdout.

    Parameters
    ----------
    block : Sequence[str]
        The rendered block lines.

    Returns
    -------
    int
        EXIT_OK.
    """
    sys.stdout.write("\n".join(block) + "\n")

    return EXIT_OK


def write_block(path: Path, block: Sequence[str]) -> int:
    """Replace the region content of a file with the block.

    Parameters
    ----------
    path : Path
        The file holding the region.
    block : Sequence[str]
        The rendered block lines.

    Returns
    -------
    int
        EXIT_OK; the file is left untouched when it is already up to date.
    """
    region = load_region(path)

    updated = region.replaced_with(region_content(block))
    if updated != region.lines:
        path.write_text("\n".join(updated), encoding="utf-8")

    return EXIT_OK


def report_difference(path: Path, current: Sequence[str], expected: Sequence[str]) -> None:
    """Print a unified diff between the file's block and the generated one.

    Parameters
    ----------
    path : Path
        The file holding the region, named in the diff header.
    current : Sequence[str]
        The lines between the markers in the file.
    expected : Sequence[str]
        The lines the generator would put there.
    """
    diff = difflib.unified_diff(
        current,
        expected,
        fromfile=f"{path} (current)",
        tofile=f"{path} (generated)",
        lineterm="",
    )

    sys.stderr.write("\n".join(diff) + "\n")


def check_block(path: Path, block: Sequence[str], unicode_version: str) -> int:
    """Compare the region content of a file with the block.

    Parameters
    ----------
    path : Path
        The file holding the region.
    block : Sequence[str]
        The rendered block lines.
    unicode_version : str
        The Unicode version of the local Python.

    Returns
    -------
    int
        EXIT_OK when the file matches,
        EXIT_UNICODE_MISMATCH when the file was generated from another Unicode version,
        EXIT_FAILURE otherwise, with a unified diff on stderr.
    """
    current = load_region(path).content

    recorded = recorded_unicode_version(current)
    if recorded is not None and recorded != unicode_version:
        sys.stderr.write(
            f"{GENERATOR_NAME}: {path} was generated from Unicode {recorded}, "
            f"this Python has Unicode {unicode_version}: comparison skipped\n",
        )
        return EXIT_UNICODE_MISMATCH

    expected = region_content(block)
    if current == expected:
        return EXIT_OK

    report_difference(path, current, expected)
    return EXIT_FAILURE


# endregion


# region Command line


class ArgumentParser(argparse.ArgumentParser):
    """An argument parser whose usage errors exit with EXIT_USAGE."""

    def error(self, message: str) -> NoReturn:
        """Report a usage error and exit with EXIT_USAGE.

        Parameters
        ----------
        message : str
            The parser's description of the error.
        """
        self.print_usage(sys.stderr)
        sys.stderr.write(f"{self.prog}: error: {message}\n")
        sys.exit(EXIT_USAGE)


def parse_arguments(argv: Sequence[str] | None) -> argparse.Namespace:
    """Parse the command line.

    Parameters
    ----------
    argv : Sequence[str] | None
        The arguments without the program name, or None for sys.argv.

    Returns
    -------
    argparse.Namespace
        ``write`` and ``check``, each a Path or None; at most one is set.
    """
    parser = ArgumentParser(
        prog=GENERATOR_NAME,
        description="Generate the Unicode width table of the cdl.sh awk formatter.",
    )

    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--write", metavar="FILE", type=Path, help="replace the block in FILE in place"
    )
    mode.add_argument(
        "--check", metavar="FILE", type=Path, help="compare the block with the one in FILE"
    )

    return parser.parse_args(argv)


def run(arguments: argparse.Namespace, block: Sequence[str], unicode_version: str) -> int:
    """Run the command the arguments select.

    Parameters
    ----------
    arguments : argparse.Namespace
        The parsed command line.
    block : Sequence[str]
        The rendered block lines.
    unicode_version : str
        The Unicode version of the local Python.

    Returns
    -------
    int
        The exit code of the command.
    """
    if arguments.write is not None:
        return write_block(arguments.write, block)
    if arguments.check is not None:
        return check_block(arguments.check, block, unicode_version)

    return print_block(block)


def fail(error: Exception, code: int) -> int:
    """Report an error on stderr and hand back the exit code for it.

    Parameters
    ----------
    error : Exception
        The error to report.
    code : int
        The exit code to return.

    Returns
    -------
    int
        The given code.
    """
    sys.stderr.write(f"{GENERATOR_NAME}: {error}\n")

    return code


def main(argv: Sequence[str] | None = None) -> int:
    """Run the generator.

    Parameters
    ----------
    argv : Sequence[str] | None
        The arguments without the program name, or None for sys.argv.

    Returns
    -------
    int
        The exit code listed in the file header.
    """
    arguments = parse_arguments(argv)
    unicode_version = unicodedata.unidata_version
    block = render_block(width_ranges(), unicode_version)

    try:
        return run(arguments, block, unicode_version)
    except RegionNotFoundError as error:
        return fail(error, EXIT_NO_REGION)
    except OSError as error:
        return fail(error, EXIT_FAILURE)


if __name__ == "__main__":
    sys.exit(main())

# endregion
