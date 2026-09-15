#!/usr/bin/env bash
set -euo pipefail

if [[ -d /usr/bin ]]; then
  PATH="/usr/bin:$PATH"
fi

# Usage:
#   ./sed-template.sh <ORG> <SVC> [OUTDIR]
#   ./sed-template.sh            # 인자가 없으면 대화형 입력
#
# ORG    : GitHub owner. repoURL은 원문을 쓰고 image path에는 소문자 변환값 사용.
# SVC    : 서비스 짧은 이름. 예: notify -> repo는 svc-notify.
# OUTDIR : 결과물 위치. 기본값은 ./_generated.

SCRIPT_PATH="${BASH_SOURCE[0]}"
SCRIPT_DIR="."
if [[ "$SCRIPT_PATH" == */* ]]; then
  SCRIPT_DIR="${SCRIPT_PATH%/*}"
fi
TPL_DIR="$(cd "$SCRIPT_DIR" && pwd)"

ORG="${1:-}"
SVC="${2:-}"
OUTDIR="${3:-$TPL_DIR/_generated}"

if [[ -z "$ORG" ]]; then read -rp "ORG (GitHub owner): " ORG; fi
if [[ -z "$SVC" ]]; then read -rp "SVC (service name, e.g. notify): " SVC; fi

if [[ -z "$ORG" || -z "$SVC" ]]; then
  echo "ORG, SVC는 비워둘 수 없습니다." >&2
  exit 1
fi
if [[ ! "$ORG" =~ ^[A-Za-z0-9_.-]+$ ]]; then
  echo "ORG에는 영문, 숫자, 점, 밑줄, 하이픈만 사용할 수 있습니다: '$ORG'" >&2
  exit 1
fi
if [[ ! "$SVC" =~ ^[a-z]([a-z0-9-]{0,61}[a-z0-9])?$ ]]; then
  echo "SVC는 소문자, 숫자, 하이픈만 사용할 수 있고 소문자로 시작해야 합니다: '$SVC'" >&2
  exit 1
fi

ORGLC="$(printf '%s' "$ORG" | tr '[:upper:]' '[:lower:]')"

BUILD="$OUTDIR/svc-$SVC"
GITOPS="$OUTDIR/gitops-$SVC"

if [[ -e "$BUILD" || -e "$GITOPS" ]]; then
  echo "대상 경로가 이미 있습니다. 덮어쓰지 않습니다:" >&2
  [[ -e "$BUILD" ]] && echo "  $BUILD" >&2
  [[ -e "$GITOPS" ]] && echo "  $GITOPS" >&2
  exit 1
fi

mkdir -p "$BUILD" "$GITOPS"

mkdir -p "$BUILD/app" "$BUILD/tests"
cp "$TPL_DIR"/app/*.py "$BUILD/app"/
cp "$TPL_DIR"/tests/*.py "$BUILD/tests"/
cp "$TPL_DIR/.dockerignore" "$BUILD/.dockerignore"
cp "$TPL_DIR/.gitattributes" "$BUILD/.gitattributes"
cp "$TPL_DIR/.gitignore" "$BUILD/.gitignore"
cp "$TPL_DIR/Dockerfile" "$BUILD/Dockerfile"
cp "$TPL_DIR/Jenkinsfile" "$BUILD/Jenkinsfile"
if [[ -f "$TPL_DIR/pyproject.toml" ]]; then
  cp "$TPL_DIR/pyproject.toml" "$BUILD/pyproject.toml"
fi

cp -r "$TPL_DIR/k8s-gitops/." "$GITOPS"/
if [[ "$SVC" != "python-app" ]]; then
  mv "$GITOPS/manifests/python-app" "$GITOPS/manifests/$SVC"
  mv "$GITOPS/argocd/apps/python-app.yaml" "$GITOPS/argocd/apps/$SVC.yaml"
fi

find "$BUILD" "$GITOPS" -type f -exec sed -i \
  -e "s|__ORGLC__|$ORGLC|g" \
  -e "s|__ORG__|$ORG|g" \
  -e "s|__SVC__|$SVC|g" \
  {} +

if grep -rn '__[A-Z][A-Z0-9_]*__' "$BUILD" "$GITOPS" >/dev/null 2>&1; then
  echo "남은 토큰이 있습니다. 치환 누락을 확인하세요." >&2
  grep -rn '__[A-Z][A-Z0-9_]*__' "$BUILD" "$GITOPS" >&2
  exit 1
fi

cat <<EOF

생성 완료. 남은 토큰 0.

  빌드 저장소 (-> github.com/$ORG/svc-$SVC 루트):
    $BUILD

  gitops 조각 (-> k8s-gitops 저장소로 복사):
    $GITOPS/manifests/$SVC/        -> k8s-gitops/manifests/$SVC/
    $GITOPS/argocd/apps/$SVC.yaml  -> k8s-gitops/argocd/apps/$SVC.yaml

다음 확인:
  cd "$BUILD" && python -m unittest discover -s tests -v

수동 등록:
  1) jenkins-shared-library resources/ci/services.yaml:
       $SVC:
         language: python
  2) 네임스페이스 '$SVC' 생성
  3) AppProject 'apps' destination namespace '$SVC' 추가

검증:
  kubectl -n $SVC get deploy $SVC -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
  # -> ghcr.io/$ORGLC/svc-$SVC:<40 SHA> 이면 정상
EOF
