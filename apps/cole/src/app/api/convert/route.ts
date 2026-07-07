import { NextRequest, NextResponse } from "next/server";
import { readFile } from "fs/promises";
import { z } from "zod";
import { convertMedia, resolveConvertedPath } from "@/lib/ffmpeg/convert";

const ConvertSchema = z.object({
  output_format: z.enum(["mp4", "webm", "mp3", "wav"]).default("mp4"),
});

export async function POST(request: NextRequest) {
  try {
    const form = await request.formData();
    const file = form.get("video");
    const formatRaw = form.get("output_format");
    const output_format = ConvertSchema.shape.output_format.parse(
      typeof formatRaw === "string" ? formatRaw : "mp4"
    );

    if (!(file instanceof File)) {
      return NextResponse.json({ error: "video file required" }, { status: 400 });
    }

    const buffer = Buffer.from(await file.arrayBuffer());
    const result = await convertMedia(buffer, file.name, output_format);
    return NextResponse.json({ result });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Conversion failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}

export async function GET(request: NextRequest) {
  const id = request.nextUrl.searchParams.get("id");
  const format = request.nextUrl.searchParams.get("format");
  if (!id || !format) {
    return NextResponse.json({ error: "id and format required" }, { status: 400 });
  }

  const filePath = resolveConvertedPath(id, format);
  if (!filePath) {
    return NextResponse.json({ error: "Invalid path" }, { status: 400 });
  }

  try {
    const data = await readFile(filePath);
    const mime =
      format === "mp4"
        ? "video/mp4"
        : format === "webm"
          ? "video/webm"
          : format === "mp3"
            ? "audio/mpeg"
            : "audio/wav";

    return new NextResponse(data, {
      headers: {
        "Content-Type": mime,
        "Content-Disposition": `attachment; filename="cole-export.${format}"`,
      },
    });
  } catch {
    return NextResponse.json({ error: "File not found" }, { status: 404 });
  }
}
