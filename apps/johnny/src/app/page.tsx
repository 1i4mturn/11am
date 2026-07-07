"use client";

import { Badge, Button, Card, PageHeader } from "@11am/ui";
import { useCallback, useEffect, useState } from "react";
import { AskJohnnyBar } from "@/components/AskJohnnyBar";
import { JobMonitor } from "@/components/JobMonitor";
import type { ReviewResult } from "@/lib/types";

type Mode = "review" | "build_job";

interface GitHubRepo {
  full_name: string;
  default_branch: string;
}

export default function BuildPage() {
  const [mode, setMode] = useState<Mode>("review");
  const [query, setQuery] = useState(
    "Review the apps/johnny scaffold for consistency with other agent apps"
  );
  const [diff, setDiff] = useState("");
  const [useLocalRepo, setUseLocalRepo] = useState(true);
  const [githubRepo, setGithubRepo] = useState("");
  const [repos, setRepos] = useState<GitHubRepo[]>([]);
  const [review, setReview] = useState<ReviewResult | null>(null);
  const [loading, setLoading] = useState(false);
  const [notice, setNotice] = useState("");
  const [error, setError] = useState("");
  const [selectedJobId, setSelectedJobId] = useState<string | null>(null);
  const [estimate, setEstimate] = useState<{
    estimated_tokens: number;
    estimated_usd: number;
  } | null>(null);

  const loadRepos = useCallback(async () => {
    const res = await fetch("/api/github/repos");
    if (res.ok) {
      const data = await res.json();
      setRepos(data.repos ?? []);
      if (data.repos?.[0]) setGithubRepo(data.repos[0].full_name);
    }
  }, []);

  useEffect(() => {
    loadRepos();
  }, [loadRepos]);

  async function handleAsk() {
    if (!query.trim()) return;
    setLoading(true);
    setError("");
    setReview(null);
    setEstimate(null);

    try {
      if (mode === "review") {
        const body: Record<string, unknown> = { prompt: query.trim() };
        if (diff.trim()) body.diff = diff.trim();

        if (!diff.trim() && githubRepo && !useLocalRepo) {
          const [owner, repo] = githubRepo.split("/");
          body.github = { owner, repo, base: "main", head: "main" };
        }

        const res = await fetch("/api/review", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(body),
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error);
        setReview(data.result);
      } else {
        const repoBody = useLocalRepo
          ? { type: "local", path: undefined }
          : githubRepo
            ? {
                type: "github",
                owner: githubRepo.split("/")[0],
                repo: githubRepo.split("/")[1],
                ref: repos.find((r) => r.full_name === githubRepo)?.default_branch ?? "main",
              }
            : { type: "local" };

        const res = await fetch("/api/jobs", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ prompt: query.trim(), repo: repoBody }),
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error);
        setSelectedJobId(data.job.id);
        setEstimate(data.estimate);
        setNotice(`Build job queued: ${data.job.id.slice(0, 8)}…`);
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : "Request failed");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="am-section space-y-6">
      <PageHeader
        title="Build"
        description="Code review, async sandboxed build jobs, and suite-wide job infrastructure."
      />

      <Card padding="md">
        <p className="am-label mb-2">architecture</p>
        <p className="am-copy text-sm text-[var(--am-muted)]">
          Anthropic tool-use inside Docker-isolated workers. Per-job repo scoping, hard token/time/cost
          budgets with kill switch. Review-at-completion only in v1. Queue designed for Leo + Cole reuse.
        </p>
      </Card>

      <div className="flex flex-wrap gap-2">
        {(
          [
            { value: "review" as const, label: "Code review" },
            { value: "build_job" as const, label: "Async build job" },
          ] as const
        ).map((m) => (
          <button
            key={m.value}
            type="button"
            onClick={() => setMode(m.value)}
            className={`am-btn am-copy px-3 py-1.5 text-xs ${
              mode === m.value ? "am-btn-primary" : "am-btn-secondary"
            }`}
          >
            {m.label}
          </button>
        ))}
      </div>

      {mode === "review" && (
        <Card padding="md" className="space-y-3">
          <p className="am-label">optional diff</p>
          <textarea
            value={diff}
            onChange={(e) => setDiff(e.target.value)}
            placeholder="Paste a git diff, or leave empty to snapshot local repo"
            className="am-input min-h-24 w-full px-4 py-2 font-mono text-xs"
          />
        </Card>
      )}

      <Card padding="md" className="space-y-3">
        <p className="am-label">repo scope</p>
        <div className="flex flex-wrap gap-2">
          <button
            type="button"
            onClick={() => setUseLocalRepo(true)}
            className={`am-btn am-copy px-3 py-1.5 text-xs ${
              useLocalRepo ? "am-btn-primary" : "am-btn-secondary"
            }`}
          >
            Local (LiamOS)
          </button>
          <button
            type="button"
            onClick={() => setUseLocalRepo(false)}
            className={`am-btn am-copy px-3 py-1.5 text-xs ${
              !useLocalRepo ? "am-btn-primary" : "am-btn-secondary"
            }`}
          >
            GitHub
          </button>
        </div>
        {!useLocalRepo && (
          <select
            value={githubRepo}
            onChange={(e) => setGithubRepo(e.target.value)}
            className="am-input w-full px-4 py-2 text-sm"
          >
            {repos.map((r) => (
              <option key={r.full_name} value={r.full_name}>
                {r.full_name}
              </option>
            ))}
          </select>
        )}
        {repos.length === 0 && !useLocalRepo && (
          <p className="am-copy text-sm text-[var(--am-muted)]">
            Set GITHUB_TOKEN in .env.local to list repos
          </p>
        )}
      </Card>

      <AskJohnnyBar
        value={query}
        onChange={setQuery}
        onAsk={handleAsk}
        loading={loading}
        onScheduled={setNotice}
        taskType={mode === "review" ? "review" : "build_job"}
      />

      {estimate && mode === "build_job" && (
        <Card padding="md">
          <p className="am-label mb-2">cost estimate</p>
          <p className="am-copy text-sm">
            ~{estimate.estimated_tokens.toLocaleString()} tokens · ~$
            {estimate.estimated_usd.toFixed(2)} (hard budget enforced)
          </p>
        </Card>
      )}

      {notice && <p className="am-copy text-sm">{notice}</p>}
      {error && <p className="am-copy am-error text-sm">{error}</p>}

      {review && (
        <Card padding="lg" className="space-y-4">
          <p className="am-label">review</p>
          <p className="am-copy text-sm">{review.summary}</p>
          {review.findings?.length > 0 && (
            <ul className="am-copy space-y-2 text-sm">
              {review.findings.map((f, i) => (
                <li key={i} className="flex gap-2">
                  <Badge tone={f.severity === "high" ? "high" : "low"}>{f.severity}</Badge>
                  <span>
                    {f.file ? `${f.file}: ` : ""}
                    {f.message}
                  </span>
                </li>
              ))}
            </ul>
          )}
          {review.architecture_notes && (
            <p className="am-copy text-sm text-[var(--am-muted)]">{review.architecture_notes}</p>
          )}
        </Card>
      )}

      <JobMonitor selectedJobId={selectedJobId} onSelectJob={setSelectedJobId} />
    </div>
  );
}
