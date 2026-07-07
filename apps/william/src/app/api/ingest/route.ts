import { NextRequest, NextResponse } from "next/server";
import { extractContent } from "@/lib/ingestion/extract";
import { ingestCorpus } from "@/lib/ingestion";
import { getUser } from "@/lib/tiers";

export async function POST(request: NextRequest) {
  const user = await getUser();
  if (user.tier !== "pro") {
    return NextResponse.json({ error: "Ingestion requires Pro tier" }, { status: 403 });
  }

  const contentType = request.headers.get("content-type") ?? "";

  try {
    if (contentType.includes("multipart/form-data")) {
      const formData = await request.formData();
      const file = formData.get("file") as File | null;
      const url = formData.get("url") as string | null;
      const paste = formData.get("text") as string | null;

      if (paste) {
        const text = await extractContent(paste, "paste");
        const result = await ingestCorpus(text, "paste");
        return NextResponse.json({ success: true, ...result, chars: text.length });
      }

      if (url) {
        const text = await extractContent(url, "url");
        const result = await ingestCorpus(text, "url", "default", { url });
        return NextResponse.json({ success: true, ...result, chars: text.length });
      }

      if (file) {
        const buffer = Buffer.from(await file.arrayBuffer());
        const ext = file.name.split(".").pop()?.toLowerCase() ?? "txt";
        const typeMap: Record<string, "txt" | "md" | "docx" | "pdf"> = {
          txt: "txt",
          md: "md",
          docx: "docx",
          pdf: "pdf",
        };
        const type = typeMap[ext];
        if (!type) {
          return NextResponse.json({ error: "Unsupported file type" }, { status: 400 });
        }
        const text = await extractContent(buffer, type);
        const result = await ingestCorpus(text, "upload", "default", {
          filename: file.name,
        });
        return NextResponse.json({ success: true, ...result, chars: text.length });
      }

      return NextResponse.json({ error: "No content provided" }, { status: 400 });
    }

    const body = await request.json();
    if (body.text) {
      const text = await extractContent(body.text, "paste");
      const result = await ingestCorpus(text, "paste");
      return NextResponse.json({ success: true, ...result, chars: text.length });
    }

    return NextResponse.json({ error: "No content provided" }, { status: 400 });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Ingestion failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
