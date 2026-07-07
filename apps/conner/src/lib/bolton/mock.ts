import type { ConnerStrategySummary, GeorgeNumbersSummary } from "@/lib/types";

/** Mock Bolton entries — used when George/James summaries aren't in Bolton yet */
export const MOCK_GEORGE_NUMBERS: GeorgeNumbersSummary = {
  as_of: "2026-07-06",
  revenue: "AUD 8.2k MRR (mock)",
  margin_pct: 72,
  runway_months: 14,
  burn_rate: "AUD 4.1k/mo net burn",
  flags: ["MRR growth flat last 2 months", "One-off project revenue masking recurring baseline"],
  confidence: "medium",
};

export const MOCK_JAMES_PRICING_RESEARCH = {
  topic: "AI writing assistant pricing (mock)",
  key_findings: [
    "Solo-founder tools cluster at USD 15–29/mo for voice-fidelity positioning",
    "Usage-based tiers common above USD 49/mo",
    "Annual discounts typically 15–20%",
  ],
  competitive_range: "USD 12–49/mo for comparable positioning",
  recommendation: "Anchor mid-tier at USD 24/mo with annual option; avoid race-to-bottom on generic AI pricing",
  confidence: "medium" as const,
};

export const MOCK_JAMES_MARKET_RESEARCH = {
  topic: "Voice-fidelity AI for solo founders (mock)",
  key_findings: [
    "Market fragmented — no clear category leader for 'sounds like me' positioning",
    "Buyers care about edit time saved, not word count",
    "Distribution via creator communities outperforms paid search at early stage",
  ],
  recommendation: "Lead with time-to-publish and voice consistency, not generic AI features",
  confidence: "medium" as const,
};

export const MOCK_CONNER_STRATEGY: ConnerStrategySummary = {
  source_agent: "conner",
  as_of: "2026-07-06",
  positioning_update:
    "11am as a calm, multi-agent operating layer for solo operators — not another chatbot wrapper (mock)",
  target_segment: "Solo founders and small teams running multiple business functions without hiring",
  key_decisions: [
    "Ship agent suite depth before horizontal marketing",
    "Price on time saved, not seat count",
  ],
  confidence: "medium",
};
