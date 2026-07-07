import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { searchMemory } from "@/lib/search";
import { getUser } from "@/lib/tiers";
import { isPro, resolveUserId } from "@/lib/config";

const SearchSchema = z.object({ query: z.string().min(1) });

export async function POST(request: NextRequest) {
  const userId = resolveUserId(request.headers.get("x-user-id"));
  const user = await getUser(userId);
  const body = SearchSchema.parse(await request.json());
  const pro = isPro(user.tier);
  const results = await searchMemory(body.query, userId, pro);
  return NextResponse.json({ results, semantic: pro });
}
