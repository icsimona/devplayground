#!/usr/bin/env bash
set -euo pipefail

log() { echo "[INFO] $*"; }
die() { echo "[ERROR] $*" >&2; exit 1; }

find_file() {
  local pattern="$1"
  local path
  path="$(find ~/devplayground -name "$pattern" -print -quit 2>/dev/null || true)"
  [[ -n "$path" ]] || die "Required file not found: $pattern"
  echo "$path"
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

main() {
  need kind
  need kubectl
  need flux
  need git
  need sed

  local cluster_name="${1:-${cluster_name:-playground}}"

  log "Using cluster name: ${cluster_name}"

  local cluster_config_path
  cluster_config_path="$(find_file "cluster-config.yaml")"


  log "Creating kind cluster '${cluster_name}'..."
  kind create cluster -n "$cluster_name" --config "$cluster_config_path"
  log "Kind cluster '${cluster_name}' has been created."

  local kind_context="kind-${cluster_name}"
  kubectl config use-context "$kind_context" >/dev/null
  log "Using kube context: ${kind_context}"

  local git_branch="${FLUX_GIT_BRANCH:-dev}"
  local git_url="${FLUX_GIT_URL:-}"

  if [[ -z "$git_url" ]]; then
    git_url="$(git remote get-url origin)" \
      || die "Could not determine git remote URL. Set FLUX_GIT_URL."
  fi

  log "Flux will follow:"
  log "  Repo:   ${git_url}"
  log "  Branch: ${git_branch}"

  log "Installing Flux controllers..."
  flux install
  log "Flux controllers installation is complete."

  local gitrepo_tmpl_path
  gitrepo_tmpl_path="$(find_file "gitrepo.yaml.tmpl")"

  log "Applying Flux GitRepository..."
  sed \
    -e "s|__GIT_URL__|${git_url}|g" \
    -e "s|__GIT_BRANCH__|${git_branch}|g" \
    "$gitrepo_tmpl_path" \
    | kubectl apply -f -

  local sync_path
  sync_path="$(find_file "sync.yaml")"

  log "Applying Flux sync Kustomization..."
  kubectl apply -f "$sync_path"

  log "Kicking initial reconcile..."
  flux reconcile source git upstream || true
  flux reconcile kustomization sync-cluster-addons || true


  log "Bootstrap complete."
  log "Check status with:"
  log "  flux get sources git -A"
  log "  flux get kustomizations -A"
  log "  kubectl -n flux-system get pods"
}

main "$@"
