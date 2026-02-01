import Link from "next/link";
import { notFound } from "next/navigation";
import {
  getCategoryBySlug,
  getScriptsByCategory,
  getParametersForScript,
} from "../../../../lib/db";

const kcsColors: Record<string, string> = {
  draft: "#ca8a04",
  approved: "#2563eb",
  published: "#16a34a",
  retired: "#9ca3af",
};

export default async function CategoryPage({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  const category = getCategoryBySlug(slug);
  if (!category) notFound();

  const scripts = getScriptsByCategory(category.id);

  // Group by subcategory
  const grouped = scripts.reduce(
    (acc, s) => {
      const key = s.subcategory || "General";
      if (!acc[key]) acc[key] = [];
      acc[key].push(s);
      return acc;
    },
    {} as Record<string, typeof scripts>
  );

  return (
    <div className="space-y-8">
      {/* Breadcrumb */}
      <nav className="flex items-center gap-2 text-sm text-muted">
        <Link href="/categories" className="hover:text-foreground">
          Categories
        </Link>
        <span>/</span>
        <span className="text-foreground">{category.name}</span>
      </nav>

      <div className="space-y-2">
        <h1 className="text-3xl font-bold tracking-tight">{category.name}</h1>
        <p className="text-muted">{category.description}</p>
        <p className="text-sm text-muted">
          {category.script_count} script
          {category.script_count !== 1 ? "s" : ""} in this category
        </p>
      </div>

      {Object.entries(grouped).map(([sub, subScripts]) => (
        <section key={sub} className="space-y-4">
          <h2 className="flex items-center gap-2 text-lg font-semibold">
            <span className="h-px flex-1 bg-border" />
            <span className="px-2">{sub}</span>
            <span className="h-px flex-1 bg-border" />
          </h2>
          <div className="space-y-3">
            {subScripts.map((script) => {
              const paramCount = getParametersForScript(script.id).length;
              return (
                <Link
                  key={script.id}
                  href={`/scripts/${script.id}`}
                  className="block rounded-lg border border-border p-5 transition-all hover:border-foreground/20 hover:bg-surface"
                >
                  <div className="flex items-start justify-between gap-4">
                    <div className="min-w-0">
                      <div className="flex flex-wrap items-center gap-2">
                        <span className="font-semibold">{script.name}</span>
                        <span
                          className="rounded-full px-1.5 py-0.5 text-[10px] font-medium text-white"
                          style={{ backgroundColor: kcsColors[script.kcs_state] || kcsColors.draft }}
                        >
                          {script.kcs_state}
                        </span>
                        {script.supports_whatif === 1 && (
                          <span className="rounded border border-border px-1.5 py-0.5 text-[10px] font-medium text-muted">
                            WhatIf
                          </span>
                        )}
                        {script.supports_csv_export === 1 && (
                          <span className="rounded border border-border px-1.5 py-0.5 text-[10px] font-medium text-muted">
                            CSV
                          </span>
                        )}
                      </div>
                      <p className="mt-1.5 text-sm text-muted">
                        {script.synopsis}
                      </p>
                      <div className="mt-2 font-mono text-xs text-muted">
                        {script.file_path}
                      </div>
                    </div>
                    <div className="flex shrink-0 items-center gap-2">
                      {paramCount > 0 && (
                        <span className="text-xs text-muted">
                          {paramCount} param{paramCount !== 1 ? "s" : ""}
                        </span>
                      )}
                      <svg
                        className="text-muted"
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
                  </div>
                </Link>
              );
            })}
          </div>
        </section>
      ))}
    </div>
  );
}
