import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { appendBuildSessionToNotion, getNotionStatus } from "@/lib/notion";

export async function GET() {
  return NextResponse.json(await getNotionStatus());
}

const AppendSchema = z.object({
  title: z.string().min(1),
  sections: z.array(
    z.object({
      heading: z.string(),
      bullets: z.array(z.string()),
    })
  ),
});

export async function POST(request: NextRequest) {
  try {
    const body = AppendSchema.parse(await request.json());
    const result = await appendBuildSessionToNotion(body.title, body.sections);
    if (!result.synced) {
      return NextResponse.json({ error: result.reason }, { status: 400 });
    }
    return NextResponse.json(result);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Notion append failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
