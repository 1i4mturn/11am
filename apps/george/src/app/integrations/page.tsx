"use client";

import { Button, Card, PageHeader } from "@11am/ui";
import { Suspense, useCallback, useEffect, useState } from "react";
import { useSearchParams } from "next/navigation";
import { TaxDisclaimer } from "@/components/TaxDisclaimer";

function IntegrationsContent() {
  const searchParams = useSearchParams();
  const [stripe, setStripe] = useState<Record<string, unknown> | null>(null);
  const [xero, setXero] = useState<Record<string, unknown> | null>(null);
  const [stripeKey, setStripeKey] = useState("");
  const [importResult, setImportResult] = useState("");
  const [summary, setSummary] = useState<Record<string, unknown> | null>(null);
  const [notice, setNotice] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  const loadStripe = useCallback(async () => {
    const res = await fetch("/api/stripe");
    setStripe(await res.json());
  }, []);

  const loadXero = useCallback(async () => {
    const res = await fetch("/api/xero");
    setXero(await res.json());
  }, []);

  useEffect(() => {
    loadStripe();
    loadXero();
  }, [loadStripe, loadXero]);

  useEffect(() => {
    const x = searchParams.get("xero");
    if (x === "connected") setNotice("Xero connected.");
    if (x === "error") setError("Xero connection failed.");
  }, [searchParams]);

  async function connectStripe() {
    setError("");
    const res = await fetch("/api/stripe", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ key: stripeKey }),
    });
    const data = await res.json();
    if (!res.ok) setError(data.error);
    else {
      setNotice("Stripe connected.");
      await loadStripe();
    }
  }

  async function importSpreadsheet(file: File) {
    setLoading(true);
    setError("");
    const form = new FormData();
    form.append("file", file);
    try {
      const res = await fetch("/api/import", { method: "POST", body: form });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);
      setImportResult(data.analysis);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Import failed");
    } finally {
      setLoading(false);
    }
  }

  async function publishSummary() {
    setLoading(true);
    try {
      const res = await fetch("/api/summary", { method: "POST" });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error);
      setSummary(data.summary);
      setNotice("Latest numbers written to Bolton.");
    } catch (e) {
      setError(e instanceof Error ? e.message : "Summary failed");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="am-section space-y-6">
      <PageHeader
        title="Integrations"
        description="Stripe revenue, Xero P&L, spreadsheet import, and Bolton latest-numbers summary."
        actions={
          <Button variant="primary" size="sm" onClick={publishSummary} disabled={loading}>
            Publish latest numbers
          </Button>
        }
      />

      <TaxDisclaimer />
      {notice && <p className="am-copy text-sm">{notice}</p>}
      {error && <p className="am-copy am-error text-sm">{error}</p>}

      <div className="grid gap-4 md:grid-cols-2">
        <Card padding="md">
          <p className="am-label mb-3">Stripe</p>
          {stripe?.configured && stripe.metrics ? (
            <pre className="am-copy whitespace-pre-wrap text-xs">
              {JSON.stringify(stripe.metrics, null, 2)}
            </pre>
          ) : (
            <div className="space-y-2">
              <input
                className="am-input w-full"
                type="password"
                placeholder="Restricted API key (rk_live_... or rk_test_...)"
                value={stripeKey}
                onChange={(e) => setStripeKey(e.target.value)}
              />
              <Button variant="secondary" size="sm" onClick={connectStripe}>
                Connect Stripe
              </Button>
            </div>
          )}
        </Card>

        <Card padding="md">
          <p className="am-label mb-3">Xero</p>
          {xero?.connected ? (
            <pre className="am-copy max-h-64 overflow-auto whitespace-pre-wrap text-xs">
              {JSON.stringify(xero.financials ?? xero, null, 2)}
            </pre>
          ) : (
            <div>
              <p className="am-copy mb-2 text-sm text-[var(--am-muted)]">
                Uncertified OAuth — works immediately for your org.
              </p>
              {typeof xero?.authUrl === "string" && (
                <a href={xero.authUrl} className="am-btn am-btn-primary px-3 py-1.5 am-label inline-block">
                  Connect Xero
                </a>
              )}
            </div>
          )}
        </Card>
      </div>

      <Card padding="md">
        <p className="am-label mb-3">Spreadsheet import (.xlsx)</p>
        <input
          type="file"
          accept=".xlsx,.xls"
          className="am-copy text-sm"
          onChange={(e) => {
            const file = e.target.files?.[0];
            if (file) importSpreadsheet(file);
          }}
          disabled={loading}
        />
        {importResult && (
          <pre className="am-copy mt-4 whitespace-pre-wrap text-sm">{importResult}</pre>
        )}
      </Card>

      {summary && (
        <Card padding="md">
          <p className="am-label mb-2">Latest numbers (Bolton)</p>
          <pre className="am-copy whitespace-pre-wrap text-sm">{JSON.stringify(summary, null, 2)}</pre>
        </Card>
      )}
    </div>
  );
}

export default function IntegrationsPage() {
  return (
    <Suspense>
      <IntegrationsContent />
    </Suspense>
  );
}
