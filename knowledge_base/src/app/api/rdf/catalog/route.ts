import { NextResponse } from "next/server";
import { getAllCategories, getStats, getCatalogJsonLd } from "../../../../../lib/db";

export async function GET() {
  const categories = getAllCategories();
  const stats = getStats();
  const jsonLd = getCatalogJsonLd(categories, stats);

  return NextResponse.json(jsonLd, {
    headers: {
      "Content-Type": "application/ld+json; charset=utf-8",
    },
  });
}
