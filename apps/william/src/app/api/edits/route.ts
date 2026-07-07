import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { queueProfileUpdate } from "@/lib/voice/profile-jobs";
import { db } from "@/lib/db";
import { generations } from "@/lib/db/schema";
import { eq } from "drizzle-orm";
import { getUser } from "@/lib/tiers";
import { isPro } from "@/lib/config";

const EditSchema = z.object({
  generationId: z.string().uuid(),
  editedOutput: z.string().min(1),
});

export async function POST(request: NextRequest) {
  try {
    const userId = "default";
    const user = await getUser(userId);

    if (!isPro(user.tier)) {
      return NextResponse.json(
        { error: "Edit learning requires Pro tier" },
        { status: 403 }
      );
    }

    const body = EditSchema.parse(await request.json());

    const [gen] = await db
      .select()
      .from(generations)
      .where(eq(generations.id, body.generationId))
      .limit(1);

    if (!gen) {
      return NextResponse.json({ error: "Generation not found" }, { status: 404 });
    }

    await db
      .update(generations)
      .set({ editedOutput: body.editedOutput })
      .where(eq(generations.id, body.generationId));

    await queueProfileUpdate(userId, "edit", {
      originalOutput: gen.output,
      editedOutput: body.editedOutput,
    });

    return NextResponse.json({ success: true, message: "Edit logged. Profile updating in background." });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Edit logging failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
