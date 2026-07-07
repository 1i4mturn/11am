import { eq, desc, sql } from "drizzle-orm";
import { db } from "@/lib/db";
import {
  boltonVoiceProfiles,
  boltonAgentSummaries,
  writingSamples,
} from "@/lib/db/schema";
import type { VoiceProfile } from "@/lib/types/voice-profile";
import { writeToBolton } from "@/lib/bolton/client";

const DEFAULT_USER = "default";

export function voiceProfileToMarkdown(profile: VoiceProfile): string {
  const platformSection = Object.entries(profile.platform_rules)
    .map(([platform, rules]) => `### ${platform}\n${rules}`)
    .join("\n\n");

  return `# Voice Profile

## Tone
${profile.tone_adjectives.join(", ")}

## Sentence Rhythm
${profile.sentence_rhythm}

## Vocabulary Preferences
${profile.vocabulary_preferences.map((v) => `- ${v}`).join("\n")}

## Phrases to Avoid
${profile.avoid_phrases.map((p) => `- "${p}"`).join("\n")}

## Argument Style
${profile.argument_style}

## Platform-Specific Rules
${platformSection || "No platform-specific rules yet."}
`;
}

export async function getVoiceProfile(userId = DEFAULT_USER) {
  const [profile] = await db
    .select()
    .from(boltonVoiceProfiles)
    .where(eq(boltonVoiceProfiles.userId, userId))
    .limit(1);
  return profile ?? null;
}

export async function saveVoiceProfile(
  userId: string,
  profile: VoiceProfile
): Promise<void> {
  const markdown = voiceProfileToMarkdown(profile);
  const existing = await getVoiceProfile(userId);

  if (existing) {
    await db
      .update(boltonVoiceProfiles)
      .set({
        toneAdjectives: profile.tone_adjectives,
        sentenceRhythm: profile.sentence_rhythm,
        vocabularyPreferences: profile.vocabulary_preferences,
        avoidPhrases: profile.avoid_phrases,
        platformRules: profile.platform_rules,
        argumentStyle: profile.argument_style,
        profileMarkdown: markdown,
        updatedAt: new Date(),
      })
      .where(eq(boltonVoiceProfiles.userId, userId));
  } else {
    await db.insert(boltonVoiceProfiles).values({
      userId,
      toneAdjectives: profile.tone_adjectives,
      sentenceRhythm: profile.sentence_rhythm,
      vocabularyPreferences: profile.vocabulary_preferences,
      avoidPhrases: profile.avoid_phrases,
      platformRules: profile.platform_rules,
      argumentStyle: profile.argument_style,
      profileMarkdown: markdown,
    });
  }

  writeToBolton({
    source_agent: "William",
    entry_type: "voice",
    title: "Voice profile update",
    summary: markdown.slice(0, 500),
    full_content: markdown,
    tags: ["voice", "william", "identity"],
    importance_score: 0.9,
  }).catch(() => {});
}

export async function getLatestAgentSummaries(userId = DEFAULT_USER) {
  const george = await db
    .select()
    .from(boltonAgentSummaries)
    .where(
      sql`${boltonAgentSummaries.userId} = ${userId} AND ${boltonAgentSummaries.agentId} = 'george'`
    )
    .orderBy(desc(boltonAgentSummaries.createdAt))
    .limit(1);

  const conner = await db
    .select()
    .from(boltonAgentSummaries)
    .where(
      sql`${boltonAgentSummaries.userId} = ${userId} AND ${boltonAgentSummaries.agentId} = 'conner'`
    )
    .orderBy(desc(boltonAgentSummaries.createdAt))
    .limit(1);

  return {
    george: george[0] ?? null,
    conner: conner[0] ?? null,
  };
}

export async function saveAgentSummary(
  agentId: "george" | "conner",
  summary: Record<string, unknown>,
  sessionNote?: string,
  userId = DEFAULT_USER
): Promise<void> {
  await db.insert(boltonAgentSummaries).values({
    agentId,
    userId,
    summary,
    sessionNote,
  });
}

export async function retrieveSimilarSamples(
  queryEmbedding: number[],
  limit = 5,
  userId = DEFAULT_USER
) {
  const embeddingStr = `[${queryEmbedding.join(",")}]`;

  const results = await db.execute(sql`
    SELECT id, content, source, is_high_signal,
           1 - (embedding <=> ${embeddingStr}::vector) AS similarity
    FROM writing_samples
    WHERE user_id = ${userId}
      AND embedding IS NOT NULL
    ORDER BY embedding <=> ${embeddingStr}::vector
    LIMIT ${limit}
  `);

  return results as unknown as Array<{
    id: string;
    content: string;
    source: string;
    is_high_signal: boolean;
    similarity: number;
  }>;
}

export async function addWritingSample(
  content: string,
  source: string,
  embedding: number[],
  options: {
    userId?: string;
    isHighSignal?: boolean;
    sourceMeta?: Record<string, string>;
  } = {}
): Promise<void> {
  const userId = options.userId ?? DEFAULT_USER;
  const embeddingStr = `[${embedding.join(",")}]`;

  await db.execute(sql`
    INSERT INTO writing_samples (user_id, content, source, source_meta, embedding, is_high_signal)
    VALUES (
      ${userId},
      ${content},
      ${source},
      ${JSON.stringify(options.sourceMeta ?? {})}::jsonb,
      ${embeddingStr}::vector,
      ${options.isHighSignal ?? false}
    )
  `);
}

export async function getSampleCount(userId = DEFAULT_USER): Promise<number> {
  const [row] = await db
    .select({ count: sql<number>`count(*)::int` })
    .from(writingSamples)
    .where(eq(writingSamples.userId, userId));
  return row?.count ?? 0;
}
