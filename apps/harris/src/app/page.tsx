"use client";

import { Badge, Button, Card, PageHeader } from "@11am/ui";
import { useCallback, useEffect, useState } from "react";
import { AskHarrisBar } from "@/components/AskHarrisBar";
import { LearningHubPanel } from "@/components/LearningHubPanel";
import type { LearningHub, SkillGapSignal, WorkflowType } from "@/lib/types";

const WORKFLOWS: { value: WorkflowType; label: string; description: string }[] = [
  { value: "plan", label: "Learning plan", description: "Generate a study plan for any skill" },
  { value: "roadmap", label: "Roadmap", description: "Skill roadmap with milestones" },
  { value: "exercises", label: "Exercises", description: "Practice exercises for a skill" },
  { value: "explain", label: "Explain", description: "Clear concept explanation + practice prompt" },
  {
    value: "gap_plan",
    label: "Gap-driven plan",
    description: "Plan from a real skill-gap signal in Bolton (James feed)",
  },
  { value: "french", label: "French", description: "Lightweight French help + optional SRS cards" },
];

const DEFAULT_PROMPTS: Record<WorkflowType, string> = {
  plan: "Next.js App Router patterns for multi-agent handoffs",
  roadmap: "TypeScript advanced types",
  exercises: "Public speaking for solo founder demos",
  explain: "What is spaced repetition and when does it actually work?",
  gap_plan: "",
  french: "Explain passé composé vs imparfait with two example sentences",
};

const API_ROUTES: Record<WorkflowType, string | null> = {
  plan: "/api/plan",
  roadmap: "/api/roadmap",
  exercises: "/api/exercises",
  explain: "/api/explain",
  gap_plan: "/api/gap-plan",
  french: "/api/french",
};

const BODY_KEYS: Partial<Record<WorkflowType, string>> = {
  plan: "skill",
  roadmap: "skill",
  exercises: "skill",
  explain: "concept",
  french: "query",
};

export default function LearnPage() {
  const [workflow, setWorkflow] = useState<WorkflowType>("plan");
  const [query, setQuery] = useState(DEFAULT_PROMPTS.plan);
  const [hub, setHub] = useState<LearningHub | null>(null);
  const [gaps, setGaps] = useState<SkillGapSignal[]>([]);
  const [gapsMock, setGapsMock] = useState(false);
  const [result, setResult] = useState<Record<string, unknown> | null>(null);
  const [loading, setLoading] = useState(false);
  const [progressSaving, setProgressSaving] = useState(false);
  const [notice, setNotice] = useState("");
  const [error, setError] = useState("");
  const [frenchBack, setFrenchBack] = useState("");

  const loadHub = useCallback(async () => {
    const res = await fetch("/api/hub");
    if (res.ok) {
      const data = await res.json();
      setHub(data.hub);
    }
  }, []);

  const loadGaps = useCallback(async () => {
    const res = await fetch("/api/skill-gaps");
    if (res.ok) {
      const data = await res.json();
      setGaps(data.gaps ?? []);
      setGapsMock(data.from_mock ?? false);
    }
  }, []);

  useEffect(() => {
    loadHub();
    loadGaps();
  }, [loadHub, loadGaps]);

  function selectWorkflow(w: WorkflowType) {
    setWorkflow(w);
    setQuery(DEFAULT_PROMPTS[w]);
    setResult(null);
    setError("");
  }

  async function handleAsk() {
    if (workflow === "gap_plan") {
      setLoading(true);
      setError("");
      setResult(null);
      try {
        const res = await fetch("/api/gap-plan", { method: "POST" });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error);
        setResult(data.result);
        await loadHub();
      } catch (e) {
        setError(e instanceof Error ? e.message : "Gap plan failed");
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

      const key = BODY_KEYS[workflow];
      const body = key ? { [key]: query.trim() } : {};

      const res = await fetch(route, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);

      setResult(data.result ?? data);
      if (workflow !== "explain" && workflow !== "french") await loadHub();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Request failed");
    } finally {
      setLoading(false);
    }
  }

  async function handleProgressUpdate(planId: string, percent: number, note?: string) {
    setProgressSaving(true);
    try {
      const res = await fetch("/api/hub/progress", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          plan_id: planId,
          percent_self_reported: percent,
          last_session_note: note,
          sessions_completed: undefined,
        }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);
      setHub(data.hub);
      setNotice("Progress saved");
    } catch (e) {
      setError(e instanceof Error ? e.message : "Progress save failed");
    } finally {
      setProgressSaving(false);
    }
  }

  async function addFrenchCard() {
    if (!query.trim() || !frenchBack.trim()) return;
    const res = await fetch("/api/french", {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ front: query.trim(), back: frenchBack.trim() }),
    });
    if (res.ok) {
      setNotice("French SRS card added");
      setFrenchBack("");
      await loadHub();
    }
  }

  function renderResult() {
    if (!result) return null;
    const r = result as Record<string, unknown>;

    if (workflow === "plan" || workflow === "gap_plan") {
      const plan = (r.plan ?? r) as Record<string, unknown>;
      const planContent = plan.plan as { overview?: string; phases?: unknown[] } | undefined;
      return (
        <Card padding="lg">
          <div className="mb-4 flex flex-wrap gap-2">
            {workflow === "gap_plan" && r.from_mock === true && (
              <Badge tone="medium">skill gap (mock)</Badge>
            )}
            <Badge tone="high">Saved to Learning Hub</Badge>
          </div>
          <p className="am-copy whitespace-pre-wrap text-sm">
            {String(planContent?.overview ?? r.narrative ?? "")}
          </p>
        </Card>
      );
    }

    if (workflow === "roadmap") {
      return (
        <Card padding="lg">
          <pre className="am-copy whitespace-pre-wrap text-sm">{String(r.roadmap)}</pre>
        </Card>
      );
    }

    if (workflow === "exercises") {
      const exercises = (r.exercises as Array<{ title: string; content: string }>) ?? [];
      return (
        <Card padding="lg">
          <ul className="am-copy space-y-4 text-sm">
            {exercises.map((ex, i) => (
              <li key={i}>
                <p className="am-label mb-1">{ex.title}</p>
                <p>{ex.content}</p>
              </li>
            ))}
          </ul>
        </Card>
      );
    }

    if (workflow === "explain") {
      return (
        <Card padding="lg">
          <p className="am-copy whitespace-pre-wrap text-sm">{String(r.explanation)}</p>
          <p className="am-label mt-4">try now</p>
          <p className="am-copy text-sm">{String(r.practice_prompt)}</p>
        </Card>
      );
    }

    if (workflow === "french") {
      const items = (r.practice_items as string[]) ?? [];
      return (
        <Card padding="lg">
          <p className="am-copy whitespace-pre-wrap text-sm">{String(r.explanation)}</p>
          {items.length > 0 && (
            <ul className="am-copy mt-4 list-disc space-y-1 pl-5 text-sm">
              {items.map((item, i) => (
                <li key={i}>{item}</li>
              ))}
            </ul>
          )}
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
        title="Learn"
        description="Study paths and skill-building — standalone today, sharper when James's skill-gap feed lands."
      />

      {hub && (
        <LearningHubPanel
          hub={hub}
          onProgressUpdate={handleProgressUpdate}
          updating={progressSaving}
        />
      )}

      {gaps.length > 0 && (
        <Card padding="md">
          <p className="am-label mb-2">skill gaps {gapsMock && "(mock)"}</p>
          <ul className="am-copy space-y-2 text-sm">
            {gaps.slice(0, 3).map((g, i) => (
              <li key={i}>
                <Badge tone={g.priority === "high" ? "medium" : "low"}>{g.priority}</Badge>{" "}
                {g.skill_gap}
              </li>
            ))}
          </ul>
        </Card>
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

      {workflow === "gap_plan" ? (
        <Button variant="primary" onClick={handleAsk} disabled={loading}>
          {loading ? "Building…" : "Build plan from top skill gap"}
        </Button>
      ) : workflow === "french" ? (
        <>
          <AskHarrisBar
            value={query}
            onChange={setQuery}
            onAsk={handleAsk}
            loading={loading}
            onScheduled={setNotice}
            taskType="french"
          />
          <div className="flex gap-2">
            <input
              className="am-input flex-1 text-sm"
              placeholder="SRS card back (translation)"
              value={frenchBack}
              onChange={(e) => setFrenchBack(e.target.value)}
            />
            <Button variant="secondary" size="sm" onClick={addFrenchCard}>
              Add SRS card
            </Button>
          </div>
        </>
      ) : (
        <AskHarrisBar
          value={query}
          onChange={setQuery}
          onAsk={handleAsk}
          loading={loading}
          onScheduled={setNotice}
          taskType={workflow === "plan" ? "plan" : workflow}
        />
      )}

      {notice && <p className="am-copy text-sm">{notice}</p>}
      {error && <p className="am-copy am-error text-sm">{error}</p>}

      {renderResult()}
    </div>
  );
}
