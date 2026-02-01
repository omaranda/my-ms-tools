import type { Metadata } from "next";
import "./globals.css";
import { ThemeProvider } from "../components/ThemeProvider";
import { ThemeToggle } from "../components/ThemeToggle";

export const metadata: Metadata = {
  title: "Knowledge Base | MS Tools",
  description:
    "Microsoft 365 & Infrastructure Automation Toolkit — KCS Knowledge Base",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        {/* Prevent FOUC: apply theme before render */}
        <script
          dangerouslySetInnerHTML={{
            __html: `(function(){try{var t=localStorage.getItem('kb-theme');var d=document.documentElement;d.classList.remove('light','dark');if(t==='dark')d.classList.add('dark');else if(t==='light')d.classList.add('light');else{d.classList.add(window.matchMedia('(prefers-color-scheme:dark)').matches?'dark':'light')}}catch(e){}})()`,
          }}
        />
        {/* JSON-LD: Organization & WebSite structured data for RDF interoperability */}
        <script
          type="application/ld+json"
          dangerouslySetInnerHTML={{
            __html: JSON.stringify({
              "@context": "https://schema.org",
              "@graph": [
                {
                  "@type": "WebSite",
                  "@id": "urn:ms-tools:knowledge-base",
                  name: "MS Tools Knowledge Base",
                  description:
                    "KCS-compliant knowledge base for Microsoft 365 & Infrastructure automation scripts",
                  inLanguage: "en",
                },
                {
                  "@type": "Organization",
                  "@id": "urn:ms-tools:team",
                  name: "MS Tools Team",
                },
              ],
            }),
          }}
        />
      </head>
      <body className="min-h-screen bg-background text-foreground antialiased">
        <ThemeProvider>
          <header className="sticky top-0 z-50 border-b border-border bg-background/80 backdrop-blur-sm">
            <div className="mx-auto flex h-16 max-w-6xl items-center justify-between px-6">
              <a
                href="/"
                className="flex items-center gap-3 font-semibold tracking-tight"
              >
                <svg
                  width="28"
                  height="28"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="2"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                >
                  <path d="M4 19.5v-15A2.5 2.5 0 0 1 6.5 2H20v20H6.5a2.5 2.5 0 0 1 0-5H20" />
                </svg>
                <span>MS Tools Knowledge Base</span>
              </a>
              <nav className="flex items-center gap-6 text-sm">
                <a
                  href="/"
                  className="text-muted transition-colors hover:text-foreground"
                >
                  Home
                </a>
                <a
                  href="/search"
                  className="text-muted transition-colors hover:text-foreground"
                >
                  Search
                </a>
                <a
                  href="/categories"
                  className="text-muted transition-colors hover:text-foreground"
                >
                  Categories
                </a>
                <ThemeToggle />
              </nav>
            </div>
          </header>
          <main className="mx-auto max-w-6xl px-6 py-10">{children}</main>
          <footer className="border-t border-border py-8 text-center text-sm text-muted">
            <div className="mx-auto max-w-6xl px-6 space-y-2">
              <div>Microsoft 365 &amp; Infrastructure Automation Toolkit</div>
              <div className="flex items-center justify-center gap-4 text-xs">
                <span>KCS v6 Methodology</span>
                <span>&middot;</span>
                <a
                  href="/api/rdf/catalog"
                  className="transition-colors hover:text-foreground"
                  title="RDF/JSON-LD Catalog"
                >
                  RDF Catalog
                </a>
                <span>&middot;</span>
                <a
                  href="/api/rdf/categories"
                  className="transition-colors hover:text-foreground"
                  title="RDF/JSON-LD Categories (SKOS)"
                >
                  SKOS Taxonomy
                </a>
              </div>
            </div>
          </footer>
        </ThemeProvider>
      </body>
    </html>
  );
}
