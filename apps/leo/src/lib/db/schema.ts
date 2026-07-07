import { pgTable, text, timestamp, integer, boolean } from "drizzle-orm/pg-core";

/** Shared user record — calendar tokens stored here, not duplicated in Leo */
export const users = pgTable("users", {
  id: text("id").primaryKey().default("default"),
  tier: text("tier").notNull().default("free"),
  actionsThisMonth: integer("actions_this_month").notNull().default(0),
  generationsThisMonth: integer("generations_this_month").notNull().default(0),
  monthResetAt: timestamp("month_reset_at").defaultNow().notNull(),
  gmailAccessToken: text("gmail_access_token"),
  gmailRefreshToken: text("gmail_refresh_token"),
  gmailTokenExpiry: timestamp("gmail_token_expiry"),
  gmailHistoryId: text("gmail_history_id"),
  lastSyncAt: timestamp("last_sync_at"),
  calendarAccessToken: text("calendar_access_token"),
  calendarRefreshToken: text("calendar_refresh_token"),
  calendarTokenExpiry: timestamp("calendar_token_expiry"),
  calendarConnectedAt: timestamp("calendar_connected_at"),
  fullContentIndexing: boolean("full_content_indexing").default(false).notNull(),
  updatedAt: timestamp("updated_at").defaultNow().notNull(),
});
