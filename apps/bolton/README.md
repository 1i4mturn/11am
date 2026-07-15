# Bolton - 11am Memory Layer

Curated institutional memory for the 11am agent suite. Bolton decides what to save, where it belongs, and what it supersedes.

## Stack

- **Next.js 16** - Memory review UI + shared API
- **@11am/ui** - Shared design system
- **PostgreSQL + pgvector** - Shared database for William, Marc, and Bolton
- **Claude Sonnet** - Capture classification, conflict detection, search parsing
- **OpenAI embeddings** - Semantic memory retrieval

## Quick start (start here for the whole suite)

```bash
cd ~/Projects/11am/apps/bolton

# Start shared Postgres - all three agents use this
docker compose up -d
npm install
cp .env.example .env.local
npm run db:migrate

# Terminal 1 - Bolton (memory layer)
npm run dev   # http://localhost:3002

# Terminal 2 - William
cd ~/Projects/11am/apps/william && npm run dev   # http://localhost:3000

# Terminal 3 - Marc
cd ~/Projects/11am/apps/marc && npm run dev      # http://localhost:3001
```

All apps use: `DATABASE_URL=postgresql://elevenam:elevenam@localhost:5435/elevenam`

See `~/Projects/11am/README.md` for the full setup guide.

## Architecture

```
William ──writes──► Voice profiles, accepted outputs
Marc    ──writes──► Sender memory, inbox rules, thread summaries
Conner  ──writes──► Strategy decisions, commercial context
George  ──writes──► Financial summaries
         │
         ▼
    BOLTON (memory_entries + entities + decisions)
         │
         ▼
All agents read context packs, search memory, retrieve entities
```

## Agent integration

William and Marc call Bolton via `BOLTON_API_URL=http://localhost:3002`:

- William writes voice profile updates to `/api/memory`
- Marc writes sender memory to `/api/memory`
- Marc reads person context from `/api/entities?q=...`
- Any agent can request context packs from `/api/context`
