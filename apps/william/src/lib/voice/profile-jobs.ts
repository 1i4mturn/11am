import { eq } from "drizzle-orm";
import { db } from "@/lib/db";
import { profileUpdateJobs } from "@/lib/db/schema";
import {
  getVoiceProfile,
  saveVoiceProfile,
  addWritingSample,
} from "@/lib/bolton";
import { analyseCorpus, updateProfileFromEdits } from "@/lib/voice/analyse";
import { embedText } from "@/lib/voice/embeddings";
import type { VoiceProfile } from "@/lib/types/voice-profile";

export async function queueProfileUpdate(
  userId: string,
  trigger: "edit" | "ingestion",
  payload: Record<string, unknown>
): Promise<string> {
  const [job] = await db
    .insert(profileUpdateJobs)
    .values({ userId, trigger, payload, status: "pending" })
    .returning({ id: profileUpdateJobs.id });

  processProfileUpdateJob(job.id).catch(console.error);
  return job.id;
}

async function processProfileUpdateJob(jobId: string): Promise<void> {
  const [job] = await db
    .select()
    .from(profileUpdateJobs)
    .where(eq(profileUpdateJobs.id, jobId))
    .limit(1);

  if (!job || job.status !== "pending") return;

  await db
    .update(profileUpdateJobs)
    .set({ status: "processing" })
    .where(eq(profileUpdateJobs.id, jobId));

  try {
    const payload = job.payload ?? {};

    if (job.trigger === "edit") {
      const originalOutput = payload.originalOutput as string;
      const editedOutput = payload.editedOutput as string;

      const embedding = await embedText(editedOutput);
      await addWritingSample(editedOutput, "edit", embedding, {
        userId: job.userId,
        isHighSignal: true,
      });

      const existing = await getVoiceProfile(job.userId);
      if (existing) {
        const currentProfile: VoiceProfile = {
          tone_adjectives: existing.toneAdjectives as string[],
          sentence_rhythm: existing.sentenceRhythm,
          vocabulary_preferences: existing.vocabularyPreferences as string[],
          avoid_phrases: existing.avoidPhrases as string[],
          platform_rules: existing.platformRules as Record<string, string>,
          argument_style: existing.argumentStyle,
        };
        const updated = await updateProfileFromEdits(
          currentProfile,
          originalOutput,
          editedOutput
        );
        await saveVoiceProfile(job.userId, updated);
      }
    }

    if (job.trigger === "ingestion") {
      const corpus = payload.corpus as string;
      if (corpus) {
        const profile = await analyseCorpus(corpus);
        await saveVoiceProfile(job.userId, profile);
      }
    }

    await db
      .update(profileUpdateJobs)
      .set({ status: "done", completedAt: new Date() })
      .where(eq(profileUpdateJobs.id, jobId));
  } catch (error) {
    console.error("Profile update job failed:", error);
    await db
      .update(profileUpdateJobs)
      .set({ status: "failed", completedAt: new Date() })
      .where(eq(profileUpdateJobs.id, jobId));
  }
}
