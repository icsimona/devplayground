#!/usr/bin/env bash
set -euo pipefail

echo "Checking if Chocolatey is installed.."
if choco_version="$(choco --version 2>/dev/null)"; then
  echo "Chocolatey version $choco_version is installed."
else
  echo "Chocolatey not installed. Installing..."
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \
    "[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))"

  export PATH="/c/ProgramData/chocolatey/bin:$PATH"

  if choco_version="$(choco --version 2>/dev/null)"; then
    echo "Chocolatey installation complete: $choco_version"
  else
    echo "Installation failed. Please install Chocolatey manually."
    exit 1
  fi
fi

echo "Checking if kind is installed"
if kind_version="$(kind --version 2>/dev/null)"; then
  echo "$kind_version is installed."
else
  echo "kind is not installed. Installing.."
  choco install -y kind
  kind_version="$(kind --version 2>/dev/null)" || {
    echo "Installation failed. Please install kind manually and run the script again."
    exit 1
  }
  echo "kind installation complete: $kind_version"
fi

echo "Checking if kubectl is installed"
if kubectl_version="$(kubectl version --client --output=yaml 2>/dev/null | head -n 1)"; then
  echo "kubectl is installed."
else
  echo "kubectl is not installed. Installing.."
  choco install -y kubernetes-cli
  kubectl version --client --output=yaml >/dev/null 2>&1 || {
    echo "Installation failed. Please install kubectl manually and run the script again."
    exit 1
  }
  echo "kubectl installation complete."
fi

echo "Checking if helm is installed"
if helm_version="$(helm version --short 2>/dev/null)"; then
  echo "helm is installed: $helm_version"
else
  echo "helm is not installed. Installing..."
  choco install -y kubernetes-helm

  helm_version="$(helm version --short 2>/dev/null)" || {
    echo "Installation failed. Please install helm manually and run the script again."
    exit 1
  }

  echo "helm installation complete: $helm_version"
fi

echo "Adding necessary helm repos"

if ! helm repo list | awk '{print $1}' | grep -qx 'istio'; then
  helm repo add istio https://istio-release.storage.googleapis.com/charts
fi

helm repo update

echo "Checking if kustomize is installed"
if kustomize_version="$(kustomize version 2>/dev/null)"; then
  echo "kustomize version $kustomize_version is installed"
else
  echo "kustomize is not installed. Installing.."
  choco install -y kustomize
  kustomize_version="$(kustomize version 2>/dev/null)" || {
    echo "Installation failed. Please install kustomize manually and run the script again."
    exit 1
  }
  echo "kustomize installation complete: $kustomize_version"
fi

echo "Checking if the Flux CLI is installed"
if flux_version="$(flux --version 2>/dev/null)"; then
  echo "$flux_version is installed"
else
  echo "flux is not installed. Installing.."
  choco install -y flux
  flux_version="$(flux --version 2>/dev/null)" || {
    echo "Installation failed. Please install flux manually and run the script again."
    exit 1
  }
  echo "flux installation is complete: $flux_version"
fi