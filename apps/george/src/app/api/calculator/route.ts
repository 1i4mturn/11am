import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { generateCalculatorHtml } from "@/lib/finance/engine";
import { listCalculators, saveCalculator } from "@/lib/models";
import { uploadCalculatorArtifact, isSupabaseConfigured } from "@/lib/supabase/storage";
import { writeToBolton } from "@/lib/bolton/client";

export async function GET() {
  const calculators = await listCalculators();
  return NextResponse.json({ calculators, supabase_configured: isSupabaseConfigured() });
}

const GenerateSchema = z.object({
  prompt: z.string().min(10),
  title: z.string().optional(),
});

export async function POST(request: NextRequest) {
  try {
    const body = GenerateSchema.parse(await request.json());
    const html = await generateCalculatorHtml(body.prompt);
    const cleanHtml = html.replace(/^```html?\n?/i, "").replace(/\n?```$/i, "").trim();

    const title = body.title ?? body.prompt.slice(0, 60);
    let storagePath = `local/${Date.now()}.html`;
    let publicUrl: string | null = null;

    if (isSupabaseConfigured()) {
      const uploaded = await uploadCalculatorArtifact(`${title.replace(/\s+/g, "-")}.html`, cleanHtml);
      if (uploaded) {
        storagePath = uploaded.path;
        publicUrl = uploaded.publicUrl;
      }
    }

    const memory = await writeToBolton({
      source_agent: "George",
      entry_type: "other",
      title: `Calculator: ${title}`,
      summary: `Self-contained calculator artifact - ${body.prompt.slice(0, 200)}`,
      full_content: JSON.stringify({ prompt: body.prompt, storage_path: storagePath, public_url: publicUrl }),
      tags: ["calculator", "george", "artifact"],
      force: true,
    });

    const calc = await saveCalculator({
      title,
      prompt: body.prompt,
      storagePath,
      publicUrl,
      memoryEntryId: memory?.id,
    });

    return NextResponse.json({
      calculator: calc,
      html: isSupabaseConfigured() ? undefined : cleanHtml,
      public_url: publicUrl,
      memory_id: memory?.id,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Generate failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
