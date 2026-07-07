"use client";

import { Button, Card, PageHeader } from "@11am/ui";
import { useEffect, useState } from "react";

interface SenderProfile {
  id: string;
  senderName: string | null;
  senderEmail: string;
  organisation: string | null;
  relationshipType: string;
  importanceLevel: string;
  preferredTone: string | null;
  lastInteractionSummary: string | null;
  activeThreadTopics: string[] | null;
  recurringTopics: string[] | null;
  responseExpectation: string | null;
  sensitivityNotes: string | null;
  disabled: boolean;
}

export default function SendersPage() {
  const [profiles, setProfiles] = useState<SenderProfile[]>([]);
  const [error, setError] = useState("");
  const [editing, setEditing] = useState<string | null>(null);
  const [form, setForm] = useState<Partial<SenderProfile>>({});

  useEffect(() => {
    fetch("/api/sender-memory")
      .then((r) => r.json())
      .then((d) => {
        if (d.error) setError(d.error);
        else setProfiles(d.profiles ?? []);
      });
  }, []);

  async function saveProfile() {
    const res = await fetch("/api/sender-memory", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        senderEmail: form.senderEmail,
        senderName: form.senderName,
        organisation: form.organisation,
        relationshipType: form.relationshipType,
        importanceLevel: form.importanceLevel,
        preferredTone: form.preferredTone,
        lastInteractionSummary: form.lastInteractionSummary,
        responseExpectation: form.responseExpectation,
        sensitivityNotes: form.sensitivityNotes,
        disabled: form.disabled,
      }),
    });
    const data = await res.json();
    if (res.ok) {
      setProfiles((p) => {
        const idx = p.findIndex((x) => x.senderEmail === data.profile.senderEmail);
        if (idx >= 0) {
          const next = [...p];
          next[idx] = data.profile;
          return next;
        }
        return [...p, data.profile];
      });
      setEditing(null);
    } else setError(data.error);
  }

  async function deleteProfile(id: string) {
    if (!confirm("Delete this sender memory?")) return;
    await fetch(`/api/sender-memory?id=${id}`, { method: "DELETE" });
    setProfiles((p) => p.filter((x) => x.id !== id));
  }

  if (error && !profiles.length) {
    return <PageHeader title="Sender memory" description={error} />;
  }

  return (
    <>
      <PageHeader
        title="Sender memory"
        description="Marc's relationship layer — view, edit, disable, or delete."
      />

      <div className="space-y-8">
        {profiles.map((p) => (
          <Card key={p.id} padding="md">
            {editing === p.id ? (
              <div className="space-y-4">
                <input
                  value={form.organisation ?? ""}
                  onChange={(e) => setForm({ ...form, organisation: e.target.value })}
                  placeholder="Organisation"
                  className="am-input am-copy w-full px-3 py-2"
                />
                <input
                  value={form.preferredTone ?? ""}
                  onChange={(e) => setForm({ ...form, preferredTone: e.target.value })}
                  placeholder="Preferred tone"
                  className="am-input am-copy w-full px-3 py-2"
                />
                <input
                  value={form.relationshipType ?? ""}
                  onChange={(e) => setForm({ ...form, relationshipType: e.target.value })}
                  placeholder="Relationship type"
                  className="am-input am-copy w-full px-3 py-2"
                />
                <input
                  value={form.responseExpectation ?? ""}
                  onChange={(e) => setForm({ ...form, responseExpectation: e.target.value })}
                  placeholder="Response expectation (prompt / normal / low)"
                  className="am-input am-copy w-full px-3 py-2"
                />
                <textarea
                  value={form.lastInteractionSummary ?? ""}
                  onChange={(e) => setForm({ ...form, lastInteractionSummary: e.target.value })}
                  placeholder="Last interaction summary"
                  rows={2}
                  className="am-input am-copy w-full px-3 py-2"
                />
                <textarea
                  value={form.sensitivityNotes ?? ""}
                  onChange={(e) => setForm({ ...form, sensitivityNotes: e.target.value })}
                  placeholder="Sensitivity notes"
                  rows={2}
                  className="am-input am-copy w-full px-3 py-2"
                />
                <div className="flex gap-2">
                  <Button onClick={saveProfile} size="sm">
                    Save
                  </Button>
                  <Button onClick={() => setEditing(null)} variant="ghost" size="sm">
                    Cancel
                  </Button>
                </div>
              </div>
            ) : (
              <>
                <div className="flex justify-between gap-4">
                  <div>
                    <p className="am-title">{p.senderName ?? p.senderEmail}</p>
                    <p className="am-detail-meta mt-1">{p.senderEmail}</p>
                    {p.organisation && <p className="am-detail-meta">{p.organisation}</p>}
                  </div>
                  <span className="am-label">
                    {p.relationshipType} · {p.importanceLevel}
                  </span>
                </div>
                {p.preferredTone && (
                  <p className="am-detail-meta mt-3">Tone: {p.preferredTone}</p>
                )}
                {p.responseExpectation && (
                  <p className="am-detail-meta">Expectation: {p.responseExpectation}</p>
                )}
                {p.lastInteractionSummary && (
                  <p className="am-copy mt-4">{p.lastInteractionSummary}</p>
                )}
                {p.activeThreadTopics && p.activeThreadTopics.length > 0 && (
                  <p className="am-detail-meta mt-2">
                    Active topics: {p.activeThreadTopics.join(", ")}
                  </p>
                )}
                {p.sensitivityNotes && (
                  <p className="am-detail-meta mt-2">{p.sensitivityNotes}</p>
                )}
                <div className="mt-4 flex gap-3">
                  <Button
                    onClick={() => {
                      setEditing(p.id);
                      setForm(p);
                    }}
                    variant="ghost"
                    size="sm"
                  >
                    Edit
                  </Button>
                  <Button onClick={() => deleteProfile(p.id)} variant="ghost" size="sm">
                    Delete
                  </Button>
                </div>
              </>
            )}
          </Card>
        ))}
        {!profiles.length && (
          <p className="am-copy py-8 text-center">
            No sender profiles yet. Marc builds these as you triage your inbox.
          </p>
        )}
      </div>
    </>
  );
}
