import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { eq } from "drizzle-orm";
import { suggestCleanupCandidates, suggestArchiveRules } from "@/lib/cleanup";
import { archiveMessages } from "@/lib/gmail/actions";
import { batchUnsubscribe } from "@/lib/gmail/unsubscribe";
import { getUser } from "@/lib/tiers";
import { isPro } from "@/lib/config";
import { db } from "@/lib/db";
import { emailMessages } from "@/lib/db/schema";

export async function GET() {
  const user = await getUser();
  if (!isPro(user.tier)) {
    return NextResponse.json({ error: "Cleanup tools require Pro tier" }, { status: 403 });
  }

  const candidates = await suggestCleanupCandidates();
  const rules = await suggestArchiveRules();
  return NextResponse.json({ candidates, suggestedRules: rules });
}

const ArchiveSchema = z.object({
  messageIds: z.array(z.string()).min(1),
  confirmed: z.literal(true),
});

const UnsubscribeSchema = z.object({
  action: z.literal("unsubscribe"),
  messageIds: z.array(z.string()).min(1),
  confirmed: z.literal(true),
});

export async function POST(request: NextRequest) {
  const user = await getUser();
  if (!isPro(user.tier)) {
    return NextResponse.json({ error: "Cleanup tools require Pro tier" }, { status: 403 });
  }

  const body = await request.json();

  if (body.action === "unsubscribe") {
    const parsed = UnsubscribeSchema.parse(body);
    const rows = await db
      .select()
      .from(emailMessages)
      .where(eq(emailMessages.userId, "default"));

    const items = rows
      .filter(
        (r) =>
          parsed.messageIds.includes(r.messageId) &&
          r.listUnsubscribe &&
          r.hasUnsubscribe
      )
      .map((r) => ({
        messageId: r.messageId,
        listUnsubscribe: r.listUnsubscribe!,
      }));

    if (!items.length) {
      return NextResponse.json(
        { error: "No messages with HTTPS list-unsubscribe headers selected" },
        { status: 400 }
      );
    }

    const results = await batchUnsubscribe(items, "default", true);
    const succeeded = results.filter((r) => r.success).length;
    return NextResponse.json({ success: true, unsubscribed: succeeded, results });
  }

  const parsed = ArchiveSchema.parse(body);
  await archiveMessages(parsed.messageIds, "default", parsed.confirmed);
  return NextResponse.json({ success: true, archived: parsed.messageIds.length });
}
