"use client";

import { Badge, Button, Card, PageHeader } from "@11am/ui";
import { useState } from "react";
import { AskGeorgeBar } from "@/components/AskGeorgeBar";
import { TaxDisclaimer } from "@/components/TaxDisclaimer";
import type { ModelType, TaxFlag } from "@/lib/types";

interface Message {
  role: "user" | "assistant";
  content: string;
}

const MODEL_TYPES: { value: ModelType; label: string }[] = [
  { value: "general", label: "General" },
  { value: "pl", label: "P&L" },
  { value: "runway", label: "Runway" },
  { value: "cashflow", label: "Cash flow" },
  { value: "breakeven", label: "Break-even" },
];

export default function ModelPage() {
  const [query, setQuery] = useState("");
  const [modelType, setModelType] = useState<ModelType>("general");
  const [messages, setMessages] = useState<Message[]>([]);
  const [taxFlags, setTaxFlags] = useState<TaxFlag[]>([]);
  const [loading, setLoading] = useState(false);
  const [notice, setNotice] = useState("");
  const [error, setError] = useState("");
  const [saveName, setSaveName] = useState("");
  const [termQuery, setTermQuery] = useState("");
  const [termResult, setTermResult] = useState("");

  async function handleAsk() {
    if (!query.trim()) return;
    setLoading(true);
    setError("");
    const userMsg = query.trim();
    setQuery("");

    try {
      const res = await fetch("/api/chat", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          message: userMsg,
          history: messages,
          model_type: modelType,
        }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);

      setMessages((m) => [
        ...m,
        { role: "user", content: userMsg },
        { role: "assistant", content: data.reply },
      ]);
      setTaxFlags(data.tax_flags ?? []);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Ask failed");
    } finally {
      setLoading(false);
    }
  }

  async function saveModel() {
    if (!saveName.trim() || messages.length === 0) return;
    try {
      const res = await fetch("/api/models", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name: saveName,
          model_type: modelType,
          conversation: messages,
        }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);
      setNotice(`Model saved: ${data.model.name}`);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Save failed");
    }
  }

  async function explainTerm() {
    if (!termQuery.trim()) return;
    setTermResult("");
    const res = await fetch("/api/terms", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ term: termQuery }),
    });
    const data = await res.json();
    if (res.ok) setTermResult(data.explanation);
  }

  return (
    <div className="am-section space-y-6">
      <PageHeader
        title="Financial modelling"
        description="Conversational P&L, runway, cash flow, and break-even — powered by Claude."
      />

      <TaxDisclaimer />

      <div className="flex flex-wrap gap-2">
        {MODEL_TYPES.map((t) => (
          <button
            key={t.value}
            type="button"
            onClick={() => setModelType(t.value)}
            className={`am-btn am-copy px-3 py-1.5 text-xs ${
              modelType === t.value ? "am-btn-primary" : "am-btn-secondary"
            }`}
          >
            {t.label}
          </button>
        ))}
      </div>

      <AskGeorgeBar
        value={query}
        onChange={setQuery}
        onAsk={handleAsk}
        loading={loading}
        onScheduled={setNotice}
        taskType="finance_review"
      />

      {notice && <p className="am-copy text-sm">{notice}</p>}
      {error && <p className="am-copy am-error text-sm">{error}</p>}

      {taxFlags.length > 0 && (
        <Card padding="md">
          <p className="am-label mb-2">Tax flags (awareness only)</p>
          <ul className="space-y-2">
            {taxFlags.map((f, i) => (
              <li key={i} className="flex gap-2">
                <Badge tone={f.severity === "review" ? "medium" : "low"}>{f.category}</Badge>
                <span className="am-copy text-sm">{f.description}</span>
              </li>
            ))}
          </ul>
        </Card>
      )}

      {messages.length > 0 && (
        <Card padding="lg">
          <div className="space-y-4">
            {messages.map((m, i) => (
              <div key={i}>
                <p className="am-label mb-1 text-xs">{m.role}</p>
                <pre className="am-copy whitespace-pre-wrap text-sm">{m.content}</pre>
              </div>
            ))}
          </div>
          <div className="mt-6 flex flex-wrap items-end gap-3">
            <input
              className="am-input flex-1"
              placeholder="Model name to save"
              value={saveName}
              onChange={(e) => setSaveName(e.target.value)}
            />
            <Button variant="secondary" size="sm" onClick={saveModel}>
              Save model
            </Button>
          </div>
        </Card>
      )}

      <Card padding="md">
        <p className="am-label mb-3">Explain a term</p>
        <div className="flex gap-2">
          <input
            className="am-input flex-1"
            placeholder="e.g. gross margin, burn rate, CAC"
            value={termQuery}
            onChange={(e) => setTermQuery(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && explainTerm()}
          />
          <Button variant="ghost" size="sm" onClick={explainTerm}>
            Explain
          </Button>
        </div>
        {termResult && (
          <pre className="am-copy mt-4 whitespace-pre-wrap text-sm">{termResult}</pre>
        )}
      </Card>
    </div>
  );
}
