"use client";

import type { ReactNode } from "react";
import { SectionNav } from "./SectionNav";
import { useSuiteNav } from "./SuiteNavContext";

export interface PageHeaderProps {
  title: string;
  description?: string;
  eyebrow?: string;
  meta?: ReactNode;
  actions?: ReactNode;
}

/** Editorial page header - title, description, then section nav (from AppShell) */
export function PageHeader({ title, description, eyebrow, meta, actions }: PageHeaderProps) {
  const { items, actions: shellActions } = useSuiteNav();

  return (
    <header className="am-page-intro">
      {eyebrow && <p className="am-eyebrow">{eyebrow}</p>}
      <h1 className="am-hero am-hero-blur">{title}</h1>
      {description && <p className="am-sub">{description}</p>}
      {meta && <p className="am-detail-meta">{meta}</p>}
      {actions && <div className="mt-2 flex items-center gap-3">{actions}</div>}
      <SectionNav items={items} actions={shellActions} />
    </header>
  );
}
