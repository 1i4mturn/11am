import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { eq } from "drizzle-orm";
import { proposeRuleFromNaturalLanguage } from "@/lib/rules";
import { listInboxRules, activateInboxRule, getInboxRule } from "@/lib/bolton";
import { applyLabel, archiveMessages } from "@/lib/gmail/actions";
import { getUser } from "@/lib/tiers";
import { isPro } from "@/lib/config";
import { db } from "@/lib/db";
import { emailMessages } from "@/lib/db/schema";

export async function GET() {
  const user = await getUser();
  if (!isPro(user.tier)) {
    return NextResponse.json({ error: "Rule builder requires Pro tier" }, { status: 403 });
  }
  const rules = await listInboxRules();
  return NextResponse.json({ rules });
}

const ProposeSchema = z.object({
  instruction: z.string().min(5),
});

export async function POST(request: NextRequest) {
  const user = await getUser();
  if (!isPro(user.tier)) {
    return NextResponse.json({ error: "Rule builder requires Pro tier" }, { status: 403 });
  }

  const body = ProposeSchema.parse(await request.json());
  const proposal = await proposeRuleFromNaturalLanguage(body.instruction);
  return NextResponse.json({ proposal });
}

const ApplySchema = z.object({
  ruleId: z.string().uuid(),
  confirmed: z.literal(true),
  applyToMessageIds: z.array(z.string()).optional(),
});

function ruleWantsArchive(actions: string[]): boolean {
  return actions.some((a) => a.toLowerCase().includes("archive"));
}

function ruleWantsLabel(actions: string[]): string | null {
  const labelAction = actions.find((a) => a.toLowerCase().includes("label"));
  if (!labelAction) return null;
  const match = labelAction.match(/label[:\s]+(.+)/i);
  return match?.[1]?.trim() ?? "Marc-Rule";
}

async function findMatchingMessageIds(
  rule: { trigger: string; conditions: string[] | null },
  userId = "default"
): Promise<string[]> {
  const messages = await db
    .select()
    .from(emailMessages)
    .where(eq(emailMessages.userId, userId))
    .limit(200);

  const trigger = rule.trigger.toLowerCase();
  const keywords = rule.conditions ?? [];

  return messages
    .filter((m) => {
      const text = `${m.senderEmail} ${m.subject} ${m.body ?? ""}`.toLowerCase();
      if (trigger.includes("@") && m.senderEmail.includes(trigger.replace("sender:", ""))) {
        return true;
      }
      return keywords.some((k) => text.includes(k.toLowerCase().replace(/contains /i, "")));
    })
    .map((m) => m.messageId);
}

export async function PUT(request: NextRequest) {
  const user = await getUser();
  if (!isPro(user.tier)) {
    return NextResponse.json({ error: "Rule builder requires Pro tier" }, { status: 403 });
  }

  const body = ApplySchema.parse(await request.json());
  const rule = await getInboxRule(body.ruleId);
  if (!rule) {
    return NextResponse.json({ error: "Rule not found" }, { status: 404 });
  }

  await activateInboxRule(body.ruleId);

  const actions = (rule.actions as string[]) ?? [];
  const messageIds =
    body.applyToMessageIds?.length
      ? body.applyToMessageIds
      : await findMatchingMessageIds(
          { trigger: rule.trigger, conditions: rule.conditions as string[] },
          "default"
        );

  if (messageIds.length) {
    if (ruleWantsArchive(actions)) {
      await archiveMessages(messageIds, "default", body.confirmed);
    }
    const labelName = ruleWantsLabel(actions);
    if (labelName) {
      await applyLabel(messageIds, labelName, "default", body.confirmed);
    }
  }

  return NextResponse.json({
    success: true,
    status: "active",
    appliedTo: messageIds.length,
  });
}
