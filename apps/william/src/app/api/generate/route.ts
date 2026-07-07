import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { generateCopyComplete } from "@/lib/generation";
import { prepareGenerationContext } from "@/lib/generation/prepare";
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
      return NextResponse.json({ error: gate.reason }, { status: 429 });
    }

    const { ctx, tier } = await prepareGenerationContext(userId, body);
    const result = await generateCopyComplete(ctx);

    await incrementGenerationCount(userId);

    const [gen] = await db
      .insert(generations)
      .values({
        userId,
        prompt: body.prompt,
        platform: body.platform,
        output: result.output,
        confidence: result.confidence,
        usedVoiceProfile: !!ctx.voiceProfile,
        usedBusinessContext: !!(ctx.george || ctx.conner),
      })
      .returning({ id: generations.id });

    return NextResponse.json({
      id: gen.id,
      output: result.output,
      confidence: result.confidence,
      handoff: result.handoff,
      tier,
      remaining: SINGLE_USER_DEBUG ? null : gate.remaining !== null ? gate.remaining - 1 : null,
    });
  } catch (error) {
    console.error("Generation error:", error);
    const message = error instanceof Error ? error.message : "Generation failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
