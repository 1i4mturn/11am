import { NextRequest } from "next/server";
import { z } from "zod";
import { prepareGenerationContext } from "@/lib/generation/prepare";
import { streamGenerateCopy, computeConfidence } from "@/lib/generation";
import { canGenerate, incrementGenerationCount } from "@/lib/tiers";
import { SINGLE_USER_DEBUG } from "@/lib/config";
import { db } from "@/lib/db";
import { generations } from "@/lib/db/schema";
import { PlatformSchema } from "@/lib/types/voice-profile";

const GenerateSchema = z.object({
  prompt: z.string().min(1),
  platform: PlatformSchema,
  context: z.string().optional(),
  includeBusinessContext: z.boolean().default(false),
});

export async function POST(request: NextRequest) {
  try {
    const body = GenerateSchema.parse(await request.json());
    const userId = "default";

    const gate = await canGenerate(userId);
    if (!gate.allowed) {
      return new Response(JSON.stringify({ error: gate.reason }), { status: 429 });
    }

    const { ctx, tier } = await prepareGenerationContext(userId, body);

    const encoder = new TextEncoder();
    let fullOutput = "";

    const stream = new ReadableStream({
      async start(controller) {
        const send = (event: string, data: unknown) => {
          controller.enqueue(encoder.encode(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`));
        };

        try {
          for await (const chunk of streamGenerateCopy(ctx)) {
            fullOutput += chunk;
            send("delta", { text: chunk });
          }

          fullOutput = fullOutput.trim();
          const confidence = computeConfidence(ctx.fewShotExamples ?? [], tier);
          const handoff = {
            copy: fullOutput,
            platform: body.platform.charAt(0).toUpperCase() + body.platform.slice(1),
            format: body.platform === "linkedin" ? "single image post" : "text",
            tone_notes: ctx.voiceProfile
              ? ctx.voiceProfile.tone_adjectives.slice(0, 3).join(", ")
              : "Warm, clear, conversational",
            visual_direction:
              "Clean, authentic, human - editorial white space, no stock-photo energy",
          };

          await incrementGenerationCount(userId);

          const [gen] = await db
            .insert(generations)
            .values({
              userId,
              prompt: body.prompt,
              platform: body.platform,
              output: fullOutput,
              confidence,
              usedVoiceProfile: !!ctx.voiceProfile,
              usedBusinessContext: !!(ctx.george || ctx.conner),
            })
            .returning({ id: generations.id });

          send("done", {
            id: gen.id,
            output: fullOutput,
            confidence,
            handoff,
            tier,
            remaining: SINGLE_USER_DEBUG ? null : gate.remaining !== null ? gate.remaining - 1 : null,
          });
        } catch (error) {
          const message = error instanceof Error ? error.message : "Generation failed";
          send("error", { error: message });
        } finally {
          controller.close();
        }
      },
    });

    return new Response(stream, {
      headers: {
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache",
        Connection: "keep-alive",
      },
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Generation failed";
    return new Response(JSON.stringify({ error: message }), { status: 500 });
  }
}
