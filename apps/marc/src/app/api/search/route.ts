import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { hybridSearch } from "@/lib/search";
import { canPerformAction, incrementActionCount, getUser } from "@/lib/tiers";
import { isPro } from "@/lib/config";

const SearchSchema = z.object({
  query: z.string().min(1),
});

export async function POST(request: NextRequest) {
  try {
    const userId = "default";
    const gate = await canPerformAction(userId);
    if (!gate.allowed) {
      return NextResponse.json({ error: gate.reason }, { status: 429 });
    }

    const user = await getUser(userId);
    const body = SearchSchema.parse(await request.json());
    const pro = isPro(user.tier);

    if (!pro && body.query.length > 100) {
      return NextResponse.json(
        { error: "Semantic search requires Pro tier" },
        { status: 403 }
      );
    }

    const results = await hybridSearch(body.query, userId, pro);
    await incrementActionCount(userId);

    return NextResponse.json({
      results,
      tier: user.tier,
      semantic: pro,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Search failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
