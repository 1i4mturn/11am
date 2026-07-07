import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { runIdeaValidation } from "@/lib/strategy/engine";

const ValidateSchema = z.object({
  idea: z.string().min(1),
});

/** Standalone idea validation + offer creation — no Bolton dependency */
export async function POST(request: NextRequest) {
  try {
    const body = ValidateSchema.parse(await request.json());
    const result = await runIdeaValidation(body.idea);
    return NextResponse.json({ result });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Validation failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
