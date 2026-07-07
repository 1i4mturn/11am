# 11am — Quick start

## Every time — one command

```bash
cd ~/Projects/11am
npm start
```

| App | URL |
|-----|-----|
| William | http://localhost:3000 |
| Marc | http://localhost:3001 |
| Bolton | http://localhost:3002 |

Press **Ctrl+C** to stop everything.

If a port is stuck or localhost won't load:

```bash
npm run stop
npm start
```

**No inline comments** on the same line as commands (e.g. don't write `npm start # comment`).

---

## Database (for memory, inbox, voice profiles)

The apps need **Docker Desktop** for the shared Postgres database.

1. Install [Docker Desktop for Mac](https://docs.docker.com/desktop/setup/install/mac-install/)
2. Open Docker Desktop and wait until it says **Docker is running**
3. Run once:

```bash
cd ~/Projects/11am
npm run db
```

After that, `npm start` will start the database automatically.

**No Docker?** `npm start` still launches all three UIs — you just won't have shared memory until Docker is set up.

---

## First time

```bash
cd ~/Projects/11am
npm install
npm start
```

`.env.local` files are created automatically. Add API keys when you want AI features.

## Other commands

| Command | What it does |
|---------|----------------|
| `npm run db` | Start database + run migrations (needs Docker) |
| `npm run dev` | Dev servers only, no database step |
| `npm run build` | Production build check for all apps |
