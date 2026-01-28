#!/usr/bin/env bash
set -euo pipefail

DEFAULT_CLUSTER_NAME="lab"
read -p "Enter cluster name [$DEFAULT_CLUSTER_NAME]: " cluster_name
cluster_name="${cluster_name:-$DEFAULT_CLUSTER_NAME}"

echo "Checking if Chocolatey is installed.."
if choco_version="$(choco --version 2>/dev/null)"; then
  echo "Chocolatey version $choco_version is installed."
else
  echo "Chocolatey not installed. Instaklling..."
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

echo "Creating kind cluster '$cluster_name'.."
CLUSTER_CONFIG_PATH=$(find . -name "cluster-config.yaml" -print -quit || true)
if kind create cluster -n "$cluster_name" --config "$CLUSTER_CONFIG_PATH"; then
  echo "Kind cluster '$cluster_name' has been created."
else
  echo "Try installing manually with:"
  echo "  kind create cluster -n "$cluster_name" --config "$CLUSTER_CONFIG_PATH""
  exit 1
fi

echo "Configuring Flux Git source..."
GIT_BRANCH="${FLUX_GIT_BRANCH:-dev}"

if [[ -n "${FLUX_GIT_URL:-}" ]]; then
  GIT_URL="${FLUX_GIT_URL}"
else
  GIT_URL="$(git remote get-url origin)"
fi

echo "Flux will follow:"
echo "  Repo:   ${GIT_URL}"
echo "  Branch: ${GIT_BRANCH}"

echo "Installing Flux controllers..."
if flux install; then
  echo "Flux controllers installation is complete."
else
  echo "Flux failed to install. Try:"
  echo "  kubectl config use-context ${KIND_CONTEXT}"
  echo "  flux install"
  exit 1
fi

echo "Applying Flux GitRepository..."
GITREPO_TMPL_PATH=$(find . -name "gitrepo.yaml.tmpl" -print -quit || true)
sed \
  -e "s|__GIT_URL__|${GIT_URL}|g" \
  -e "s|__GIT_BRANCH__|${GIT_BRANCH}|g" \
  "$GITREPO_TMPL_PATH" \
  | kubectl apply -f -

echo "Applying Flux sync Kustomization..."
SYNC_PATH=$(find . -name "sync.yaml" -print -quit || true)
kubectl apply -f "$SYNC_PATH"

echo "Kicking initial reconcile..."
flux reconcile source git upstream || true
flux reconcile kustomization sync-cluster-addons || t
echo
echo "Bootstrap complete."
echo "Check status with:"
echo "  flux get sources git -A"
echo "  flux get kustomizations -A"
echo "  kubectl -n flux-system get pods"
