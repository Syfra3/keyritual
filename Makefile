.DEFAULT_GOAL := help

CARGO_HOME ?= $(HOME)/.cargo
export CARGO_HOME

# Avoid embedding a maintainer's home directory in the bundled release binary.
RUSTFLAGS ?= --remap-path-prefix=$(HOME)=/build
export RUSTFLAGS

CORE := $(CARGO_HOME)/bin/keyritual-core

.PHONY: help build bundle bundle-check test run run-engine install install-restart insall

help:
	@printf '%s\n' \
	  'make build       Build the optimized Rust binary (target/release/keyritual-core)' \
	  'make bundle      Refresh the tracked x86_64 plugin engine (bin/keyritual-core)' \
	  'make bundle-check  Confirm tracked engine matches current release build' \
	  'make test        Run Rust formatting, unit tests, and Clippy' \
	  'make run-engine  Start the JSON-lines Rust engine on stdin/stdout' \
	  'make install     Upgrade Omarchy if needed; install without restarting the shell' \
	  'make install-restart  Install and restart the shell (briefly interrupts bar/overlays)' \
	  'make run         Toggle the installed Quattro desktop overlay'

build:
	cargo build --release --locked

bundle: build
	install -Dm755 target/release/keyritual-core bin/keyritual-core
	@bin/keyritual-core --version

bundle-check: build
	@test -x bin/keyritual-core
	@cmp bin/keyritual-core target/release/keyritual-core
	@bin/keyritual-core --version

test:
	cargo fmt --check
	cargo test
	cargo clippy --all-targets -- -D warnings

run-engine:
	@cargo run --quiet -- serve

install:
	@bash scripts/ensure-omarchy.sh
	@$(MAKE) bundle
	@bash scripts/install-plugin.sh --check
	cargo install --path . --locked
	@bash scripts/install-plugin.sh
	@bash scripts/install-launcher.sh
	@printf '%s\n' 'If the UI still looks old, run: omarchy restart shell (briefly interrupts bar/overlays).'

install-restart: install
	@if command -v omarchy-shell >/dev/null 2>&1; then \
	  omarchy restart shell; \
	else \
	  printf '%s\n' 'Omarchy shell is unavailable; cannot restart it.' >&2; \
	  exit 1; \
	fi

insall:
	@printf '%s\n' 'Did you mean: make install ?' >&2
	@exit 2

run:
	@if ! command -v omarchy-shell >/dev/null 2>&1; then \
	  printf '%s\n' 'Keyritual overlay needs Omarchy Quattro / 4.x. Run make install in a terminal, then rerun after the upgrade and reboot.' >&2; \
	  exit 1; \
	fi
	@if [ -x "$(CORE)" ]; then "$(CORE)" launch; \
	else cargo run --quiet -- launch; fi
