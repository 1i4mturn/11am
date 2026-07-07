import { NextResponse } from "next/server";
import { getSkillGapSignals } from "@/lib/bolton/client";

export async function GET() {
  try {
    const { gaps, from_mock } = await getSkillGapSignals();
    return NextResponse.json({ gaps, from_mock });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Fetch failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
