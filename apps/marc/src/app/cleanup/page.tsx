"use client";

import { Button, Card, PageHeader } from "@11am/ui";
import { useEffect, useState } from "react";

interface Candidate {
  message_id: string;
  sender: string;
  subject: string;
  category: string;
  reason: string;
  has_unsubscribe: boolean;
  list_unsubscribe?: string | null;
  safe_to_archive: boolean;
}

export default function CleanupPage() {
  const [candidates, setCandidates] = useState<Candidate[]>([]);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    fetch("/api/cleanup")
      .then((r) => r.json())
      .then((d) => {
        if (d.error) setError(d.error);
        else setCandidates(d.candidates ?? []);
      });
  }, []);

  function toggle(id: string) {
    setSelected((s) => {
      const next = new Set(s);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  const selectedCandidates = candidates.filter((c) => selected.has(c.message_id));
  const canUnsubscribe = selectedCandidates.some((c) => c.has_unsubscribe && c.list_unsubscribe);

  async function archiveSelected() {
    if (!selected.size || !confirm(`Archive ${selected.size} messages in Gmail?`)) return;
    setBusy(true);
    const res = await fetch("/api/cleanup", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        action: "archive",
        messageIds: Array.from(selected),
        confirmed: true,
      }),
    });
    const data = await res.json();
    setBusy(false);
    if (res.ok) {
      setNotice(`Archived ${data.archived} messages.`);
      setCandidates((c) => c.filter((x) => !selected.has(x.message_id)));
      setSelected(new Set());
    } else setError(data.error);
  }

  async function unsubscribeSelected() {
    const unsubscribable = selectedCandidates.filter((c) => c.has_unsubscribe && c.list_unsubscribe);
    if (
      !unsubscribable.length ||
      !confirm(`Send unsubscribe requests for ${unsubscribable.length} newsletters? Billing/security emails are excluded.`)
    ) {
      return;
    }
    setBusy(true);
    const res = await fetch("/api/cleanup", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        action: "unsubscribe",
        messageIds: unsubscribable.map((c) => c.message_id),
        confirmed: true,
      }),
    });
    const data = await res.json();
    setBusy(false);
    if (res.ok) {
      setNotice(`Unsubscribe sent for ${data.unsubscribed} of ${unsubscribable.length} messages.`);
    } else setError(data.error);
  }

  if (error && !candidates.length) {
    return <PageHeader title="Inbox cleanup" description={error} />;
  }

  return (
    <>
      <PageHeader
        title="Inbox cleanup"
        description="Safe unsubscribe and archive candidates — billing and security emails excluded."
      />

      {notice && (
        <Card padding="sm" className="am-section !p-4">
          <p className="am-copy">{notice}</p>
        </Card>
      )}

      {selected.size > 0 && (
        <div className="am-section flex flex-wrap gap-3">
          <Button onClick={archiveSelected} disabled={busy}>
            Archive {selected.size} selected
          </Button>
          {canUnsubscribe && (
            <Button onClick={unsubscribeSelected} disabled={busy} variant="secondary">
              Unsubscribe selected
            </Button>
          )}
        </div>
      )}

      <div className="space-y-6">
        {candidates.map((c) => (
          <Card key={c.message_id} padding="md" className="!p-4">
            <label className="flex cursor-pointer items-start gap-3">
              <input
                type="checkbox"
                checked={selected.has(c.message_id)}
                onChange={() => toggle(c.message_id)}
                className="mt-1"
              />
              <div>
                <p className="am-title">
                  {c.sender} — {c.subject}
                </p>
                <p className="am-detail-meta mt-1">
                  {c.category} · {c.reason}
                  {c.has_unsubscribe ? " · list-unsubscribe available" : ""}
                </p>
              </div>
            </label>
          </Card>
        ))}
      </div>
    </>
  );
}
