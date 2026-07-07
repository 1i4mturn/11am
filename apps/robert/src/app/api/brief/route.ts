import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { createImplementationBrief } from "@/lib/design/engine";

const WilliamHandoffSchema = z.object({
  copy: z.string(),
  platform: z.string(),
  format: z.string(),
  tone_notes: z.string(),
  visual_direction: z.string(),
});

const Schema = z.object({
  target: z.enum(["johnny", "cole"]),
  project: z.string().min(1),
  objective: z.string().min(1),
  william_handoff: WilliamHandoffSchema.optional(),
});

export async function POST(request: NextRequest) {
  try {
    const body = Schema.parse(await request.json());
    const { brief, memory_id } = await createImplementationBrief(body);
    return NextResponse.json({ brief, memory_id });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Brief handoff failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
