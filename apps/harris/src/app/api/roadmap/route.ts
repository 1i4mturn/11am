import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { generateRoadmap } from "@/lib/learning/engine";

const Schema = z.object({ skill: z.string().min(1) });

export async function POST(request: NextRequest) {
  try {
    const body = Schema.parse(await request.json());
    const result = await generateRoadmap(body.skill);
    return NextResponse.json({ result });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Roadmap failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
