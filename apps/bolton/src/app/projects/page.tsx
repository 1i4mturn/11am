"use client";

import { Card, PageHeader } from "@11am/ui";
import { useEffect, useState } from "react";

interface MemoryEntry {
  id: string;
  title: string;
  summary: string;
  source_agent: string;
  status: string;
  created_at: string;
}

export default function ProjectsPage() {
  const [projects, setProjects] = useState<MemoryEntry[]>([]);

  useEffect(() => {
    fetch("/api/memory?entry_type=project")
      .then((r) => r.json())
      .then((d) => setProjects(d.entries ?? []));
  }, []);

  return (
    <>
      <PageHeader
        title="Projects"
        description="Active project memory from all agents — sourced from Bolton entries tagged as projects."
      />

      <div className="space-y-8">
        {projects.map((p) => (
          <Card key={p.id} grain padding="md">
            <div className="flex justify-between gap-4">
              <h2 className="am-title">{p.title}</h2>
              <span className="am-label">{p.status}</span>
            </div>
            <p className="am-detail-meta mt-1">{p.source_agent}</p>
            <p className="am-copy mt-4">{p.summary}</p>
          </Card>
        ))}
        {!projects.length && (
          <p className="am-copy py-12 text-center">No project entries yet.</p>
        )}
      </div>
    </>
  );
}
