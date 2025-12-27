# Makefile for fetch-pubmed
#
# Usage:
#   make check    - Verify dependencies (perl, curl, gsplit)
#   make run      - Run the full fetch and parse pipeline
#   make install  - Install to /usr/local (requires sudo)
#   make clean    - Remove output files

PREFIX ?= $(HOME)/.local
BIN_DIR = $(PREFIX)/bin
LIB_DIR = $(PREFIX)/libexec/fetch-pubmed

# Detect shell explicitly
SHELL := /bin/bash

.PHONY: all check run install clean uninstall

all: check

# 1. Dependency Checking
# Ensures the user has the required tools before trying to run
check:
	@echo "Checking dependencies..."
	@command -v perl >/dev/null 2>&1 || { echo >&2 "Error: perl is not installed."; exit 1; }
	@command -v curl >/dev/null 2>&1 || { echo >&2 "Error: curl is not installed."; exit 1; }
	@command -v gsplit >/dev/null 2>&1 || { echo >&2 "Error: gsplit is not installed. (Try 'brew install coreutils' on macOS)"; exit 1; }
	@echo "All dependencies found."

# 2. Execution Wrapper
# Creates the output directory and runs the main script
run: check
	@mkdir -p output
	@echo "Starting pipeline..."
	@./bin/fetch-all.zsh

# 3. Installation
# Installs binaries and internal libraries to standard system locations
install: check
	@echo "Installing to $(PREFIX)..."
	@install -d $(BIN_DIR)
	@install -d $(LIB_DIR)
	@install -m 755 bin/fetch-all.zsh $(BIN_DIR)/fetch-pubmed
	@install -m 755 libexec/fetch-pubmed/xml-to-tsv $(LIB_DIR)/xml-to-tsv
	@# We need to patch the installed script to find the installed library
	@sed -i.bak 's|PROJECT_ROOT=.*|PROJECT_ROOT=$(PREFIX)|' $(BIN_DIR)/fetch-pubmed && rm $(BIN_DIR)/fetch-pubmed.bak
	@echo "Installation complete. You can now run 'fetch-pubmed'."

# 4. Cleanup
clean:
	@echo "Cleaning output directory..."
	@rm -rf output/
	@echo "Done."

uninstall:
	@rm -f $(BIN_DIR)/fetch-pubmed
	@rm -rf $(LIB_DIR)
	@echo "Uninstalled."
