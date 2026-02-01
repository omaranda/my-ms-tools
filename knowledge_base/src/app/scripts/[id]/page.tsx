import Link from "next/link";
import { notFound } from "next/navigation";
import {
  getScriptById,
  getParametersForScript,
  getTagsForScript,
  getContributorsForScript,
  getScriptJsonLd,
  incrementViewCount,
} from "../../../../lib/db";

const kcsStateColors: Record<string, string> = {
  draft: "var(--color-kcs-draft)",
  approved: "var(--color-kcs-approved)",
  published: "var(--color-kcs-published)",
  retired: "var(--color-kcs-retired)",
};

function ConfidenceBar({ value }: { value: number }) {
  const color =
    value >= 80
      ? "var(--color-confidence-high)"
      : value >= 50
        ? "var(--color-confidence-mid)"
        : "var(--color-confidence-low)";
  return (
    <div className="flex items-center gap-2">
      <div className="h-2 w-24 rounded-full bg-border">
        <div
          className="h-2 rounded-full transition-all"
          style={{ width: `${value}%`, backgroundColor: color }}
        />
      </div>
      <span className="text-xs font-medium">{value}%</span>
    </div>
  );
}

export default async function ScriptDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const script = getScriptById(Number(id));
  if (!script) notFound();

  // KCS: track article views
  incrementViewCount(script.id);

  const parameters = getParametersForScript(script.id);
  const tags = getTagsForScript(script.id);
  const contributors = getContributorsForScript(script.id);
  const jsonLd = getScriptJsonLd(script, parameters, tags);

  return (
    <div className="space-y-10">
      {/* JSON-LD structured data for this script */}
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
      />

      {/* Breadcrumb */}
      <nav className="flex items-center gap-2 text-sm text-muted">
        <Link href="/categories" className="hover:text-foreground">
          Categories
        </Link>
        <span>/</span>
        <Link
          href={`/categories/${script.category_slug}`}
          className="hover:text-foreground"
        >
          {script.category_name}
        </Link>
        <span>/</span>
        <span className="text-foreground">{script.name}</span>
      </nav>

      {/* Header */}
      <div className="space-y-4">
        <div className="flex flex-wrap items-center gap-3">
          <div className="flex h-12 w-12 items-center justify-center rounded-lg bg-accent text-sm font-bold text-background">
            PS
          </div>
          <div>
            <h1 className="text-3xl font-bold tracking-tight">
              {script.name}
            </h1>
            {script.subcategory && (
              <span className="text-sm text-muted">{script.subcategory}</span>
            )}
          </div>
        </div>

        <p className="text-lg text-muted">{script.synopsis}</p>

        {/* Badges */}
        <div className="flex flex-wrap gap-2">
          {/* KCS State Badge */}
          <span
            className="rounded-md px-2.5 py-1 text-xs font-medium text-white"
            style={{ backgroundColor: kcsStateColors[script.kcs_state] || kcsStateColors.draft }}
          >
            KCS: {script.kcs_state.charAt(0).toUpperCase() + script.kcs_state.slice(1)}
          </span>
          {script.supports_whatif === 1 && (
            <span className="rounded-md border border-border px-2.5 py-1 text-xs font-medium">
              Supports -WhatIf
            </span>
          )}
          {script.supports_csv_export === 1 && (
            <span className="rounded-md border border-border px-2.5 py-1 text-xs font-medium">
              CSV Export
            </span>
          )}
          <a
            href={`/api/rdf/scripts/${script.id}`}
            className="rounded-md border border-border px-2.5 py-1 text-xs font-medium text-muted transition-colors hover:text-foreground"
            title="View JSON-LD / RDF representation"
          >
            JSON-LD
          </a>
        </div>
      </div>

      {/* KCS Metadata */}
      <section className="grid gap-4 sm:grid-cols-2">
        <div className="rounded-lg border border-border p-5 space-y-3">
          <h2 className="text-sm font-semibold uppercase tracking-wider text-muted">
            KCS Article Info
          </h2>
          <div className="space-y-2 text-sm">
            <div className="flex justify-between">
              <span className="text-muted">Confidence</span>
              <ConfidenceBar value={script.confidence} />
            </div>
            <div className="flex justify-between">
              <span className="text-muted">Views</span>
              <span className="font-mono text-xs">{script.view_count}</span>
            </div>
            <div className="flex justify-between">
              <span className="text-muted">Author</span>
              <span className="text-xs">{script.author || "Unknown"}</span>
            </div>
            {script.last_reviewed_at && (
              <div className="flex justify-between">
                <span className="text-muted">Last Reviewed</span>
                <span className="text-xs">
                  {new Date(script.last_reviewed_at).toLocaleDateString()}
                </span>
              </div>
            )}
          </div>
        </div>

        {(script.environment || script.cause) && (
          <div className="rounded-lg border border-border p-5 space-y-3">
            <h2 className="text-sm font-semibold uppercase tracking-wider text-muted">
              Environment &amp; Context
            </h2>
            {script.environment && (
              <div>
                <div className="text-xs font-medium text-muted mb-1">Environment</div>
                <p className="text-sm">{script.environment}</p>
              </div>
            )}
            {script.cause && (
              <div>
                <div className="text-xs font-medium text-muted mb-1">Cause / Use Case</div>
                <p className="text-sm">{script.cause}</p>
              </div>
            )}
          </div>
        )}
      </section>

      {/* KCS Resolution */}
      {script.resolution && (
        <section className="space-y-3">
          <h2 className="text-sm font-semibold uppercase tracking-wider text-muted">
            Resolution
          </h2>
          <div className="rounded-lg border border-border bg-surface p-5">
            <p className="text-sm leading-relaxed">{script.resolution}</p>
          </div>
        </section>
      )}

      {/* File path */}
      <section className="space-y-2">
        <h2 className="text-sm font-semibold uppercase tracking-wider text-muted">
          File Path
        </h2>
        <div className="rounded-lg bg-surface px-5 py-3 font-mono text-sm">
          {script.file_path}
        </div>
      </section>

      {/* Description */}
      {script.description && (
        <section className="space-y-3">
          <h2 className="text-sm font-semibold uppercase tracking-wider text-muted">
            Description
          </h2>
          <p className="leading-relaxed">{script.description}</p>
        </section>
      )}

      {/* Parameters */}
      {parameters.length > 0 && (
        <section className="space-y-4">
          <h2 className="text-sm font-semibold uppercase tracking-wider text-muted">
            Parameters
          </h2>
          <div className="overflow-hidden rounded-lg border border-border">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-border bg-surface text-left">
                  <th className="px-5 py-3 font-medium">Name</th>
                  <th className="px-5 py-3 font-medium">Description</th>
                  <th className="px-5 py-3 font-medium">Required</th>
                  <th className="px-5 py-3 font-medium">Default</th>
                </tr>
              </thead>
              <tbody>
                {parameters.map((p) => (
                  <tr
                    key={p.id}
                    className="border-b border-border last:border-0"
                  >
                    <td className="px-5 py-3">
                      <code className="rounded bg-badge-bg px-1.5 py-0.5 font-mono text-xs">
                        -{p.name}
                      </code>
                    </td>
                    <td className="px-5 py-3 text-muted">{p.description}</td>
                    <td className="px-5 py-3">
                      {p.is_required ? (
                        <span className="font-semibold text-foreground">
                          Yes
                        </span>
                      ) : (
                        <span className="text-muted">No</span>
                      )}
                    </td>
                    <td className="px-5 py-3 font-mono text-xs">
                      {p.default_value ?? "\u2014"}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      )}

      {/* Usage example */}
      <section className="space-y-3">
        <h2 className="text-sm font-semibold uppercase tracking-wider text-muted">
          Quick Usage
        </h2>
        <div className="rounded-lg bg-surface px-5 py-4 font-mono text-sm leading-relaxed">
          <div className="text-muted"># Basic usage</div>
          <div>
            ./{script.file_path}
            {parameters
              .filter((p) => p.is_required)
              .map((p) => ` -${p.name} <value>`)
              .join("")}
          </div>
          {script.supports_whatif === 1 && (
            <>
              <div className="mt-3 text-muted"># Dry run (safe testing)</div>
              <div>
                ./{script.file_path} -WhatIf
                {parameters
                  .filter((p) => p.is_required)
                  .map((p) => ` -${p.name} <value>`)
                  .join("")}
              </div>
            </>
          )}
          {script.supports_csv_export === 1 && (
            <>
              <div className="mt-3 text-muted"># Export to CSV</div>
              <div>
                ./{script.file_path} -ExportPath &quot;./output.csv&quot;
                {parameters
                  .filter((p) => p.is_required)
                  .map((p) => ` -${p.name} <value>`)
                  .join("")}
              </div>
            </>
          )}
          <div className="mt-3 text-muted"># Full help</div>
          <div>Get-Help ./{script.file_path} -Full</div>
        </div>
      </section>

      {/* Contributors */}
      {contributors.length > 0 && (
        <section className="space-y-3">
          <h2 className="text-sm font-semibold uppercase tracking-wider text-muted">
            Contributors
          </h2>
          <div className="flex flex-wrap gap-2">
            {contributors.map((c) => (
              <span
                key={c.id}
                className="rounded-full bg-badge-bg px-3 py-1 text-xs font-medium text-badge-text"
              >
                {c.name}
                <span className="ml-1 text-muted">({c.contribution_type})</span>
              </span>
            ))}
          </div>
        </section>
      )}

      {/* Tags */}
      {tags.length > 0 && (
        <section className="space-y-3">
          <h2 className="text-sm font-semibold uppercase tracking-wider text-muted">
            Tags
          </h2>
          <div className="flex flex-wrap gap-2">
            {tags.map((t) => (
              <span
                key={t.id}
                className="rounded-full bg-badge-bg px-3 py-1 text-xs font-medium text-badge-text"
              >
                {t.name}
              </span>
            ))}
          </div>
        </section>
      )}

      {/* Back link */}
      <div className="border-t border-border pt-6">
        <Link
          href={`/categories/${script.category_slug}`}
          className="inline-flex items-center gap-2 text-sm text-muted transition-colors hover:text-foreground"
        >
          <svg
            width="14"
            height="14"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
            viewBox="0 0 24 24"
          >
            <path d="m15 18-6-6 6-6" />
          </svg>
          Back to {script.category_name}
        </Link>
      </div>
    </div>
  );
}
