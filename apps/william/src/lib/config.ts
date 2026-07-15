/** Single-user debug build - tier/quota gates disabled unless explicitly turned off */
export const SINGLE_USER_DEBUG = process.env.WILLIAM_SINGLE_USER !== "false";

export function effectiveTier(storedTier: string): "pro" | "free" {
  return SINGLE_USER_DEBUG ? "pro" : storedTier === "pro" ? "pro" : "free";
}

export function isPro(storedTier: string): boolean {
  return effectiveTier(storedTier) === "pro";
}
