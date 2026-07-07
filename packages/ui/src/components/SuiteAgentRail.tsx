import type { AgentId } from "../tokens";
import { agentRoster, agents, getAgentAppUrl } from "../tokens";

export interface SuiteAgentRailProps {
  current: AgentId;
}

/** Left rail — 11 flat tiles, identical on every agent page */
export function SuiteAgentRail({ current }: SuiteAgentRailProps) {
  return (
    <nav className="am-suite-rail" aria-label="agents">
      <div className="am-suite-tilegrid">
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
              <span className="am-mono-flat">{config.monogram}</span>
            </a>
          );
        })}
      </div>
    </nav>
  );
}
