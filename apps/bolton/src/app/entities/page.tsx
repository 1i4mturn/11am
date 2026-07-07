"use client";

import { Card, PageHeader } from "@11am/ui";
import { useEffect, useState } from "react";

export default function EntitiesPage() {
  const [entities, setEntities] = useState<Array<Record<string, unknown>>>([]);

  useEffect(() => {
    fetch("/api/entities").then((r) => r.json()).then((d) => setEntities(d.entities ?? []));
  }, []);

  return (
    <>
      <PageHeader title="Entities" description="People, projects, tools, agents — connected, not isolated notes." />
      <div className="grid gap-8 sm:grid-cols-2">
        {entities.map((e) => (
          <Card key={String(e.id)} grain padding="md">
            <p className="am-title">{String(e.name)}</p>
            <p className="am-detail-meta">{String(e.entityType)} · {String(e.importanceLevel)}</p>
            {Boolean(e.summary) && <p className="am-copy mt-3">{String(e.summary)}</p>}
          </Card>
        ))}
        {!entities.length && <p className="am-copy col-span-2 py-8 text-center">Entities build as agents contribute memory.</p>}
      </div>
    </>
  );
}
