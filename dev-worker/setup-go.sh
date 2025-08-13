#!/bin/bash

set -e

print_status() { echo "[INFO] $1"; }
print_success() { echo "[SUCCESS] $1"; }
print_warning() { echo "[WARNING] $1"; }
print_error() { echo "[ERROR] $1"; }

REQUIRED_MAJOR=1
REQUIRED_MINOR=22
GO_INSTALL_DIR="$HOME/.local/go"
GO_BIN_DIR="$GO_INSTALL_DIR/bin"

ensure_path_exports() {
  local export_line="export PATH=\"$GO_BIN_DIR:$PATH\""
  if [ -f "$HOME/.bashrc" ] && ! grep -Fq "$GO_BIN_DIR" "$HOME/.bashrc" 2>/dev/null; then
    echo "$export_line" >> "$HOME/.bashrc"
  fi
  if [ -f "$HOME/.profile" ] && ! grep -Fq "$GO_BIN_DIR" "$HOME/.profile" 2>/dev/null; then
    echo "$export_line" >> "$HOME/.profile"
  fi
  export PATH="$GO_BIN_DIR:$PATH"
}

go_version_ok() {
  local v
  v=$(go version 2>/dev/null | awk '{print $3}' | sed 's/go//')
  # v like 1.22.6
  local major minor
  major=$(echo "$v" | cut -d. -f1)
  minor=$(echo "$v" | cut -d. -f2)
  [ -n "$major" ] && [ -n "$minor" ] || return 1
  if [ "$major" -gt "$REQUIRED_MAJOR" ]; then return 0; fi
  if [ "$major" -lt "$REQUIRED_MAJOR" ]; then return 1; fi
  [ "$minor" -ge "$REQUIRED_MINOR" ]
}

install_go_tarball() {
  local url="https://go.dev/dl/go1.22.6.linux-amd64.tar.gz"
  local tmp="/tmp/go1.22.6.linux-amd64.tar.gz"
  print_status "Downloading Go from $url"
  curl -fsSL "$url" -o "$tmp"
  mkdir -p "$HOME/.local"
  rm -rf "$GO_INSTALL_DIR"
  tar -C "$HOME/.local" -xzf "$tmp"
  ensure_path_exports
  if command -v go >/dev/null 2>&1; then
    print_success "Go installed at $GO_INSTALL_DIR"
  else
    print_error "Go installation failed"
    return 1
  fi
}

print_status "Checking Go toolchain (require >= ${REQUIRED_MAJOR}.${REQUIRED_MINOR})"
if command -v go >/dev/null 2>&1 && go_version_ok; then
  print_success "Go present: $(go version)"
  ensure_path_exports
  exit 0
fi

print_warning "Go not present or too old; installing user-local toolchain"
install_go_tarball
print_success "Go ready: $(go version)"


