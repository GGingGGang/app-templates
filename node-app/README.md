# node-app

Node.js 22 / TypeScript / Fastify HTTP 서비스 씨앗. `sed-template.sh` 로 `__ORG__`/`__ORGLC__`/`__SVC__` 토큰을 치환해 새 `svc-<SVC>` 서비스를 찍어낸다.

## 포함된 것

- `Dockerfile` — node:22-alpine 빌드(tsc) → distroless nodejs22 nonroot 멀티스테이지
- `Jenkinsfile` — thin pipeline (`@Library('shared')` + `kanikoBuild` + `deployBump`)
- `package.json` / `tsconfig.json` — ESM(NodeNext), `svc-<SVC>` 로 치환되는 name
- `src/server.ts` — 엔트리(포트·graceful shutdown), `src/router.ts` — Fastify 앱·라우트, `src/health.ts` — 핸들러
- `k8s-gitops/manifests/node-app/` — deployment/service/httproute/servicemonitor/kustomization
- `k8s-gitops/argocd/apps/node-app.yaml` — Application 포인터

사용법은 상위 [`../README.md`](../README.md) 참조 (스탬프 → 이동 → 구동 순서).

> TypeScript ESM(NodeNext) 규약상 소스 import 는 컴파일 결과(`.js`)를 가리킨다 — 예: `./router.js`.
> 런타임은 `dist/`(tsc 산출물)를 실행하고, distroless 이미지의 ENTRYPOINT(`node`)가 `dist/server.js` 를 띄운다.

## Ports

| Port | Purpose |
|------|---------|
| `3000` | HTTP API + `/metrics` |

## 관측

`/metrics` — `prom-client` 의 `collectDefaultMetrics()` 기반 Node/프로세스 런타임 기본 메트릭만 노출(go-app promhttp 대응). 커스텀 앱 메트릭·OTel 트레이싱은 씨앗에 없음 — 생성된 서비스가 직접 추가.

`servicemonitor.yaml` 이 클러스터의 kube-prometheus-stack(`release: kps`)에 자동 스크랩 등록됨 — 별도 설정 불필요.

## Environment Variables

```bash
HTTP_PORT=3000          # listen port (기본 3000)
NODE_ENV=production     # deployment 에서 주입
APP_VERSION=<GIT_SHA>   # Dockerfile 이 GIT_SHA 로 주입 (기본 dev)
```

## API

| Method | Path | Description |
|--------|------|-------------|
| GET | `/healthz` | Liveness probe → `{"status":"ok"}` |
| GET | `/readyz` | Readiness probe → `{"status":"ready"}` |
| GET | `/metrics` | Prometheus 스크랩 엔드포인트 |

도메인 라우트(사용자/인증/세션/토큰 등)는 없음 — 씨앗은 hello 서버까지. 생성된 서비스가 `src/`에 직접 추가.

## 로컬 확인 (선택)

```bash
npm install
npm run dev        # tsx watch, :3000
# 또는
npm run build && npm start   # dist/server.js
```
