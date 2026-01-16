# ABOUTME: Build, test, and install targets for transcribe-summarize.
# ABOUTME: Use `make build` for release, `make test` to run tests.

.PHONY: build test clean install install-venv uninstall help

VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
VENV_DIR := $(HOME)/.local/share/transcribe-summarize/venv

build:
	swift build -c release

build-debug:
	swift build

test:
	swift test

test-verbose:
	swift test --verbose

clean:
	swift package clean
	rm -rf .build

install: build
	install -d /usr/local/bin
	install -m 755 .build/release/transcribe-summarize /usr/local/bin/
	install -d /usr/local/share/transcribe-summarize
	install -m 644 scripts/diarize.py /usr/local/share/transcribe-summarize/
	@echo "Installed. Diarization venv will be created on first use."

install-venv:
	@echo "Setting up Python virtual environment for diarization..."
	@mkdir -p $(dir $(VENV_DIR))
	@python3 -m venv $(VENV_DIR)
	@$(VENV_DIR)/bin/pip install --upgrade pip --quiet
	@$(VENV_DIR)/bin/pip install pyannote.audio torch --quiet
	@echo "Diarization environment ready at $(VENV_DIR)"

uninstall:
	rm -f /usr/local/bin/transcribe-summarize
	rm -rf /usr/local/share/transcribe-summarize
	rm -rf $(VENV_DIR)

help:
	@echo "Available targets:"
	@echo "  build        - Build release binary"
	@echo "  build-debug  - Build debug binary"
	@echo "  test         - Run all tests"
	@echo "  test-verbose - Run tests with verbose output"
	@echo "  clean        - Remove build artifacts"
	@echo "  install      - Install binary (venv created on first diarization use)"
	@echo "  install-venv - Pre-install diarization Python environment"
	@echo "  uninstall    - Remove installed files and venv"
