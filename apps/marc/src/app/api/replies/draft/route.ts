import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { getMessageById } from "@/lib/gmail/sync";
import { draftReply, buildWilliamHandoff } from "@/lib/replies";
import { createHandoff } from "@/lib/handoffs";
import { canPerformAction, incrementActionCount, getUser } from "@/lib/tiers";
import { isPro } from "@/lib/config";

const DraftSchema = z.object({
  messageId: z.string(),
  desiredOutcome: z.string().optional(),
  handoffToWilliam: z.boolean().default(false),
});

export async function POST(request: NextRequest) {
  try {
    const userId = "default";
    const gate = await canPerformAction(userId);
    if (!gate.allowed) {
      return NextResponse.json({ error: gate.reason }, { status: 429 });
    }

    const user = await getUser(userId);
    const body = DraftSchema.parse(await request.json());
    const message = await getMessageById(body.messageId, userId);

    if (!message) {
      return NextResponse.json({ error: "Message not found" }, { status: 404 });
    }

    const pro = isPro(user.tier);
    const brief = await draftReply(message, {
      desiredOutcome: body.desiredOutcome,
      isPro: pro,
      useWilliam: body.handoffToWilliam,
    });

    let handoffId: string | null = null;
    if (brief.use_william && pro) {
      const handoff = await createHandoff(
        "william",
        buildWilliamHandoff(brief),
        body.messageId,
        userId
      );
      handoffId = handoff.id;
    }

    await incrementActionCount(userId);

    return NextResponse.json({ brief, handoffId, handoffAgent: brief.use_william ? "william" : null });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Draft failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
