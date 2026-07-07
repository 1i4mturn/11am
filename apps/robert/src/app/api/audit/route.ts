import { NextRequest, NextResponse } from "next/server";
import { runBrandAudit } from "@/lib/design/engine";

const ALLOWED_TYPES = new Set([
  "image/jpeg",
  "image/png",
  "image/gif",
  "image/webp",
]);

export async function POST(request: NextRequest) {
  try {
    const form = await request.formData();
    const file = form.get("asset");
    if (!(file instanceof File)) {
      return NextResponse.json({ error: "asset file required" }, { status: 400 });
    }

    const mediaType = file.type as "image/jpeg" | "image/png" | "image/gif" | "image/webp";
    if (!ALLOWED_TYPES.has(mediaType)) {
      return NextResponse.json({ error: "Unsupported image type" }, { status: 400 });
    }

    const buffer = Buffer.from(await file.arrayBuffer());
    const base64 = buffer.toString("base64");
    const result = await runBrandAudit(base64, mediaType, file.name);
    return NextResponse.json({ result });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Audit failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
