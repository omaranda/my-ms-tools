"use client";

import { useEffect, useState, useCallback } from "react";
import Link from "next/link";

interface Script {
  id: number;
  name: string;
  file_path: string;
  subcategory: string | null;
  synopsis: string | null;
  supports_whatif: number;
  supports_csv_export: number;
  category_name: string;
  category_slug: string;
  kcs_state: string;
  confidence: number;
}

const kcsColors: Record<string, string> = {
  draft: "#ca8a04",
  approved: "#2563eb",
  published: "#16a34a",
  retired: "#9ca3af",
};

export default function SearchPage() {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<Script[]>([]);
  const [loading, setLoading] = useState(false);
  const [hasSearched, setHasSearched] = useState(false);

  const search = useCallback(async (q: string) => {
    setLoading(true);
    try {
      const res = await fetch(`/api/search?q=${encodeURIComponent(q)}`);
      const data = await res.json();
      setResults(data);
    } finally {
      setLoading(false);
      setHasSearched(true);
    }
  }, []);

  useEffect(() => {
    const timer = setTimeout(() => {
      search(query);
    }, 200);
    return () => clearTimeout(timer);
  }, [query, search]);

  return (
    <div className="space-y-8">
      <div className="space-y-2">
        <h1 className="text-3xl font-bold tracking-tight">Search</h1>
        <p className="text-muted">
          Search across all scripts, parameters, and descriptions.
        </p>
      </div>

      <div className="relative">
        <svg
          className="absolute left-4 top-1/2 -translate-y-1/2 text-muted"
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
        <input
          type="text"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search scripts, parameters, categories..."
          autoFocus
          className="w-full rounded-lg border border-border bg-surface py-3.5 pl-12 pr-4 text-foreground placeholder:text-muted focus:border-foreground/30 focus:outline-none focus:ring-1 focus:ring-foreground/10"
        />
      </div>

      {loading ? (
        <div className="py-12 text-center text-muted">Searching...</div>
      ) : (
        <div className="space-y-2">
          <div className="text-sm text-muted">
            {results.length} result{results.length !== 1 ? "s" : ""}
            {query.trim() ? ` for "${query}"` : ""}
          </div>

          {results.length === 0 && hasSearched ? (
            <div className="rounded-lg border border-border py-16 text-center text-muted">
              No scripts found. Try a different search term.
            </div>
          ) : (
            <div className="divide-y divide-border rounded-lg border border-border">
              {results.map((script) => (
                <Link
                  key={script.id}
                  href={`/scripts/${script.id}`}
                  className="flex items-start gap-4 px-5 py-4 transition-colors hover:bg-surface"
                >
                  <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-md bg-accent text-xs font-bold text-background">
                    PS
                  </div>
                  <div className="min-w-0 flex-1">
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="font-semibold">{script.name}</span>
                      <span className="rounded-full bg-badge-bg px-2 py-0.5 text-xs text-badge-text">
                        {script.category_name}
                      </span>
                      {script.subcategory && (
                        <span className="rounded-full bg-badge-bg px-2 py-0.5 text-xs text-badge-text">
                          {script.subcategory}
                        </span>
                      )}
                      {script.kcs_state && (
                        <span
                          className="rounded-full px-2 py-0.5 text-[10px] font-medium text-white"
                          style={{ backgroundColor: kcsColors[script.kcs_state] || kcsColors.draft }}
                        >
                          {script.kcs_state}
                        </span>
                      )}
                    </div>
                    <p className="mt-1 text-sm text-muted line-clamp-2">
                      {script.synopsis}
                    </p>
                    <div className="mt-2 flex gap-2">
                      {script.supports_whatif === 1 && (
                        <span className="rounded border border-border px-1.5 py-0.5 text-[10px] font-medium text-muted">
                          WhatIf
                        </span>
                      )}
                      {script.supports_csv_export === 1 && (
                        <span className="rounded border border-border px-1.5 py-0.5 text-[10px] font-medium text-muted">
                          CSV Export
                        </span>
                      )}
                    </div>
                  </div>
                  <svg
                    className="mt-1 shrink-0 text-muted"
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
                </Link>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
