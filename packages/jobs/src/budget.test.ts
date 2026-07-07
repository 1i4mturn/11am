import { test } from "node:test";
import assert from "node:assert/strict";
import {
  addTokenUsage,
  estimateCostUsd,
  estimateJobCost,
  isBudgetExceeded,
} from "./budget.ts";
import type { JobBudget, JobCost } from "./types.ts";

const budget: JobBudget = {
  max_tokens: 100_000,
  max_time_ms: 30 * 60 * 1000,
  max_cost_usd: 2.0,
};

test("estimateCostUsd uses per-million pricing", () => {
  assert.equal(estimateCostUsd(1_000_000, 0), 3.0);
  assert.equal(estimateCostUsd(0, 1_000_000), 15.0);
  assert.equal(estimateCostUsd(500_000, 200_000), 1.5 + 3.0);
});

test("estimateJobCost never exceeds the budget caps", () => {
  const longPrompt = "x".repeat(200_000);
  const estimate = estimateJobCost(longPrompt, budget);
  assert.ok(estimate.estimated_tokens <= budget.max_tokens);
  assert.ok(estimate.estimated_usd <= budget.max_cost_usd);
});

test("estimateJobCost has a sensible floor for short prompts", () => {
  const estimate = estimateJobCost("hi", budget);
  assert.ok(estimate.estimated_tokens >= 8_000);
});

test("isBudgetExceeded flags token, cost, and time overruns", () => {
  const now = Date.now();
  const okCost: JobCost = { input_tokens: 10, output_tokens: 10, estimated_usd: 0.01, elapsed_ms: 0 };
  assert.equal(isBudgetExceeded(okCost, budget, now).exceeded, false);

  const tokenBlown: JobCost = { ...okCost, input_tokens: budget.max_tokens };
  assert.equal(isBudgetExceeded(tokenBlown, budget, now).reason, "Token budget exceeded");

  const costBlown: JobCost = { ...okCost, estimated_usd: budget.max_cost_usd };
  assert.equal(isBudgetExceeded(costBlown, budget, now).reason, "Cost budget exceeded");

  const timeBlown = isBudgetExceeded(okCost, budget, now - budget.max_time_ms - 1);
  assert.equal(timeBlown.reason, "Time budget exceeded");
});

test("addTokenUsage accumulates and re-prices", () => {
  const start: JobCost = { input_tokens: 100, output_tokens: 50, estimated_usd: 0, elapsed_ms: 5 };
  const next = addTokenUsage(start, 900, 950);
  assert.equal(next.input_tokens, 1_000);
  assert.equal(next.output_tokens, 1_000);
  assert.equal(next.elapsed_ms, 5);
  assert.ok(Math.abs(next.estimated_usd - estimateCostUsd(1_000, 1_000)) < 1e-12);
});
