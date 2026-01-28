#!/usr/bin/env bash
set -euo pipefail

die() { echo "[ERROR] $*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

install_pkg_manager() {
  echo "Checking if Chocolatey is installed..."
  if have choco; then
    echo "Chocolatey is installed: $(choco --version)"
    return 0
  fi

  echo "Chocolatey not installed. Installing..."
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \
    "[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))"

  export PATH="/c/ProgramData/chocolatey/bin:$PATH"

  have choco || die "Chocolatey installation failed. Please install Chocolatey manually."
  echo "Chocolatey installation complete: $(choco --version)"
}

install() {
  local cmd="$1"
  local pkg="$2"

  echo "Checking if $cmd is installed..."
  if have "$cmd"; then
    echo "$cmd is installed."
    return 0
  fi

  echo "$cmd is not installed. Installing..."
  choco install -y "$pkg"

  have "$cmd" || die "Installation failed. Please install $name manually and run the script again."
  echo "$cmd installation complete."
}

add_helm_repo() {
  local repo="$1"
  echo "Adding necessary helm repos..."
  if ! helm repo list | awk 'NR>1 {print $1}' | grep -qx $repo; then
    helm repo add istio https://istio-release.storage.googleapis.com/charts
  fi

  helm repo update
}

main() {
  install_pkg_manager

  install kind kind
  install kubectl kubernetes-cli
  install helm kubernetes-helm
  install kustomize kustomize
  install flux flux

  add_helm_repo istio
}

main "$@"
