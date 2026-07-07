import { eq, desc, sql, and } from "drizzle-orm";
import { db } from "@/lib/db";
import {
  boltonSenderProfiles,
  boltonInboxRules,
  boltonMemories,
  boltonVoiceProfiles,
} from "@/lib/db/schema";
import type { VoiceProfile, BoltonMemoryUpdate, InboxRule } from "@/lib/types";
import { writeToBolton } from "@/lib/bolton/client";

const DEFAULT_USER = "default";

export async function getVoiceProfile(userId = DEFAULT_USER): Promise<VoiceProfile | null> {
  const [profile] = await db
    .select()
    .from(boltonVoiceProfiles)
    .where(eq(boltonVoiceProfiles.userId, userId))
    .limit(1);

  if (!profile) return null;

  return {
    tone_adjectives: profile.toneAdjectives as string[],
    sentence_rhythm: profile.sentenceRhythm,
    vocabulary_preferences: profile.vocabularyPreferences as string[],
    avoid_phrases: profile.avoidPhrases as string[],
    platform_rules: profile.platformRules as Record<string, string>,
    argument_style: profile.argumentStyle,
  };
}

export function voiceProfileToMarkdown(profile: VoiceProfile): string {
  return `# Voice Profile
Tone: ${profile.tone_adjectives.join(", ")}
Rhythm: ${profile.sentence_rhythm}
Vocabulary: ${profile.vocabulary_preferences.join(", ")}
Avoid: ${profile.avoid_phrases.join(", ")}
Argument style: ${profile.argument_style}
Email rules: ${profile.platform_rules.email ?? "Standard professional tone"}`;
}

export async function getSenderProfile(senderEmail: string, userId = DEFAULT_USER) {
  const [profile] = await db
    .select()
    .from(boltonSenderProfiles)
    .where(
      and(
        eq(boltonSenderProfiles.userId, userId),
        eq(boltonSenderProfiles.senderEmail, senderEmail.toLowerCase())
      )
    )
    .limit(1);
  return profile ?? null;
}

export async function listSenderProfiles(userId = DEFAULT_USER) {
  return db
    .select()
    .from(boltonSenderProfiles)
    .where(eq(boltonSenderProfiles.userId, userId))
    .orderBy(desc(boltonSenderProfiles.lastUpdated));
}

export async function upsertSenderProfile(
  data: {
    senderEmail: string;
    senderName?: string;
    organisation?: string;
    relationshipType?: string;
    importanceLevel?: string;
    preferredTone?: string;
    lastInteractionSummary?: string;
    activeThreadTopics?: string[];
    urgencyHistory?: string[];
    sensitivityNotes?: string;
    responseExpectation?: string;
    relatedAgentFlags?: string[];
    disabled?: boolean;
  },
  userId = DEFAULT_USER
) {
  const email = data.senderEmail.toLowerCase();
  const existing = await getSenderProfile(email, userId);

  if (existing) {
    const [updated] = await db
      .update(boltonSenderProfiles)
      .set({
        senderName: data.senderName ?? existing.senderName,
        organisation: data.organisation ?? existing.organisation,
        relationshipType: data.relationshipType ?? existing.relationshipType,
        importanceLevel: data.importanceLevel ?? existing.importanceLevel,
        preferredTone: data.preferredTone ?? existing.preferredTone,
        lastInteractionSummary:
          data.lastInteractionSummary ?? existing.lastInteractionSummary,
        activeThreadTopics: data.activeThreadTopics ?? existing.activeThreadTopics,
        urgencyHistory: data.urgencyHistory ?? existing.urgencyHistory,
        sensitivityNotes: data.sensitivityNotes ?? existing.sensitivityNotes,
        responseExpectation: data.responseExpectation ?? existing.responseExpectation,
        relatedAgentFlags: data.relatedAgentFlags ?? existing.relatedAgentFlags,
        disabled: data.disabled ?? existing.disabled,
        lastUpdated: new Date(),
      })
      .where(eq(boltonSenderProfiles.id, existing.id))
      .returning();

    writeToBolton({
      source_agent: "Marc",
      entry_type: "sender_memory",
      title: `Sender: ${updated!.senderName ?? email}`,
      summary: updated!.lastInteractionSummary ?? `${updated!.relationshipType} contact, ${updated!.importanceLevel} importance`,
      tags: ["sender", "marc", updated!.relationshipType],
      importance_score: updated!.importanceLevel === "high" ? 0.85 : 0.6,
    }).catch(() => {});

    return updated;
  }

  const [created] = await db
    .insert(boltonSenderProfiles)
    .values({
      userId,
      senderEmail: email,
      senderName: data.senderName,
      organisation: data.organisation,
      relationshipType: data.relationshipType ?? "unknown",
      importanceLevel: data.importanceLevel ?? "medium",
      preferredTone: data.preferredTone ?? "concise",
      lastInteractionSummary: data.lastInteractionSummary,
      activeThreadTopics: data.activeThreadTopics ?? [],
      urgencyHistory: data.urgencyHistory ?? [],
      sensitivityNotes: data.sensitivityNotes,
      responseExpectation: data.responseExpectation ?? "normal",
      relatedAgentFlags: data.relatedAgentFlags ?? [],
      disabled: data.disabled ?? false,
    })
    .returning();

  writeToBolton({
    source_agent: "Marc",
    entry_type: "sender_memory",
    title: `Sender: ${created!.senderName ?? email}`,
    summary: created!.lastInteractionSummary ?? `New ${created!.relationshipType} contact`,
    tags: ["sender", "marc"],
    importance_score: 0.6,
  }).catch(() => {});

  return created;
}

export async function deleteSenderProfile(id: string, userId = DEFAULT_USER) {
  await db
    .delete(boltonSenderProfiles)
    .where(
      and(eq(boltonSenderProfiles.id, id), eq(boltonSenderProfiles.userId, userId))
    );
}

export async function saveMemory(update: BoltonMemoryUpdate, userId = DEFAULT_USER) {
  const [memory] = await db
    .insert(boltonMemories)
    .values({
      userId,
      memoryType: update.memory_type,
      sourceThread: update.source_thread,
      summary: update.summary,
      confidence: update.confidence,
      expiryOrReviewDate: update.expiry_or_review_date
        ? new Date(update.expiry_or_review_date)
        : null,
    })
    .returning();
  return memory;
}

export async function listInboxRules(userId = DEFAULT_USER) {
  return db
    .select()
    .from(boltonInboxRules)
    .where(eq(boltonInboxRules.userId, userId))
    .orderBy(desc(boltonInboxRules.createdAt));
}

export async function saveInboxRule(rule: InboxRule, userId = DEFAULT_USER) {
  const [saved] = await db
    .insert(boltonInboxRules)
    .values({
      userId,
      ruleName: rule.rule_name,
      trigger: rule.trigger,
      conditions: rule.conditions,
      actions: rule.actions,
      exceptions: rule.exceptions,
      status: rule.status,
      createdBy: rule.created_by,
    })
    .returning();
  return saved;
}

export async function getInboxRule(ruleId: string, userId = DEFAULT_USER) {
  const [rule] = await db
    .select()
    .from(boltonInboxRules)
    .where(
      and(eq(boltonInboxRules.id, ruleId), eq(boltonInboxRules.userId, userId))
    )
    .limit(1);
  return rule ?? null;
}

export async function activateInboxRule(ruleId: string, userId = DEFAULT_USER) {
  await db
    .update(boltonInboxRules)
    .set({ status: "active", appliedAt: new Date() })
    .where(
      and(eq(boltonInboxRules.id, ruleId), eq(boltonInboxRules.userId, userId))
    );
}

export async function listMemories(userId = DEFAULT_USER) {
  return db
    .select()
    .from(boltonMemories)
    .where(eq(boltonMemories.userId, userId))
    .orderBy(desc(boltonMemories.createdAt))
    .limit(50);
}
