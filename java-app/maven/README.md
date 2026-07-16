# java-app (Maven)

Java 21 / Spring Boot 3.4 HTTP 서비스 씨앗. `sed-template.sh` 로 `__ORG__`/`__ORGLC__`/`__SVC__` 토큰을 치환해 새 `svc-<SVC>` 서비스를 찍어낸다.

## 포함된 것

- `Dockerfile` — Maven 빌드 → distroless java21 nonroot 멀티스테이지 빌드
- `Jenkinsfile` — thin pipeline (`@Library('shared')` + `kanikoBuild` + `trivyImageScan` + `deployBump`)
- `pom.xml` — spring-boot-starter-parent 기반, `finalName` 을 `svc-<SVC>` 로 고정
- `src/main/java/cloud/ggang/app/` — `Application` + `HealthController` (healthz/readyz)
- `src/main/resources/application.yml` — 포트·graceful shutdown·actuator(/metrics) 설정
- `k8s-gitops/manifests/java-app/` — deployment/service/httproute/servicemonitor/kustomization
- `k8s-gitops/argocd/apps/java-app.yaml` — Application 포인터

사용법은 상위 [`../../README.md`](../../README.md) 참조 (스탬프 → 이동 → 구동 순서).

> 패키지는 `cloud.ggang.app` 로 고정 (서비스 이름을 패키지에 넣지 않아 디렉터리 리네임 불필요).
> Maven artifactId·name 과 jar 이름(finalName)만 `svc-<SVC>` 로 치환된다.

## Ports

| Port | Purpose |
|------|---------|
| `8080` | HTTP API + `/metrics` |

## 관측

`/metrics` — Spring Boot Actuator + Micrometer Prometheus 레지스트리. `management.endpoints.web`
설정으로 actuator 의 prometheus 엔드포인트를 `/metrics` 로 재매핑해 go-app 씨앗과 같은 경로로 노출.
JVM/프로세스 기본 메트릭만 나오며, 커스텀 앱 메트릭·OTel 트레이싱은 씨앗에 없음 — 생성된 서비스가 직접 추가.

`servicemonitor.yaml` 이 클러스터의 kube-prometheus-stack(`release: kps`)에 자동 스크랩 등록됨 — 별도 설정 불필요.

## Environment Variables

```bash
HTTP_PORT=8080                              # listen port (기본 8080)
JAVA_TOOL_OPTIONS=-XX:MaxRAMPercentage=75.0 # 컨테이너 메모리 대비 힙 비율 (deployment 에서 주입)
APP_VERSION=<GIT_SHA>                       # Dockerfile 이 GIT_SHA 로 주입 (기본 dev)
```

## API

| Method | Path | Description |
|--------|------|-------------|
| GET | `/healthz` | Liveness probe → `{"status":"ok"}` |
| GET | `/readyz` | Readiness probe → `{"status":"ready"}` |
| GET | `/metrics` | Prometheus 스크랩 엔드포인트 |

도메인 라우트는 없음 — 씨앗은 hello 서버까지. 생성된 서비스가 `src/main/java/cloud/ggang/app/`에 직접 추가.

## 로컬 확인 (선택)

```bash
mvn -q -DskipTests package     # target/svc-<SVC>.jar
java -jar target/svc-<SVC>.jar # :8080
```
