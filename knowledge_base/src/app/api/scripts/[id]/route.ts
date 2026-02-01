import { NextRequest, NextResponse } from "next/server";
import { getScriptById, getParametersForScript, getTagsForScript } from "../../../../../lib/db";

export async function GET(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const script = getScriptById(Number(id));
  if (!script) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }
  const parameters = getParametersForScript(script.id);
  const tags = getTagsForScript(script.id);
  return NextResponse.json({ ...script, parameters, tags });
}
