import Link from "next/link";
import { getAllCategories, getStats, getAllDockerComponents } from "../../lib/db";

const categoryIcons: Record<string, string> = {
  "01-infrastructure": "M5 12h14M12 5l7 7-7 7",
  "02-cloud-hybrid": "M3 15a4 4 0 0 0 4 4h9a5 5 0 1 0-.1-9.999A6 6 0 0 0 4.085 12.028 4 4 0 0 0 3 15z",
  "03-security-compliance": "M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z",
  "04-backup-dr": "M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4M7 10l5 5 5-5M12 15V3",
  "05-networking": "M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zM2 12h20M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z",
  "06-monitoring": "M22 12h-4l-3 9L9 3l-3 9H2",
  "07-automation": "M12 2v4m0 12v4M4.93 4.93l2.83 2.83m8.48 8.48l2.83 2.83M2 12h4m12 0h4M4.93 19.07l2.83-2.83m8.48-8.48l2.83-2.83",
  docker: "M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0z",
};

export default function Home() {
  const categories = getAllCategories();
  const stats = getStats();
  const dockerComponents = getAllDockerComponents();

  return (
    <div className="space-y-16">
      {/* Hero */}
      <section className="space-y-6 pt-8 text-center">
        <h1 className="text-4xl font-bold tracking-tight sm:text-5xl">
          Knowledge Base
        </h1>
        <p className="mx-auto max-w-2xl text-lg text-muted">
          Microsoft 365 &amp; Infrastructure Automation Toolkit — find every
          script, parameter, and monitoring component in one place.
        </p>
        <p className="mx-auto max-w-xl text-sm text-muted">
          Powered by KCS v6 methodology &middot; RDF/JSON-LD interoperable
        </p>

        {/* Quick search */}
        <div className="mx-auto max-w-xl">
          <Link
            href="/search"
            className="flex items-center gap-3 rounded-lg border border-border bg-surface px-5 py-3.5 text-muted transition-colors hover:border-foreground/20"
          >
            <svg
              width="18"
              height="18"
              fill="none"
              stroke="currentColor"
              strokeWidth="2"
              strokeLinecap="round"
              strokeLinejoin="round"
              viewBox="0 0 24 24"
            >
              <circle cx="11" cy="11" r="8" />
              <path d="m21 21-4.35-4.35" />
            </svg>
            <span>Search scripts, parameters, categories...</span>
          </Link>
        </div>
      </section>

      {/* Stats */}
      <section className="grid grid-cols-2 gap-4 sm:grid-cols-5">
        {[
          { label: "Scripts", value: stats.scriptCount },
          { label: "Categories", value: stats.categoryCount },
          { label: "Parameters", value: stats.parameterCount },
          { label: "Published (KCS)", value: stats.publishedCount },
          { label: "Docker Components", value: stats.dockerCount },
        ].map((s) => (
          <div
            key={s.label}
            className="rounded-lg border border-border bg-surface p-6 text-center"
          >
            <div className="text-3xl font-bold">{s.value}</div>
            <div className="mt-1 text-sm text-muted">{s.label}</div>
          </div>
        ))}
      </section>

      {/* Categories */}
      <section className="space-y-6">
        <div className="flex items-center justify-between">
          <h2 className="text-2xl font-semibold">Categories</h2>
          <Link
            href="/categories"
            className="text-sm text-muted transition-colors hover:text-foreground"
          >
            View all &rarr;
          </Link>
        </div>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {categories.map((cat) => (
            <Link
              key={cat.slug}
              href={`/categories/${cat.slug}`}
              className="group rounded-lg border border-border p-6 transition-all hover:border-foreground/30 hover:bg-surface"
            >
              <div className="mb-3 flex items-center gap-3">
                <div className="flex h-10 w-10 items-center justify-center rounded-md bg-accent text-background">
                  <svg
                    width="20"
                    height="20"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="2"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    viewBox="0 0 24 24"
                  >
                    <path d={categoryIcons[cat.slug] || "M12 2v20M2 12h20"} />
                  </svg>
                </div>
                <h3 className="font-semibold group-hover:underline">
                  {cat.name}
                </h3>
              </div>
              <p className="text-sm leading-relaxed text-muted">
                {cat.description}
              </p>
              <div className="mt-4 text-xs font-medium text-muted">
                {cat.script_count} script{cat.script_count !== 1 ? "s" : ""}
              </div>
            </Link>
          ))}
        </div>
      </section>

      {/* Docker Stack */}
      <section className="space-y-6">
        <h2 className="text-2xl font-semibold">Docker Monitoring Stack</h2>
        <div className="overflow-hidden rounded-lg border border-border">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-border bg-surface text-left">
                <th className="px-5 py-3 font-medium">Component</th>
                <th className="px-5 py-3 font-medium">Type</th>
                <th className="px-5 py-3 font-medium">Port</th>
                <th className="hidden px-5 py-3 font-medium sm:table-cell">
                  Description
                </th>
              </tr>
            </thead>
            <tbody>
              {dockerComponents.map((dc) => (
                <tr
                  key={dc.id}
                  className="border-b border-border last:border-0"
                >
                  <td className="px-5 py-3 font-medium">{dc.name}</td>
                  <td className="px-5 py-3">
                    <span className="rounded-full bg-badge-bg px-2.5 py-0.5 text-xs font-medium text-badge-text">
                      {dc.component_type}
                    </span>
                  </td>
                  <td className="px-5 py-3 font-mono text-xs">
                    {dc.port ?? "\u2014"}
                  </td>
                  <td className="hidden px-5 py-3 text-muted sm:table-cell">
                    {dc.description}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>

      {/* KCS Info */}
      <section className="space-y-4 rounded-lg border border-border bg-surface p-6">
        <h2 className="text-lg font-semibold">Knowledge-Centered Service (KCS v6)</h2>
        <p className="text-sm leading-relaxed text-muted">
          This knowledge base follows the KCS methodology for creating, managing, and improving
          knowledge articles. Each script article includes lifecycle states (Draft, Approved,
          Published, Retired), structured fields (Environment, Resolution, Cause), confidence
          scoring, and contributor tracking.
        </p>
        <div className="flex flex-wrap gap-3 text-xs">
          <span className="rounded-full px-3 py-1 font-medium" style={{ backgroundColor: "var(--color-kcs-draft)", color: "#fff" }}>
            Draft
          </span>
          <span className="rounded-full px-3 py-1 font-medium" style={{ backgroundColor: "var(--color-kcs-approved)", color: "#fff" }}>
            Approved
          </span>
          <span className="rounded-full px-3 py-1 font-medium" style={{ backgroundColor: "var(--color-kcs-published)", color: "#fff" }}>
            Published
          </span>
          <span className="rounded-full px-3 py-1 font-medium" style={{ backgroundColor: "var(--color-kcs-retired)", color: "#fff" }}>
            Retired
          </span>
        </div>
        <div className="mt-2 text-xs text-muted">
          RDF/JSON-LD endpoints available at{" "}
          <a href="/api/rdf/catalog" className="underline hover:text-foreground">/api/rdf/catalog</a>
          {" "}for semantic interoperability with external knowledge systems.
        </div>
      </section>
    </div>
  );
}
