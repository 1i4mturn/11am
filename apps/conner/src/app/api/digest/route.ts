import { NextResponse } from "next/server";
import { runWeeklyDigest } from "@/lib/strategy/engine";

/** Manual on-demand weekly digest - no scheduler in v1 */
export async function POST() {
  try {
    const result = await runWeeklyDigest();
    return NextResponse.json({ result });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Digest failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
