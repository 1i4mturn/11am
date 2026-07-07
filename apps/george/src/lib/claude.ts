import Anthropic from "@anthropic-ai/sdk";
import { GEORGE_SYSTEM_BASE } from "@/lib/config";

const MODEL = "claude-sonnet-4-20250514";

export function getAnthropicClient() {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) throw new Error("ANTHROPIC_API_KEY not set");
  return new Anthropic({ apiKey });
}

export async function askGeorge(
  systemExtra: string,
  userPrompt: string,
  maxTokens = 4096
): Promise<string> {
  const client = getAnthropicClient();
  const response = await client.messages.create({
    model: MODEL,
    max_tokens: maxTokens,
    system: `${GEORGE_SYSTEM_BASE}\n\n${systemExtra}`,
    messages: [{ role: "user", content: userPrompt }],
  });
  const block = response.content.find((b) => b.type === "text");
  return block?.type === "text" ? block.text : "";
}

export async function askGeorgeWithHistory(
  systemExtra: string,
  messages: Array<{ role: "user" | "assistant"; content: string }>,
  maxTokens = 4096
): Promise<string> {
  const client = getAnthropicClient();
  const response = await client.messages.create({
    model: MODEL,
    max_tokens: maxTokens,
    system: `${GEORGE_SYSTEM_BASE}\n\n${systemExtra}`,
    messages,
  });
  const block = response.content.find((b) => b.type === "text");
  return block?.type === "text" ? block.text : "";
}
