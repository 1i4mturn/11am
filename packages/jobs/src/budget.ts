import type { JobBudget, JobCost } from "./types";

const DEFAULT_INPUT_PRICE = 3.0;
const DEFAULT_OUTPUT_PRICE = 15.0;

export function estimateCostUsd(
  inputTokens: number,
  outputTokens: number,
  inputPricePerM = DEFAULT_INPUT_PRICE,
  outputPricePerM = DEFAULT_OUTPUT_PRICE
): number {
  return (
    (inputTokens / 1_000_000) * inputPricePerM +
    (outputTokens / 1_000_000) * outputPricePerM
  );
}

export function estimateJobCost(prompt: string, budget: JobBudget): {
  estimated_tokens: number;
  estimated_usd: number;
  budget: JobBudget;
} {
  const estimated_tokens = Math.min(
    budget.max_tokens,
    Math.max(8_000, prompt.length * 4 + 20_000)
  );
  const estimated_usd = Math.min(
    budget.max_cost_usd,
    estimateCostUsd(estimated_tokens * 0.7, estimated_tokens * 0.3)
  );
  return { estimated_tokens, estimated_usd, budget };
}

export function isBudgetExceeded(
  cost: JobCost,
  budget: JobBudget,
  startedAt: number
): { exceeded: boolean; reason?: string } {
  if (cost.input_tokens + cost.output_tokens >= budget.max_tokens) {
    return { exceeded: true, reason: "Token budget exceeded" };
  }
  if (cost.estimated_usd >= budget.max_cost_usd) {
    return { exceeded: true, reason: "Cost budget exceeded" };
  }
  if (Date.now() - startedAt >= budget.max_time_ms) {
    return { exceeded: true, reason: "Time budget exceeded" };
  }
  return { exceeded: false };
}

export function addTokenUsage(
  cost: JobCost,
  inputTokens: number,
  outputTokens: number,
  inputPricePerM?: number,
  outputPricePerM?: number
): JobCost {
  const input_tokens = cost.input_tokens + inputTokens;
  const output_tokens = cost.output_tokens + outputTokens;
  return {
    input_tokens,
    output_tokens,
    estimated_usd: estimateCostUsd(
      input_tokens,
      output_tokens,
      inputPricePerM,
      outputPricePerM
    ),
    elapsed_ms: cost.elapsed_ms,
  };
}
