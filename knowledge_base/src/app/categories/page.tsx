import Link from "next/link";
import { getAllCategories } from "../../../lib/db";

export default function CategoriesPage() {
  const categories = getAllCategories();

  return (
    <div className="space-y-8">
      <div className="space-y-2">
        <h1 className="text-3xl font-bold tracking-tight">Categories</h1>
        <p className="text-muted">
          Browse all script categories in the toolkit.
        </p>
      </div>

      <div className="divide-y divide-border rounded-lg border border-border">
        {categories.map((cat) => (
          <Link
            key={cat.slug}
            href={`/categories/${cat.slug}`}
            className="flex items-center justify-between px-6 py-5 transition-colors hover:bg-surface"
          >
            <div>
              <h2 className="font-semibold">{cat.name}</h2>
              <p className="mt-1 text-sm text-muted">{cat.description}</p>
            </div>
            <div className="flex items-center gap-3">
              <span className="rounded-full bg-accent px-3 py-1 text-xs font-medium text-background">
                {cat.script_count}
              </span>
              <svg
                className="shrink-0 text-muted"
                width="16"
                height="16"
                fill="none"
                stroke="currentColor"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
                viewBox="0 0 24 24"
              >
                <path d="m9 18 6-6-6-6" />
              </svg>
            </div>
          </Link>
        ))}
      </div>
    </div>
  );
}
