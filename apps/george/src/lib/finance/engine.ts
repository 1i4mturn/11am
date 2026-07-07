import { askGeorge, askGeorgeWithHistory } from "@/lib/claude";
import type { ChatMessage } from "@/lib/db/schema";
import type { ModelType, UnitEconomicsInput } from "@/lib/types";
import { detectTaxFlags } from "@/lib/finance/tax";

const MODEL_PROMPTS: Record<ModelType, string> = {
  pl: "Focus on P&L structure: revenue, COGS, gross margin, opex, net profit. Show monthly or annual as appropriate.",
  runway: "Focus on cash runway: current cash, monthly burn, revenue offset, months remaining, zero-cash date.",
  cashflow: "Focus on cash in/out timing, operating vs investing vs financing, net cash movement.",
  breakeven: "Focus on fixed costs, variable cost per unit, contribution margin, break-even units and revenue.",
  unit_economics: "Focus on CAC, LTV, LTV:CAC ratio, payback period, gross margin.",
  general: "General financial modelling — clarify assumptions and show workings.",
};

export async function runModelConversation(
  message: string,
  history: ChatMessage[],
  modelType: ModelType = "general"
): Promise<{ reply: string; tax_flags: Awaited<ReturnType<typeof detectTaxFlags>> }> {
  const messages = [
    ...history.map((m) => ({ role: m.role, content: m.content })),
    { role: "user" as const, content: message },
  ];

  const reply = await askGeorgeWithHistory(
    MODEL_PROMPTS[modelType],
    messages,
    6000
  );

  const tax_flags = await detectTaxFlags(`${message}\n\n${reply}`);
  return { reply, tax_flags };
}

export async function runUnitEconomics(input: UnitEconomicsInput): Promise<{
  analysis: string;
  tax_flags: Awaited<ReturnType<typeof detectTaxFlags>>;
}> {
  const analysis = await askGeorge(
    `Analyse unit economics. Calculate LTV:CAC ratio, payback period, and margin health where data allows. Flag gaps in inputs. Markdown output with a summary table.`,
    `Unit economics inputs:\n${JSON.stringify(input, null, 2)}`
  );
  const tax_flags = await detectTaxFlags(analysis);
  return { analysis, tax_flags };
}

export async function generateCalculatorHtml(prompt: string): Promise<string> {
  return askGeorge(
    `Generate a COMPLETE self-contained HTML file for a business calculator based on the user's request.
Requirements:
- Single file with inline <style> and <script> — no external dependencies except optional CDN for React if needed
- Use a clean, minimal design (white background, dark text, simple inputs)
- Interactive: user can change inputs and see results update
- Include a title and brief instructions
- Output ONLY the raw HTML starting with <!DOCTYPE html> — no markdown fences`,
    prompt,
    8000
  );
}

export async function extractModelState(
  conversation: ChatMessage[],
  modelType: ModelType
): Promise<{
  inputs: Record<string, unknown>;
  assumptions: Record<string, unknown>;
  scenarios: unknown[];
}> {
  const result = await askGeorge(
    `From this financial modelling conversation, extract structured state as JSON only:
{ "inputs": {}, "assumptions": {}, "scenarios": [] }
Model type: ${modelType}`,
    JSON.stringify(conversation, null, 2),
    2000
  );

  try {
    const match = result.match(/\{[\s\S]*\}/);
    if (match) return JSON.parse(match[0]);
  } catch {
    // fall through
  }
  return { inputs: {}, assumptions: {}, scenarios: [] };
}

export async function buildLatestNumbersSummary(context: {
  stripe?: Record<string, unknown>;
  xero?: Record<string, unknown>;
  modelNotes?: string;
}): Promise<{
  source_agent: "George";
  as_of: string;
  revenue: string;
  margin_pct: number;
  runway_months: number;
  burn_rate: string;
  flags: string[];
  confidence: "high" | "medium" | "low";
}> {
  const result = await askGeorge(
    `Produce a latest-numbers summary as JSON ONLY with this exact shape:
{
  "source_agent": "George",
  "as_of": "YYYY-MM-DD",
  "revenue": "human readable string e.g. AUD 42k MRR",
  "margin_pct": number,
  "runway_months": number,
  "burn_rate": "human readable string",
  "flags": ["string array of concerns"],
  "confidence": "high" | "medium" | "low"
}
Use integration data where available; estimate conservatively otherwise.`,
    JSON.stringify(context, null, 2),
    1500
  );

  try {
    const match = result.match(/\{[\s\S]*\}/);
    if (match) {
      const parsed = JSON.parse(match[0]);
      return {
        source_agent: "George",
        as_of: parsed.as_of ?? new Date().toISOString().slice(0, 10),
        revenue: parsed.revenue ?? "Unknown",
        margin_pct: Number(parsed.margin_pct) || 0,
        runway_months: Number(parsed.runway_months) || 0,
        burn_rate: parsed.burn_rate ?? "Unknown",
        flags: Array.isArray(parsed.flags) ? parsed.flags : [],
        confidence: parsed.confidence ?? "medium",
      };
    }
  } catch {
    // fall through
  }

  return {
    source_agent: "George",
    as_of: new Date().toISOString().slice(0, 10),
    revenue: "Not yet calculated",
    margin_pct: 0,
    runway_months: 0,
    burn_rate: "Unknown",
    flags: ["Insufficient data for summary"],
    confidence: "low",
  };
}
