import { readFile } from "fs/promises";
import path from "path";
import { runInSandbox } from "../sandbox";

export interface SeoCheckResult {
  semantic_html: { issues: string[]; score: number };
  schema_markup: { found: string[]; missing: string[] };
  crawlability: { robots_txt: boolean; sitemap: boolean; notes: string[] };
  pagespeed?: { score: number; metrics: Record<string, number>; error?: string };
  summary: string;
}

async function scanHtmlFiles(workspacePath: string): Promise<string[]> {
  const targets = ["index.html", "apps/home/src/app/page.tsx", "src/app/page.tsx"];
  const contents: string[] = [];
  for (const t of targets) {
    try {
      contents.push(await readFile(path.join(workspacePath, t), "utf-8"));
    } catch {
      // skip
    }
  }
  return contents;
}

export async function runSeoReview(
  sandboxImage: string,
  workspacePath: string,
  siteUrl?: string,
  pagespeedApiKey?: string
): Promise<SeoCheckResult> {
  const htmlFiles = await scanHtmlFiles(workspacePath);
  const combined = htmlFiles.join("\n");

  const semantic_issues: string[] = [];
  if (!combined.includes("<main")) semantic_issues.push("Missing <main> landmark");
  if (!combined.includes("<h1")) semantic_issues.push("Missing <h1>");
  if (!combined.includes("alt=")) semantic_issues.push("Images may lack alt attributes");

  const schema_found: string[] = [];
  const schema_missing: string[] = [];
  if (combined.includes("application/ld+json")) schema_found.push("JSON-LD");
  else schema_missing.push("JSON-LD structured data");
  if (combined.includes("og:")) schema_found.push("Open Graph");
  else schema_missing.push("Open Graph meta tags");

  const robots = await runInSandbox(sandboxImage, workspacePath, [
    "sh",
    "-c",
    "test -f public/robots.txt || test -f robots.txt && echo yes || echo no",
  ]);
  const sitemap = await runInSandbox(sandboxImage, workspacePath, [
    "sh",
    "-c",
    "test -f public/sitemap.xml || test -f sitemap.xml && echo yes || echo no",
  ]);

  const crawl_notes: string[] = [];
  if (robots.stdout.trim() === "yes") crawl_notes.push("robots.txt present");
  else crawl_notes.push("robots.txt missing");

  let pagespeed: SeoCheckResult["pagespeed"];
  if (siteUrl && pagespeedApiKey) {
    try {
      const url = `https://www.googleapis.com/pagespeedonline/v5/runPagespeed?url=${encodeURIComponent(siteUrl)}&category=PERFORMANCE&strategy=MOBILE&key=${pagespeedApiKey}`;
      const res = await fetch(url);
      if (res.ok) {
        const data = (await res.json()) as {
          lighthouseResult?: {
            categories?: { performance?: { score?: number } };
            audits?: Record<string, { numericValue?: number }>;
          };
        };
        const score = data.lighthouseResult?.categories?.performance?.score ?? 0;
        const audits = data.lighthouseResult?.audits ?? {};
        pagespeed = {
          score: Math.round(score * 100),
          metrics: {
            lcp: audits["largest-contentful-paint"]?.numericValue ?? 0,
            cls: audits["cumulative-layout-shift"]?.numericValue ?? 0,
            inp: audits["interaction-to-next-paint"]?.numericValue ?? 0,
          },
        };
      }
    } catch (e) {
      pagespeed = { score: 0, metrics: {}, error: String(e) };
    }
  }

  const semantic_score = Math.max(0, 100 - semantic_issues.length * 20);

  return {
    semantic_html: { issues: semantic_issues, score: semantic_score },
    schema_markup: { found: schema_found, missing: schema_missing },
    crawlability: {
      robots_txt: robots.stdout.trim() === "yes",
      sitemap: sitemap.stdout.trim() === "yes",
      notes: crawl_notes,
    },
    pagespeed,
    summary: `SEO review: semantic ${semantic_score}/100, schema ${schema_found.length} found, ${schema_missing.length} missing.`,
  };
}
