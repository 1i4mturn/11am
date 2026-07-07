import type { ReactNode } from "react";

export interface PageHeaderProps {
  title: string;
  description?: string;
  eyebrow?: string;
  meta?: ReactNode;
  actions?: ReactNode;
}

/** Editorial page header — Robert agent-page pattern */
export function PageHeader({ title, description, eyebrow, meta, actions }: PageHeaderProps) {
  return (
    <header className="mb-10">
      {eyebrow && <p className="am-eyebrow">{eyebrow}</p>}
      <h1 className="am-hero am-hero-blur">{title}</h1>
      {description && <p className="am-sub">{description}</p>}
      {meta && <p className="am-detail-meta">{meta}</p>}
      {actions && <div className="mt-2 flex items-center gap-3">{actions}</div>}
    </header>
  );
}
