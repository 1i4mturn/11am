import { NextRequest, NextResponse } from "next/server";
import { getModel } from "@/lib/models";

export async function GET(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const model = await getModel(id);
  if (!model) return NextResponse.json({ error: "Not found" }, { status: 404 });
  return NextResponse.json({ model });
}
