import type { RequestType } from "@/lib/types";

export interface SourceRouting {
  request_type: RequestType;
  label: string;
  preferred_sources: string;
  allowed_domains?: string[];
  search_guidance: string;
}

export const SOURCE_ROUTING: Record<RequestType, SourceRouting> = {
  market: {
    request_type: "market",
    label: "Market",
    preferred_sources: "industry reports, news, competitor sites, G2, Capterra, market research firms",
    search_guidance:
      "Prioritise recent market sizing, competitor positioning, and category trends. Cross-check at least two independent sources.",
  },
  technical: {
    request_type: "technical",
    label: "Technical",
    preferred_sources: "official docs, GitHub, technical blogs, Stack Overflow, engineering write-ups",
    search_guidance:
      "Prioritise primary documentation and maintainer sources. Note version/date for fast-moving tools.",
  },
  cultural: {
    request_type: "cultural",
    label: "Cultural",
    preferred_sources: "social trends, Reddit, cultural commentary, creator platforms, niche communities",
    search_guidance:
      "Capture how audiences talk about the topic, not just press releases. Flag anecdotal vs representative.",
  },
  academic: {
    request_type: "academic",
    label: "Academic",
    preferred_sources: "papers, arXiv, university research, scholarly summaries",
    search_guidance:
      "Prefer peer-reviewed or preprint primary sources. Note methodology limits and recency.",
  },
  pricing: {
    request_type: "pricing",
    label: "Pricing",
    preferred_sources: "official pricing pages, public pricing databases, reviews mentioning price",
    allowed_domains: undefined,
    search_guidance:
      "Always hit official pricing pages first. Note plan tiers, annual vs monthly, and hidden fees if reported.",
  },
  general: {
    request_type: "general",
    label: "General",
    preferred_sources: "authoritative mix of primary and secondary sources",
    search_guidance: "Use best available evidence; route toward specialised sources when the topic narrows.",
  },
};

const TYPE_PATTERNS: Array<{ type: RequestType; patterns: RegExp[] }> = [
  {
    type: "pricing",
    patterns: [/\bpric(e|ing)\b/i, /\bcost\b/i, /\bmrr\b/i, /\bsubscription\b/i, /\bfee\b/i],
  },
  {
    type: "technical",
    patterns: [
      /\bapi\b/i,
      /\barchitecture\b/i,
      /\bstack\b/i,
      /\bframework\b/i,
      /\bimplementation\b/i,
      /\bgithub\b/i,
      /\bdocs?\b/i,
    ],
  },
  {
    type: "market",
    patterns: [
      /\bmarket\b/i,
      /\bcompetitor\b/i,
      /\blandscape\b/i,
      /\btam\b/i,
      /\bsam\b/i,
      /\bcategory\b/i,
      /\bindustry\b/i,
    ],
  },
  {
    type: "academic",
    patterns: [/\bpaper\b/i, /\bresearch study\b/i, /\barxiv\b/i, /\bacademic\b/i, /\bpeer.?review/i],
  },
  {
    type: "cultural",
    patterns: [/\bculture\b/i, /\btrend\b/i, /\breddit\b/i, /\btiktok\b/i, /\baudience\b/i, /\bcommunity\b/i],
  },
];

export function classifyRequestType(question: string, explicit?: RequestType): RequestType {
  if (explicit && explicit !== "general") return explicit;
  for (const { type, patterns } of TYPE_PATTERNS) {
    if (patterns.some((p) => p.test(question))) return type;
  }
  return "general";
}

export function isDeepResearch(question: string, priority?: string): boolean {
  if (priority === "urgent") return false;
  return /\b(compare|versus|vs\.?|landscape|deep dive|comprehensive|multi|benchmark|evaluate options)\b/i.test(
    question
  );
}

export function searchMaxUses(depth: "standard" | "deep"): number {
  return depth === "deep" ? 12 : 4;
}
