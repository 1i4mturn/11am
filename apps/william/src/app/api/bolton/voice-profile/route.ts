import { NextResponse } from "next/server";
import { getVoiceProfile, getSampleCount } from "@/lib/bolton";

/**
 * Bolton read endpoint — voice profile is identity data shared across 11am agents.
 * Robert, Conner, and others pull from here rather than William's session store.
 */
export async function GET() {
  const userId = "default";
  const profile = await getVoiceProfile(userId);
  const sampleCount = await getSampleCount(userId);

  if (!profile) {
    return NextResponse.json({ profile: null, sampleCount: 0 });
  }

  return NextResponse.json({
    profile: {
      tone_adjectives: profile.toneAdjectives,
      sentence_rhythm: profile.sentenceRhythm,
      vocabulary_preferences: profile.vocabularyPreferences,
      avoid_phrases: profile.avoidPhrases,
      platform_rules: profile.platformRules,
      argument_style: profile.argumentStyle,
      profile_markdown: profile.profileMarkdown,
      updated_at: profile.updatedAt,
    },
    sampleCount,
    source: "bolton",
  });
}
