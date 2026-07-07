import path from "path";
import { readFile, readdir } from "fs/promises";
import {
  fetchRepoDiff,
  fetchBoltonContext,
  boltonContextBlock,
} from "@11am/jobs";
import { askJohnny, extractJson } from "@/lib/claude";
import type { ReviewInput, ReviewResult } from "@/lib/types";

async function collectRepoSnapshot(repoPath: string, maxFiles = 12): Promise<string> {
  const parts: string[] = [];
  const targets = ["package.json", "tsconfig.json", "README.md", "src/app/page.tsx"];

  for (const t of targets) {
    try {
      const content = await readFile(path.join(repoPath, t), "utf-8");
      parts.push(`--- ${t}\n${content.slice(0, 4000)}`);
    } catch {
      // skip
    }
  }

  try {
    const appsDir = path.join(repoPath, "apps");
    const apps = await readdir(appsDir);
    parts.push(`apps/: ${apps.slice(0, maxFiles).join(", ")}`);
  } catch {
    // skip
  }

  return parts.join("\n\n");
}

export async function runCodeReview(input: ReviewInput): Promise<ReviewResult> {
  const boltonPack = await fetchBoltonContext(
    {
      dataDir: "",
      boltonApiUrl: process.env.BOLTON_API_URL ?? "http://localhost:3002",
      anthropicApiKey: process.env.ANTHROPIC_API_KEY ?? "",
      githubToken: process.env.GITHUB_TOKEN,
      sandboxImage: process.env.SANDBOX_IMAGE ?? "11am-job-sandbox:latest",
    },
    input.prompt
  );

  let diffOrSnapshot = input.diff ?? "";

  if (!diffOrSnapshot && input.github) {
    const token = process.env.GITHUB_TOKEN;
    if (!token) throw new Error("GITHUB_TOKEN required for GitHub diff review");
    diffOrSnapshot = await fetchRepoDiff(
      token,
      input.github.owner,
      input.github.repo,
      input.github.base,
      input.github.head
    );
  }

  if (!diffOrSnapshot && input.repo_path) {
    diffOrSnapshot = await collectRepoSnapshot(input.repo_path);
  }

  if (!diffOrSnapshot) {
    throw new Error("Provide diff, repo_path, or github compare params");
  }

  const raw = await askJohnny(
    `Bolton context:\n${boltonContextBlock(boltonPack)}\n\nReturn JSON: { summary, findings: [{ severity, file?, message }], suggestions: [], architecture_notes }`,
    `Review request: ${input.prompt}\n\n--- CODE / DIFF ---\n${diffOrSnapshot.slice(0, 80_000)}`
  );

  const parsed = extractJson<ReviewResult>(raw);
  if (parsed) return { ...parsed, raw };

  return {
    summary: raw.slice(0, 500),
    findings: [],
    suggestions: [],
    architecture_notes: "",
    raw,
  };
}

export async function runHandoff(body: {
  from_agent: string;
  task: string;
  priority: string;
}): Promise<{ summary: string }> {
  const result = await runCodeReview({ prompt: body.task });
  return { summary: result.summary };
}
