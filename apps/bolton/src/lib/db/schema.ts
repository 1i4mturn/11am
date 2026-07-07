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
  real,
} from "drizzle-orm/pg-core";

/** Shared user record across 11am agents */
export const users = pgTable("users", {
  id: text("id").primaryKey().default("default"),
  tier: text("tier").notNull().default("free"),
  actionsThisMonth: integer("actions_this_month").notNull().default(0),
  generationsThisMonth: integer("generations_this_month").notNull().default(0),
  monthResetAt: timestamp("month_reset_at").defaultNow().notNull(),
  gmailAccessToken: text("gmail_access_token"),
  gmailRefreshToken: text("gmail_refresh_token"),
  gmailTokenExpiry: timestamp("gmail_token_expiry"),
  gmailHistoryId: text("gmail_history_id"),
  lastSyncAt: timestamp("last_sync_at"),
  calendarAccessToken: text("calendar_access_token"),
  calendarRefreshToken: text("calendar_refresh_token"),
  calendarTokenExpiry: timestamp("calendar_token_expiry"),
  calendarConnectedAt: timestamp("calendar_connected_at"),
  stripeRestrictedKey: text("stripe_restricted_key"),
  xeroAccessToken: text("xero_access_token"),
  xeroRefreshToken: text("xero_refresh_token"),
  xeroTokenExpiry: timestamp("xero_token_expiry"),
  xeroTenantId: text("xero_tenant_id"),
  xeroConnectedAt: timestamp("xero_connected_at"),
  fullContentIndexing: boolean("full_content_indexing").default(false).notNull(),
  updatedAt: timestamp("updated_at").defaultNow().notNull(),
});

/** Core Bolton memory entries */
export const memoryEntries = pgTable(
  "memory_entries",
  {
    id: uuid("id").defaultRandom().primaryKey(),
    userId: text("user_id").notNull().default("default"),
    sourceAgent: text("source_agent").notNull(),
    entryType: text("entry_type").notNull(),
    title: text("title").notNull(),
    summary: text("summary").notNull(),
    fullContent: text("full_content"),
    tags: jsonb("tags").$type<string[]>().notNull().default([]),
    relatedEntities: jsonb("related_entities").$type<string[]>().default([]),
    relatedEntries: jsonb("related_entries").$type<string[]>().default([]),
    importanceScore: real("importance_score").notNull().default(0.5),
    confidence: text("confidence").notNull().default("medium"),
    status: text("status").notNull().default("active"),
    supersededById: uuid("superseded_by_id"),
    cadence: text("cadence"),
    customSchedule: text("custom_schedule"),
    embedding: vector("embedding", { dimensions: 1536 }),
    createdAt: timestamp("created_at").defaultNow().notNull(),
    lastAccessedAt: timestamp("last_accessed_at").defaultNow().notNull(),
  },
  (table) => [
    index("memory_entries_embedding_idx").using(
      "hnsw",
      table.embedding.op("vector_cosine_ops")
    ),
    index("memory_entries_user_status_idx").on(table.userId, table.status),
  ]
);

/** Entity graph */
export const entities = pgTable("entities", {
  id: uuid("id").defaultRandom().primaryKey(),
  userId: text("user_id").notNull().default("default"),
  entityType: text("entity_type").notNull(),
  name: text("name").notNull(),
  aliases: jsonb("aliases").$type<string[]>().default([]),
  summary: text("summary").notNull().default(""),
  importanceLevel: text("importance_level").notNull().default("medium"),
  sourceEntries: jsonb("source_entries").$type<string[]>().default([]),
  firstSeenAt: timestamp("first_seen_at").defaultNow().notNull(),
  lastUpdatedAt: timestamp("last_updated_at").defaultNow().notNull(),
});

export const entityRelationships = pgTable("entity_relationships", {
  id: uuid("id").defaultRandom().primaryKey(),
  userId: text("user_id").notNull().default("default"),
  entityAId: uuid("entity_a_id").notNull(),
  relationshipType: text("relationship_type").notNull(),
  entityBId: uuid("entity_b_id").notNull(),
  context: text("context"),
  confidenceScore: real("confidence_score").default(0.8),
  createdAt: timestamp("created_at").defaultNow().notNull(),
});

/** Decision Log */
export const decisions = pgTable("decisions", {
  id: uuid("id").defaultRandom().primaryKey(),
  userId: text("user_id").notNull().default("default"),
  decision: text("decision").notNull(),
  context: text("context").notNull().default(""),
  rationale: text("rationale").notNull().default(""),
  alternativesConsidered: jsonb("alternatives_considered").$type<string[]>().default([]),
  sourceAgent: text("source_agent").notNull(),
  relatedProject: uuid("related_project"),
  relatedEntries: jsonb("related_entries").$type<string[]>().default([]),
  decisionType: text("decision_type").notNull().default("product"),
  status: text("status").notNull().default("active"),
  supersededById: uuid("superseded_by_id"),
  createdAt: timestamp("created_at").defaultNow().notNull(),
});

/** Conflict review items */
export const conflicts = pgTable("conflicts", {
  id: uuid("id").defaultRandom().primaryKey(),
  userId: text("user_id").notNull().default("default"),
  conflictType: text("conflict_type").notNull(),
  entriesInvolved: jsonb("entries_involved").$type<string[]>().notNull(),
  description: text("description").notNull(),
  recommendedResolution: text("recommended_resolution"),
  confidence: text("confidence").notNull().default("medium"),
  status: text("status").notNull().default("open"),
  createdAt: timestamp("created_at").defaultNow().notNull(),
  resolvedAt: timestamp("resolved_at"),
});

/** William — voice profiles */
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
  memoryEntryId: uuid("memory_entry_id"),
  updatedAt: timestamp("updated_at").defaultNow().notNull(),
  createdAt: timestamp("created_at").defaultNow().notNull(),
});

/** William — writing samples for RAG */
export const writingSamples = pgTable(
  "writing_samples",
  {
    id: uuid("id").defaultRandom().primaryKey(),
    userId: text("user_id").notNull().default("default"),
    content: text("content").notNull(),
    source: text("source").notNull(),
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

/** Marc — sender memory */
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
  memoryEntryId: uuid("memory_entry_id"),
  disabled: boolean("disabled").default(false).notNull(),
  lastUpdated: timestamp("last_updated").defaultNow().notNull(),
  createdAt: timestamp("created_at").defaultNow().notNull(),
});

/** Marc — inbox rules */
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
  memoryEntryId: uuid("memory_entry_id"),
  createdAt: timestamp("created_at").defaultNow().notNull(),
  appliedAt: timestamp("applied_at"),
});

/** George / Conner agent summaries */
export const boltonAgentSummaries = pgTable("bolton_agent_summaries", {
  id: uuid("id").defaultRandom().primaryKey(),
  agentId: text("agent_id").notNull(),
  userId: text("user_id").notNull().default("default"),
  summary: jsonb("summary").$type<Record<string, unknown>>().notNull(),
  sessionNote: text("session_note"),
  memoryEntryId: uuid("memory_entry_id"),
  createdAt: timestamp("created_at").defaultNow().notNull(),
});

/** George — full financial models (not stored in Bolton) */
export const georgeFinancialModels = pgTable("george_financial_models", {
  id: uuid("id").defaultRandom().primaryKey(),
  userId: text("user_id").notNull().default("default"),
  name: text("name").notNull(),
  modelType: text("model_type").notNull().default("general"),
  inputs: jsonb("inputs").$type<Record<string, unknown>>().notNull().default({}),
  assumptions: jsonb("assumptions").$type<Record<string, unknown>>().notNull().default({}),
  scenarios: jsonb("scenarios").$type<unknown[]>().notNull().default([]),
  conversation: jsonb("conversation").$type<unknown[]>().notNull().default([]),
  createdAt: timestamp("created_at").defaultNow().notNull(),
  updatedAt: timestamp("updated_at").defaultNow().notNull(),
});

/** George — generated calculator artifacts (HTML in Supabase storage) */
export const georgeCalculators = pgTable("george_calculators", {
  id: uuid("id").defaultRandom().primaryKey(),
  userId: text("user_id").notNull().default("default"),
  title: text("title").notNull(),
  prompt: text("prompt").notNull(),
  storagePath: text("storage_path").notNull(),
  publicUrl: text("public_url"),
  memoryEntryId: uuid("memory_entry_id"),
  createdAt: timestamp("created_at").defaultNow().notNull(),
});

/** Marc — email index */
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
    index("email_messages_embedding_idx").using(
      "hnsw",
      table.embedding.op("vector_cosine_ops")
    ),
  ]
);

/** William generation history */
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
