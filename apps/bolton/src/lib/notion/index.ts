import type { CaptureCandidate } from "@/lib/types";

const NOTION_VERSION = "2022-06-28";

interface NotionSyncResult {
  synced: boolean;
  notion_page_id?: string;
  action?: "created" | "updated" | "skipped" | "appended";
  reason?: string;
}

function notionConfigured(): boolean {
  return !!process.env.NOTION_API_KEY;
}

function memoryDbConfigured(): boolean {
  return !!(process.env.NOTION_API_KEY && process.env.NOTION_MEMORY_DATABASE_ID);
}

async function notionRequest(path: string, method: string, body?: unknown) {
  const res = await fetch(`https://api.notion.com/v1${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${process.env.NOTION_API_KEY}`,
      "Notion-Version": NOTION_VERSION,
      "Content-Type": "application/json",
    },
    body: body ? JSON.stringify(body) : undefined,
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Notion API ${res.status}: ${text.slice(0, 400)}`);
  }

  return res.json();
}

/** Sync a memory entry to Notion — updates existing page by title match or creates new */
export async function syncEntryToNotion(
  entryId: string,
  candidate: CaptureCandidate
): Promise<NotionSyncResult> {
  if (!memoryDbConfigured()) {
    return {
      synced: false,
      reason: "Notion memory DB not configured (NOTION_API_KEY + NOTION_MEMORY_DATABASE_ID)",
    };
  }

  const databaseId = process.env.NOTION_MEMORY_DATABASE_ID!;

  try {
    const query = await notionRequest(`/databases/${databaseId}/query`, "POST", {
      filter: {
        property: "Title",
        title: { equals: candidate.title.slice(0, 100) },
      },
      page_size: 1,
    });

    const properties = buildMemoryProperties(entryId, candidate);

    const existing = query.results?.[0];
    if (existing?.id) {
      await notionRequest(`/pages/${existing.id}`, "PATCH", {
        properties,
        archived: false,
      });
      return { synced: true, notion_page_id: existing.id, action: "updated" };
    }

    const created = await notionRequest("/pages", "POST", {
      parent: { database_id: databaseId },
      properties,
    });

    return { synced: true, notion_page_id: created.id, action: "created" };
  } catch (error) {
    return {
      synced: false,
      reason: error instanceof Error ? error.message : "Notion sync failed",
    };
  }
}

function buildMemoryProperties(entryId: string, candidate: CaptureCandidate) {
  const props: Record<string, unknown> = {
    Title: { title: [{ text: { content: candidate.title.slice(0, 100) } }] },
    Summary: {
      rich_text: [{ text: { content: candidate.summary.slice(0, 2000) } }],
    },
    Agent: { select: { name: candidate.source_agent } },
    Type: { select: { name: candidate.entry_type } },
    BoltonId: { rich_text: [{ text: { content: entryId } }] },
  };

  if (candidate.cadence) {
    props.Cadence = { select: { name: candidate.cadence } };
  }

  return props;
}

/** Archive stale Notion page when Bolton entry is archived/superseded */
export async function archiveNotionPageByTitle(title: string): Promise<NotionSyncResult> {
  if (!memoryDbConfigured()) {
    return { synced: false, reason: "Notion memory DB not configured" };
  }

  const databaseId = process.env.NOTION_MEMORY_DATABASE_ID!;

  try {
    const query = await notionRequest(`/databases/${databaseId}/query`, "POST", {
      filter: {
        property: "Title",
        title: { equals: title.slice(0, 100) },
      },
      page_size: 1,
    });

    const page = query.results?.[0];
    if (!page?.id) return { synced: false, reason: "No matching Notion page" };

    await notionRequest(`/pages/${page.id}`, "PATCH", { archived: true });
    return { synced: true, notion_page_id: page.id, action: "updated" };
  } catch (error) {
    return {
      synced: false,
      reason: error instanceof Error ? error.message : "Notion archive failed",
    };
  }
}

/** Append build-session blocks to a LiamOS project page (NOTION_11AM_PROJECT_PAGE_ID) */
export async function appendBuildSessionToNotion(
  title: string,
  sections: Array<{ heading: string; bullets: string[] }>
): Promise<NotionSyncResult> {
  const pageId = process.env.NOTION_11AM_PROJECT_PAGE_ID;
  if (!notionConfigured() || !pageId) {
    return {
      synced: false,
      reason: "Set NOTION_API_KEY and NOTION_11AM_PROJECT_PAGE_ID to append build logs",
    };
  }

  const children = [
    {
      object: "block",
      type: "heading_2",
      heading_2: {
        rich_text: [{ type: "text", text: { content: title.slice(0, 200) } }],
      },
    },
    {
      object: "block",
      type: "paragraph",
      paragraph: {
        rich_text: [
          {
            type: "text",
            text: { content: new Date().toISOString().slice(0, 10) + " — filed from Bolton build session" },
          },
        ],
      },
    },
    ...sections.flatMap((section) => [
      {
        object: "block",
        type: "heading_3",
        heading_3: {
          rich_text: [{ type: "text", text: { content: section.heading.slice(0, 200) } }],
        },
      },
      ...section.bullets.map((bullet) => ({
        object: "block",
        type: "bulleted_list_item",
        bulleted_list_item: {
          rich_text: [{ type: "text", text: { content: bullet.slice(0, 2000) } }],
        },
      })),
    ]),
  ];

  try {
    await notionRequest(`/blocks/${pageId}/children`, "PATCH", { children });
    return { synced: true, notion_page_id: pageId, action: "appended" };
  } catch (error) {
    return {
      synced: false,
      reason: error instanceof Error ? error.message : "Notion append failed",
    };
  }
}

/** Create a row in a Notion database (Decision Log, Memory Bank, etc.) */
export async function createNotionDatabaseRow(
  databaseId: string,
  properties: Record<string, unknown>
): Promise<NotionSyncResult> {
  if (!notionConfigured()) {
    return { synced: false, reason: "NOTION_API_KEY not set" };
  }

  try {
    const created = await notionRequest("/pages", "POST", {
      parent: { database_id: databaseId },
      properties,
    });
    return { synced: true, notion_page_id: created.id, action: "created" };
  } catch (error) {
    return {
      synced: false,
      reason: error instanceof Error ? error.message : "Notion create failed",
    };
  }
}

export async function getNotionStatus() {
  return {
    configured: notionConfigured(),
    memory_database: process.env.NOTION_MEMORY_DATABASE_ID ? "set" : "missing",
    project_page: process.env.NOTION_11AM_PROJECT_PAGE_ID ? "set" : "missing",
    decision_log_database: process.env.NOTION_DECISION_LOG_DATABASE_ID ? "set" : "missing",
    memory_bank_database: process.env.NOTION_MEMORY_BANK_DATABASE_ID ? "set" : "missing",
  };
}
