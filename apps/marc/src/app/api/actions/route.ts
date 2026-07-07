import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import {
  archiveMessages,
  applyLabel,
  createDraftReply,
  sendReply,
  markRead,
} from "@/lib/gmail/actions";
import { getMessageById } from "@/lib/gmail/sync";

const ActionSchema = z.object({
  action: z.enum(["archive", "label", "draft", "send", "mark_read"]),
  messageIds: z.array(z.string()).optional(),
  threadId: z.string().optional(),
  labelName: z.string().optional(),
  replyBody: z.string().optional(),
  confirmed: z.literal(true),
});

export async function POST(request: NextRequest) {
  try {
    const body = ActionSchema.parse(await request.json());

    if (!body.confirmed) {
      return NextResponse.json({ error: "User confirmation required" }, { status: 400 });
    }

    switch (body.action) {
      case "archive":
        if (!body.messageIds?.length) throw new Error("messageIds required");
        await archiveMessages(body.messageIds, "default", true);
        return NextResponse.json({ success: true, action: "archive" });

      case "label":
        if (!body.messageIds?.length || !body.labelName) {
          throw new Error("messageIds and labelName required");
        }
        await applyLabel(body.messageIds, body.labelName, "default", true);
        return NextResponse.json({ success: true, action: "label" });

      case "mark_read":
        if (!body.messageIds?.length) throw new Error("messageIds required");
        await markRead(body.messageIds, "default", true);
        return NextResponse.json({ success: true, action: "mark_read" });

      case "draft":
      case "send": {
        if (!body.threadId || !body.replyBody || !body.messageIds?.[0]) {
          throw new Error("threadId, replyBody, and messageId required");
        }
        const msg = await getMessageById(body.messageIds[0]);
        if (!msg) throw new Error("Message not found");

        if (body.action === "draft") {
          const draft = await createDraftReply(
            body.threadId,
            msg.senderEmail,
            msg.subject,
            body.replyBody,
            "default",
            true
          );
          return NextResponse.json({ success: true, action: "draft", draftId: draft.id });
        }

        const sent = await sendReply(
          body.threadId,
          msg.senderEmail,
          msg.subject,
          body.replyBody,
          "default",
          true
        );
        return NextResponse.json({ success: true, action: "send", messageId: sent.id });
      }

      default:
        return NextResponse.json({ error: "Unknown action" }, { status: 400 });
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : "Action failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
