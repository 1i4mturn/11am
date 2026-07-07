import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { buildContextPack } from "@/lib/memory";
import { getUser } from "@/lib/tiers";
import { isPro, resolveUserId } from "@/lib/config";

const ContextSchema = z.object({
  requesting_agent: z.string(),
  task: z.string().min(1),
});

export async function POST(request: NextRequest) {
  const userId = resolveUserId(request.headers.get("x-user-id"));
  const user = await getUser(userId);
  if (!isPro(user.tier)) {
    return NextResponse.json({ error: "Context packs require Pro tier" }, { status: 403 });
  }

  const body = ContextSchema.parse(await request.json());
  const pack = await buildContextPack(body.requesting_agent, body.task, userId);
  return NextResponse.json({ context_pack: pack });
}
