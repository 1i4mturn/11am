/** Hardcoded connector registry - OAuth setup entry points for LiamOS v1 */

export interface ConnectorDefinition {
  id: string;
  name: string;
  agent: string;
  agentId: string;
  description: string;
  /** App base URL (e.g. http://localhost:3001) */
  appUrl: string;
  /** Path on that app with connect UI fallback */
  setupPath: string;
  /** Server route that returns { connected, authUrl, needsReauth?, message? } */
  statusPath: string;
  envHint: string;
}

export const CONNECTORS: ConnectorDefinition[] = [
  {
    id: "marc-gmail",
    name: "Gmail",
    agent: "marc",
    agentId: "marc",
    description: "Inbox triage, priority classification, and reply drafts",
    appUrl: "http://localhost:3001",
    setupPath: "/",
    statusPath: "/api/gmail",
    envHint: "GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, GOOGLE_REDIRECT_URI → :3001/api/gmail/callback",
  },
  {
    id: "william-gmail",
    name: "Gmail (voice corpus)",
    agent: "william",
    agentId: "william",
    description: "Sent-mail ingestion for voice profile training",
    appUrl: "http://localhost:3000",
    setupPath: "/setup",
    statusPath: "/api/gmail",
    envHint: "Same Google OAuth app; redirect → :3000/api/gmail/callback · Pro tier",
  },
  {
    id: "leo-calendar",
    name: "Google Calendar",
    agent: "leo",
    agentId: "leo",
    description: "Calendar events + Bolton scheduled tasks on Leo's board",
    appUrl: "http://localhost:3006",
    setupPath: "/calendar",
    statusPath: "/api/calendar",
    envHint: "GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, GOOGLE_REDIRECT_URI → :3006/api/calendar/callback",
  },
  {
    id: "george-xero",
    name: "Xero",
    agent: "george",
    agentId: "george",
    description: "P&L, cash position, and finance snapshots",
    appUrl: "http://localhost:3004",
    setupPath: "/integrations",
    statusPath: "/api/xero",
    envHint: "XERO_CLIENT_ID, XERO_CLIENT_SECRET, XERO_REDIRECT_URI → :3004/api/xero/callback",
  },
];
