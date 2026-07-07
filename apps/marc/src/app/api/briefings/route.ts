import { NextRequest, NextResponse } from "next/server";
import { generateDailyBriefing, generateWeeklyBriefing } from "@/lib/briefings";
import { canPerformAction, incrementActionCount, getUser } from "@/lib/tiers";

export async function GET(request: NextRequest) {
  try {
    const userId = "default";
    const gate = await canPerformAction(userId);
    if (!gate.allowed) {
      return NextResponse.json({ error: gate.reason }, { status: 429 });
    }

    const user = await getUser(userId);
    const isPro = user.tier === "pro";
    const type = request.nextUrl.searchParams.get("type") ?? "daily";

    const briefing =
      type === "weekly"
        ? await generateWeeklyBriefing(userId, isPro)
        : await generateDailyBriefing(userId, isPro);

    await incrementActionCount(userId);

    return NextResponse.json({ briefing, tier: user.tier });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Briefing failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
