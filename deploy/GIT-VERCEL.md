# Deploy 11am via GitHub → Vercel

**Use this.** Skip `npm run deploy:all` (CLI loop, 12 projects, painful).

One GitHub repo. Add Vercel projects in the browser — each `git push` redeploys automatically.

## Quick start (home dashboard only)

```bash
cd ~/Projects/11am
git push origin main          # make sure latest code is on GitHub
npm run deploy:git            # prints exact steps
```

Then in the browser:

1. [vercel.com/new](https://vercel.com/new) → **Import** `1i4mturn/11am`
2. **Project Name:** `11am-suite`
3. **Root Directory:** `apps/home` (click Edit, type the path)
4. **Deploy**

Home loads without env vars. Agent sidebar links point at localhost until you deploy more apps.

## Add Bolton (memory API)

```bash
npm run deploy:git bolton
```

Same import flow, new project:

- **Project Name:** `11am-suite-bolton`
- **Root Directory:** `apps/bolton`
- **Env:** `DATABASE_URL` = your Neon pooled URL

## Add more agents later

Same pattern: `apps/leo`, `apps/marc`, etc. One Vercel project per app, all from the **same Git repo**. Only add what you need — no need for all 12 on day one.

| App | Root Directory | Extra env |
|-----|----------------|-----------|
| home | `apps/home` | `NEXT_PUBLIC_HOME_URL` (after deploy) |
| bolton | `apps/bolton` | `DATABASE_URL` |
| leo, marc, william, george | `apps/<name>` | `DATABASE_URL` |
| others | `apps/<name>` | `BOLTON_API_URL` |

After several agents are live, paste `deploy/home-vercel.env` into the **11am-suite** project env vars and redeploy home.

## Monorepo checkbox

When you set **Root Directory** to e.g. `apps/home`, Vercel may show:

> Include source files outside of the Root Directory in the Build Step

Leave it **on** (often default). Location: **Settings → Build and Deployment → Root Directory** — only visible after a root path is set.

If you don’t see it, that’s fine — Git imports usually handle `packages/ui` automatically.

## Clean up CLI mess (optional)

If `npm run deploy:all` created broken projects, delete them in Vercel dashboard and re-import via Git above.

## Local dev unchanged

```bash
npm start              # home + bolton + leo + marc
npm run start:extended # + william + george
```
