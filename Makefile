# ABOUTME: Build, test, and install targets for transcribe-summarize.
# ABOUTME: Use `make build` for release, `make test` to run tests.

.PHONY: build test clean install uninstall

VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")

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

uninstall:
	rm -f /usr/local/bin/transcribe-summarize
	rm -rf /usr/local/share/transcribe-summarize

help:
	@echo "Available targets:"
	@echo "  build        - Build release binary"
	@echo "  build-debug  - Build debug binary"
	@echo "  test         - Run all tests"
	@echo "  test-verbose - Run tests with verbose output"
	@echo "  clean        - Remove build artifacts"
	@echo "  install      - Install to /usr/local/bin"
	@echo "  uninstall    - Remove installed files"
