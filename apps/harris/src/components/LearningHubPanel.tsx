"use client";

import { Badge, Button, Card } from "@11am/ui";
import { useState } from "react";
import type { LearningHub, LearningPlan } from "@/lib/types";

interface LearningHubPanelProps {
  hub: LearningHub;
  onProgressUpdate: (planId: string, percent: number, note?: string) => void;
  updating?: boolean;
}

export function LearningHubPanel({ hub, onProgressUpdate, updating }: LearningHubPanelProps) {
  if (hub.plans.length === 0) {
    return (
      <Card padding="md">
        <p className="am-label mb-2">learning hub</p>
        <p className="am-copy text-sm text-[var(--am-muted)]">
          No plans yet - generate one below. Full detail lives here; Bolton gets a short pointer only.
        </p>
      </Card>
    );
  }

  return (
    <Card padding="lg" className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="am-label">learning hub · {hub.plans.length} plan(s)</p>
        <span className="am-copy text-xs text-[var(--am-muted)]">updated {hub.updated_at.slice(0, 10)}</span>
      </div>

      {hub.plans.map((plan) => (
        <PlanRow
          key={plan.id}
          plan={plan}
          onProgressUpdate={onProgressUpdate}
          updating={updating}
        />
      ))}

      {hub.french_srs.length > 0 && (
        <div>
          <p className="am-label mb-2">french srs · {hub.french_srs.length} cards</p>
          <ul className="am-copy space-y-1 text-sm text-[var(--am-muted)]">
            {hub.french_srs.slice(0, 5).map((c) => (
              <li key={c.id}>
                {c.front} → review {c.next_review}
              </li>
            ))}
          </ul>
        </div>
      )}
    </Card>
  );
}

function PlanRow({
  plan,
  onProgressUpdate,
  updating,
}: {
  plan: LearningPlan;
  onProgressUpdate: (planId: string, percent: number, note?: string) => void;
  updating?: boolean;
}) {
  const [percent, setPercent] = useState(plan.progress.percent_self_reported);
  const [note, setNote] = useState(plan.progress.last_session_note ?? "");

  return (
    <div className="border-t border-[var(--am-border)] pt-4">
      <div className="mb-2 flex flex-wrap gap-2">
        <span className="am-copy font-medium">{plan.skill}</span>
        <Badge tone="low">{plan.progress.status}</Badge>
        {plan.source === "skill_gap" && <Badge tone="medium">skill gap</Badge>}
      </div>
      <p className="am-copy mb-3 text-sm text-[var(--am-muted)]">{plan.plan.overview.slice(0, 160)}…</p>
      <div className="flex flex-wrap items-end gap-3">
        <label className="am-copy text-xs">
          progress %
          <input
            type="number"
            min={0}
            max={100}
            value={percent}
            onChange={(e) => setPercent(Number(e.target.value))}
            className="am-input ml-2 w-16 px-2 py-1 text-sm"
          />
        </label>
        <input
          type="text"
          value={note}
          onChange={(e) => setNote(e.target.value)}
          placeholder="session note"
          className="am-input min-w-[12rem] flex-1 px-3 py-1 text-sm"
        />
        <Button
          variant="secondary"
          size="sm"
          disabled={updating}
          onClick={() => onProgressUpdate(plan.id, percent, note || undefined)}
        >
          Save progress
        </Button>
      </div>
    </div>
  );
}
