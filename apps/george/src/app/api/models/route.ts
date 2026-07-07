import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { listModels, saveModel } from "@/lib/models";
import { extractModelState } from "@/lib/finance/engine";

export async function GET() {
  const models = await listModels();
  return NextResponse.json({ models });
}

const SaveSchema = z.object({
  id: z.string().uuid().optional(),
  name: z.string().min(1),
  model_type: z
    .enum(["pl", "runway", "cashflow", "breakeven", "unit_economics", "general"])
    .default("general"),
  conversation: z.array(
    z.object({ role: z.enum(["user", "assistant"]), content: z.string() })
  ),
  inputs: z.record(z.string(), z.unknown()).optional(),
  assumptions: z.record(z.string(), z.unknown()).optional(),
  scenarios: z.array(z.unknown()).optional(),
});

export async function POST(request: NextRequest) {
  try {
    const body = SaveSchema.parse(await request.json());
    const extracted =
      body.inputs && body.assumptions
        ? { inputs: body.inputs, assumptions: body.assumptions, scenarios: body.scenarios ?? [] }
        : await extractModelState(body.conversation, body.model_type);

    const model = await saveModel({
      id: body.id,
      name: body.name,
      modelType: body.model_type,
      inputs: extracted.inputs,
      assumptions: extracted.assumptions,
      scenarios: extracted.scenarios,
      conversation: body.conversation,
    });
    return NextResponse.json({ model });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Save failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
