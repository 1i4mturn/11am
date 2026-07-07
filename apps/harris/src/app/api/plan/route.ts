import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { generateLearningPlan } from "@/lib/learning/engine";

const Schema = z.object({
  skill: z.string().min(1),
  context: z.string().optional(),
});

export async function POST(request: NextRequest) {
  try {
    const body = Schema.parse(await request.json());
    const result = await generateLearningPlan(body.skill, body.context);
    return NextResponse.json({ result });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Plan generation failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
