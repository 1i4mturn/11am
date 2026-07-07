import { NextResponse } from "next/server";
import { getRecentMessages } from "@/lib/gmail/sync";
import { triageInbox } from "@/lib/triage";
import { canPerformAction, incrementActionCount, getUser } from "@/lib/tiers";
import { isPro } from "@/lib/config";

export async function POST() {
  try {
    const userId = "default";
    const gate = await canPerformAction(userId);
    if (!gate.allowed) {
      return NextResponse.json({ error: gate.reason }, { status: 429 });
    }

    const user = await getUser(userId);
    const isProTier = isPro(user.tier);
    const messages = await getRecentMessages(userId, isProTier ? 50 : 20);
    const unreadFirst = [
      ...messages.filter((m) => m.isUnread),
      ...messages.filter((m) => !m.isUnread),
    ];

    const items = await triageInbox(unreadFirst, isProTier, isProTier ? 20 : 10);
    await incrementActionCount(userId);

    return NextResponse.json({
      items,
      tier: user.tier,
      remaining: gate.remaining !== null ? gate.remaining - 1 : null,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Triage failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
