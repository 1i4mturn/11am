import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { getBrandSystemFromBolton } from "@/lib/bolton/client";
import { updateBrandSystem } from "@/lib/design/engine";

export async function GET() {
  try {
    const { doc, from_mock } = await getBrandSystemFromBolton();
    return NextResponse.json({ brand_system: doc, from_mock });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Fetch failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}

const WriteSchema = z.object({
  update_brief: z.string().min(1),
});

export async function POST(request: NextRequest) {
  try {
    const body = WriteSchema.parse(await request.json());
    const { doc, memory_ids_written } = await updateBrandSystem(body.update_brief);
    return NextResponse.json({ brand_system: doc, memory_ids_written });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Brand system write failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
