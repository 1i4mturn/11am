import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { addFrenchSrsCard, frenchHelp, reviewFrenchCard } from "@/lib/learning/engine";

const HelpSchema = z.object({ query: z.string().min(1) });

const CardSchema = z.object({
  front: z.string().min(1),
  back: z.string().min(1),
});

const ReviewSchema = z.object({
  card_id: z.string(),
  quality: z.enum(["again", "hard", "good", "easy"]),
});

export async function POST(request: NextRequest) {
  try {
    const body = HelpSchema.parse(await request.json());
    const result = await frenchHelp(body.query);
    return NextResponse.json({ result });
  } catch (error) {
    const message = error instanceof Error ? error.message : "French help failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}

export async function PUT(request: NextRequest) {
  try {
    const body = CardSchema.parse(await request.json());
    const card = await addFrenchSrsCard(body.front, body.back);
    return NextResponse.json({ card });
  } catch (error) {
    const message = error instanceof Error ? error.message : "SRS add failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}

export async function PATCH(request: NextRequest) {
  try {
    const body = ReviewSchema.parse(await request.json());
    const card = await reviewFrenchCard(body.card_id, body.quality);
    if (!card) return NextResponse.json({ error: "Card not found" }, { status: 404 });
    return NextResponse.json({ card });
  } catch (error) {
    const message = error instanceof Error ? error.message : "SRS review failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
