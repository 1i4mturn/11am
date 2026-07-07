import postgres from "postgres";

const connectionString =
  process.env.DATABASE_URL ?? "postgresql://elevenam:elevenam@localhost:5435/elevenam";

async function migrate() {
  const sql = postgres(connectionString, { max: 1 });
  console.log("Creating extensions and tables…");

  await sql`CREATE EXTENSION IF NOT EXISTS vector`;

  await sql`
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY DEFAULT 'default',
      tier TEXT NOT NULL DEFAULT 'free',
      actions_this_month INTEGER NOT NULL DEFAULT 0,
      month_reset_at TIMESTAMP NOT NULL DEFAULT NOW(),
      gmail_access_token TEXT,
      gmail_refresh_token TEXT,
      gmail_token_expiry TIMESTAMP,
      gmail_history_id TEXT,
      last_sync_at TIMESTAMP,
      full_content_indexing BOOLEAN NOT NULL DEFAULT false,
      updated_at TIMESTAMP NOT NULL DEFAULT NOW()
    )
  `;

  await sql`
    CREATE TABLE IF NOT EXISTS email_messages (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id TEXT NOT NULL DEFAULT 'default',
      message_id TEXT NOT NULL,
      thread_id TEXT NOT NULL,
      sender_email TEXT NOT NULL,
      sender_name TEXT,
      recipients JSONB DEFAULT '[]',
      subject TEXT NOT NULL,
      snippet TEXT,
      body TEXT,
      labels JSONB DEFAULT '[]',
      received_at TIMESTAMP NOT NULL,
      is_unread BOOLEAN NOT NULL DEFAULT true,
      thread_summary TEXT,
      urgency_classification TEXT,
      action_classification TEXT,
      sender_memory_id UUID,
      embedding vector(1536),
      has_unsubscribe BOOLEAN DEFAULT false,
      list_unsubscribe TEXT,
      indexed_at TIMESTAMP NOT NULL DEFAULT NOW(),
      UNIQUE(user_id, message_id)
    )
  `;

  await sql`CREATE INDEX IF NOT EXISTS email_messages_message_id_idx ON email_messages(message_id)`;
  await sql`CREATE INDEX IF NOT EXISTS email_messages_thread_id_idx ON email_messages(thread_id)`;
  await sql`CREATE INDEX IF NOT EXISTS email_messages_sender_idx ON email_messages(sender_email)`;
  await sql`
    CREATE INDEX IF NOT EXISTS email_messages_embedding_idx
    ON email_messages USING hnsw (embedding vector_cosine_ops)
  `;

  await sql`
    CREATE TABLE IF NOT EXISTS bolton_sender_profiles (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id TEXT NOT NULL DEFAULT 'default',
      sender_name TEXT,
      sender_email TEXT NOT NULL,
      organisation TEXT,
      relationship_type TEXT NOT NULL DEFAULT 'unknown',
      importance_level TEXT NOT NULL DEFAULT 'medium',
      preferred_tone TEXT DEFAULT 'concise',
      last_interaction_summary TEXT,
      active_thread_topics JSONB DEFAULT '[]',
      recurring_topics JSONB DEFAULT '[]',
      urgency_history JSONB DEFAULT '[]',
      sensitivity_notes TEXT,
      response_expectation TEXT DEFAULT 'normal',
      related_agent_flags JSONB DEFAULT '[]',
      disabled BOOLEAN NOT NULL DEFAULT false,
      last_updated TIMESTAMP NOT NULL DEFAULT NOW(),
      created_at TIMESTAMP NOT NULL DEFAULT NOW(),
      UNIQUE(user_id, sender_email)
    )
  `;

  await sql`
    CREATE TABLE IF NOT EXISTS bolton_inbox_rules (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id TEXT NOT NULL DEFAULT 'default',
      rule_name TEXT NOT NULL,
      trigger TEXT NOT NULL,
      conditions JSONB NOT NULL DEFAULT '[]',
      actions JSONB NOT NULL DEFAULT '[]',
      exceptions JSONB DEFAULT '[]',
      status TEXT NOT NULL DEFAULT 'pending',
      created_by TEXT NOT NULL DEFAULT 'Marc',
      gmail_label_id TEXT,
      created_at TIMESTAMP NOT NULL DEFAULT NOW(),
      applied_at TIMESTAMP
    )
  `;

  await sql`
    CREATE TABLE IF NOT EXISTS bolton_memories (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id TEXT NOT NULL DEFAULT 'default',
      memory_type TEXT NOT NULL,
      source_thread TEXT,
      summary TEXT NOT NULL,
      confidence TEXT NOT NULL DEFAULT 'medium',
      expiry_or_review_date TIMESTAMP,
      created_at TIMESTAMP NOT NULL DEFAULT NOW()
    )
  `;

  await sql`
    CREATE TABLE IF NOT EXISTS bolton_voice_profiles (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id TEXT NOT NULL DEFAULT 'default',
      tone_adjectives JSONB NOT NULL DEFAULT '[]',
      sentence_rhythm TEXT NOT NULL DEFAULT '',
      vocabulary_preferences JSONB NOT NULL DEFAULT '[]',
      avoid_phrases JSONB NOT NULL DEFAULT '[]',
      platform_rules JSONB NOT NULL DEFAULT '{}',
      argument_style TEXT NOT NULL DEFAULT '',
      profile_markdown TEXT NOT NULL DEFAULT '',
      updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
      created_at TIMESTAMP NOT NULL DEFAULT NOW()
    )
  `;

  await sql`
    CREATE TABLE IF NOT EXISTS action_log (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id TEXT NOT NULL DEFAULT 'default',
      action_type TEXT NOT NULL,
      target_ids JSONB DEFAULT '[]',
      payload JSONB DEFAULT '{}',
      status TEXT NOT NULL DEFAULT 'completed',
      created_at TIMESTAMP NOT NULL DEFAULT NOW()
    )
  `;

  await sql`
    CREATE TABLE IF NOT EXISTS handoffs (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id TEXT NOT NULL DEFAULT 'default',
      target_agent TEXT NOT NULL,
      artifact JSONB NOT NULL,
      source_message_id TEXT,
      status TEXT NOT NULL DEFAULT 'pending',
      created_at TIMESTAMP NOT NULL DEFAULT NOW()
    )
  `;

  await sql`INSERT INTO users (id) VALUES ('default') ON CONFLICT (id) DO NOTHING`;

  console.log("Migration complete.");
  await sql.end();
}

migrate().catch((err) => {
  console.error(err);
  process.exit(1);
});
