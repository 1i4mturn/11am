import { askConner, extractJson } from "@/lib/claude";
import {
  getAvailableAgentSummaries,
  getBoltonContext,
  getGeorgeNumbers,
  getJamesMarketResearch,
  getJamesPricingResearch,
  persistStrategyToBolton,
} from "@/lib/bolton/client";
import { LEO_API_URL } from "@/lib/config";
import type {
  ConnerStrategySummary,
  DigestResult,
  GrowthResult,
  GtmResult,
  IdeaValidationResult,
  JamesInvokeResult,
  PricingResult,
  StressTestResult,
} from "@/lib/types";
import { ConnerStrategySummarySchema } from "@/lib/types";

const IDEA_VALIDATION_PROMPT = `Validate a business idea and draft an initial offer.
Respond with JSON ONLY using this exact shape:
{
  "verdict": "pursue" | "refine" | "park" | "kill",
  "reasoning": "string",
  "market_assumptions": ["string"],
  "risks": ["string"],
  "offer": {
    "headline": "string",
    "promise": "string",
    "audience": "string",
    "price_anchor": "string",
    "delivery": "string"
  },
  "next_steps": ["string"],
  "confidence": "high" | "medium" | "low"
}
Then after the JSON, add a blank line and a markdown narrative section starting with "## Conner's take".`;

const STRESS_TEST_PROMPT = `Stress-test a business model against George's latest numbers.
Use the finance data to flag runway risk, margin pressure, and unrealistic assumptions.
Respond with JSON ONLY:
{
  "stress_points": ["string"],
  "runway_impact": "string",
  "unit_economics_flags": ["string"],
  "recommendation": "string",
  "confidence": "high" | "medium" | "low"
}
Then a markdown narrative starting with "## Stress test".`;

const GTM_PROMPT = `Create a go-to-market and launch plan.
If James market research is provided, ground channel choices in it.
Respond with JSON ONLY:
{
  "launch_brief": "string",
  "channels": [{ "channel": "string", "rationale": "string", "priority": "now" | "next" | "later" }],
  "timeline_phases": [{ "phase": "string", "duration": "string", "actions": ["string"] }],
  "confidence": "high" | "medium" | "low"
}
Then markdown narrative starting with "## GTM plan".`;

const GROWTH_PROMPT = `Design a growth strategy synthesising George's numbers and James's research.
Respond with JSON ONLY:
{
  "strategy_summary": "string",
  "levers": [{ "lever": "string", "impact": "high|medium|low", "effort": "high|medium|low" }],
  "experiments": ["string"],
  "confidence": "high" | "medium" | "low"
}
Then markdown narrative starting with "## Growth strategy".`;

const PRICING_PROMPT = `Recommend a pricing strategy using George's unit economics and James's pricing research.
Respond with JSON ONLY:
{
  "pricing_model": "string",
  "tiers_or_packages": [{ "name": "string", "price": "string", "rationale": "string" }],
  "unit_economics_check": "string",
  "competitive_position": "string",
  "recommendation": "string",
  "confidence": "high" | "medium" | "low"
}
Then markdown narrative starting with "## Pricing strategy".`;

const DIGEST_PROMPT = `Synthesise a weekly business health digest from available agent summaries.
Respond with JSON ONLY:
{
  "health_score": "strong" | "stable" | "caution" | "critical",
  "highlights": ["string"],
  "concerns": ["string"],
  "cross_agent_synthesis": "string",
  "recommended_actions": ["string"]
}
Then markdown narrative starting with "## Weekly digest".`;

const STRATEGY_SUMMARY_PROMPT = `Distil this Conner session into a latest-strategy summary.
Respond with JSON ONLY using this exact shape:
{
  "source_agent": "conner",
  "as_of": "YYYY-MM-DD",
  "positioning_update": "string — current positioning in 1-2 sentences",
  "target_segment": "string — who we're building for",
  "key_decisions": ["string — concrete decisions made or recommended"],
  "confidence": "high" | "medium" | "low"
}`;

function splitNarrative(text: string): { json: Record<string, unknown> | null; narrative: string } {
  const json = extractJson<Record<string, unknown>>(text);
  const narrativeMatch = text.match(/##[\s\S]*/);
  const narrative = narrativeMatch?.[0] ?? text;
  return { json, narrative };
}

export async function runIdeaValidation(idea: string): Promise<IdeaValidationResult> {
  const raw = await askConner(IDEA_VALIDATION_PROMPT, `Business idea to validate:\n${idea}`, 5000);
  const { json, narrative } = splitNarrative(raw);

  return {
    workflow: "idea_validation",
    idea,
    verdict: (json?.verdict as IdeaValidationResult["verdict"]) ?? "refine",
    reasoning: String(json?.reasoning ?? "See narrative"),
    market_assumptions: Array.isArray(json?.market_assumptions)
      ? (json.market_assumptions as string[])
      : [],
    risks: Array.isArray(json?.risks) ? (json.risks as string[]) : [],
    offer: {
      headline: String(json?.offer && typeof json.offer === "object" && "headline" in json.offer ? (json.offer as { headline: string }).headline : "Draft offer"),
      promise: String(json?.offer && typeof json.offer === "object" && "promise" in json.offer ? (json.offer as { promise: string }).promise : ""),
      audience: String(json?.offer && typeof json.offer === "object" && "audience" in json.offer ? (json.offer as { audience: string }).audience : ""),
      price_anchor: String(json?.offer && typeof json.offer === "object" && "price_anchor" in json.offer ? (json.offer as { price_anchor: string }).price_anchor : ""),
      delivery: String(json?.offer && typeof json.offer === "object" && "delivery" in json.offer ? (json.offer as { delivery: string }).delivery : ""),
    },
    next_steps: Array.isArray(json?.next_steps) ? (json.next_steps as string[]) : [],
    confidence: (json?.confidence as IdeaValidationResult["confidence"]) ?? "medium",
    narrative,
  };
}

export async function runStressTest(ideaOrModel: string): Promise<StressTestResult> {
  const { data: george, from_mock } = await getGeorgeNumbers();
  const raw = await askConner(
    STRESS_TEST_PROMPT,
    `Business model to stress-test:\n${ideaOrModel}\n\nGeorge's latest numbers:\n${JSON.stringify(george, null, 2)}`,
    5000
  );
  const { json, narrative } = splitNarrative(raw);

  return {
    workflow: "stress_test",
    idea_or_model: ideaOrModel,
    george_context: george,
    used_mock_george: from_mock,
    stress_points: Array.isArray(json?.stress_points) ? (json.stress_points as string[]) : [],
    runway_impact: String(json?.runway_impact ?? ""),
    unit_economics_flags: Array.isArray(json?.unit_economics_flags)
      ? (json.unit_economics_flags as string[])
      : [],
    recommendation: String(json?.recommendation ?? ""),
    confidence: (json?.confidence as StressTestResult["confidence"]) ?? "medium",
    narrative,
  };
}

export async function runGtmPlanning(brief: string): Promise<GtmResult> {
  const { data: james, from_mock } = await getJamesMarketResearch();
  const raw = await askConner(
    GTM_PROMPT,
    `Launch brief:\n${brief}\n\nJames market research (if available):\n${JSON.stringify(james, null, 2)}`,
    6000
  );
  const { json, narrative } = splitNarrative(raw);

  return {
    workflow: "gtm",
    launch_brief: String(json?.launch_brief ?? brief),
    channels: Array.isArray(json?.channels)
      ? (json.channels as GtmResult["channels"])
      : [],
    timeline_phases: Array.isArray(json?.timeline_phases)
      ? (json.timeline_phases as GtmResult["timeline_phases"])
      : [],
    james_context_used: true,
    used_mock_james: from_mock,
    confidence: (json?.confidence as GtmResult["confidence"]) ?? "medium",
    narrative,
  };
}

export async function runGrowthStrategy(focus: string): Promise<GrowthResult> {
  const summaries = await getAvailableAgentSummaries();
  const raw = await askConner(
    GROWTH_PROMPT,
    `Growth focus:\n${focus}\n\nGeorge numbers:\n${JSON.stringify(summaries.george, null, 2)}\n\nJames research:\n${JSON.stringify(summaries.james, null, 2)}`,
    6000
  );
  const { json, narrative } = splitNarrative(raw);

  return {
    workflow: "growth",
    strategy_summary: String(json?.strategy_summary ?? ""),
    levers: Array.isArray(json?.levers) ? (json.levers as GrowthResult["levers"]) : [],
    experiments: Array.isArray(json?.experiments) ? (json.experiments as string[]) : [],
    george_context_used: summaries.george !== null,
    james_context_used: summaries.james !== null,
    used_mock_george: summaries.george_mock,
    used_mock_james: summaries.james_mock,
    confidence: (json?.confidence as GrowthResult["confidence"]) ?? "medium",
    narrative,
  };
}

export async function runPricingStrategy(context: string): Promise<PricingResult> {
  const georgeResult = await getGeorgeNumbers();
  const jamesResult = await getJamesPricingResearch();
  const raw = await askConner(
    PRICING_PROMPT,
    `Pricing context:\n${context}\n\nGeorge unit economics / numbers:\n${JSON.stringify(georgeResult.data, null, 2)}\n\nJames pricing research:\n${JSON.stringify(jamesResult.data, null, 2)}`,
    6000
  );
  const { json, narrative } = splitNarrative(raw);

  return {
    workflow: "pricing",
    pricing_model: String(json?.pricing_model ?? ""),
    tiers_or_packages: Array.isArray(json?.tiers_or_packages)
      ? (json.tiers_or_packages as PricingResult["tiers_or_packages"])
      : [],
    unit_economics_check: String(json?.unit_economics_check ?? ""),
    competitive_position: String(json?.competitive_position ?? ""),
    george_context: georgeResult.data,
    james_research_summary: JSON.stringify(jamesResult.data),
    used_mock_george: georgeResult.from_mock,
    used_mock_james: jamesResult.from_mock,
    recommendation: String(json?.recommendation ?? ""),
    confidence: (json?.confidence as PricingResult["confidence"]) ?? "medium",
    narrative,
  };
}

export async function runWeeklyDigest(): Promise<DigestResult> {
  const summaries = await getAvailableAgentSummaries();
  const contextPack = await getBoltonContext(
    "Latest summaries from all agents — George finance, James research, Conner strategy"
  );

  const agentsAvailable: string[] = [];
  const agentsMissing: string[] = [];

  if (summaries.george) agentsAvailable.push(summaries.george_mock ? "George (mock)" : "George");
  else agentsMissing.push("George");

  if (summaries.james) agentsAvailable.push(summaries.james_mock ? "James (mock)" : "James");
  else agentsMissing.push("James");

  if (summaries.conner) agentsAvailable.push("Conner");
  else agentsMissing.push("Conner");

  const raw = await askConner(
    DIGEST_PROMPT,
    `Available agent data:\n${JSON.stringify(
      {
        george: summaries.george,
        james: summaries.james,
        conner: summaries.conner,
        bolton_context: contextPack?.context_pack ?? null,
      },
      null,
      2
    )}`,
    6000
  );
  const { json, narrative } = splitNarrative(raw);

  return {
    workflow: "digest",
    period_label: `Week of ${new Date().toISOString().slice(0, 10)}`,
    health_score: (json?.health_score as DigestResult["health_score"]) ?? "stable",
    highlights: Array.isArray(json?.highlights) ? (json.highlights as string[]) : [],
    concerns: Array.isArray(json?.concerns) ? (json.concerns as string[]) : [],
    cross_agent_synthesis: String(json?.cross_agent_synthesis ?? ""),
    agents_available: agentsAvailable,
    agents_missing: agentsMissing,
    recommended_actions: Array.isArray(json?.recommended_actions)
      ? (json.recommended_actions as string[])
      : [],
    narrative,
  };
}

export async function buildLatestStrategyFromSession(
  sessionSummary: string
): Promise<ConnerStrategySummary> {
  const raw = await askConner(STRATEGY_SUMMARY_PROMPT, sessionSummary, 2000);
  const parsed = extractJson<ConnerStrategySummary>(raw);

  if (parsed) {
    const validated = ConnerStrategySummarySchema.safeParse({
      ...parsed,
      source_agent: "conner",
      as_of: parsed.as_of ?? new Date().toISOString().slice(0, 10),
    });
    if (validated.success) return validated.data;
  }

  return {
    source_agent: "conner",
    as_of: new Date().toISOString().slice(0, 10),
    positioning_update: sessionSummary.slice(0, 300),
    target_segment: "To be refined",
    key_decisions: [],
    confidence: "low",
  };
}

export async function writeLatestStrategy(sessionSummary: string): Promise<{
  summary: ConnerStrategySummary;
  memory_ids_written: string[];
}> {
  const summary = await buildLatestStrategyFromSession(sessionSummary);
  const memory_ids_written = await persistStrategyToBolton(summary);
  return { summary, memory_ids_written };
}

export async function invokeJamesResearch(
  task: string,
  priority: "normal" | "urgent" = "normal"
): Promise<JamesInvokeResult> {
  const res = await fetch(`${LEO_API_URL}/api/invoke`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      from_agent: "conner",
      to_agent: "james",
      task,
      priority,
      response_mode: "sync",
    }),
  });

  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error((err as { error?: string }).error ?? "James invoke failed");
  }

  return res.json() as Promise<JamesInvokeResult>;
}

export async function runHandoff(input: {
  from_agent: string;
  task: string;
  request_type?: string;
  context_ref?: string;
  priority?: "normal" | "urgent";
}): Promise<{
  summary: string;
  structured_result?: Record<string, unknown>;
  memory_ids_written: string[];
}> {
  const requestType = input.request_type ?? "general";
  let result: Record<string, unknown>;
  let summary: string;

  switch (requestType) {
    case "positioning":
    case "offer":
    case "idea_validation": {
      const r = await runIdeaValidation(input.task);
      result = r as unknown as Record<string, unknown>;
      summary = `${r.verdict.toUpperCase()}: ${r.reasoning}`;
      break;
    }
    case "pricing": {
      const r = await runPricingStrategy(input.task);
      result = r as unknown as Record<string, unknown>;
      summary = r.recommendation;
      break;
    }
    case "gtm": {
      const r = await runGtmPlanning(input.task);
      result = r as unknown as Record<string, unknown>;
      summary = r.launch_brief;
      break;
    }
    case "experiment":
    case "growth": {
      const r = await runGrowthStrategy(input.task);
      result = r as unknown as Record<string, unknown>;
      summary = r.strategy_summary;
      break;
    }
    default: {
      const r = await runIdeaValidation(input.task);
      result = r as unknown as Record<string, unknown>;
      summary = r.reasoning;
    }
  }

  const strategyWrite = await writeLatestStrategy(
    `Handoff from ${input.from_agent} (${requestType}): ${input.task}\n\n${summary}`
  );

  return {
    summary,
    structured_result: result,
    memory_ids_written: strategyWrite.memory_ids_written,
  };
}
