import Link from "next/link";
import type { AgentId } from "../tokens";
import { agents } from "../tokens";
import { SuiteAtmosphere } from "./SuiteAtmosphere";
import { SuiteLogo } from "./SuiteLogo";

export interface NavItem {
  href: string;
  label: string;
}

export interface AppShellProps {
  agent: AgentId;
  nav: NavItem[];
  /** Extra links shown in a second row — use when an agent has many sections (e.g. Marc) */
  secondaryNav?: NavItem[];
  children: React.ReactNode;
  /** Path to agent logo in public folder, e.g. /logos/william_wm.svg */
  logoSrc?: string;
  actions?: React.ReactNode;
}

export function AppShell({ agent, nav, secondaryNav, children, logoSrc, actions }: AppShellProps) {
  const config = agents[agent];
  const agentLogo = logoSrc ?? `/logos/${config.logoFile}`;

  return (
    <div className="am-suite">
      <SuiteAtmosphere />

      <header className="am-suite-header am-page">
        <div className="am-suite-header-inner">
          <SuiteLogo />

          <div className="am-suite-agent-marker">
            {agentLogo ? (
              <img src={agentLogo} alt="" className="am-suite-agent-mono" aria-hidden="true" />
            ) : (
              <span className="am-suite-agent-mono am-suite-agent-mono-text">{config.monogram}</span>
            )}
            <span className="am-suite-agent-label">
              {config.name.toLowerCase()} · {config.role}
            </span>
          </div>
        </div>

        <div className="am-suite-nav-row">
          <nav className="am-suite-nav">
            {nav.map((item) => (
              <Link key={item.href} href={item.href} className="am-suite-nav-link">
                {item.label}
              </Link>
            ))}
          </nav>
          {actions && <div className="am-suite-actions">{actions}</div>}
        </div>

        {secondaryNav && secondaryNav.length > 0 && (
          <nav className="am-suite-nav am-suite-nav-secondary">
            {secondaryNav.map((item) => (
              <Link key={item.href} href={item.href} className="am-suite-nav-link am-suite-nav-link-sub">
                {item.label}
              </Link>
            ))}
          </nav>
        )}
      </header>

      <main className="am-page am-suite-main">{children}</main>
    </div>
  );
}
