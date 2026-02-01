import { NextRequest, NextResponse } from "next/server";
import { searchScripts, getAllScripts } from "../../../../lib/db";

export async function GET(request: NextRequest) {
  const q = request.nextUrl.searchParams.get("q") ?? "";
  const scripts = q.trim() ? searchScripts(q) : getAllScripts();
  return NextResponse.json(scripts);
}
