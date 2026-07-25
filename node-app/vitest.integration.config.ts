import { defineConfig } from "vitest/config";

// Integration suite (testcontainers — requires Docker).
// Run via `npm run test:integration` (this repo's GitHub Actions, per
// test-contract.md §3/§4 — not the Jenkins unit gate).
// The seed ships no integration tests — passWithNoTests keeps the command
// green until the generated service adds its first *.integration.test.ts.
export default defineConfig({
  test: {
    include: ["**/*.integration.test.ts"],
    passWithNoTests: true,
  },
});
