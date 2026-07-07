"use client";

import { Badge, Button, Card, PageHeader } from "@11am/ui";
import { useCallback, useEffect, useState } from "react";
import { AskRobertBar } from "@/components/AskRobertBar";
import { BrandSystemDisplay } from "@/components/BrandSystemDisplay";
import type { BrandSystemDoc, ImplementationBrief, WorkflowType } from "@/lib/types";

const WORKFLOWS: { value: WorkflowType; label: string; description: string }[] = [
  {
    value: "brand_direction",
    label: "Brand direction",
    description: "Claude + Conner commercial context from Bolton",
  },
  {
    value: "color_typography",
    label: "Colour / type",
    description: "Structured token output — not prose",
  },
  {
    value: "moodboard",
    label: "Moodboard",
    description: "OpenAI DALL-E reference images (session-capped)",
  },
  {
    value: "logo_concepts",
    label: "Logo concepts",
    description: "Direction + concept images only — not production vectors",
  },
  {
    value: "brand_audit",
    label: "Brand audit",
    description: "Upload an asset — compared against brand-system tokens",
  },
  {
    value: "competitor_landscape",
    label: "Competitor landscape",
    description: "James research from Bolton + visual interpretation",
  },
  {
    value: "handoff",
    label: "Design brief",
    description: "Structured brief for Johnny (build) or Cole (motion)",
  },
];

const DEFAULT_PROMPTS: Record<WorkflowType, string> = {
  brand_direction: "How should 11am position visually against generic AI productivity tools?",
  color_typography: "Refine warm neutrals for the agent suite — keep editorial, not corporate",
  moodboard: "Warm editorial SaaS — solo founder calm, not startup bro energy",
  logo_concepts: "Lowercase monogram mark for dark ask bars — minimal, confident",
  brand_audit: "",
  competitor_landscape: "AI agent suites and productivity tools visual positioning",
  handoff: "Home dashboard glance cards",
};

const API_ROUTES: Partial<Record<WorkflowType, string>> = {
  brand_direction: "/api/direction",
  color_typography: "/api/tokens",
  moodboard: "/api/moodboard",
  logo_concepts: "/api/logo-concepts",
  competitor_landscape: "/api/landscape",
  handoff: "/api/brief",
};

function getSessionId(): string {
  if (typeof window === "undefined") return "server";
  const key = "robert-image-session";
  let id = localStorage.getItem(key);
  if (!id) {
    id = crypto.randomUUID();
    localStorage.setItem(key, id);
  }
  return id;
}

export default function DirectionPage() {
  const [workflow, setWorkflow] = useState<WorkflowType>("brand_direction");
  const [query, setQuery] = useState(DEFAULT_PROMPTS.brand_direction);
  const [result, setResult] = useState<Record<string, unknown> | null>(null);
  const [brandSystem, setBrandSystem] = useState<BrandSystemDoc | null>(null);
  const [brandMock, setBrandMock] = useState(false);
  const [loading, setLoading] = useState(false);
  const [notice, setNotice] = useState("");
  const [error, setError] = useState("");
  const [auditFile, setAuditFile] = useState<File | null>(null);
  const [handoffTarget, setHandoffTarget] = useState<"johnny" | "cole">("johnny");
  const [briefResult, setBriefResult] = useState<ImplementationBrief | null>(null);
  const [routing, setRouting] = useState(false);

  const loadBrandSystem = useCallback(async () => {
    try {
      const res = await fetch("/api/brand-system");
      const data = await res.json();
      if (res.ok) {
        setBrandSystem(data.brand_system);
        setBrandMock(data.from_mock ?? false);
      }
    } catch {
      // non-blocking
    }
  }, []);

  useEffect(() => {
    loadBrandSystem();
  }, [loadBrandSystem]);

  function selectWorkflow(w: WorkflowType) {
    setWorkflow(w);
    setQuery(DEFAULT_PROMPTS[w]);
    setResult(null);
    setError("");
    setBriefResult(null);
  }

  async function handleAsk() {
    if (workflow === "brand_audit") {
      if (!auditFile) return;
      setLoading(true);
      setError("");
      setResult(null);
      try {
        const form = new FormData();
        form.append("asset", auditFile);
        const res = await fetch("/api/audit", { method: "POST", body: form });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error);
        setResult(data.result);
      } catch (e) {
        setError(e instanceof Error ? e.message : "Audit failed");
      } finally {
        setLoading(false);
      }
      return;
    }

    if (workflow === "handoff") {
      if (!query.trim()) return;
      setLoading(true);
      setError("");
      setBriefResult(null);
      try {
        const res = await fetch("/api/brief", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            target: handoffTarget,
            project: query.trim(),
            objective: `Implement ${query.trim()} per living brand system`,
          }),
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error);
        setBriefResult(data.brief);
        setNotice(data.memory_id ? `Brief saved to Bolton (${data.memory_id})` : "Brief created");
      } catch (e) {
        setError(e instanceof Error ? e.message : "Brief failed");
      } finally {
        setLoading(false);
      }
      return;
    }

    if (!query.trim()) return;
    setLoading(true);
    setError("");
    setResult(null);

    try {
      const route = API_ROUTES[workflow];
      if (!route) throw new Error("Unknown workflow");

      let body: Record<string, unknown> = {};
      if (workflow === "brand_direction") body = { query: query.trim() };
      else if (workflow === "color_typography") body = { brief: query.trim() };
      else if (workflow === "moodboard" || workflow === "logo_concepts") {
        body = {
          prompt: query.trim(),
          direction: query.trim(),
          session_id: getSessionId(),
          ...(workflow === "moodboard" ? { count: 2 } : {}),
        };
      } else if (workflow === "competitor_landscape") body = { focus: query.trim() };

      const res = await fetch(route, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);

      setResult(data.result ?? data.tokens ?? data);

      if (workflow === "color_typography" && data.tokens) {
        const updateRes = await fetch("/api/brand-system", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            update_brief: `Apply token recommendation: ${query}\n${JSON.stringify(data.tokens)}`,
          }),
        });
        if (updateRes.ok) {
          const updated = await updateRes.json();
          setBrandSystem(updated.brand_system);
          setNotice("Brand system updated in Bolton");
        }
      } else if (workflow === "brand_direction") {
        const updateRes = await fetch("/api/brand-system", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            update_brief: `Direction session: ${query}\n${data.result?.advice ?? ""}`,
          }),
        });
        if (updateRes.ok) {
          const updated = await updateRes.json();
          setBrandSystem(updated.brand_system);
        }
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : "Request failed");
    } finally {
      setLoading(false);
    }
  }

  async function routeBrief(target: "johnny" | "cole") {
    if (!brandSystem) return;
    setRouting(true);
    setError("");
    try {
      const res = await fetch("/api/brief", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          target,
          project: `Brand system v${brandSystem.version}`,
          objective:
            target === "johnny"
              ? "Implement UI per living brand-system tokens"
              : "Motion direction per brand-system motion_tokens",
        }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);
      setBriefResult(data.brief);
      setNotice(
        `Routed to ${target}${data.memory_id ? ` · Bolton ${data.memory_id}` : ""}`
      );
    } catch (e) {
      setError(e instanceof Error ? e.message : "Route failed");
    } finally {
      setRouting(false);
    }
  }

  function renderResult() {
    if (briefResult) {
      return (
        <Card padding="lg">
          <div className="mb-4 flex flex-wrap gap-2">
            <Badge tone="high">Brief → {briefResult.target_agent}</Badge>
            <Badge tone="low">{briefResult.as_of}</Badge>
          </div>
          <pre className="am-copy whitespace-pre-wrap text-sm">
            {JSON.stringify(briefResult, null, 2)}
          </pre>
        </Card>
      );
    }

    if (!result) return null;
    const r = result as Record<string, unknown>;

    if (workflow === "brand_direction") {
      return (
        <Card padding="lg">
          <div className="mb-4 flex flex-wrap gap-2">
            <Badge tone="low">{String(r.confidence)} confidence</Badge>
            {r.used_mock_conner === true && <Badge tone="medium">Conner (mock)</Badge>}
          </div>
          <p className="am-copy whitespace-pre-wrap text-sm">{String(r.advice)}</p>
        </Card>
      );
    }

    if (workflow === "color_typography") {
      const tokens = r as Record<string, Record<string, string>>;
      return (
        <Card padding="lg">
          <pre className="am-copy whitespace-pre-wrap text-sm">
            {JSON.stringify(tokens, null, 2)}
          </pre>
        </Card>
      );
    }

    if (workflow === "moodboard") {
      const images = (r.images as Array<{ url: string }>) ?? [];
      return (
        <Card padding="lg">
          <p className="am-label mb-2">moodboard · {String(r.images_remaining)} images remaining</p>
          <div className="grid gap-4 sm:grid-cols-2">
            {images.map((img, i) => (
              <img
                key={i}
                src={img.url}
                alt={`Moodboard ${i + 1}`}
                className="w-full rounded border border-[var(--am-border)]"
              />
            ))}
          </div>
        </Card>
      );
    }

    if (workflow === "logo_concepts") {
      const concepts = (r.concepts as Array<{ id: string; description: string; image_url?: string }>) ?? [];
      return (
        <Card padding="lg">
          <p className="am-copy mb-4 text-sm">{String(r.direction)}</p>
          <p className="am-label mb-4 text-xs text-[var(--am-muted)]">{String(r.disclaimer)}</p>
          <div className="grid gap-4 sm:grid-cols-2">
            {concepts.map((c) => (
              <div key={c.id}>
                <p className="am-label mb-2">{c.id}</p>
                <p className="am-copy mb-2 text-sm">{c.description}</p>
                {c.image_url && (
                  <img
                    src={c.image_url}
                    alt={c.id}
                    className="w-full rounded border border-[var(--am-border)]"
                  />
                )}
              </div>
            ))}
          </div>
        </Card>
      );
    }

    if (workflow === "brand_audit") {
      return (
        <Card padding="lg">
          <Badge tone={r.overall_verdict === "on_brand" ? "high" : "medium"}>
            {String(r.overall_verdict)}
          </Badge>
          <p className="am-copy mt-4 text-sm">{String(r.summary)}</p>
        </Card>
      );
    }

    if (workflow === "competitor_landscape") {
      return (
        <Card padding="lg">
          {r.used_mock_james === true && (
            <Badge tone="medium" className="mb-4">
              James (mock)
            </Badge>
          )}
          <p className="am-copy whitespace-pre-wrap text-sm">{String(r.recommendation)}</p>
        </Card>
      );
    }

    return (
      <Card padding="lg">
        <pre className="am-copy whitespace-pre-wrap text-sm">{JSON.stringify(result, null, 2)}</pre>
      </Card>
    );
  }

  return (
    <div className="am-section space-y-6">
      <PageHeader
        title="Direction"
        description="Visual direction, living brand system, and structured briefs — Johnny builds, Cole moves."
      />

      {brandSystem && (
        <BrandSystemDisplay
          doc={brandSystem}
          fromMock={brandMock}
          onRouteJohnny={() => routeBrief("johnny")}
          onRouteCole={() => routeBrief("cole")}
          routing={routing}
        />
      )}

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

      {workflow === "brand_audit" ? (
        <Card padding="md">
          <p className="am-label mb-3">upload asset</p>
          <input
            type="file"
            accept="image/*"
            onChange={(e) => setAuditFile(e.target.files?.[0] ?? null)}
            className="am-copy text-sm"
          />
          <Button
            variant="primary"
            size="sm"
            className="mt-4"
            onClick={handleAsk}
            disabled={loading || !auditFile}
          >
            {loading ? "Auditing…" : "Run brand audit"}
          </Button>
        </Card>
      ) : workflow === "handoff" ? (
        <Card padding="md">
          <div className="mb-4 flex gap-2">
            {(["johnny", "cole"] as const).map((t) => (
              <button
                key={t}
                type="button"
                onClick={() => setHandoffTarget(t)}
                className={`am-btn am-copy px-3 py-1.5 text-xs ${
                  handoffTarget === t ? "am-btn-primary" : "am-btn-secondary"
                }`}
              >
                {t === "johnny" ? "Johnny (build)" : "Cole (motion)"}
              </button>
            ))}
          </div>
          <AskRobertBar
            value={query}
            onChange={setQuery}
            onAsk={handleAsk}
            loading={loading}
            onScheduled={setNotice}
            taskType="general"
          />
        </Card>
      ) : (
        <AskRobertBar
          value={query}
          onChange={setQuery}
          onAsk={handleAsk}
          loading={loading}
          onScheduled={setNotice}
          taskType={
            workflow === "competitor_landscape"
              ? "competitor_landscape"
              : workflow === "moodboard"
                ? "moodboard"
                : workflow === "logo_concepts"
                  ? "logo_concepts"
                  : workflow === "color_typography"
                    ? "color_typography"
                    : "brand_direction"
          }
        />
      )}

      {notice && <p className="am-copy text-sm">{notice}</p>}
      {error && <p className="am-copy am-error text-sm">{error}</p>}

      {renderResult()}
    </div>
  );
}
