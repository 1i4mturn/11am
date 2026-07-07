"use client";

import { Badge, Button, Card, PageHeader } from "@11am/ui";
import { useState } from "react";
import { AskConnerBar } from "@/components/AskConnerBar";
import type { WorkflowType } from "@/lib/types";

const WORKFLOWS: { value: WorkflowType; label: string; description: string }[] = [
  {
    value: "idea_validation",
    label: "Idea validation",
    description: "Validate a business idea and draft an offer — standalone, no Bolton required",
  },
  {
    value: "stress_test",
    label: "Stress test",
    description: "Stress-test a model against George's latest numbers (Bolton or mock)",
  },
  {
    value: "gtm",
    label: "GTM / launch",
    description: "Go-to-market plan with optional James market research from Bolton",
  },
  {
    value: "growth",
    label: "Growth strategy",
    description: "Growth levers synthesising George + James Bolton context",
  },
  {
    value: "pricing",
    label: "Pricing",
    description: "Pricing strategy from George unit economics + James pricing research",
  },
  {
    value: "digest",
    label: "Weekly digest",
    description: "On-demand health digest across available agent summaries",
  },
];

const DEFAULT_PROMPTS: Record<WorkflowType, string> = {
  idea_validation:
    "Voice-fidelity AI writing suite for solo founders — multi-agent OS that sounds like you, not generic AI",
  stress_test:
    "11am agent suite at AUD 24/mo with 200 paying users target in 12 months",
  gtm: "Soft launch 11am to indie hacker communities and creator newsletters",
  growth: "Grow MRR from 8k to 25k in 6 months without paid ads",
  pricing: "Price the 11am agent suite for solo founders — subscription vs usage hybrid",
  digest: "",
};

const API_ROUTES: Record<WorkflowType, string> = {
  idea_validation: "/api/validate",
  stress_test: "/api/stress-test",
  gtm: "/api/gtm",
  growth: "/api/growth",
  pricing: "/api/pricing",
  digest: "/api/digest",
};

const BODY_KEYS: Record<WorkflowType, string> = {
  idea_validation: "idea",
  stress_test: "idea_or_model",
  gtm: "brief",
  growth: "focus",
  pricing: "context",
  digest: "",
};

export default function StrategyPage() {
  const [workflow, setWorkflow] = useState<WorkflowType>("idea_validation");
  const [query, setQuery] = useState(DEFAULT_PROMPTS.idea_validation);
  const [result, setResult] = useState<Record<string, unknown> | null>(null);
  const [loading, setLoading] = useState(false);
  const [notice, setNotice] = useState("");
  const [error, setError] = useState("");
  const [jamesTask, setJamesTask] = useState("");
  const [jamesLoading, setJamesLoading] = useState(false);
  const [strategyWritten, setStrategyWritten] = useState(false);

  function selectWorkflow(w: WorkflowType) {
    setWorkflow(w);
    setQuery(DEFAULT_PROMPTS[w]);
    setResult(null);
    setError("");
    setStrategyWritten(false);
  }

  async function handleAsk() {
    if (workflow !== "digest" && !query.trim()) return;
    setLoading(true);
    setError("");
    setResult(null);
    setStrategyWritten(false);

    try {
      const route = API_ROUTES[workflow];
      const bodyKey = BODY_KEYS[workflow];
      const body =
        workflow === "digest"
          ? undefined
          : { [bodyKey]: query.trim() };

      const res = await fetch(route, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: body ? JSON.stringify(body) : undefined,
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);

      setResult(data.result);

      if (workflow !== "digest" && workflow !== "idea_validation") {
        const narrative = String(
          (data.result as { narrative?: string }).narrative ??
            JSON.stringify(data.result, null, 2)
        );
        const strategyRes = await fetch("/api/strategy", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ session_summary: `${workflow}: ${query}\n\n${narrative}` }),
        });
        if (strategyRes.ok) setStrategyWritten(true);
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : "Request failed");
    } finally {
      setLoading(false);
    }
  }

  async function handleJamesInvoke() {
    if (!jamesTask.trim()) return;
    setJamesLoading(true);
    setError("");
    try {
      const res = await fetch("/api/invoke-james", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ task: jamesTask.trim() }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);
      setNotice(`James: ${data.result.summary}`);
    } catch (e) {
      setError(e instanceof Error ? e.message : "James invoke failed");
    } finally {
      setJamesLoading(false);
    }
  }

  function renderResult() {
    if (!result) return null;
    const r = result as Record<string, unknown>;

    if (workflow === "idea_validation") {
      const offer = r.offer as Record<string, string> | undefined;
      return (
        <>
          <div className="flex flex-wrap gap-2">
            <Badge tone={r.verdict === "pursue" ? "high" : r.verdict === "kill" ? "medium" : "low"}>
              {String(r.verdict)}
            </Badge>
            <Badge tone="low">{String(r.confidence)} confidence</Badge>
          </div>
          <Card padding="lg">
            <p className="am-label mb-2">Reasoning</p>
            <p className="am-copy text-sm">{String(r.reasoning)}</p>
            {offer && (
              <>
                <p className="am-label mb-2 mt-6">Offer draft</p>
                <ul className="am-copy space-y-1 text-sm">
                  <li><strong>Headline:</strong> {offer.headline}</li>
                  <li><strong>Promise:</strong> {offer.promise}</li>
                  <li><strong>Audience:</strong> {offer.audience}</li>
                  <li><strong>Price anchor:</strong> {offer.price_anchor}</li>
                  <li><strong>Delivery:</strong> {offer.delivery}</li>
                </ul>
              </>
            )}
            <pre className="am-copy mt-6 whitespace-pre-wrap text-sm">{String(r.narrative)}</pre>
          </Card>
        </>
      );
    }

    const mockBadges = [];
    if (r.used_mock_george) mockBadges.push("George (mock)");
    if (r.used_mock_james) mockBadges.push("James (mock)");

    return (
      <>
        <div className="flex flex-wrap gap-2">
          {"confidence" in r && r.confidence != null && (
            <Badge tone="low">{String(r.confidence)} confidence</Badge>
          )}
          {mockBadges.map((b) => (
            <Badge key={b} tone="medium">{b}</Badge>
          ))}
          {strategyWritten && <Badge tone="high">Strategy saved to Bolton</Badge>}
        </div>
        <Card padding="lg">
          <pre className="am-copy whitespace-pre-wrap text-sm">
            {String(r.narrative ?? JSON.stringify(result, null, 2))}
          </pre>
        </Card>
      </>
    );
  }

  return (
    <div className="am-section space-y-6">
      <PageHeader
        title="Strategy"
        description="Commercial direction — positioning, offers, GTM, and growth. Cross-agent reasoning over George's numbers and James's research."
      />

      <div className="flex flex-wrap gap-2">
        {WORKFLOWS.map((w) => (
          <button
            key={w.value}
            type="button"
            onClick={() => selectWorkflow(w.value)}
            className={`am-btn am-copy px-3 py-1.5 text-xs ${
              workflow === w.value ? "am-btn-primary" : "am-btn-secondary"
            }`}
          >
            {w.label}
          </button>
        ))}
      </div>

      <p className="am-copy text-sm text-[var(--am-muted)]">
        {WORKFLOWS.find((w) => w.value === workflow)?.description}
      </p>

      {workflow !== "digest" && (
        <AskConnerBar
          value={query}
          onChange={setQuery}
          onAsk={handleAsk}
          loading={loading}
          onScheduled={setNotice}
          taskType={workflow === "idea_validation" ? "idea_validation" : workflow}
        />
      )}

      {workflow === "digest" && (
        <Button variant="primary" onClick={handleAsk} disabled={loading}>
          {loading ? "Synthesising…" : "Run weekly digest"}
        </Button>
      )}

      {notice && <p className="am-copy text-sm">{notice}</p>}
      {error && <p className="am-copy text-sm text-red-700">{error}</p>}

      {renderResult()}

      <Card padding="md">
        <p className="am-label mb-3">Request James research</p>
        <p className="am-copy mb-4 text-sm text-[var(--am-muted)]">
          Routes via Leo&apos;s shared agent-invocation contract
        </p>
        <div className="flex gap-2">
          <input
            className="am-input flex-1"
            placeholder="e.g. Compare pricing for multi-agent SaaS tools targeting solo founders"
            value={jamesTask}
            onChange={(e) => setJamesTask(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && handleJamesInvoke()}
          />
          <Button variant="secondary" size="sm" onClick={handleJamesInvoke} disabled={jamesLoading}>
            {jamesLoading ? "…" : "Send to James"}
          </Button>
        </div>
      </Card>
    </div>
  );
}
