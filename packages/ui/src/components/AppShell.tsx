import type { AgentId } from "../tokens";
import { agents, suite } from "../tokens";
import { CursorLamp } from "./CursorLamp";
import { SuiteAgentRail } from "./SuiteAgentRail";
import { SuiteAtmosphere } from "./SuiteAtmosphere";
import { SuiteLogo } from "./SuiteLogo";
import { SuiteNavProvider } from "./SuiteNavContext";

export interface NavItem {
  href: string;
  label: string;
}

export interface AppShellProps {
  agent: AgentId;
  /** In-app section links - rendered below the page title via PageHeader */
  nav?: NavItem[];
  /** @deprecated Merged into nav - pass one combined list instead */
  secondaryNav?: NavItem[];
  children: React.ReactNode;
  /** @deprecated Shell uses SVG monograms from /logos - logoSrc is ignored */
  logoSrc?: string;
  actions?: React.ReactNode;
}

export function AppShell({ agent, nav, secondaryNav, children, actions }: AppShellProps) {
  const config = agents[agent];
  const sectionNav = [...(nav ?? []), ...(secondaryNav ?? [])];

  return (
    <SuiteNavProvider items={sectionNav} actions={actions}>
      <div className="am-suite">
        <SuiteAtmosphere />
        <CursorLamp />

        <header className="am-suite-bar am-page">
          <div className="am-suite-bar-brand">
            <SuiteLogo />
          </div>
          <div className="am-suite-agent-marker">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src={`/logos/${config.logoFile}`}
              alt=""
              className="am-suite-agent-mono-img"
              aria-hidden="true"
            />
            <span className="am-suite-agent-label">
              {config.name.toLowerCase()}{" "}
              <span className="am-suite-agent-role">· {config.role}</span>
            </span>
          </div>
        </header>

        <div className="am-suite-shell">
          <aside className="am-suite-rail">
            <SuiteAgentRail current={agent} />
          </aside>

          <main className="am-page am-suite-main">{children}</main>
        </div>
      </div>
    </SuiteNavProvider>
  );
}
