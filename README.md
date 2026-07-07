# 11am — Local Development

Monorepo for the 11am agent suite. Three apps, one shared memory layer, one design system.

## Quick start

```bash
cd ~/Projects/11am
npm start
```

That's it. Database + all three apps start in one terminal. See [START.md](./START.md) for details.

| App | URL |
|-----|-----|
| William (writing) | http://localhost:3000 |
| Marc (inbox) | http://localhost:3001 |
| Bolton (memory) | http://localhost:3002 |

Press **Ctrl+C** to stop.

## First-time setup

If `npm start` fails on a fresh machine:

```bash
cd ~/Projects/11am
npm run setup
```

Then add API keys to `apps/*/.env.local` when you need AI features.

## Design system

`@11am/ui` in `packages/ui` — Robert's locked decisions:
- Alte Haas Grotesk (TTF bundled in package)
- Papery white `#faf9f7`, graphite copy `#2f2f2f`
- Agent monogram SVGs, multi-layer grain, embossed logos
- Editorial `PageHeader` typography from v5 mockup

## Data flow

- **William** → voice profiles → Bolton `memory_entries` + `bolton_voice_profiles`
- **Marc** → sender memory → Bolton `memory_entries` + `bolton_sender_profiles`
- **Bolton** → curates, searches, context packs for all agents
