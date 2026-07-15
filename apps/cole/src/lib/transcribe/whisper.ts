import { writeFile, unlink } from "fs/promises";
import path from "path";
import { randomUUID } from "crypto";
import type { TranscriptionResult } from "@/lib/types";

function formatSrtTime(seconds: number): string {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = Math.floor(seconds % 60);
  const ms = Math.floor((seconds % 1) * 1000);
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")},${String(ms).padStart(3, "0")}`;
}

function formatVttTime(seconds: number): string {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}:${s.toFixed(3).padStart(6, "0")}`;
}

function segmentsToSrt(
  segments: Array<{ start: number; end: number; text: string }>
): string {
  return segments
    .map(
      (seg, i) =>
        `${i + 1}\n${formatSrtTime(seg.start)} --> ${formatSrtTime(seg.end)}\n${seg.text.trim()}\n`
    )
    .join("\n");
}

function segmentsToVtt(
  segments: Array<{ start: number; end: number; text: string }>
): string {
  const body = segments
    .map(
      (seg) =>
        `${formatVttTime(seg.start)} --> ${formatVttTime(seg.end)}\n${seg.text.trim()}\n`
    )
    .join("\n");
  return `WEBVTT\n\n${body}`;
}

/** OpenAI Whisper API - instant-key transcription */
export async function transcribeAudio(
  buffer: Buffer,
  filename: string
): Promise<TranscriptionResult> {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) throw new Error("OPENAI_API_KEY not set - required for Whisper transcription");

  const tmpPath = path.join(process.cwd(), ".data", "uploads", `${randomUUID()}-${filename}`);
  await writeFile(tmpPath, buffer);

  try {
    const form = new FormData();
    const blob = new Blob([new Uint8Array(buffer)]);
    form.append("file", blob, filename);
    form.append("model", "whisper-1");
    form.append("response_format", "verbose_json");
    form.append("timestamp_granularities[]", "segment");

    const res = await fetch("https://api.openai.com/v1/audio/transcriptions", {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}` },
      body: form,
    });

    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      throw new Error(
        (err as { error?: { message?: string } }).error?.message ?? "Transcription failed"
      );
    }

    const data = (await res.json()) as {
      text?: string;
      segments?: Array<{ start: number; end: number; text: string }>;
    };

    const segments = (data.segments ?? []).map((s) => ({
      start: s.start,
      end: s.end,
      text: s.text,
    }));

    return {
      text: data.text ?? "",
      segments,
      srt: segmentsToSrt(segments),
      vtt: segmentsToVtt(segments),
    };
  } finally {
    await unlink(tmpPath).catch(() => {});
  }
}
