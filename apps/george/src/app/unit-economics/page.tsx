"use client";

import { Button, Card, PageHeader } from "@11am/ui";
import { useState } from "react";
import { TaxDisclaimer } from "@/components/TaxDisclaimer";
import type { TaxFlag } from "@/lib/types";

export default function UnitEconomicsPage() {
  const [form, setForm] = useState({
    cac: "",
    ltv: "",
    arpu: "",
    gross_margin_pct: "",
    monthly_churn_pct: "",
    customers: "",
    notes: "",
  });
  const [analysis, setAnalysis] = useState("");
  const [taxFlags, setTaxFlags] = useState<TaxFlag[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  async function analyse() {
    setLoading(true);
    setError("");
    try {
      const payload = {
        cac: form.cac ? Number(form.cac) : undefined,
        ltv: form.ltv ? Number(form.ltv) : undefined,
        arpu: form.arpu ? Number(form.arpu) : undefined,
        gross_margin_pct: form.gross_margin_pct ? Number(form.gross_margin_pct) : undefined,
        monthly_churn_pct: form.monthly_churn_pct ? Number(form.monthly_churn_pct) : undefined,
        customers: form.customers ? Number(form.customers) : undefined,
        notes: form.notes || undefined,
      };
      const res = await fetch("/api/unit-economics", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);
      setAnalysis(data.analysis);
      setTaxFlags(data.tax_flags ?? []);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Analysis failed");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="am-section space-y-6">
      <PageHeader
        title="Unit economics"
        description="CAC, LTV, margin, and payback analysis from your figures."
      />
      <TaxDisclaimer />

      <Card padding="md">
        <div className="grid gap-3 md:grid-cols-3">
          {(["cac", "ltv", "arpu", "gross_margin_pct", "monthly_churn_pct", "customers"] as const).map(
            (field) => (
              <input
                key={field}
                className="am-input"
                type="number"
                placeholder={field.replace(/_/g, " ")}
                value={form[field]}
                onChange={(e) => setForm({ ...form, [field]: e.target.value })}
              />
            )
          )}
          <textarea
            className="am-input md:col-span-3"
            placeholder="Notes (optional)"
            rows={2}
            value={form.notes}
            onChange={(e) => setForm({ ...form, notes: e.target.value })}
          />
        </div>
        <Button variant="primary" size="sm" className="mt-4" onClick={analyse} disabled={loading}>
          {loading ? "Analysing…" : "Analyse"}
        </Button>
      </Card>

      {error && <p className="am-copy text-sm text-red-700">{error}</p>}
      {analysis && (
        <Card padding="lg">
          <pre className="am-copy whitespace-pre-wrap text-sm">{analysis}</pre>
        </Card>
      )}
      {taxFlags.length > 0 && (
        <Card padding="md">
          <p className="am-label mb-2">Tax flags</p>
          {taxFlags.map((f, i) => (
            <p key={i} className="am-copy text-sm">
              {f.category}: {f.description}
            </p>
          ))}
        </Card>
      )}
    </div>
  );
}
