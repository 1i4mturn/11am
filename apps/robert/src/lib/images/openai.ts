import { MAX_IMAGES_PER_SESSION } from "@/lib/config";

const sessionCounts = new Map<string, number>();

export function getSessionImageCount(sessionId: string): number {
  return sessionCounts.get(sessionId) ?? 0;
}

export function getImagesRemaining(sessionId: string): number {
  return Math.max(0, MAX_IMAGES_PER_SESSION - getSessionImageCount(sessionId));
}

export function recordImageGenerated(sessionId: string, count = 1): void {
  sessionCounts.set(sessionId, getSessionImageCount(sessionId) + count);
}

export interface GeneratedImage {
  url: string;
  revised_prompt?: string;
}

/** OpenAI DALL-E 3 - instant-key provider, session-capped */
export async function generateImage(
  prompt: string,
  sessionId: string,
  options?: { size?: "1024x1024" | "1792x1024" | "1024x1792" }
): Promise<GeneratedImage> {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) throw new Error("OPENAI_API_KEY not set - required for image generation");

  const remaining = getImagesRemaining(sessionId);
  if (remaining <= 0) {
    throw new Error(
      `Session image cap reached (${MAX_IMAGES_PER_SESSION}). Start a new session or wait for reset.`
    );
  }

  const res = await fetch("https://api.openai.com/v1/images/generations", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "dall-e-3",
      prompt,
      n: 1,
      size: options?.size ?? "1024x1024",
      response_format: "url",
    }),
  });

  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(
      (err as { error?: { message?: string } }).error?.message ?? "Image generation failed"
    );
  }

  const data = (await res.json()) as {
    data: Array<{ url?: string; revised_prompt?: string }>;
  };
  const item = data.data[0];
  if (!item?.url) throw new Error("No image URL returned");

  recordImageGenerated(sessionId, 1);

  return { url: item.url, revised_prompt: item.revised_prompt };
}
