"use client";

import { Card, PageHeader } from "@11am/ui";
import { useEffect, useState } from "react";

export default function DecisionsPage() {
  const [decisions, setDecisions] = useState<Array<Record<string, unknown>>>([]);

  useEffect(() => {
    fetch("/api/decisions").then((r) => r.json()).then((d) => setDecisions(d.decisions ?? []));
  }, []);

  return (
    <>
      <PageHeader title="Decision log" description="First-class decisions - plain English, searchable, supersedeable." />
      <div className="space-y-8">
        {decisions.map((d) => (
          <Card key={String(d.id)} grain padding="md">
            <p className="am-title">{String(d.decision)}</p>
            <p className="am-detail-meta mt-1">{String(d.sourceAgent)} · {String(d.decisionType)} · {String(d.status)}</p>
            {Boolean(d.context) && <p className="am-detail-meta mt-3">Context: {String(d.context)}</p>}
            {Boolean(d.rationale) && <p className="am-copy mt-2">Rationale: {String(d.rationale)}</p>}
          </Card>
        ))}
        {!decisions.length && <p className="am-copy py-8 text-center">No decisions logged yet.</p>}
      </div>
    </>
  );
}
