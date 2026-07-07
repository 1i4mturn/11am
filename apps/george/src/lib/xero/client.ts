import { eq } from "drizzle-orm";
import { db } from "@/lib/db";
import { users } from "@/lib/db/schema";

const XERO_AUTH_URL = "https://login.xero.com/identity/connect/authorize";
const XERO_TOKEN_URL = "https://identity.xero.com/connect/token";
const XERO_CONNECTIONS_URL = "https://api.xero.com/connections";
const XERO_API = "https://api.xero.com/api.xro/2.0";

const SCOPES = [
  "openid",
  "profile",
  "email",
  "accounting.reports.read",
  "accounting.transactions.read",
  "offline_access",
].join(" ");

export function getXeroAuthUrl(): string | null {
  const clientId = process.env.XERO_CLIENT_ID;
  if (!clientId) return null;

  const redirectUri =
    process.env.XERO_REDIRECT_URI ?? "http://localhost:3004/api/xero/callback";

  const params = new URLSearchParams({
    response_type: "code",
    client_id: clientId,
    redirect_uri: redirectUri,
    scope: SCOPES,
    state: "george-xero",
  });
  return `${XERO_AUTH_URL}?${params.toString()}`;
}

export async function saveXeroTokens(
  userId: string,
  tokens: { access_token: string; refresh_token?: string; expires_in?: number },
  tenantId?: string
) {
  await db
    .update(users)
    .set({
      xeroAccessToken: tokens.access_token,
      xeroRefreshToken: tokens.refresh_token ?? undefined,
      xeroTokenExpiry: tokens.expires_in
        ? new Date(Date.now() + tokens.expires_in * 1000)
        : null,
      xeroTenantId: tenantId ?? undefined,
      xeroConnectedAt: new Date(),
      updatedAt: new Date(),
    })
    .where(eq(users.id, userId));
}

export async function getXeroAuthStatus(userId = "default") {
  const [user] = await db.select().from(users).where(eq(users.id, userId)).limit(1);
  const connected = !!user?.xeroRefreshToken;
  return {
    connected,
    tenantId: user?.xeroTenantId ?? null,
    authUrl: connected ? null : getXeroAuthUrl(),
  };
}

async function refreshXeroToken(userId: string) {
  const [user] = await db.select().from(users).where(eq(users.id, userId)).limit(1);
  if (!user?.xeroRefreshToken) throw new Error("Xero not connected");

  const res = await fetch(XERO_TOKEN_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Authorization: `Basic ${Buffer.from(
        `${process.env.XERO_CLIENT_ID}:${process.env.XERO_CLIENT_SECRET}`
      ).toString("base64")}`,
    },
    body: new URLSearchParams({
      grant_type: "refresh_token",
      refresh_token: user.xeroRefreshToken,
    }),
  });

  if (!res.ok) throw new Error("Xero token refresh failed");
  const tokens = await res.json();
  await saveXeroTokens(userId, tokens, user.xeroTenantId ?? undefined);
  return tokens.access_token as string;
}

export async function getXeroAccessToken(userId = "default"): Promise<string> {
  const [user] = await db.select().from(users).where(eq(users.id, userId)).limit(1);
  if (!user?.xeroAccessToken) throw new Error("Xero not connected");

  const expired =
    user.xeroTokenExpiry && new Date(user.xeroTokenExpiry).getTime() < Date.now() + 60_000;
  if (expired && user.xeroRefreshToken) {
    return refreshXeroToken(userId);
  }
  return user.xeroAccessToken;
}

export async function exchangeXeroCode(code: string) {
  const redirectUri =
    process.env.XERO_REDIRECT_URI ?? "http://localhost:3004/api/xero/callback";

  const tokenRes = await fetch(XERO_TOKEN_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Authorization: `Basic ${Buffer.from(
        `${process.env.XERO_CLIENT_ID}:${process.env.XERO_CLIENT_SECRET}`
      ).toString("base64")}`,
    },
    body: new URLSearchParams({
      grant_type: "authorization_code",
      code,
      redirect_uri: redirectUri,
    }),
  });

  if (!tokenRes.ok) throw new Error("Xero token exchange failed");
  const tokens = await tokenRes.json();

  const connRes = await fetch(XERO_CONNECTIONS_URL, {
    headers: { Authorization: `Bearer ${tokens.access_token}` },
  });
  const connections = (await connRes.json()) as Array<{ tenantId: string }>;
  const tenantId = connections[0]?.tenantId;

  await saveXeroTokens("default", tokens, tenantId);
  return { tenantId };
}

export async function getXeroFinancials(userId = "default") {
  const [user] = await db.select().from(users).where(eq(users.id, userId)).limit(1);
  const tenantId = user?.xeroTenantId;
  if (!tenantId) throw new Error("Xero tenant not set");

  const token = await getXeroAccessToken(userId);
  const headers = {
    Authorization: `Bearer ${token}`,
    "Xero-tenant-id": tenantId,
    Accept: "application/json",
  };

  const [plRes, bankRes] = await Promise.all([
    fetch(`${XERO_API}/Reports/ProfitAndLoss`, { headers }),
    fetch(`${XERO_API}/Reports/BankSummary`, { headers }),
  ]);

  const pl = plRes.ok ? await plRes.json() : null;
  const bank = bankRes.ok ? await bankRes.json() : null;

  return {
    profit_and_loss: pl,
    bank_summary: bank,
    tenant_id: tenantId,
  };
}
