import type { SkillGapSignal } from "@/lib/types";

export const MOCK_SKILL_GAPS: SkillGapSignal[] = [
  {
    source_agent: "James",
    skill_gap: "TypeScript generics for shared agent handoff types",
    evidence:
      "Recent James research on agent contracts flagged repeated type duplication across apps - Liam would ship faster with stronger generic patterns (mock)",
    suggested_for: "Harris",
    priority: "medium",
  },
  {
    source_agent: "James",
    skill_gap: "French conversational fluency - past tense in real dialogue",
    evidence: "User notes from French class: struggles with passé composé vs imparfait in conversation (mock)",
    suggested_for: "Harris",
    priority: "low",
  },
];
