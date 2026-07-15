# Marc - 11am Inbox Agent

Relationship-aware inbox intelligence over Gmail. Marc triages email, maintains sender memory in Bolton, drafts replies using William's voice profile, and routes cross-agent handoffs.

## Stack

- **Next.js 16** - App Router, TypeScript, Tailwind
- **@11am/ui** - Shared design system
- **PostgreSQL + pgvector** - Hybrid email index (metadata + vector search)
- **Bolton** - Sender memory, inbox rules, cross-agent memories
- **William** - Voice profile pulled from Bolton for reply drafting
- **Claude Sonnet** - Triage, search parsing, briefings, rule proposals
- **Gmail OAuth** - Read, modify, send (with explicit user confirmation)

## Quick start

```bash
# Start shared Postgres (from Bolton project)
cd ~/Projects/11am/apps/bolton && docker compose up -d && npm run db:migrate

# Install dependencies
npm install

# Copy env and add API keys
cp .env.example .env.local

# Start dev server (port 3001 - William uses 3000)
npm run dev
```

Open [http://localhost:3001](http://localhost:3001).

**Shared Bolton:** Marc reads William's voice profile and writes sender memory to the shared Bolton database. See `~/Projects/11am/README.md`.

## Features (v1)

| Feature | Free | Pro |
|---------|------|-----|
| Gmail OAuth + sync | ✓ | ✓ |
| Inbox triage | ✓ (limited) | ✓ unlimited |
| Thread summaries | ✓ | ✓ |
| Simple reply drafting | ✓ | ✓ |
| Basic metadata search | ✓ | ✓ |
| Daily/weekly briefing | ✓ (limited) | ✓ full |
| Sender memory | - | ✓ |
| William voice integration | - | ✓ |
| Semantic search | - | ✓ |
| Bulk cleanup | - | ✓ |
| Inbox rule builder | - | ✓ |
| Cross-agent handoffs | - | ✓ |

Use **Switch to Pro** on the Inbox page for local testing.

## Safety model

Marc **never** sends, archives, deletes, unsubscribes, or applies rules without explicit user confirmation. All mutations are logged in `action_log` for rollback visibility.
