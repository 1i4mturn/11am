"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import type { NavItem } from "./AppShell";

export interface SectionNavProps {
  items: NavItem[];
  actions?: React.ReactNode;
}

function isActive(pathname: string, href: string) {
  if (href === "/") return pathname === "/";
  return pathname === href || pathname.startsWith(`${href}/`);
}

/** In-app section links - rendered below the page title on every agent page */
export function SectionNav({ items, actions }: SectionNavProps) {
  const pathname = usePathname();

  if (!items.length && !actions) return null;

  return (
    <div className="am-section-nav-row">
      {items.length > 0 && (
        <nav className="am-section-nav" aria-label="sections">
          {items.map((item) => {
            const active = isActive(pathname, item.href);
            return (
              <Link
                key={item.href}
                href={item.href}
                className={`am-section-nav-link${active ? " am-section-nav-link-active" : ""}`}
                aria-current={active ? "page" : undefined}
              >
                {item.label}
              </Link>
            );
          })}
        </nav>
      )}
      {actions && <div className="am-suite-actions">{actions}</div>}
    </div>
  );
}
