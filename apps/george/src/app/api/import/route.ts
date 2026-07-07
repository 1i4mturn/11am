import { NextRequest, NextResponse } from "next/server";
import { parseSpreadsheet } from "@/lib/import/spreadsheet";
import { askGeorge } from "@/lib/claude";
import { detectTaxFlags } from "@/lib/finance/tax";

export async function POST(request: NextRequest) {
  try {
    const formData = await request.formData();
    const file = formData.get("file");
    if (!file || !(file instanceof File)) {
      return NextResponse.json({ error: "No file uploaded" }, { status: 400 });
    }

    const buffer = Buffer.from(await file.arrayBuffer());
    const { sheets, textSummary } = parseSpreadsheet(buffer);

    const analysis = await askGeorge(
      "Analyse this imported spreadsheet data. Summarise key financial figures, trends, and anything that looks like P&L, cash flow, or unit economics. Markdown output.",
      textSummary.slice(0, 12000),
      4000
    );

    const tax_flags = await detectTaxFlags(analysis);

    return NextResponse.json({
      filename: file.name,
      sheet_count: sheets.length,
      sheet_names: sheets.map((s) => s.name),
      analysis,
      tax_flags,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Import failed";
    return NextResponse.json({ error: message }, { status: 500 });
  }
}
