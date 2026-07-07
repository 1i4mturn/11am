import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { generateExercises } from "@/lib/learning/engine";

const Schema = z.object({
  skill: z.string().min(1),
  focus: z.string().optional(),
});

export async function POST(request: NextRequest) {
  try {
    const body = Schema.parse(await request.json());
    const result = await generateExercises(body.skill, body.focus);
    return NextResponse.json({ result });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Exercises failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
