import { NextResponse } from "next/server";
import { getAllCategories } from "../../../../lib/db";

export async function GET() {
  return NextResponse.json(getAllCategories());
}
