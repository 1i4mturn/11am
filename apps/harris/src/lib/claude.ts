import Anthropic from "@anthropic-ai/sdk";
import { HARRIS_SYSTEM_BASE } from "@/lib/config";

const MODEL = "claude-sonnet-4-20250514";

export function getAnthropicClient() {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) throw new Error("ANTHROPIC_API_KEY not set");
  return new Anthropic({ apiKey });
}

export async function askHarris(
  systemExtra: string,
  userPrompt: string,
  maxTokens = 4096
): Promise<string> {
  const client = getAnthropicClient();
  const response = await client.messages.create({
    model: MODEL,
    max_tokens: maxTokens,
    system: `${HARRIS_SYSTEM_BASE}\n\n${systemExtra}`,
    messages: [{ role: "user", content: userPrompt }],
  });
  const block = response.content.find((b) => b.type === "text");
  return block?.type === "text" ? block.text : "";
}

export function extractJson<T>(text: string): T | null {
  try {
    const match = text.match(/\{[\s\S]*\}/);
    if (match) return JSON.parse(match[0]) as T;
  } catch {
    // fall through
  }
  return null;
}
