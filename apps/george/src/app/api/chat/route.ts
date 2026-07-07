import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { runModelConversation } from "@/lib/finance/engine";

const ChatSchema = z.object({
  message: z.string().min(1),
  history: z
    .array(z.object({ role: z.enum(["user", "assistant"]), content: z.string() }))
    .default([]),
  model_type: z
    .enum(["pl", "runway", "cashflow", "breakeven", "unit_economics", "general"])
    .default("general"),
});

export async function POST(request: NextRequest) {
  try {
    const body = ChatSchema.parse(await request.json());
    const result = await runModelConversation(body.message, body.history, body.model_type);
    return NextResponse.json(result);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Chat failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
