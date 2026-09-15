# python-app

Python 3.13 표준 라이브러리만 사용하는 최소 HTTP 서비스 템플릿입니다. `sed-template.sh`로 `__ORG__`, `__ORGLC__`, `__SVC__` 토큰을 치환해서 `svc-<SVC>` 빌드 저장소와 GitOps 조각을 만듭니다.

## 포함된 것

- `app/` 표준 라이브러리 HTTP 서버와 정상 종료 처리
- `/healthz`, `/readyz`, `/metrics` 엔드포인트
- `tests/` `unittest` 기반 설정, HTTP, 서버 종료 테스트
- `Dockerfile` Python 3.13 slim, nonroot 실행, read-only root filesystem 배포에 맞춘 런타임
- `Jenkinsfile` `@Library('shared')` + `ci(service: '<svc>')`
- `k8s-gitops/` Deployment, Service, ServiceMonitor, Kustomization, ArgoCD Application

기본 기능은 자체 상태 확인과 실행 시간·준비 상태 메트릭입니다. 알림 처리 같은 업무 기능은 생성된 서비스에서 구현합니다. 아래 `notify`는 생성할 서비스 이름의 예시입니다.

## 1. 서비스 생성

아래 명령은 원본 `app-templates/python-app`에서 실행합니다:

```bash
bash sed-template.sh <ORG> <SVC> [OUTDIR]
```

예시 — `app-templates` 저장소 루트에서 시작합니다:

```bash
cd python-app
bash sed-template.sh GGingGGang notify ./_generated
```

생성 결과는 `python-app/_generated/svc-notify/`와 `python-app/_generated/gitops-notify/`입니다. 기존 출력 폴더는 덮어쓰지 않습니다. 출력 경로를 생략해도 템플릿 폴더의 `_generated/`를 사용합니다.

이 문서의 이후 명령은 **생성된 `svc-notify` 폴더에서** 실행합니다:

```bash
# 위 생성 명령에 이어서 실행
cd _generated/svc-notify
```

## 2. 로컬 실행 · 테스트

```bash
python -m unittest discover -s tests -v
python -m app.main
```

기본 포트는 `8080`입니다.

## 3. 환경변수 · 배포 설정

| 환경 변수 | 기본값 | 설명 |
| --- | --- | --- |
| `SERVICE_NAME` | `svc-__SVC__` | 메트릭 라벨에 쓰는 서비스 이름 |
| `HTTP_HOST` | `0.0.0.0` | HTTP listen host |
| `HTTP_PORT` | `8080` | HTTP listen port |
| `APP_VERSION` | `dev` | Docker 빌드에서 `GIT_SHA`로 주입 |

생성된 GitOps 조각은 내부 Service와 Prometheus scrape를 제공합니다. 외부 HTTPRoute는 필요할 때 생성된 서비스의 GitOps 설정에 추가합니다.

컨테이너는 UID/GID 65532로 실행하며 읽기 전용 루트 파일시스템을 사용합니다. `SIGTERM` 또는 `SIGINT`를 받으면 HTTP 서버를 종료합니다.

## 4. Docker 확인

생성된 `svc-notify` 폴더에서 실행합니다. 다른 서비스 이름이면 이미지 태그와 컨테이너 이름도 바꿉니다. 아래는 ARM64 노드 기준이며 로컬 CPU가 다르면 `--platform`을 로컬 환경에 맞춥니다.

```bash
docker build --platform linux/arm64 -t svc-notify:local .
docker run -d --rm --name notify-smoke --read-only --tmpfs /tmp:rw,noexec,nosuid,size=16m -p 127.0.0.1:8080:8080 svc-notify:local
curl http://127.0.0.1:8080/healthz
curl http://127.0.0.1:8080/readyz
curl http://127.0.0.1:8080/metrics
docker stop notify-smoke
```

## 5. CI 등록 · 온보딩

첫 push 전에 `jenkins-shared-library/resources/ci/services.yaml`의 기존 `services` 항목에 추가합니다:

```yaml
  notify:
    language: python
```

다른 이름으로 생성했다면 `notify`를 해당 이름으로 바꿉니다. 공통 라이브러리의 Python 언어 게이트도 먼저 반영되어 있어야 합니다:

```yaml
testImage: docker.io/library/python:3.13-slim
testCmd: python -m unittest discover -s tests -v
```

GitOps 조각 이동, 네임스페이스·AppProject 등록, 이미지 pull Secret과 Jenkins 연결은 `app-templates/README.md`의 공통 온보딩 절차를 따릅니다.
