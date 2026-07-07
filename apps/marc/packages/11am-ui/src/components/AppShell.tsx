import Link from "next/link";
import type { AgentId } from "../tokens";
import { agents, brand } from "../tokens";

export interface NavItem {
  href: string;
  label: string;
}

export interface AppShellProps {
  agent: AgentId;
  nav: NavItem[];
  children: React.ReactNode;
  /** Path to agent logo in public folder, e.g. /logos/william_wm.svg */
  logoSrc?: string;
  actions?: React.ReactNode;
}

export function AppShell({ agent, nav, children, logoSrc, actions }: AppShellProps) {
  const config = agents[agent];

  return (
    <div className="am-grain min-h-full flex flex-col">
      <header className="am-page border-b border-border bg-surface/90 backdrop-blur-sm sticky top-0 z-20">
        <div className="mx-auto flex max-w-6xl items-center justify-between px-6 py-4">
          <Link href="/" className="flex items-center gap-3 group">
            {logoSrc ? (
              <img src={logoSrc} alt={config.name} className="h-9 w-9" />
            ) : (
              <div className="flex h-9 w-9 items-center justify-center rounded-full border border-border bg-surface text-[10px] font-bold tracking-widest uppercase text-graphite">
                {config.monogram}
              </div>
            )}
            <div>
              <p className="am-title text-sm">{config.name}</p>
              <p className="am-label mt-0.5">
                {config.role} · {brand.name}
              </p>
            </div>
          </Link>
          <div className="flex items-center gap-4">
            <nav className="hidden sm:flex items-center gap-4 text-sm">
              {nav.map((item) => (
                <Link
                  key={item.href}
                  href={item.href}
                  className="text-muted hover:text-foreground transition-colors am-copy"
                >
                  {item.label}
                </Link>
              ))}
            </nav>
            {actions}
          </div>
        </div>
      </header>
      <main className="am-page flex-1">{children}</main>
      <footer className="am-page border-t border-border py-4">
        <p className="text-center am-label">{brand.suiteLabel}</p>
      </footer>
    </div>
  );
}
