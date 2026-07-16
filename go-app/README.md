# go-app

Go 1.23 / chi HTTP 서비스 씨앗. `sed-template.sh` 로 `__ORG__`/`__ORGLC__`/`__SVC__` 토큰을 치환해 새 `svc-<SVC>` 서비스를 찍어낸다.

## 포함된 것

- `Dockerfile` — distroless nonroot 멀티스테이지 빌드
- `Jenkinsfile` — thin pipeline (`@Library('shared')` + `kanikoBuild` + `trivyImageScan` + `deployBump`)
- `cmd/server/main.go` + `internal/api/{router,health}.go` — hello 서버 (healthz/readyz)
- `k8s-gitops/manifests/go-app/` — deployment/service/httproute/servicemonitor/kustomization
- `k8s-gitops/argocd/apps/go-app.yaml` — Application 포인터

사용법은 상위 [`../README.md`](../README.md) 참조 (스탬프 → 이동 → 구동 순서).

## Ports

| Port | Purpose |
|------|---------|
| `8080` | HTTP API + `/metrics` |

## 관측

`/metrics` — `promhttp.Handler()` 기반 Go 런타임 기본 메트릭(GC, goroutine 등)만 노출. 커스텀 앱 메트릭·OTel 트레이싱은 씨앗에 없음 — 생성된 서비스가 직접 추가.

`servicemonitor.yaml` 이 클러스터의 kube-prometheus-stack(`release: kps`)에 자동 스크랩 등록됨 — 별도 설정 불필요.

## Environment Variables

```bash
HTTP_PORT=8080   # listen port (기본 8080)
```

## API

| Method | Path | Description |
|--------|------|-------------|
| GET | `/healthz` | Liveness probe → `{"status":"ok"}` |
| GET | `/readyz` | Readiness probe → `{"status":"ready"}` |
| GET | `/metrics` | Prometheus 스크랩 엔드포인트 |

도메인 라우트는 없음 — 씨앗은 hello 서버까지. 생성된 서비스가 `internal/api/`에 직접 추가.
