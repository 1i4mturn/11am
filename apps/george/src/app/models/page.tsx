"use client";

import { Button, Card, PageHeader } from "@11am/ui";
import Link from "next/link";
import { useCallback, useEffect, useState } from "react";

interface SavedModel {
  id: string;
  name: string;
  model_type: string;
  updated_at: string;
  conversation: Array<{ role: string; content: string }>;
}

export default function ModelsPage() {
  const [models, setModels] = useState<SavedModel[]>([]);
  const [selected, setSelected] = useState<SavedModel | null>(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    const res = await fetch("/api/models");
    const data = await res.json();
    setModels(data.models ?? []);
    setLoading(false);
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  async function loadModel(id: string) {
    const res = await fetch(`/api/models/${id}`);
    const data = await res.json();
    if (res.ok) setSelected(data.model);
  }

  return (
    <div className="am-section space-y-6">
      <PageHeader
        title="Saved models"
        description="Full working models live in George's Postgres table — not Bolton."
        actions={
          <Link href="/" className="am-btn am-btn-secondary px-3 py-1.5 am-label">
            New model
          </Link>
        }
      />

      <Card padding="md">
        {loading ? (
          <p className="am-copy text-sm">Loading…</p>
        ) : models.length ? (
          <ul className="space-y-3">
            {models.map((m) => (
              <li key={m.id} className="flex items-center justify-between border-b border-[var(--am-border)] pb-3 last:border-0">
                <div>
                  <p className="am-copy font-medium">{m.name}</p>
                  <p className="am-copy text-xs text-[var(--am-muted)]">
                    {m.model_type} · {new Date(m.updated_at).toLocaleString()}
                  </p>
                </div>
                <Button variant="ghost" size="sm" onClick={() => loadModel(m.id)}>
                  Load
                </Button>
              </li>
            ))}
          </ul>
        ) : (
          <p className="am-copy text-sm text-[var(--am-muted)]">
            No saved models — build one on the Model page and hit Save.
          </p>
        )}
      </Card>

      {selected && (
        <Card padding="lg">
          <p className="am-label mb-3">{selected.name}</p>
          <div className="space-y-4">
            {selected.conversation.map((m, i) => (
              <div key={i}>
                <p className="am-label text-xs">{m.role}</p>
                <pre className="am-copy whitespace-pre-wrap text-sm">{m.content}</pre>
              </div>
            ))}
          </div>
        </Card>
      )}
    </div>
  );
}
