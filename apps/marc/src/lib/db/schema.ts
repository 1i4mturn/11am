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

/** User tier, Gmail tokens, usage limits */
export const users = pgTable("users", {
  id: text("id").primaryKey().default("default"),
  tier: text("tier").notNull().default("free"),
  actionsThisMonth: integer("actions_this_month").notNull().default(0),
  monthResetAt: timestamp("month_reset_at").defaultNow().notNull(),
  gmailAccessToken: text("gmail_access_token"),
  gmailRefreshToken: text("gmail_refresh_token"),
  gmailTokenExpiry: timestamp("gmail_token_expiry"),
  gmailHistoryId: text("gmail_history_id"),
  lastSyncAt: timestamp("last_sync_at"),
  fullContentIndexing: boolean("full_content_indexing").default(false).notNull(),
  updatedAt: timestamp("updated_at").defaultNow().notNull(),
});

/** Server-side email index */
export const emailMessages = pgTable(
  "email_messages",
  {
    id: uuid("id").defaultRandom().primaryKey(),
    userId: text("user_id").notNull().default("default"),
    messageId: text("message_id").notNull(),
    threadId: text("thread_id").notNull(),
    senderEmail: text("sender_email").notNull(),
    senderName: text("sender_name"),
    recipients: jsonb("recipients").$type<string[]>().default([]),
    subject: text("subject").notNull(),
    snippet: text("snippet"),
    body: text("body"),
    labels: jsonb("labels").$type<string[]>().default([]),
    receivedAt: timestamp("received_at").notNull(),
    isUnread: boolean("is_unread").default(true).notNull(),
    threadSummary: text("thread_summary"),
    urgencyClassification: text("urgency_classification"),
    actionClassification: text("action_classification"),
    senderMemoryId: uuid("sender_memory_id"),
    embedding: vector("embedding", { dimensions: 1536 }),
    hasUnsubscribe: boolean("has_unsubscribe").default(false),
    listUnsubscribe: text("list_unsubscribe"),
    indexedAt: timestamp("indexed_at").defaultNow().notNull(),
  },
  (table) => [
    index("email_messages_message_id_idx").on(table.messageId),
    index("email_messages_thread_id_idx").on(table.threadId),
    index("email_messages_sender_idx").on(table.senderEmail),
    index("email_messages_embedding_idx").using(
      "hnsw",
      table.embedding.op("vector_cosine_ops")
    ),
  ]
);

/** Bolton sender memory - persistent relationship context */
export const boltonSenderProfiles = pgTable("bolton_sender_profiles", {
  id: uuid("id").defaultRandom().primaryKey(),
  userId: text("user_id").notNull().default("default"),
  senderName: text("sender_name"),
  senderEmail: text("sender_email").notNull(),
  organisation: text("organisation"),
  relationshipType: text("relationship_type").notNull().default("unknown"),
  importanceLevel: text("importance_level").notNull().default("medium"),
  preferredTone: text("preferred_tone").default("concise"),
  lastInteractionSummary: text("last_interaction_summary"),
  activeThreadTopics: jsonb("active_thread_topics").$type<string[]>().default([]),
  recurringTopics: jsonb("recurring_topics").$type<string[]>().default([]),
  urgencyHistory: jsonb("urgency_history").$type<string[]>().default([]),
  sensitivityNotes: text("sensitivity_notes"),
  responseExpectation: text("response_expectation").default("normal"),
  relatedAgentFlags: jsonb("related_agent_flags").$type<string[]>().default([]),
  disabled: boolean("disabled").default(false).notNull(),
  lastUpdated: timestamp("last_updated").defaultNow().notNull(),
  createdAt: timestamp("created_at").defaultNow().notNull(),
});

/** Bolton inbox rules */
export const boltonInboxRules = pgTable("bolton_inbox_rules", {
  id: uuid("id").defaultRandom().primaryKey(),
  userId: text("user_id").notNull().default("default"),
  ruleName: text("rule_name").notNull(),
  trigger: text("trigger").notNull(),
  conditions: jsonb("conditions").$type<string[]>().notNull().default([]),
  actions: jsonb("actions").$type<string[]>().notNull().default([]),
  exceptions: jsonb("exceptions").$type<string[]>().default([]),
  status: text("status").notNull().default("pending"),
  createdBy: text("created_by").notNull().default("Marc"),
  gmailLabelId: text("gmail_label_id"),
  createdAt: timestamp("created_at").defaultNow().notNull(),
  appliedAt: timestamp("applied_at"),
});

/** Bolton general memories from Marc */
export const boltonMemories = pgTable("bolton_memories", {
  id: uuid("id").defaultRandom().primaryKey(),
  userId: text("user_id").notNull().default("default"),
  memoryType: text("memory_type").notNull(),
  sourceThread: text("source_thread"),
  summary: text("summary").notNull(),
  confidence: text("confidence").notNull().default("medium"),
  expiryOrReviewDate: timestamp("expiry_or_review_date"),
  createdAt: timestamp("created_at").defaultNow().notNull(),
});

/** William voice profile - read from shared Bolton layer */
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
});

/** Confirmed user actions log - rollback support */
export const actionLog = pgTable("action_log", {
  id: uuid("id").defaultRandom().primaryKey(),
  userId: text("user_id").notNull().default("default"),
  actionType: text("action_type").notNull(),
  targetIds: jsonb("target_ids").$type<string[]>().default([]),
  payload: jsonb("payload").$type<Record<string, unknown>>().default({}),
  status: text("status").notNull().default("completed"),
  createdAt: timestamp("created_at").defaultNow().notNull(),
});

/** Cross-agent handoff queue */
export const handoffs = pgTable("handoffs", {
  id: uuid("id").defaultRandom().primaryKey(),
  userId: text("user_id").notNull().default("default"),
  targetAgent: text("target_agent").notNull(),
  artifact: jsonb("artifact").$type<Record<string, unknown>>().notNull(),
  sourceMessageId: text("source_message_id"),
  status: text("status").notNull().default("pending"),
  createdAt: timestamp("created_at").defaultNow().notNull(),
});
