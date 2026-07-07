import postgres from "postgres";

const connectionString =
  process.env.DATABASE_URL ?? "postgresql://elevenam:elevenam@localhost:5435/elevenam";

async function migrate() {
  const sql = postgres(connectionString, { max: 1 });
  console.log("Creating shared 11am Bolton schema…");

  await sql`CREATE EXTENSION IF NOT EXISTS vector`;

  await sql`
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY DEFAULT 'default',
      tier TEXT NOT NULL DEFAULT 'free',
      actions_this_month INTEGER NOT NULL DEFAULT 0,
      generations_this_month INTEGER NOT NULL DEFAULT 0,
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
    CREATE TABLE IF NOT EXISTS memory_entries (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id TEXT NOT NULL DEFAULT 'default',
      source_agent TEXT NOT NULL,
      entry_type TEXT NOT NULL,
      title TEXT NOT NULL,
      summary TEXT NOT NULL,
      full_content TEXT,
      tags JSONB NOT NULL DEFAULT '[]',
      related_entities JSONB DEFAULT '[]',
      related_entries JSONB DEFAULT '[]',
      importance_score REAL NOT NULL DEFAULT 0.5,
      confidence TEXT NOT NULL DEFAULT 'medium',
      status TEXT NOT NULL DEFAULT 'active',
      superseded_by_id UUID,
      cadence TEXT,
      custom_schedule TEXT,
      embedding vector(1536),
      created_at TIMESTAMP NOT NULL DEFAULT NOW(),
      last_accessed_at TIMESTAMP NOT NULL DEFAULT NOW()
    )
  `;

  await sql`CREATE INDEX IF NOT EXISTS memory_entries_user_status_idx ON memory_entries(user_id, status)`;
  await sql`CREATE INDEX IF NOT EXISTS memory_entries_embedding_idx ON memory_entries USING hnsw (embedding vector_cosine_ops)`;

  await sql`
    CREATE TABLE IF NOT EXISTS entities (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id TEXT NOT NULL DEFAULT 'default',
      entity_type TEXT NOT NULL,
      name TEXT NOT NULL,
      aliases JSONB DEFAULT '[]',
      summary TEXT NOT NULL DEFAULT '',
      importance_level TEXT NOT NULL DEFAULT 'medium',
      source_entries JSONB DEFAULT '[]',
      first_seen_at TIMESTAMP NOT NULL DEFAULT NOW(),
      last_updated_at TIMESTAMP NOT NULL DEFAULT NOW()
    )
  `;

  await sql`
    CREATE TABLE IF NOT EXISTS entity_relationships (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id TEXT NOT NULL DEFAULT 'default',
      entity_a_id UUID NOT NULL,
      relationship_type TEXT NOT NULL,
      entity_b_id UUID NOT NULL,
      context TEXT,
      confidence_score REAL DEFAULT 0.8,
      created_at TIMESTAMP NOT NULL DEFAULT NOW()
    )
  `;

  await sql`
    CREATE TABLE IF NOT EXISTS decisions (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id TEXT NOT NULL DEFAULT 'default',
      decision TEXT NOT NULL,
      context TEXT NOT NULL DEFAULT '',
      rationale TEXT NOT NULL DEFAULT '',
      alternatives_considered JSONB DEFAULT '[]',
      source_agent TEXT NOT NULL,
      related_project UUID,
      related_entries JSONB DEFAULT '[]',
      decision_type TEXT NOT NULL DEFAULT 'product',
      status TEXT NOT NULL DEFAULT 'active',
      superseded_by_id UUID,
      created_at TIMESTAMP NOT NULL DEFAULT NOW()
    )
  `;

  await sql`
    CREATE TABLE IF NOT EXISTS conflicts (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id TEXT NOT NULL DEFAULT 'default',
      conflict_type TEXT NOT NULL,
      entries_involved JSONB NOT NULL,
      description TEXT NOT NULL,
      recommended_resolution TEXT,
      confidence TEXT NOT NULL DEFAULT 'medium',
      status TEXT NOT NULL DEFAULT 'open',
      created_at TIMESTAMP NOT NULL DEFAULT NOW(),
      resolved_at TIMESTAMP
    )
  `;

  // William tables
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
      memory_entry_id UUID,
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

  await sql`CREATE INDEX IF NOT EXISTS writing_samples_embedding_idx ON writing_samples USING hnsw (embedding vector_cosine_ops)`;

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

  // Marc tables
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
      memory_entry_id UUID,
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
      memory_entry_id UUID,
      created_at TIMESTAMP NOT NULL DEFAULT NOW(),
      applied_at TIMESTAMP
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

  await sql`CREATE INDEX IF NOT EXISTS email_messages_embedding_idx ON email_messages USING hnsw (embedding vector_cosine_ops)`;

  await sql`
    CREATE TABLE IF NOT EXISTS bolton_agent_summaries (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      agent_id TEXT NOT NULL,
      user_id TEXT NOT NULL DEFAULT 'default',
      summary JSONB NOT NULL,
      session_note TEXT,
      memory_entry_id UUID,
      created_at TIMESTAMP NOT NULL DEFAULT NOW()
    )
  `;

  await sql`ALTER TABLE memory_entries ADD COLUMN IF NOT EXISTS cadence TEXT`;
  await sql`ALTER TABLE memory_entries ADD COLUMN IF NOT EXISTS custom_schedule TEXT`;

  await sql`ALTER TABLE users ADD COLUMN IF NOT EXISTS calendar_access_token TEXT`;
  await sql`ALTER TABLE users ADD COLUMN IF NOT EXISTS calendar_refresh_token TEXT`;
  await sql`ALTER TABLE users ADD COLUMN IF NOT EXISTS calendar_token_expiry TIMESTAMP`;
  await sql`ALTER TABLE users ADD COLUMN IF NOT EXISTS calendar_connected_at TIMESTAMP`;
  await sql`ALTER TABLE users ADD COLUMN IF NOT EXISTS stripe_restricted_key TEXT`;
  await sql`ALTER TABLE users ADD COLUMN IF NOT EXISTS xero_access_token TEXT`;
  await sql`ALTER TABLE users ADD COLUMN IF NOT EXISTS xero_refresh_token TEXT`;
  await sql`ALTER TABLE users ADD COLUMN IF NOT EXISTS xero_token_expiry TIMESTAMP`;
  await sql`ALTER TABLE users ADD COLUMN IF NOT EXISTS xero_tenant_id TEXT`;
  await sql`ALTER TABLE users ADD COLUMN IF NOT EXISTS xero_connected_at TIMESTAMP`;

  await sql`
    CREATE TABLE IF NOT EXISTS george_financial_models (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id TEXT NOT NULL DEFAULT 'default',
      name TEXT NOT NULL,
      model_type TEXT NOT NULL DEFAULT 'general',
      inputs JSONB NOT NULL DEFAULT '{}',
      assumptions JSONB NOT NULL DEFAULT '{}',
      scenarios JSONB NOT NULL DEFAULT '[]',
      conversation JSONB NOT NULL DEFAULT '[]',
      created_at TIMESTAMP NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMP NOT NULL DEFAULT NOW()
    )
  `;

  await sql`
    CREATE TABLE IF NOT EXISTS george_calculators (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id TEXT NOT NULL DEFAULT 'default',
      title TEXT NOT NULL,
      prompt TEXT NOT NULL,
      storage_path TEXT NOT NULL,
      public_url TEXT,
      memory_entry_id UUID,
      created_at TIMESTAMP NOT NULL DEFAULT NOW()
    )
  `;

  await sql`INSERT INTO users (id) VALUES ('default') ON CONFLICT (id) DO NOTHING`;

  // Seed demo data for cross-agent context (locked schemas)
  await sql`
    INSERT INTO bolton_agent_summaries (agent_id, user_id, summary, session_note)
    SELECT 'george', 'default', '{"source_agent":"george","as_of":"2026-07-01","revenue":"AUD 42k MRR (+18% QoQ)","margin_pct":62,"runway_months":14,"burn_rate":"AUD 8.2k/mo","flags":["Stripe payout delay"],"confidence":"high"}'::jsonb, 'Q1 finance review'
    WHERE NOT EXISTS (SELECT 1 FROM bolton_agent_summaries WHERE agent_id = 'george' LIMIT 1)
  `;

  await sql`
    INSERT INTO bolton_agent_summaries (agent_id, user_id, summary, session_note)
    SELECT 'conner', 'default', '{"source_agent":"conner","as_of":"2026-07-01","positioning_update":"11am is the voice-fidelity layer for solo operators — agents that sound like you, not generic AI","target_segment":"Founders building with AI agents who care about authentic output","key_decisions":["Bolton as shared memory before Marc","William leads copy; Robert handles visual handoff"],"confidence":"high"}'::jsonb, 'Strategy session'
    WHERE NOT EXISTS (SELECT 1 FROM bolton_agent_summaries WHERE agent_id = 'conner' LIMIT 1)
  `;

  await sql`
    UPDATE bolton_agent_summaries
    SET summary = '{"source_agent":"george","as_of":"2026-07-01","revenue":"AUD 42k MRR (+18% QoQ)","margin_pct":62,"runway_months":14,"burn_rate":"AUD 8.2k/mo","flags":["Stripe payout delay"],"confidence":"high"}'::jsonb
    WHERE agent_id = 'george' AND NOT (summary ? 'source_agent')
  `;

  await sql`
    UPDATE bolton_agent_summaries
    SET summary = '{"source_agent":"conner","as_of":"2026-07-01","positioning_update":"11am is the voice-fidelity layer for solo operators — agents that sound like you, not generic AI","target_segment":"Founders building with AI agents who care about authentic output","key_decisions":["Bolton as shared memory before Marc","William leads copy; Robert handles visual handoff"],"confidence":"high"}'::jsonb
    WHERE agent_id = 'conner' AND NOT (summary ? 'source_agent')
  `;

  await sql`
    INSERT INTO decisions (user_id, decision, context, rationale, source_agent, decision_type)
    SELECT 'default', 'Build Bolton as shared memory layer before Marc', 'Solo build dashboard sequencing', 'Marc defensibility depends on sender memory in Bolton', 'Conner', 'agent_architecture'
    WHERE NOT EXISTS (SELECT 1 FROM decisions LIMIT 1)
  `;

  // Seed demo memory entries for search/testing (keyword-indexed, no embeddings)
  await sql`
    INSERT INTO memory_entries (user_id, source_agent, entry_type, title, summary, tags, importance_score, confidence)
    SELECT * FROM (VALUES
      ('default', 'Conner', 'decision', 'Bolton before Marc', 'Build shared memory layer before inbox agent — Marc moat depends on Bolton sender memory.', '["decision","architecture"]'::jsonb, 0.9, 'high'),
      ('default', 'William', 'voice', 'Liam voice profile direction', 'Warm, clear, conversational — avoid corporate filler and generic AI phrasing in all copy.', '["voice","william"]'::jsonb, 0.85, 'high'),
      ('default', 'William', 'preference', 'LinkedIn tone preference', 'Hook in first line, no hashtag spam, authentic not performative.', '["linkedin","tone"]'::jsonb, 0.7, 'medium'),
      ('default', 'Marc', 'sender_memory', 'Sender: JC franchisee', 'JC is a franchisee contact — high importance, concise tone, prompt response expected.', '["sender","franchisee"]'::jsonb, 0.8, 'high'),
      ('default', 'Conner', 'project', '11am agent suite', 'Voice-fidelity layer for solo operators — William, Marc, Bolton, Leo as core agents.', '["project","11am"]'::jsonb, 0.85, 'high'),
      ('default', 'George', 'research', 'Q1 revenue snapshot', 'AUD 42k MRR, 18% QoQ growth, 14 months runway, Stripe payout delay flagged.', '["finance","george"]'::jsonb, 0.75, 'high'),
      ('default', 'Bolton', 'reference', 'Memory capture rules', 'Never store secrets or credentials. Supersede instead of delete. Link related entries.', '["bolton","policy"]'::jsonb, 0.9, 'high'),
      ('default', 'William', 'task', 'Weekly LinkedIn post', 'Draft LinkedIn post about voice fidelity as moat — include business context from George.', '["task","william","cadence:weekly"]'::jsonb, 0.6, 'medium'),
      ('default', 'Marc', 'task', 'Daily inbox review', 'Review unread inbox, triage high-priority senders, draft replies for needs_reply items.', '["task","marc","cadence:daily"]'::jsonb, 0.65, 'medium'),
      ('default', 'James', 'research', 'Competitor voice tools scan', 'Most AI writing tools optimize for generic output — differentiation is voice fidelity and sender memory.', '["research","competitive"]'::jsonb, 0.6, 'medium'),
      ('default', 'Conner', 'preference', 'Platform language', 'Say voice fidelity not AI writing assistant — emphasize authentic output over speed.', '["positioning","language"]'::jsonb, 0.7, 'medium'),
      ('default', 'William', 'output', 'Launch announcement draft', '11am is live — agents that sound like you, starting with William for copy and Marc for inbox.', '["announcement","launch"]'::jsonb, 0.5, 'medium'),
      ('default', 'Marc', 'preference', 'Inbox rule: newsletters', 'Auto-archive promotional newsletters after reading — never touch billing or security emails.', '["inbox","rules"]'::jsonb, 0.7, 'medium'),
      ('default', 'Leo', 'task', 'Weekly planning sync', 'Review scheduled agent tasks and calendar cadence from William and Marc.', '["task","leo","cadence:weekly"]'::jsonb, 0.6, 'medium'),
      ('default', 'Bolton', 'person', 'Liam Turner', 'Founder and sole user of 11am debug build — all agents serve Liam only for now.', '["person","founder"]'::jsonb, 0.95, 'high'),
      ('default', 'Robert', 'reference', 'Brand guidelines July 2026', 'Dark ask bars with inverted monogram, editorial white space, warm not corporate.', '["brand","design"]'::jsonb, 0.8, 'high'),
      ('default', 'William', 'research', 'Email platform rules', 'Email copy: professional but personal, subject line when appropriate, no preamble.', '["email","platform"]'::jsonb, 0.55, 'medium'),
      ('default', 'Marc', 'decision', 'Gmail Testing mode OAuth', 'Keep Google Cloud app in Testing with Liam as sole test user — no CASA until second user.', '["gmail","oauth"]'::jsonb, 0.85, 'high'),
      ('default', 'Conner', 'project', 'William voice RAG', 'pgvector writing samples for few-shot retrieval at generation time — edits feed back into store.', '["william","rag"]'::jsonb, 0.75, 'medium'),
      ('default', 'George', 'reference', 'Burn rate baseline', 'AUD 8.2k monthly burn — monitor against MRR growth for runway projections.', '["finance","burn"]'::jsonb, 0.7, 'medium'),
      ('default', 'Bolton', 'preference', 'Notion parallel archive', 'Postgres is operational source; Notion is long-term brain — sync on save, archive on supersede.', '["notion","sync"]'::jsonb, 0.65, 'medium'),
      ('default', 'Marc', 'sender_memory', 'Sender: billing@stripe.com', 'Stripe billing notifications — protected from cleanup, finance-relevant, do not unsubscribe.', '["sender","billing","protected"]'::jsonb, 0.9, 'high')
    ) AS v(user_id, source_agent, entry_type, title, summary, tags, importance_score, confidence)
    WHERE (SELECT count(*) FROM memory_entries) < 5
  `;

  await sql`
    UPDATE memory_entries SET cadence = 'weekly'
    WHERE entry_type = 'task' AND title ILIKE '%Weekly%' AND cadence IS NULL
  `;
  await sql`
    UPDATE memory_entries SET cadence = 'daily'
    WHERE entry_type = 'task' AND title ILIKE '%Daily%' AND cadence IS NULL
  `;

  await sql`
    INSERT INTO entities (user_id, entity_type, name, summary, importance_level)
    SELECT * FROM (VALUES
      ('default', 'person', 'Liam Turner', 'Founder and sole 11am user', 'high'),
      ('default', 'project', '11am agent suite', 'Voice-fidelity agent platform for solo operators', 'high'),
      ('default', 'project', 'William voice RAG', 'pgvector writing sample retrieval for copy generation', 'medium'),
      ('default', 'person', 'JC franchisee', 'Franchisee contact — high importance sender for Marc', 'high'),
      ('default', 'concept', 'Voice fidelity', 'Core positioning — authentic output over generic AI', 'high')
    ) AS v(user_id, entity_type, name, summary, importance_level)
    WHERE (SELECT count(*) FROM entities) < 2
  `;

  console.log("Shared 11am schema ready.");
  await sql.end();
}

migrate().catch((err) => {
  console.error(err);
  process.exit(1);
});
