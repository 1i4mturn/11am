import { z } from "zod";

export const GeorgeNumbersSummarySchema = z.object({
  source_agent: z.literal("george"),
  as_of: z.string(),
  revenue: z.string(),
  margin_pct: z.number(),
  runway_months: z.number(),
  burn_rate: z.string(),
  flags: z.array(z.string()),
  confidence: z.enum(["high", "medium", "low"]),
});

export const ConnerStrategySummarySchema = z.object({
  source_agent: z.literal("conner"),
  as_of: z.string(),
  positioning_update: z.string(),
  target_segment: z.string(),
  key_decisions: z.array(z.string()),
  confidence: z.enum(["high", "medium", "low"]),
});

export type GeorgeNumbersSummary = z.infer<typeof GeorgeNumbersSummarySchema>;
export type ConnerStrategySummary = z.infer<typeof ConnerStrategySummarySchema>;

export function parseGeorgeSummary(raw: unknown): GeorgeNumbersSummary | null {
  const parsed = GeorgeNumbersSummarySchema.safeParse(raw);
  return parsed.success ? parsed.data : null;
}

export function parseConnerSummary(raw: unknown): ConnerStrategySummary | null {
  const parsed = ConnerStrategySummarySchema.safeParse(raw);
  return parsed.success ? parsed.data : null;
}

export function formatGeorgeForPrompt(summary: GeorgeNumbersSummary): string {
  return `Revenue: ${summary.revenue}. Margin: ${summary.margin_pct}%. Runway: ${summary.runway_months} months. Burn: ${summary.burn_rate}. Flags: ${summary.flags.join("; ") || "none"}. (as of ${summary.as_of}, confidence ${summary.confidence})`;
}

export function formatConnerForPrompt(summary: ConnerStrategySummary): string {
  return `Positioning: ${summary.positioning_update}. Target segment: ${summary.target_segment}. Key decisions: ${summary.key_decisions.join("; ")}. (as of ${summary.as_of}, confidence ${summary.confidence})`;
}
