import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import {
  listSenderProfiles,
  upsertSenderProfile,
  deleteSenderProfile,
} from "@/lib/bolton";
import { getUser } from "@/lib/tiers";
import { isPro } from "@/lib/config";

export async function GET() {
  const user = await getUser();
  if (!isPro(user.tier)) {
    return NextResponse.json({ error: "Sender memory requires Pro tier" }, { status: 403 });
  }

  const profiles = await listSenderProfiles();
  return NextResponse.json({ profiles });
}

const UpdateSchema = z.object({
  senderEmail: z.string().email(),
  senderName: z.string().optional(),
  organisation: z.string().optional(),
  relationshipType: z.string().optional(),
  importanceLevel: z.string().optional(),
  preferredTone: z.string().optional(),
  lastInteractionSummary: z.string().optional(),
  sensitivityNotes: z.string().optional(),
  responseExpectation: z.string().optional(),
  disabled: z.boolean().optional(),
});

export async function POST(request: NextRequest) {
  const user = await getUser();
  if (!isPro(user.tier)) {
    return NextResponse.json({ error: "Sender memory requires Pro tier" }, { status: 403 });
  }

  const body = UpdateSchema.parse(await request.json());
  const profile = await upsertSenderProfile(body);
  return NextResponse.json({ profile });
}

export async function DELETE(request: NextRequest) {
  const user = await getUser();
  if (!isPro(user.tier)) {
    return NextResponse.json({ error: "Sender memory requires Pro tier" }, { status: 403 });
  }

  const id = request.nextUrl.searchParams.get("id");
  if (!id) return NextResponse.json({ error: "Missing id" }, { status: 400 });

  await deleteSenderProfile(id);
  return NextResponse.json({ success: true });
}
