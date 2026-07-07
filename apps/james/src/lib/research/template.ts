import type { ResearchBrief } from "@/lib/types";

/** Locked template — reusable across UI, API, and handoffs */
export const RESEARCH_TEMPLATE_SECTIONS = [
  "Research question",
  "Key findings",
  "What this means",
  "Recommendation",
  "Sources",
] as const;

export const RESEARCH_SYSTEM_SUFFIX = `
You MUST structure every research output using this exact template (markdown headings):

## Research question
[Restate the question]

## Key findings
- [Bullet findings with inline citations where possible]

## What this means
[Interpretation for Liam / the requesting agent]

## Recommendation
[Clear actionable recommendation]

## Sources
- [Title](url) — credibility: N/5 — brief note

After the markdown, output a JSON block on its own line starting with RESEARCH_JSON: followed by:
{
  "research_question": "...",
  "key_findings": ["..."],
  "what_this_means": "...",
  "recommendation": "...",
  "sources": [{ "title": "...", "url": "...", "credibility_score": 4, "notes": "..." }]
}

Score each source credibility 1-5 inline (Claude-judged): 5=primary/official, 3=reasonable secondary, 1=weak/unverified.
`;

export function briefToMarkdown(brief: ResearchBrief): string {
  return `## Research question
${brief.research_question}

## Key findings
${brief.key_findings.map((f) => `- ${f}`).join("\n")}

## What this means
${brief.what_this_means}

## Recommendation
${brief.recommendation}

## Sources
${brief.sources
  .map(
    (s) =>
      `- [${s.title}](${s.url}) — credibility: ${s.credibility_score}/5${s.notes ? ` — ${s.notes}` : ""}`
  )
  .join("\n")}`;
}

export function parseResearchJson(raw: string): ResearchBrief | null {
  const match = raw.match(/RESEARCH_JSON:\s*(\{[\s\S]*\})/);
  if (!match) return null;
  try {
    const parsed = JSON.parse(match[1]) as ResearchBrief;
    if (!parsed.research_question || !Array.isArray(parsed.key_findings)) return null;
    return {
      research_question: parsed.research_question,
      key_findings: parsed.key_findings,
      what_this_means: parsed.what_this_means ?? "",
      recommendation: parsed.recommendation ?? "",
      sources: Array.isArray(parsed.sources) ? parsed.sources : [],
    };
  } catch {
    return null;
  }
}
