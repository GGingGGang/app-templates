# app-templates

서비스 씨앗 모음. 각 템플릿을 `sed-template.sh` 로 찍어, 빌드 레포와 k8s-gitops 레포로 나눠 폴더째 옮긴다.

| 템플릿 · 사용 문서 | 용도 | Jenkins `language` |
|-------------------|------|--------------------|
| [go-app](./go-app/README.md) | Go (chi) HTTP 서비스 | `go` |
| [java-app/gradle](./java-app/gradle/README.md) | Java 21 / Spring Boot 3 HTTP 서비스 | `java` |
| [node-app](./node-app/README.md) | Node.js 22 / TypeScript / Fastify HTTP 서비스 | `node` |
| [javascript-app](./javascript-app/README.md) | JavaScript 웹 SPA + nginx (`svc-web`) | `node` |

> `java-app/maven` 은 참고용 변형 — 표준 씨앗은 `java-app/gradle`. Jenkinsfile 은 두 변형이 동일하지만 **파이프라인이 빌드툴 비의존인 것은 아니다**: `services.yaml` 의 `languages.java` 가 `gradle --no-daemon test` 하나로 정의돼 있어, maven 으로 찍은 서비스는 Test 게이트(파이프라인 맨 앞)에서 실패해 이미지 빌드에 도달하지 못한다. maven 서비스를 실제로 온보딩하려면 `jenkins-shared-library` 에 언어 키 추가가 선행돼야 한다.

## 1. 템플릿별 생성 방법

사용할 템플릿의 README에서 생성 명령과 로컬 실행 방법을 확인한다. 각 템플릿은 기본 실행·자체 상태 확인·배포 구성만 제공한다. 업무 기능과 특정 서비스 연동은 생성된 서비스에서 구현한다.

생성 스크립트의 공통 인자는 `<ORG> <SVC> [OUTDIR]`이다. `ORG`는 GitHub 소유자, `SVC`는 `web` 같은 짧은 서비스 이름이다. 출력 경로를 생략하면 **선택한 템플릿 폴더의 `_generated/`**에 생성된다. 상대 출력 경로를 지정하면 명령을 실행한 현재 폴더가 기준이다.

JavaScript는 네 번째 인자로 웹 호스트를 받는다. JavaScript 생성기는 기존 출력 폴더가 있으면 덮어쓰지 않고 실패한다.

아래 공통 온보딩의 `_generated/`는 각 템플릿에서 생성한 출력 폴더를 뜻한다. 템플릿별 실행·환경변수·Docker 확인은 위 문서를 따른다.

## 2. 이동 (한눈에)

| `_generated` 산출물 | 옮길 곳 |
|---------------------|---------|
| `svc-<SVC>/` 폴더 전체 | 새 `svc-<SVC>` 레포 루트 |
| `gitops-<SVC>/manifests/<SVC>/` | `k8s-gitops/manifests/<SVC>/` |
| `gitops-<SVC>/argocd/apps/<SVC>.yaml` | `k8s-gitops/argocd/apps/<SVC>.yaml` |

---

## 3. 공통 온보딩

### 빌드 레포

**CI 등록 선행** — 첫 push 전에 [jenkins-shared-library](https://github.com/GGingGGang/jenkins-shared-library) `resources/ci/services.yaml` 의 `services:` 에 한 줄 (그 레포에 commit·push):

```yaml
  <SVC>:
    language: go   # go-app=go, node-app/javascript-app=node, java-app/gradle=java
```

`language` 는 필수 — 미등록 상태로 빌드가 잡히면 `ci()` 가 파이프라인 조립 전에 즉시 실패한다. 복구는 등록 후 재빌드.

```bash
cd _generated/svc-<SVC>
# 선택한 템플릿 README의 로컬 검증을 먼저 완료한다.
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
