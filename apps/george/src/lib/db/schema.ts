import { pgTable, text, timestamp, integer, boolean, jsonb, uuid } from "drizzle-orm/pg-core";

export const users = pgTable("users", {
  id: text("id").primaryKey().default("default"),
  tier: text("tier").notNull().default("free"),
  actionsThisMonth: integer("actions_this_month").notNull().default(0),
  generationsThisMonth: integer("generations_this_month").notNull().default(0),
  monthResetAt: timestamp("month_reset_at").defaultNow().notNull(),
  stripeRestrictedKey: text("stripe_restricted_key"),
  xeroAccessToken: text("xero_access_token"),
  xeroRefreshToken: text("xero_refresh_token"),
  xeroTokenExpiry: timestamp("xero_token_expiry"),
  xeroTenantId: text("xero_tenant_id"),
  xeroConnectedAt: timestamp("xero_connected_at"),
  updatedAt: timestamp("updated_at").defaultNow().notNull(),
});

export const georgeFinancialModels = pgTable("george_financial_models", {
  id: uuid("id").defaultRandom().primaryKey(),
  userId: text("user_id").notNull().default("default"),
  name: text("name").notNull(),
  modelType: text("model_type").notNull().default("general"),
  inputs: jsonb("inputs").$type<Record<string, unknown>>().notNull().default({}),
  assumptions: jsonb("assumptions").$type<Record<string, unknown>>().notNull().default({}),
  scenarios: jsonb("scenarios").$type<unknown[]>().notNull().default([]),
  conversation: jsonb("conversation").$type<ChatMessage[]>().notNull().default([]),
  createdAt: timestamp("created_at").defaultNow().notNull(),
  updatedAt: timestamp("updated_at").defaultNow().notNull(),
});

export const georgeCalculators = pgTable("george_calculators", {
  id: uuid("id").defaultRandom().primaryKey(),
  userId: text("user_id").notNull().default("default"),
  title: text("title").notNull(),
  prompt: text("prompt").notNull(),
  storagePath: text("storage_path").notNull(),
  publicUrl: text("public_url"),
  memoryEntryId: uuid("memory_entry_id"),
  createdAt: timestamp("created_at").defaultNow().notNull(),
});

export interface ChatMessage {
  role: "user" | "assistant";
  content: string;
}
