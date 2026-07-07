import type { ReactNode } from "react";

export interface PageHeaderProps {
  title: string;
  description?: string;
  meta?: ReactNode;
  actions?: ReactNode;
}

/** Editorial page header — Robert v5 detail-page pattern, scaled for app chrome */
export function PageHeader({ title, description, meta, actions }: PageHeaderProps) {
  return (
    <div className="mb-12">
      <div className="am-detail-grid max-w-[880px]">
        <h1 className="am-detail-title">{title}</h1>
        {description && <p className="am-detail-copy">{description}</p>}
        {meta && <p className="am-detail-meta">{meta}</p>}
      </div>
      {actions && <div className="mt-6 flex items-center gap-3">{actions}</div>}
    </div>
  );
}
