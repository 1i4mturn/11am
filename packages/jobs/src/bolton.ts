import type { JobsConfig } from "./types";

export interface BoltonContextPack {
  architecture?: Record<string, unknown>;
  brand_system?: Record<string, unknown>;
  strategy_brief?: Record<string, unknown>;
  prior_build?: Record<string, unknown>;
  raw_entries: Array<{ title: string; summary: string; tags?: string[] }>;
}

async function boltonFetch(
  base: string,
  path: string,
  init?: RequestInit
): Promise<Response> {
  return fetch(`${base}${path}`, {
    ...init,
    headers: { "Content-Type": "application/json", ...init?.headers },
  });
}

export async function fetchBoltonContext(
  config: JobsConfig,
  task: string
): Promise<BoltonContextPack> {
  const pack: BoltonContextPack = { raw_entries: [] };

  try {
    const ctxRes = await boltonFetch(config.boltonApiUrl, "/api/context", {
      method: "POST",
      body: JSON.stringify({ requesting_agent: "Johnny", task }),
    });
    if (ctxRes.ok) {
      const data = await ctxRes.json();
      pack.architecture = data.context_pack?.architecture;
      pack.prior_build = data.context_pack?.prior_build;
      if (Array.isArray(data.entries)) {
        pack.raw_entries = data.entries.map(
          (e: { title?: string; summary?: string; tags?: string[] }) => ({
            title: e.title ?? "",
            summary: e.summary ?? "",
            tags: e.tags,
          })
        );
      }
    }
  } catch {
    // continue
  }

  try {
    const brandRes = await boltonFetch(
      config.boltonApiUrl,
      "/api/agent-summaries?agent_id=robert"
    );
    if (brandRes.ok) {
      const data = await brandRes.json();
      pack.brand_system = data.summary?.summary ?? data.summary;
    }
  } catch {
    // continue
  }

  try {
    const stratRes = await boltonFetch(
      config.boltonApiUrl,
      "/api/agent-summaries?agent_id=conner"
    );
    if (stratRes.ok) {
      const data = await stratRes.json();
      pack.strategy_brief = data.summary?.summary ?? data.summary;
    }
  } catch {
    // continue
  }

  if (pack.raw_entries.length === 0) {
    pack.raw_entries.push({
      title: "Bolton offline",
      summary: "Context fetch unavailable — job continues with repo-only analysis.",
      tags: ["fallback"],
    });
  }

  return pack;
}

export function boltonContextBlock(pack: BoltonContextPack): string {
  return JSON.stringify(
    {
      architecture: pack.architecture,
      brand_system: pack.brand_system,
      strategy_brief: pack.strategy_brief,
      prior_build: pack.prior_build,
      recent_entries: pack.raw_entries.slice(0, 8),
    },
    null,
    2
  );
}
