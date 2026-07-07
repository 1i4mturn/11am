import {
  pgTable,
  uuid,
  text,
  timestamp,
  integer,
  boolean,
  jsonb,
  vector,
  index,
} from "drizzle-orm/pg-core";

/** Bolton shared memory — voice profiles are identity data, not session data */
export const boltonVoiceProfiles = pgTable("bolton_voice_profiles", {
  id: uuid("id").defaultRandom().primaryKey(),
  userId: text("user_id").notNull().default("default"),
  toneAdjectives: jsonb("tone_adjectives").$type<string[]>().notNull().default([]),
  sentenceRhythm: text("sentence_rhythm").notNull().default(""),
  vocabularyPreferences: jsonb("vocabulary_preferences").$type<string[]>().notNull().default([]),
  avoidPhrases: jsonb("avoid_phrases").$type<string[]>().notNull().default([]),
  platformRules: jsonb("platform_rules").$type<Record<string, string>>().notNull().default({}),
  argumentStyle: text("argument_style").notNull().default(""),
  profileMarkdown: text("profile_markdown").notNull().default(""),
  updatedAt: timestamp("updated_at").defaultNow().notNull(),
  createdAt: timestamp("created_at").defaultNow().notNull(),
});

/** Writing sample chunks with embeddings for RAG retrieval */
export const writingSamples = pgTable(
  "writing_samples",
  {
    id: uuid("id").defaultRandom().primaryKey(),
    userId: text("user_id").notNull().default("default"),
    content: text("content").notNull(),
    source: text("source").notNull(), // paste | upload | url | gmail | edit
    sourceMeta: jsonb("source_meta").$type<Record<string, string>>().default({}),
    embedding: vector("embedding", { dimensions: 1536 }),
    isHighSignal: boolean("is_high_signal").default(false).notNull(),
    createdAt: timestamp("created_at").defaultNow().notNull(),
  },
  (table) => [
    index("writing_samples_embedding_idx").using(
      "hnsw",
      table.embedding.op("vector_cosine_ops")
    ),
  ]
);

/** Bolton agent summaries — George (finance) and Conner (strategy) */
export const boltonAgentSummaries = pgTable("bolton_agent_summaries", {
  id: uuid("id").defaultRandom().primaryKey(),
  agentId: text("agent_id").notNull(), // george | conner
  userId: text("user_id").notNull().default("default"),
  summary: jsonb("summary").$type<Record<string, unknown>>().notNull(),
  sessionNote: text("session_note"),
  createdAt: timestamp("created_at").defaultNow().notNull(),
});

/** Generation history and usage tracking for tier gating */
export const generations = pgTable("generations", {
  id: uuid("id").defaultRandom().primaryKey(),
  userId: text("user_id").notNull().default("default"),
  prompt: text("prompt").notNull(),
  platform: text("platform").notNull(),
  output: text("output").notNull(),
  editedOutput: text("edited_output"),
  confidence: integer("confidence").notNull().default(0),
  usedVoiceProfile: boolean("used_voice_profile").default(false).notNull(),
  usedBusinessContext: boolean("used_business_context").default(false).notNull(),
  createdAt: timestamp("created_at").defaultNow().notNull(),
});

/** User tier and Gmail OAuth tokens */
export const users = pgTable("users", {
  id: text("id").primaryKey().default("default"),
  tier: text("tier").notNull().default("free"), // free | pro
  generationsThisMonth: integer("generations_this_month").notNull().default(0),
  monthResetAt: timestamp("month_reset_at").defaultNow().notNull(),
  gmailAccessToken: text("gmail_access_token"),
  gmailRefreshToken: text("gmail_refresh_token"),
  gmailTokenExpiry: timestamp("gmail_token_expiry"),
  updatedAt: timestamp("updated_at").defaultNow().notNull(),
});

/** Background job queue for profile updates after edits */
export const profileUpdateJobs = pgTable("profile_update_jobs", {
  id: uuid("id").defaultRandom().primaryKey(),
  userId: text("user_id").notNull().default("default"),
  status: text("status").notNull().default("pending"), // pending | processing | done | failed
  trigger: text("trigger").notNull(), // edit | ingestion
  payload: jsonb("payload").$type<Record<string, unknown>>().default({}),
  createdAt: timestamp("created_at").defaultNow().notNull(),
  completedAt: timestamp("completed_at"),
});
