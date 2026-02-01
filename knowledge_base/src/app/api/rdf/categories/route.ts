import { NextResponse } from "next/server";
import { getAllCategories, getCategoryJsonLd } from "../../../../../lib/db";

export async function GET() {
  const categories = getAllCategories();
  const jsonLd = {
    "@context": {
      "@vocab": "https://schema.org/",
      skos: "http://www.w3.org/2004/02/skos/core#",
    },
    "@graph": categories.map((c) => getCategoryJsonLd(c)),
  };

  return NextResponse.json(jsonLd, {
    headers: {
      "Content-Type": "application/ld+json; charset=utf-8",
    },
  });
}
