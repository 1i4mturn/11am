import type { AgentId } from "../tokens";
import { agentRoster, agents, getAgentAppUrl } from "../tokens";

export interface SuiteAgentRailProps {
  current: AgentId;
}

/** Left rail - 11 flat tiles with SVG monograms, identical on every agent page */
export function SuiteAgentRail({ current }: SuiteAgentRailProps) {
  return (
    <nav className="am-suite-tilegrid" aria-label="agents">
      {agentRoster.map((id) => {
        const config = agents[id];
        const isCurrent = id === current;
        const title = `${config.name.toLowerCase()} · ${config.role}`;

        return (
          <a
            key={id}
            href={getAgentAppUrl(id)}
            className={`am-suite-tile${isCurrent ? " am-suite-tile-current" : ""}`}
            title={title}
            aria-current={isCurrent ? "page" : undefined}
          >
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src={`/logos/${config.logoFile}`}
              alt=""
              className="am-suite-tile-logo"
              aria-hidden="true"
            />
          </a>
        );
      })}
    </nav>
  );
}
