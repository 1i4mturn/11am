import { askGeorge } from "@/lib/claude";
import type { TaxFlag } from "@/lib/types";

export async function detectTaxFlags(content: string): Promise<TaxFlag[]> {
  const result = await askGeorge(
    `Review the content for Australian tax-related categories ONLY. Return a JSON array of flags with shape: [{ "category": "GST|depreciation|deductions|BAS|capital_gains|other", "description": "brief flag", "severity": "info|review" }].
If none apply, return [].
Do NOT give tax advice — only flag categories for awareness.
Output ONLY valid JSON array, no markdown.`,
    content.slice(0, 8000)
  );

  try {
    const parsed = JSON.parse(result.trim()) as TaxFlag[];
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

export async function explainFinancialTerm(term: string): Promise<string> {
  return askGeorge(
    "Explain financial terms in plain English for a solo founder. 2-4 short paragraphs max. Use a simple example if helpful.",
    `Explain: ${term}`
  );
}
