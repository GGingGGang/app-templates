import { describe, expect, it } from "vitest";

import { buildApp } from "./router.js";

describe("hello server routes", () => {
  it("healthz returns ok", async () => {
    const app = buildApp();
    await app.ready();

    const response = await app.inject({ method: "GET", url: "/healthz" });
    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ status: "ok" });

    await app.close();
  });

  it("readyz returns ready", async () => {
    const app = buildApp();
    await app.ready();

    const response = await app.inject({ method: "GET", url: "/readyz" });
    expect(response.statusCode).toBe(200);
    expect(response.json()).toEqual({ status: "ready" });

    await app.close();
  });

  it("metrics exposes prometheus text format", async () => {
    const app = buildApp();
    await app.ready();

    const response = await app.inject({ method: "GET", url: "/metrics" });
    expect(response.statusCode).toBe(200);
    expect(response.body).toContain("process_cpu_user_seconds_total");

    await app.close();
  });
});
