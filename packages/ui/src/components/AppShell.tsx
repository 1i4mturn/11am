import Link from "next/link";
import type { AgentId } from "../tokens";
import { agents } from "../tokens";
import { CursorLamp } from "./CursorLamp";
import { SuiteAgentRail } from "./SuiteAgentRail";
import { SuiteAtmosphere } from "./SuiteAtmosphere";
import { SuiteLogo } from "./SuiteLogo";

export interface NavItem {
  href: string;
  label: string;
}

export interface AppShellProps {
  agent: AgentId;
  /** In-app section links — rendered inside <main>, not in the locked shell */
  nav?: NavItem[];
  secondaryNav?: NavItem[];
  children: React.ReactNode;
  /** @deprecated Shell uses embossed text monograms — logoSrc is ignored */
  logoSrc?: string;
  actions?: React.ReactNode;
}

export function AppShell({ agent, nav, secondaryNav, children, actions }: AppShellProps) {
  const config = agents[agent];

  return (
    <div className="am-suite">
      <SuiteAtmosphere />
      <CursorLamp />

      <header className="am-suite-bar am-page">
        <SuiteLogo />
        <div className="am-suite-agent-marker">
          <span className="am-mono-emboss am-suite-agent-mono" aria-hidden="true">
            {config.monogram}
          </span>
          <span className="am-suite-agent-label">
            {config.name.toLowerCase()}{" "}
            <span className="am-suite-agent-role">· {config.role}</span>
          </span>
        </div>
      </header>

      <div className="am-suite-shell">
        <SuiteAgentRail current={agent} />

        <main className="am-page am-suite-main">
          {(nav?.length || actions) && (
            <div className="am-suite-subnav-row">
              {nav && nav.length > 0 && (
                <nav className="am-suite-subnav" aria-label="sections">
                  {nav.map((item) => (
                    <Link key={item.href} href={item.href} className="am-suite-subnav-link">
                      {item.label}
                    </Link>
                  ))}
                </nav>
              )}
              {actions && <div className="am-suite-actions">{actions}</div>}
            </div>
          )}

          {secondaryNav && secondaryNav.length > 0 && (
            <nav className="am-suite-subnav am-suite-subnav-secondary" aria-label="more sections">
              {secondaryNav.map((item) => (
                <Link key={item.href} href={item.href} className="am-suite-subnav-link am-suite-subnav-link-sub">
                  {item.label}
                </Link>
              ))}
            </nav>
          )}

          {children}
        </main>
      </div>
    </div>
  );
}
