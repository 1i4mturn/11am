"use client";

import { Button, Card, PageHeader } from "@11am/ui";
import { useCallback, useEffect, useState } from "react";
import { AskGeorgeBar } from "@/components/AskGeorgeBar";
import { TaxDisclaimer } from "@/components/TaxDisclaimer";

interface Calculator {
  id: string;
  title: string;
  prompt: string;
  public_url: string | null;
  storage_path: string;
  created_at: string;
}

export default function CalculatorsPage() {
  const [query, setQuery] = useState(
    "Build a SaaS runway calculator: monthly revenue, burn, cash balance, show months of runway"
  );
  const [calculators, setCalculators] = useState<Calculator[]>([]);
  const [loading, setLoading] = useState(false);
  const [notice, setNotice] = useState("");
  const [error, setError] = useState("");
  const [previewHtml, setPreviewHtml] = useState("");

  const load = useCallback(async () => {
    const res = await fetch("/api/calculator");
    const data = await res.json();
    setCalculators(data.calculators ?? []);
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  async function generate() {
    if (!query.trim()) return;
    setLoading(true);
    setError("");
    setPreviewHtml("");
    try {
      const res = await fetch("/api/calculator", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ prompt: query.trim() }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);
      setNotice("Calculator generated and linked in Bolton memory.");
      if (data.html) setPreviewHtml(data.html);
      if (data.public_url) window.open(data.public_url, "_blank");
      await load();
    } catch (e) {
      setError(e instanceof Error ? e.message : "Generate failed");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="am-section space-y-6">
      <PageHeader
        title="Custom calculators"
        description="Claude generates self-contained HTML artifacts — stored in Supabase, linked from Bolton."
      />
      <TaxDisclaimer />

      <AskGeorgeBar
        value={query}
        onChange={setQuery}
        onAsk={generate}
        loading={loading}
        onScheduled={setNotice}
        taskType="general"
      />

      {notice && <p className="am-copy text-sm">{notice}</p>}
      {error && <p className="am-copy text-sm text-red-700">{error}</p>}

      {previewHtml && (
        <Card padding="md">
          <p className="am-label mb-2">Preview (local — Supabase not configured)</p>
          <iframe
            title="Calculator preview"
            srcDoc={previewHtml}
            className="h-96 w-full border border-[var(--am-border)]"
            sandbox="allow-scripts"
          />
        </Card>
      )}

      <Card padding="md">
        <p className="am-label mb-3">Generated calculators</p>
        {calculators.length ? (
          <ul className="space-y-3">
            {calculators.map((c) => (
              <li key={c.id} className="border-b border-[var(--am-border)] pb-3 last:border-0">
                <p className="am-copy font-medium">{c.title}</p>
                <p className="am-copy text-sm text-[var(--am-muted)]">{c.prompt.slice(0, 120)}</p>
                {c.public_url && (
                  <a
                    href={c.public_url}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="am-copy mt-1 inline-block text-sm underline"
                  >
                    Open artifact
                  </a>
                )}
              </li>
            ))}
          </ul>
        ) : (
          <p className="am-copy text-sm text-[var(--am-muted)]">No calculators yet.</p>
        )}
      </Card>
    </div>
  );
}
