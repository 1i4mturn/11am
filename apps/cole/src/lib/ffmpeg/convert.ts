import { execFile } from "child_process";
import { mkdir, readFile, unlink, writeFile } from "fs/promises";
import path from "path";
import { randomUUID } from "crypto";
import { promisify } from "util";
import { FFMPEG_PATH } from "@/lib/config";
import type { ConvertResult } from "@/lib/types";

const execFileAsync = promisify(execFile);

const OUTPUT_DIR = path.join(process.cwd(), ".data", "converted");

export async function checkFfmpegAvailable(): Promise<boolean> {
  try {
    await execFileAsync(FFMPEG_PATH, ["-version"]);
    return true;
  } catch {
    return false;
  }
}

export type OutputFormat = "mp4" | "webm" | "mp3" | "wav";

const FORMAT_ARGS: Record<OutputFormat, string[]> = {
  mp4: ["-c:v", "libx264", "-preset", "fast", "-crf", "23", "-c:a", "aac", "-b:a", "128k"],
  webm: ["-c:v", "libvpx-vp9", "-crf", "30", "-b:v", "0", "-c:a", "libopus"],
  mp3: ["-vn", "-c:a", "libmp3lame", "-q:a", "2"],
  wav: ["-vn", "-c:a", "pcm_s16le"],
};

export async function convertMedia(
  buffer: Buffer,
  inputName: string,
  outputFormat: OutputFormat
): Promise<ConvertResult> {
  const available = await checkFfmpegAvailable();
  if (!available) {
    throw new Error(
      `FFmpeg not found at "${FFMPEG_PATH}". Install ffmpeg and ensure it is on PATH.`
    );
  }

  await mkdir(OUTPUT_DIR, { recursive: true });
  const id = randomUUID();
  const ext = path.extname(inputName) || ".bin";
  const inputPath = path.join(OUTPUT_DIR, `${id}-in${ext}`);
  const outputPath = path.join(OUTPUT_DIR, `${id}-out.${outputFormat}`);

  await writeFile(inputPath, buffer);

  try {
    const args = ["-y", "-i", inputPath, ...FORMAT_ARGS[outputFormat], outputPath];
    await execFileAsync(FFMPEG_PATH, args, { timeout: 120_000 });

    const stat = await readFile(outputPath);
    if (stat.length === 0) throw new Error("FFmpeg produced empty output");

    return {
      input_format: ext.replace(".", ""),
      output_format: outputFormat,
      output_path: outputPath,
      download_url: `/api/convert/download?id=${id}&format=${outputFormat}`,
    };
  } finally {
    await unlink(inputPath).catch(() => {});
  }
}

export function resolveConvertedPath(id: string, format: string): string | null {
  const safeId = id.replace(/[^a-f0-9-]/gi, "");
  const safeFormat = format.replace(/[^a-z0-9]/gi, "");
  const p = path.join(OUTPUT_DIR, `${safeId}-out.${safeFormat}`);
  if (!p.startsWith(OUTPUT_DIR)) return null;
  return p;
}
