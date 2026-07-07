import type { RequestType } from "@/lib/types";

/**
 * Codified save-vs-return rule (not per-call judgement).
 *
 * SAVE to Bolton when a finding would be useful across more than one future session.
 * RETURN ONLY when scoped to the immediate task.
 */
export function shouldSaveToBolton(input: {
  research_question: string;
  key_findings: string[];
  request_type: RequestType;
  context_ref?: string;
}): boolean {
  const q = input.research_question.toLowerCase();

  // RETURN ONLY — immediate / ephemeral scope
  const returnOnlyPatterns = [
    /\b(just for|only for)\s+(today|this|now)\b/i,
    /\bfor this (email|reply|meeting|draft|message)\b/i,
    /\bone.?off\b/i,
    /\bright now\b/i,
    /\btoday only\b/i,
    /\bimmediate(ly)?\b/i,
    /\bquick check\b/i,
  ];
  if (returnOnlyPatterns.some((p) => p.test(q))) return false;
  if (input.context_ref?.toLowerCase().includes("ephemeral")) return false;
  if (input.context_ref?.toLowerCase().includes("return-only")) return false;

  // SAVE — durable cross-session value
  const savePatterns = [
    /\bcompetitive landscape\b/i,
    /\bmarket (size|sizing|map)\b/i,
    /\bpricing benchmark\b/i,
    /\bcategory\b/i,
    /\bpositioning\b/i,
    /\bvendor comparison\b/i,
    /\blandscape\b/i,
    /\bbenchmark\b/i,
    /\bmonitor\b/i,
    /\btrack\b/i,
    /\breference\b/i,
    /\bdurable\b/i,
    /\bfor (william|marc|george|conner|leo|bolton)\b/i,
  ];
  if (savePatterns.some((p) => p.test(q))) return true;

  // SAVE — research types that are typically reusable
  if (["market", "pricing", "academic"].includes(input.request_type)) return true;

  // SAVE — multiple substantive findings suggest reference value
  if (input.key_findings.length >= 3) return true;

  // Default RETURN ONLY for narrow tactical questions
  return false;
}
