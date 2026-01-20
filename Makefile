# ABOUTME: Build, test, and install targets for transcribe-summarize.
# ABOUTME: Use `make build` for release, `make test` to run tests, `make release` to publish.

.PHONY: build test clean install install-venv uninstall release bump-version update-formula help

VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
VENV_DIR := $(HOME)/.local/share/transcribe-summarize/venv
REPO_URL := https://github.com/tigger04/transcribe-recording

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
	@echo "  build         - Build release binary"
	@echo "  build-debug   - Build debug binary"
	@echo "  test          - Run all tests"
	@echo "  test-verbose  - Run tests with verbose output"
	@echo "  clean         - Remove build artifacts"
	@echo "  install       - Install binary (venv created on first diarization use)"
	@echo "  install-venv  - Pre-install diarization Python environment"
	@echo "  uninstall     - Remove installed files and venv"
	@echo ""
	@echo "Release targets:"
	@echo "  release V=x.y.z  - Full release: bump version, tag, update formula"
	@echo "  bump-version     - Just update version in main.swift (requires V=x.y.z)"
	@echo "  update-formula   - Update formula SHA256 for current tag"

# Release management
# Usage: make release V=0.2.0
release: _check-version _check-clean test bump-version
	@echo "Creating release v$(V)..."
	git add Sources/TranscribeSummarize/main.swift
	git commit -m "chore: bump version to $(V)"
	git tag -a "v$(V)" -m "Release v$(V)"
	git push origin master
	git push origin "v$(V)"
	@echo "Waiting for GitHub to process the tag..."
	@sleep 5
	$(MAKE) update-formula
	@echo ""
	@echo "Release v$(V) complete!"
	@echo "Next steps:"
	@echo "  1. Update your Homebrew tap with the new formula"
	@echo "  2. Run: brew upgrade transcribe-summarize"

bump-version: _check-version
	@echo "Bumping version to $(V)..."
	@sed -i '' 's/version: "[^"]*"/version: "$(V)"/' Sources/TranscribeSummarize/main.swift
	@echo "Version updated in main.swift"

update-formula:
	@TAG=$$(git describe --tags --abbrev=0 2>/dev/null); \
	if [ -z "$$TAG" ]; then \
		echo "Error: No git tag found"; \
		exit 1; \
	fi; \
	VERSION=$${TAG#v}; \
	URL="$(REPO_URL)/archive/refs/tags/$$TAG.tar.gz"; \
	echo "Fetching SHA256 for $$URL..."; \
	SHA256=$$(curl -sL "$$URL" | shasum -a 256 | cut -d' ' -f1); \
	if [ -z "$$SHA256" ] || [ "$$SHA256" = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ]; then \
		echo "Error: Failed to fetch tarball or empty file"; \
		exit 1; \
	fi; \
	echo "SHA256: $$SHA256"; \
	sed -i '' "s|url \".*\"|url \"$$URL\"|" Formula/transcribe-summarize.rb; \
	sed -i '' "s/sha256 \"[^\"]*\"/sha256 \"$$SHA256\"/" Formula/transcribe-summarize.rb; \
	echo "Formula updated with version $$VERSION"

_check-version:
ifndef V
	$(error Version required. Usage: make release V=x.y.z)
endif

_check-clean:
	@if [ -n "$$(git status --porcelain)" ]; then \
		echo "Error: Working directory not clean. Commit or stash changes first."; \
		exit 1; \
	fi
