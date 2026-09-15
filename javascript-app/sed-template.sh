#!/usr/bin/env bash
set -euo pipefail

if [[ -d /usr/bin ]]; then
  PATH="/usr/bin:$PATH"
fi

# Usage:
#   ./sed-template.sh <ORG> <SVC> [OUTDIR] [HOSTNAME]
#   ./sed-template.sh
#
# ORG      : GitHub owner. Image paths are lowercased.
# SVC      : Service short name, e.g. web -> repository svc-web.
# OUTDIR   : Output directory. Default: ./_generated
# HOSTNAME : HTTPRoute hostname. Default: web.example.com

SCRIPT_PATH="${BASH_SOURCE[0]}"
SCRIPT_DIR="."
if [[ "$SCRIPT_PATH" == */* ]]; then
  SCRIPT_DIR="${SCRIPT_PATH%/*}"
fi
TPL_DIR="$(cd "$SCRIPT_DIR" && pwd)"
TPL_NAME="javascript-app"

ORG="${1:-}"
SVC="${2:-}"
OUTDIR="${3:-$TPL_DIR/_generated}"
HOSTNAME="${4:-web.example.com}"
HOSTNAME="${HOSTNAME,,}"

if [[ -z "$ORG" ]]; then read -rp "ORG (GitHub owner): " ORG; fi
if [[ -z "$SVC" ]]; then read -rp "SVC (service name, e.g. web): " SVC; fi

if [[ -z "$ORG" || -z "$SVC" ]]; then
  echo "ORG and SVC are required" >&2
  exit 1
fi
if [[ ! "$ORG" =~ ^[A-Za-z0-9_.-]+$ ]]; then
  echo "ORG may contain only letters, numbers, underscore, dot, and hyphen: '$ORG'" >&2
  exit 1
fi
if [[ ${#SVC} -gt 63 || ! "$SVC" =~ ^[a-z]([a-z0-9-]*[a-z0-9])?$ ]]; then
  echo "SVC must use lowercase letters, numbers, and hyphen, starting with a letter: '$SVC'" >&2
  exit 1
fi
if [[ ${#HOSTNAME} -gt 253 || ! "$HOSTNAME" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ || "$HOSTNAME" == *..* ]]; then
  echo "HOSTNAME must be a DNS-style hostname: '$HOSTNAME'" >&2
  exit 1
fi
IFS='.' read -ra HOST_LABELS <<< "$HOSTNAME"
for label in "${HOST_LABELS[@]}"; do
  if [[ ${#label} -gt 63 || ! "$label" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]]; then
    echo "HOSTNAME must be a DNS-style hostname: '$HOSTNAME'" >&2
    exit 1
  fi
done

ORGLC="$(printf '%s' "$ORG" | tr '[:upper:]' '[:lower:]')"

BUILD="$OUTDIR/svc-$SVC"
GITOPS="$OUTDIR/gitops-$SVC"
if [[ -e "$BUILD" || -e "$GITOPS" ]]; then
  echo "Refusing to overwrite existing output: $BUILD or $GITOPS" >&2
  exit 1
fi

mkdir -p "$BUILD" "$GITOPS"

cp "$TPL_DIR"/package.json "$TPL_DIR"/package-lock.json "$TPL_DIR"/Dockerfile "$TPL_DIR"/Jenkinsfile "$TPL_DIR"/nginx.conf "$TPL_DIR"/docker-entrypoint.sh "$TPL_DIR"/README.md "$BUILD"/
cp "$TPL_DIR"/.gitignore "$TPL_DIR"/.dockerignore "$TPL_DIR"/.gitattributes "$BUILD"/
cp -r "$TPL_DIR"/public "$BUILD"/public
cp -r "$TPL_DIR"/scripts "$BUILD"/scripts

cp -r "$TPL_DIR/k8s-gitops/." "$GITOPS"/
if [[ "$SVC" != "$TPL_NAME" ]]; then
  mv "$GITOPS/manifests/$TPL_NAME" "$GITOPS/manifests/$SVC"
  mv "$GITOPS/argocd/apps/$TPL_NAME.yaml" "$GITOPS/argocd/apps/$SVC.yaml"
fi

find "$BUILD" "$GITOPS" -type f \
  ! -path '*/node_modules/*' \
  ! -path '*/dist/*' \
  -exec sed -i \
    -e "s|__ORGLC__|$ORGLC|g" \
    -e "s|__ORG__|$ORG|g" \
    -e "s|__SVC__|$SVC|g" \
    -e "s|__HOSTNAME__|$HOSTNAME|g" \
    {} +

if grep -rn '__[A-Z][A-Z0-9_]*__' "$BUILD" "$GITOPS" >/dev/null 2>&1; then
  echo "Unresolved template tokens remain:" >&2
  grep -rn '__[A-Z][A-Z0-9_]*__' "$BUILD" "$GITOPS" >&2
  exit 1
fi

cat <<EOF

Generated JavaScript web service template.

  Service repo root:
    $BUILD

  GitOps fragments:
    $GITOPS/manifests/$SVC/        -> k8s-gitops/manifests/$SVC/
    $GITOPS/argocd/apps/$SVC.yaml  -> k8s-gitops/argocd/apps/$SVC.yaml

Next checks:
  cd "$BUILD" && npm ci && npm test && npm run build

CI registration:
  $SVC:
    language: node
EOF
