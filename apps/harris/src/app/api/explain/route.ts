import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { explainConcept } from "@/lib/learning/engine";

const Schema = z.object({ concept: z.string().min(1) });

export async function POST(request: NextRequest) {
  try {
    const body = Schema.parse(await request.json());
    const result = await explainConcept(body.concept);
    return NextResponse.json({ result });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Explanation failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
