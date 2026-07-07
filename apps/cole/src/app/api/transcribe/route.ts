import { NextRequest, NextResponse } from "next/server";
import { transcribeAudio } from "@/lib/transcribe/whisper";

const ALLOWED = new Set([
  "audio/mpeg",
  "audio/mp4",
  "audio/wav",
  "audio/webm",
  "audio/x-m4a",
  "video/mp4",
  "video/webm",
]);

export async function POST(request: NextRequest) {
  try {
    const form = await request.formData();
    const file = form.get("audio");
    if (!(file instanceof File)) {
      return NextResponse.json({ error: "audio file required" }, { status: 400 });
    }
    if (!ALLOWED.has(file.type) && !file.name.match(/\.(mp3|mp4|m4a|wav|webm|mov)$/i)) {
      return NextResponse.json({ error: "Unsupported audio/video format" }, { status: 400 });
    }

    const buffer = Buffer.from(await file.arrayBuffer());
    const result = await transcribeAudio(buffer, file.name);
    return NextResponse.json({ result });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Transcription failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
