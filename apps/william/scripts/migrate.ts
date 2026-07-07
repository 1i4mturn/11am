import { ensureExtensions } from "@/lib/db";
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
      generations_this_month INTEGER NOT NULL DEFAULT 0,
      month_reset_at TIMESTAMP NOT NULL DEFAULT NOW(),
      gmail_access_token TEXT,
      gmail_refresh_token TEXT,
      gmail_token_expiry TIMESTAMP,
      updated_at TIMESTAMP NOT NULL DEFAULT NOW()
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
    CREATE TABLE IF NOT EXISTS writing_samples (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id TEXT NOT NULL DEFAULT 'default',
      content TEXT NOT NULL,
      source TEXT NOT NULL,
      source_meta JSONB DEFAULT '{}',
      embedding vector(1536),
      is_high_signal BOOLEAN NOT NULL DEFAULT false,
      created_at TIMESTAMP NOT NULL DEFAULT NOW()
    )
  `;

  await sql`
    CREATE INDEX IF NOT EXISTS writing_samples_embedding_idx
    ON writing_samples USING hnsw (embedding vector_cosine_ops)
  `;

  await sql`
    CREATE TABLE IF NOT EXISTS bolton_agent_summaries (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      agent_id TEXT NOT NULL,
      user_id TEXT NOT NULL DEFAULT 'default',
      summary JSONB NOT NULL,
      session_note TEXT,
      created_at TIMESTAMP NOT NULL DEFAULT NOW()
    )
  `;

  await sql`
    CREATE TABLE IF NOT EXISTS generations (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id TEXT NOT NULL DEFAULT 'default',
      prompt TEXT NOT NULL,
      platform TEXT NOT NULL,
      output TEXT NOT NULL,
      edited_output TEXT,
      confidence INTEGER NOT NULL DEFAULT 0,
      used_voice_profile BOOLEAN NOT NULL DEFAULT false,
      used_business_context BOOLEAN NOT NULL DEFAULT false,
      created_at TIMESTAMP NOT NULL DEFAULT NOW()
    )
  `;

  await sql`
    CREATE TABLE IF NOT EXISTS profile_update_jobs (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id TEXT NOT NULL DEFAULT 'default',
      status TEXT NOT NULL DEFAULT 'pending',
      trigger TEXT NOT NULL,
      payload JSONB DEFAULT '{}',
      created_at TIMESTAMP NOT NULL DEFAULT NOW(),
      completed_at TIMESTAMP
    )
  `;

  await sql`INSERT INTO users (id) VALUES ('default') ON CONFLICT (id) DO NOTHING`;

  await sql`
    INSERT INTO bolton_agent_summaries (agent_id, user_id, summary, session_note)
    VALUES (
      'george',
      'default',
      '{"revenue_growth": "18% QoQ", "runway_months": 14, "key_metric": "MRR up to $42k"}'::jsonb,
      'Q1 finance review — strong quarter'
    )
  `;

  await sql`
    INSERT INTO bolton_agent_summaries (agent_id, user_id, summary, session_note)
    VALUES (
      'conner',
      'default',
      '{"positioning_shift": "platform language over product language", "target_audience": "founders building agent suites", "key_message": "voice fidelity is the moat"}'::jsonb,
      'Strategy session — repositioning for platform narrative'
    )
  `;

  console.log("Migration complete.");
  await sql.end();
}

migrate().catch((err) => {
  console.error(err);
  process.exit(1);
});
