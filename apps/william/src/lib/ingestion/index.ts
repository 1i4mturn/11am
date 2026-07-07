import { chunkText, embedText } from "@/lib/voice/embeddings";
import { addWritingSample, saveVoiceProfile } from "@/lib/bolton";
import { analyseCorpus } from "@/lib/voice/analyse";
import { queueProfileUpdate } from "@/lib/voice/profile-jobs";

export async function ingestCorpus(
  text: string,
  source: string,
  userId = "default",
  sourceMeta?: Record<string, string>
): Promise<{ chunksAdded: number; profileQueued: boolean }> {
  const chunks = chunkText(text);
  let chunksAdded = 0;

  for (const chunk of chunks) {
    const embedding = await embedText(chunk);
    await addWritingSample(chunk, source, embedding, {
      userId,
      sourceMeta,
      isHighSignal: source === "edit",
    });
    chunksAdded++;
  }

  await queueProfileUpdate(userId, "ingestion", { corpus: text.slice(0, 50000) });

  return { chunksAdded, profileQueued: true };
}

export async function buildInitialProfile(
  corpus: string,
  userId = "default"
): Promise<void> {
  const profile = await analyseCorpus(corpus);
  await saveVoiceProfile(userId, profile);

  const chunks = chunkText(corpus);
  for (const chunk of chunks) {
    const embedding = await embedText(chunk);
    await addWritingSample(chunk, "initial", embedding, { userId });
  }
}
