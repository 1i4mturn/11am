import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { listMotionTemplates, renderMotionTemplate } from "@/lib/motion/templates";

const Schema = z.object({
  template_id: z.enum(["title-reveal", "lower-third", "end-card"]),
});

export async function GET() {
  return NextResponse.json({ templates: listMotionTemplates() });
}

export async function POST(request: NextRequest) {
  try {
    const body = Schema.parse(await request.json());
    const result = await renderMotionTemplate(body.template_id);
    return NextResponse.json({ result });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Template failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
