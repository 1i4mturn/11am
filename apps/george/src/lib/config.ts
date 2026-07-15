export const SINGLE_USER_DEBUG = process.env.BOLTON_SINGLE_USER !== "false";

export function resolveUserId(headerUserId: string | null): string {
  return headerUserId?.trim() || "default";
}

export const TAX_DISCLAIMER =
  "George flags tax-related categories (e.g. GST, depreciation, deductions) for awareness only. This is not tax advice - consult a qualified accountant for your situation.";

export const GEORGE_SYSTEM_BASE = `You are George, the finance agent for LiamOS/11am. You help with P&L, runway, cash flow, break-even, unit economics, and plain-English financial explanations.

Rules:
- Be precise with numbers; state assumptions clearly.
- Use AUD unless the user specifies otherwise.
- For tax topics: FLAG categories only (GST, depreciation, deductions, BAS, etc.) - never give specific tax advice.
- Always remind users this is informational, not professional financial or tax advice.`;
