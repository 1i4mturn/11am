/** Single-user debug build — no billing/tier logic in Leo */
export const SINGLE_USER_DEBUG = process.env.BOLTON_SINGLE_USER !== "false";

export function resolveUserId(headerUserId: string | null): string {
  return headerUserId?.trim() || "default";
}
