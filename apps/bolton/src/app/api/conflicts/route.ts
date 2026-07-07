import { NextResponse } from "next/server";
import { eq } from "drizzle-orm";
import { db } from "@/lib/db";
import { conflicts } from "@/lib/db/schema";
import { detectConflicts } from "@/lib/memory";
import { getUser } from "@/lib/tiers";
import { isPro } from "@/lib/config";

export async function GET() {
  const user = await getUser();
  const open = await db
    .select()
    .from(conflicts)
    .where(eq(conflicts.userId, "default"))
    .limit(20);
  return NextResponse.json({ conflicts: open, tier: user.tier });
}

export async function POST() {
  const user = await getUser();
  if (!isPro(user.tier)) {
    return NextResponse.json({ error: "Conflict detection requires Pro tier" }, { status: 403 });
  }
  const found = await detectConflicts();
  const open = await db
    .select()
    .from(conflicts)
    .where(eq(conflicts.userId, "default"))
    .limit(20);
  return NextResponse.json({ detected: found.length, conflicts: open, flagged: found });
}
