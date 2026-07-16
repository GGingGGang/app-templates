# app-templates

서비스 씨앗 모음. 각 템플릿을 `sed-template.sh` 로 찍어, 빌드 레포와 k8s-gitops 레포로 나눠 폴더째 옮긴다.

| 템플릿 | 설명 |
|--------|------|
| `go-app` | Go (chi) HTTP 서비스 |
| `java-app/gradle` | Java 21 / Spring Boot 3 HTTP 서비스 (Gradle) |
| `node-app` | Node.js 22 / TypeScript / Fastify HTTP 서비스 |

> `java-app/maven` 은 참고용 변형 — 표준 씨앗은 `java-app/gradle`. 두 변형의 Jenkinsfile 은 동일 (파이프라인은 빌드툴 비의존).

## 1. 스탬프

```bash
cd go-app       # 또는 java-app/gradle, node-app
bash sed-template.sh <ORG> <SVC>
```

`_generated/` 아래 두 폴더가 생긴다.

## 2. 이동 (한눈에)

| `_generated` 산출물 | 옮길 곳 |
|---------------------|---------|
| `svc-<SVC>/` 폴더 전체 | 새 `svc-<SVC>` 레포 루트 |
| `gitops-<SVC>/manifests/<SVC>/` | `k8s-gitops/manifests/<SVC>/` |
| `gitops-<SVC>/argocd/apps/<SVC>.yaml` | `k8s-gitops/argocd/apps/<SVC>.yaml` |

---

## 구동 순서

### 빌드 레포

```bash
cd _generated/svc-<SVC>
go mod tidy    # go 씨앗 기준 — node 는 npm install (선택), java 는 생략 가능 (CI 가 Dockerfile 안에서 빌드)
git init
git add -A
git commit -m "bootstrap svc-<SVC>"
git remote add origin https://github.com/<ORG>/svc-<SVC>.git
git branch -M main
git push -u origin main
```

#### Jenkins 편입

레포별 push webhook 등록 — 개인 계정은 계정-레벨 훅이 없어 레포마다 1회:

```bash
# gh 토큰에 admin:repo_hook 없으면 선행: gh auth refresh -h github.com -s admin:repo_hook
gh api "repos/<ORG>/svc-<SVC>/hooks" -f name=web -F active=true \
  -f 'events[]=push' \
  -f 'config[url]=https://ci-hook.<DOMAIN>/github-webhook/' \
  -f 'config[content_type]=json'
```

webhook 은 **이미 발견된 잡만** 트리거한다. 신규 레포를 잡으로 만드는 건 스캔:

- 자동 — organizationFolder 재스캔(15m 주기) 또는 controller 재기동(부팅 스캔) 시 `svc-*` 규칙으로 편입
- 즉시 — 새 ref 생성 이벤트만 미발견 레포를 바로 편입시키므로, 임시 브랜치로 킥:

```bash
git push origin main:onboard   # 편입 + 전체 브랜치 인덱싱
git push origin :onboard       # 잡 생성 확인 후 삭제
```

> 함정: 레포를 미리 만들어 두고(초기 커밋 존재) 나중에 코드를 push 하면 `created:false` 이벤트라 편입되지 않는다 — 위 킥 또는 다음 재스캔 대기.

### gitops 레포

```bash
cp -r _generated/gitops-<SVC>/manifests/<SVC>       <k8s-gitops>/manifests/
cp -r _generated/gitops-<SVC>/argocd/apps/<SVC>.yaml <k8s-gitops>/argocd/apps/
```

네임스페이스 배선 — **`sed-template.sh` 산출물에 없음, 아래 2곳은 직접 수동 편집**:

```bash
# 네임스페이스 <SVC> 를 플랫폼 네임스페이스 매니페스트에 추가 (oci-always-free-k8s 의 kubernetes/infra/namespaces/namespaces.yaml)
# k8s-gitops/argocd/project.yaml 의 spec.destinations 에 namespace <SVC> 직접 추가 (편집)
```

네임스페이스가 생기면 **pull Secret 복사** — Secret 은 NS 스코프 + git 미보관이라 새 NS 마다 수동 1회. 누락 시 첫 배포가 `ImagePullBackOff` (GHCR 신규 패키지는 첫 push 때 private 로 생성):

```bash
kubectl -n <SVC> create secret generic ghcr-pull \
  --type=kubernetes.io/dockerconfigjson \
  --from-literal=.dockerconfigjson="$(kubectl -n core get secret ghcr-pull \
      -o go-template='{{index .data ".dockerconfigjson" | base64decode}}')"
```

DB 접속이 필요한 서비스라면 **DB 온보딩**도 같은 시점에 — 전용 DB/유저 생성 + `db-creds` Secret 등록 ([oci-always-free-k8s](https://github.com/GGingGGang/oci-always-free-k8s) 레포 소관). 씨앗 deployment.yaml 에는 `db-creds` 참조가 없음 — 필요한 서비스만 `secretKeyRef` 로 직접 추가 (실제 예: [k8s-gitops/manifests](https://github.com/GGingGGang/k8s-gitops/tree/main/manifests) 의 core/auth/batch):

```bash
cd <oci-always-free-k8s>
DB_HOST=$(terraform -chdir=terraform output -raw heatwave_ip) \
DB_PORT=$(terraform -chdir=terraform output -raw heatwave_port) \
  scripts/onboard-app-db.sh <SVC> <SVC>
```

상세는 [oci-always-free-k8s/scripts/README.md](https://github.com/GGingGGang/oci-always-free-k8s/blob/main/scripts/README.md) 참조.

커밋 — `manifests/<SVC>`·`apps/<SVC>.yaml` 은 스탬프 산출물, `project.yaml` 은 위에서 직접 편집한 결과:

```bash
cd <k8s-gitops>
git add manifests/<SVC> argocd/apps/<SVC>.yaml argocd/project.yaml
git commit -m "onboard svc-<SVC>"
git push
```

루트 app-of-apps 가 `argocd/apps/<SVC>.yaml` 을 잡아 배포한다.

### 판정

```bash
kubectl -n <SVC> get deploy <SVC> -o jsonpath='{.spec.template.spec.containers[0].image}'
```

`ghcr.io/<org-lowercase>/svc-<SVC>:<SHA>` 이면 완주.
