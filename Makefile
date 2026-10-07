# cdl: Makefile
#
# Development tasks: lint, format, test, hooks, install, benchmark, demo.
# `make` alone lists them.
#
# Needs GNU make 3.81 or newer; the one macOS ships is fine.
# Lint and format rules live in .shellcheckrc and .editorconfig,
# so editors, these targets and CI apply the very same rules.

# ─── Project ────────────────────────────────────────────────────────────

SCRIPT  := cdl.sh
PLUGIN  := cdl.plugin.zsh

# Exit codes of the recipes, the block 70-79 of this repository
# (see the exit codes in CLAUDE.md).
MAKE_ERR_TESTS        := 70
MAKE_ERR_INSTALL_MODE := 71
MAKE_ERR_SMOKE        := 72
VERSION := $(shell sed -n 's/^\# Version: *//p' $(SCRIPT))

SHELL_FILES := $(SCRIPT) \
               $(wildcard tools/*.sh tools/ci/*.sh) \
               $(wildcard tests/support/*.bash tests/support/bin/*) \
               $(wildcard docs/demo/*.bash)
BATS_FILES  := $(wildcard tests/*/*.bats)

# ─── Tools (override on the command line) ───────────────────────────────

SHELL        := bash
BATS         ?= bats
SHELLCHECK   ?= shellcheck
SHFMT        ?= shfmt
MARKDOWNLINT ?= markdownlint-cli2
PYTHON       ?= python3
PRE_COMMIT   ?= pre-commit
VHS          ?= vhs

# The test files that hold a test tagged smoke, the ones `make smoke` runs.
SMOKE_FILES = $(shell grep -l '^\# bats test_tags=.*smoke' $(wildcard tests/unit/*.bats tests/integration/*.bats))

# Shells the suite runs cdl in, one full pass each.
# On macOS: make test TEST_SHELLS='/bin/bash zsh' covers bash 3.2.
TEST_SHELLS ?= bash zsh

# Extra bats options, e.g. BATS_FLAGS='--jobs 8' with GNU parallel.
BATS_FLAGS ?=

# Where test-shells writes JUnit reports, one directory per shell;
# empty means no reports. CI sets it.
BATS_REPORT_DIR ?=

# ─── Installation ───────────────────────────────────────────────────────

# cdl.sh is sourced, not run: it goes where an rc file can source it.
INSTALL_PATH ?= $(HOME)/.cdl.sh
# symlink keeps the installed file in step with this checkout;
# copy makes a standalone file.
INSTALL_MODE ?= symlink

# ─── Output ─────────────────────────────────────────────────────────────

ifeq ($(strip $(NO_COLOR)),)
  BOLD  := \033[1m
  DIM   := \033[2m
  GREEN := \033[32m
  CYAN  := \033[36m
  RESET := \033[0m
endif

# $(call step,what): announce a step.
step = @printf '$(CYAN)→$(RESET) %s\n' $(1)

.DEFAULT_GOAL := help
MAKEFLAGS     += --no-print-directory

.PHONY: help version deps \
        lint lint-md format format-check \
        test test-shells test-style smoke check \
        hooks install uninstall bench widths demo

# ─── Help ───────────────────────────────────────────────────────────────

help: ## Show this help
	@printf '\n  $(BOLD)cdl$(RESET) $(DIM)%s$(RESET): cd and a compact ls in one step\n\n' '$(VERSION)'
	@printf '  Usage: make $(CYAN)<target>$(RESET) [VARIABLE=value ...]\n\n'
	@awk 'BEGIN { FS = ":.*## " } \
	      /^[a-z-]+:.*## / { printf "    $(CYAN)%-14s$(RESET) %s\n", $$1, $$2 }' \
	  $(MAKEFILE_LIST)
	@printf '\n  Variables:\n'
	@printf '    TEST_SHELLS    shells to test cdl in (now: %s)\n' '$(TEST_SHELLS)'
	@printf '    BATS_FLAGS     extra bats options, e.g. --jobs 8\n'
	@printf '    BATS_REPORT_DIR  JUnit reports, one directory per shell\n'
	@printf '    INSTALL_PATH   where install puts cdl.sh (now: %s)\n' '$(INSTALL_PATH)'
	@printf '    INSTALL_MODE   symlink or copy (now: %s)\n' '$(INSTALL_MODE)'
	@printf '    NO_COLOR       set to turn colors off\n\n'

version: ## Print the version of cdl.sh
	@printf '%s\n' '$(VERSION)'

deps: ## Check the tools that the targets need
	@for tool in awk bash zsh $(BATS) $(SHELLCHECK) $(SHFMT) $(MARKDOWNLINT) $(PYTHON) $(PRE_COMMIT) $(VHS); do \
	  if command -v "$$tool" >/dev/null 2>&1; then \
	    printf '  $(GREEN)✓$(RESET) %s\n' "$$tool"; \
	  else \
	    printf '  $(DIM)·$(RESET) %s (missing)\n' "$$tool"; \
	  fi; \
	done

# ─── Quality ────────────────────────────────────────────────────────────

lint: ## Run ShellCheck on every shell file, and zsh -n on the files zsh sources
	$(call step,'shellcheck')
	@$(SHELLCHECK) $(SHELL_FILES) $(BATS_FILES)
	$(call step,'zsh -n $(SCRIPT) $(PLUGIN)')
	@zsh -n $(SCRIPT) $(PLUGIN)

lint-md: ## Run markdownlint on every Markdown file, as .markdownlint-cli2.jsonc says
	$(call step,'markdownlint-cli2')
	@$(MARKDOWNLINT)

format: ## Format every shell file in place with shfmt
	$(call step,'shfmt -w')
	@$(SHFMT) -w $(SHELL_FILES) $(BATS_FILES)

format-check: ## Fail if shfmt would change any shell file
	$(call step,'shfmt -d')
	@$(SHFMT) -d $(SHELL_FILES) $(BATS_FILES)

# ─── Tests ──────────────────────────────────────────────────────────────

test: test-shells test-style ## Run the whole suite in every shell of TEST_SHELLS

test-shells: ## Run the unit and integration tests in every shell of TEST_SHELLS
	@for shell in $(TEST_SHELLS); do \
	  printf '$(CYAN)→$(RESET) bats: cdl running in %s\n' "$$shell"; \
	  report=(); \
	  if [[ -n '$(BATS_REPORT_DIR)' ]]; then \
	    report_dir='$(BATS_REPORT_DIR)'/"$${shell//\//_}"; \
	    mkdir -p "$$report_dir"; \
	    report=(--report-formatter junit --output "$$report_dir"); \
	  fi; \
	  CDL_TEST_SHELL="$$shell" $(BATS) $(BATS_FLAGS) "$${report[@]}" \
	    tests/unit tests/integration || exit $(MAKE_ERR_TESTS); \
	done

test-style: ## Check the code style rules and the facts files share
	$(call step,'bats: style rules')
	@$(BATS) $(BATS_FLAGS) tests/style

smoke: ## Run the tests tagged smoke, a quick part of the suite, in every shell of TEST_SHELLS
	@for shell in $(TEST_SHELLS); do \
	  printf '$(CYAN)→$(RESET) bats smoke: cdl running in %s\n' "$$shell"; \
	  CDL_TEST_SHELL="$$shell" $(BATS) $(BATS_FLAGS) --filter-tags smoke \
	    $(SMOKE_FILES) || exit $(MAKE_ERR_SMOKE); \
	done

check: lint lint-md format-check test ## Run everything CI runs
	@printf '\n$(GREEN)✓ all checks passed$(RESET)\n'

# ─── Installation ───────────────────────────────────────────────────────

hooks: ## Install the git hooks of .pre-commit-config.yaml, for commits and their messages
	$(call step,'pre-commit install')
	@$(PRE_COMMIT) install --install-hooks

install: ## Install cdl.sh as INSTALL_PATH and show the line for your rc file
	@case '$(INSTALL_MODE)' in \
	  symlink) ln -sfn '$(CURDIR)/$(SCRIPT)' '$(INSTALL_PATH)' ;; \
	  copy) install -m 0644 '$(SCRIPT)' '$(INSTALL_PATH)' ;; \
	  *) printf 'INSTALL_MODE must be symlink or copy\n' >&2; exit $(MAKE_ERR_INSTALL_MODE) ;; \
	esac
	@printf '$(GREEN)✓$(RESET) %s installed as %s (%s)\n\n' '$(SCRIPT)' '$(INSTALL_PATH)' '$(INSTALL_MODE)'
	@printf '  Add this line to ~/.bashrc or ~/.zshrc:\n\n'
	@printf '    [[ -f %s ]] && source %s\n\n' '$(INSTALL_PATH)' '$(INSTALL_PATH)'

uninstall: ## Remove INSTALL_PATH
	@rm -f '$(INSTALL_PATH)'
	@printf '$(GREEN)✓$(RESET) removed %s; drop its line from your rc file too\n' '$(INSTALL_PATH)'

# ─── Maintenance ────────────────────────────────────────────────────────

bench: ## Time cdl against a plain cd and ls, in bash and zsh
	@tools/bench.sh

widths: ## Regenerate the width table in cdl.sh from Unicode data
	$(call step,'width table')
	@$(PYTHON) tools/gen-width-table.py --write $(SCRIPT)

demo: ## Record docs/demo/demo.gif for the README with vhs
	$(call step,'vhs docs/demo/demo.tape')
	@$(VHS) docs/demo/demo.tape

### End
