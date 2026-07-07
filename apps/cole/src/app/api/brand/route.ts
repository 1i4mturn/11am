import { NextResponse } from "next/server";
import { getBrandContext } from "@/lib/bolton/client";

export async function GET() {
  try {
    const brand = await getBrandContext();
    return NextResponse.json({
      brand_system: brand.doc,
      from_mock: brand.from_mock,
      motion_tokens_ready: brand.motion_tokens_ready,
      motion_tokens: brand.doc.motion_tokens,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Brand fetch failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
