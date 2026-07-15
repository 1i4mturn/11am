export const SINGLE_USER_DEBUG = process.env.BOLTON_SINGLE_USER !== "false";

export type RequestType = "market" | "technical" | "cultural" | "academic" | "pricing" | "general";

export type Cadence = "once" | "daily" | "weekly" | "monthly" | "custom";

export interface ResearchSource {
  title: string;
  url: string;
  credibility_score: number;
  notes?: string;
}

/** Locked structured output template - every James response uses this shape */
export interface ResearchBrief {
  research_question: string;
  key_findings: string[];
  what_this_means: string;
  recommendation: string;
  sources: ResearchSource[];
}

/** Handoff object returned to callers - never the full research thread */
export interface JamesHandoff extends ResearchBrief {
  from_agent: "James";
  to_agent: string;
  saved_to_bolton: boolean;
  memory_id?: string;
  prior_research_used?: Array<{ id: string; title: string; summary: string }>;
  request_type: RequestType;
  depth: "standard" | "deep";
  search_uses?: number;
}

export interface PriorResearchEntry {
  id: string;
  title: string;
  summary: string;
  created_at?: string;
}
