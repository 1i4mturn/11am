import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { getVoiceProfile } from "@/lib/bolton";
import { getUser, tierFeatures } from "@/lib/tiers";
import { getSampleCount } from "@/lib/bolton";

export async function GET() {
  const userId = "default";
  const user = await getUser(userId);
  const profile = await getVoiceProfile(userId);
  const sampleCount = await getSampleCount(userId);

  return NextResponse.json({
    tier: user.tier,
    features: tierFeatures(user.tier),
    profile: profile
      ? {
          toneAdjectives: profile.toneAdjectives,
          sentenceRhythm: profile.sentenceRhythm,
          vocabularyPreferences: profile.vocabularyPreferences,
          avoidPhrases: profile.avoidPhrases,
          platformRules: profile.platformRules,
          argumentStyle: profile.argumentStyle,
          profileMarkdown: profile.profileMarkdown,
          updatedAt: profile.updatedAt,
        }
      : null,
    sampleCount,
    generationsThisMonth: user.generationsThisMonth,
  });
}

const IngestSchema = z.object({
  text: z.string().min(50),
  source: z.enum(["paste", "upload", "url", "gmail"]).default("paste"),
  sourceMeta: z.record(z.string(), z.string()).optional(),
});

export async function POST(request: NextRequest) {
  try {
    const userId = "default";
    const user = await getUser(userId);

    if (user.tier !== "pro") {
      return NextResponse.json(
        { error: "Voice profile ingestion requires Pro tier" },
        { status: 403 }
      );
    }

    const body = IngestSchema.parse(await request.json());
    const { ingestCorpus, buildInitialProfile } = await import("@/lib/ingestion");
    const existing = await getVoiceProfile(userId);

    if (!existing) {
      await buildInitialProfile(body.text, userId);
    } else {
      await ingestCorpus(body.text, body.source, userId, body.sourceMeta);
    }

    const profile = await getVoiceProfile(userId);
    return NextResponse.json({
      success: true,
      profile: profile?.profileMarkdown,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Ingestion failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
