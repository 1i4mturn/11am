# William - 11am Writing Agent

Web-first writing agent that produces copy in the user's authentic voice. Voice profiles are assembled from real outputs (emails, documents, posts) and stored in Bolton's shared memory layer.

## Stack

- **Next.js 16** - App Router, TypeScript, Tailwind
- **@11am/ui** - Shared design system
- **PostgreSQL + pgvector** - Writing sample embeddings and voice profile storage
- **Bolton** - Shared memory layer (voice profiles, George/Conner summaries)
- **Claude Sonnet** - Generation and voice analysis (Anthropic API)
- **OpenAI embeddings** - text-embedding-3-small for RAG retrieval
- **Gmail OAuth** - Sent mail ingestion (highest-value training data)

## Quick start

```bash
# Start shared Postgres (from Bolton project)
cd ~/Projects/11am/apps/bolton && docker compose up -d && npm run db:migrate

# Install dependencies
npm install

# Copy env and add API keys
cp .env.example .env.local

# Start dev server
npm run dev
```

Open [http://localhost:3000](http://localhost:3000).

**Shared Bolton:** All agents share `DATABASE_URL=postgresql://elevenam:elevenam@localhost:5435/elevenam`. See `~/Projects/11am/README.md`.

## Features (v1)

| Feature | Free | Pro |
|---------|------|-----|
| Copy generation | ✓ (10/month) | ✓ unlimited |
| Platform selector | ✓ | ✓ |
| Basic tone guidance | ✓ | ✓ |
| Living voice profile | - | ✓ |
| Asset ingestion | - | ✓ |
| Gmail OAuth | - | ✓ |
| Cross-agent context | - | ✓ |
| Edit → vector store learning | - | ✓ |
| Voice drift detection | - | ✓ |

Use the **Switch to Pro** toggle on the Write page for local testing (no payment integration in v1).

## Architecture

```
User writing → Ingestion → Voice Profile (Bolton) + Vector Store (pgvector)
                                    ↓
Prompt + Platform + RAG examples + Bolton context → Claude → Copy-ready output
                                    ↓
User edits → High-signal sample + async profile update job
```

## API routes

- `POST /api/generate` - Generate copy
- `GET/POST /api/voice-profile` - Profile status / text ingestion
- `POST /api/ingest` - Paste, upload, URL ingestion
- `POST /api/edits` - Log edits back to vector store
- `GET /api/bolton/context` - George + Conner summaries
- `GET /api/bolton/voice-profile` - Voice profile for cross-agent reads (Robert, etc.)
- `GET/POST /api/gmail` - OAuth status + sent mail sync
- `GET/POST /api/tier` - Tier management

## Environment variables

See `.env.example`. Required for generation:

- `ANTHROPIC_API_KEY`
- `OPENAI_API_KEY`
- `DATABASE_URL` (defaults to local Docker Postgres)

Gmail requires Google Cloud OAuth credentials with Gmail readonly scope.
