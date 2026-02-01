import Database from "better-sqlite3";
import path from "path";

const DB_PATH = path.join(process.cwd(), "knowledge.db");

let _db: Database.Database | null = null;

export function getDb(): Database.Database {
  if (!_db) {
    _db = new Database(DB_PATH);
    _db.pragma("journal_mode = WAL");
    _db.pragma("foreign_keys = ON");
    ensureSchema(_db);
  }
  return _db;
}

function ensureSchema(db: Database.Database) {
  db.exec(`
    CREATE TABLE IF NOT EXISTS categories (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      slug TEXT UNIQUE NOT NULL,
      name TEXT NOT NULL,
      description TEXT,
      sort_order INTEGER DEFAULT 0
    );

    CREATE TABLE IF NOT EXISTS scripts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      category_id INTEGER NOT NULL REFERENCES categories(id),
      name TEXT NOT NULL,
      file_path TEXT NOT NULL,
      subcategory TEXT,
      synopsis TEXT,
      description TEXT,
      supports_whatif INTEGER DEFAULT 0,
      supports_csv_export INTEGER DEFAULT 0,
      created_at TEXT DEFAULT (datetime('now')),
      -- KCS (Knowledge-Centered Service) fields
      kcs_state TEXT DEFAULT 'draft' CHECK(kcs_state IN ('draft','approved','published','retired')),
      environment TEXT,
      resolution TEXT,
      cause TEXT,
      confidence INTEGER DEFAULT 0 CHECK(confidence >= 0 AND confidence <= 100),
      view_count INTEGER DEFAULT 0,
      last_reviewed_at TEXT,
      author TEXT,
      UNIQUE(name)
    );

    CREATE TABLE IF NOT EXISTS parameters (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      script_id INTEGER NOT NULL REFERENCES scripts(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      description TEXT,
      is_required INTEGER DEFAULT 0,
      default_value TEXT
    );

    CREATE TABLE IF NOT EXISTS docker_components (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      component_type TEXT NOT NULL,
      port TEXT,
      description TEXT,
      location TEXT,
      details TEXT
    );

    CREATE TABLE IF NOT EXISTS tags (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT UNIQUE NOT NULL
    );

    CREATE TABLE IF NOT EXISTS script_tags (
      script_id INTEGER NOT NULL REFERENCES scripts(id) ON DELETE CASCADE,
      tag_id INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
      PRIMARY KEY (script_id, tag_id)
    );

    -- KCS article contributors (reuse & improve tracking)
    CREATE TABLE IF NOT EXISTS contributors (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      script_id INTEGER NOT NULL REFERENCES scripts(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      contribution_type TEXT NOT NULL CHECK(contribution_type IN ('author','reviewer','editor','contributor')),
      contributed_at TEXT DEFAULT (datetime('now'))
    );

    CREATE VIRTUAL TABLE IF NOT EXISTS scripts_fts USING fts5(
      name, synopsis, description, subcategory, environment, resolution, cause,
      content='scripts', content_rowid='id'
    );

    CREATE TRIGGER IF NOT EXISTS scripts_ai AFTER INSERT ON scripts BEGIN
      INSERT INTO scripts_fts(rowid, name, synopsis, description, subcategory, environment, resolution, cause)
      VALUES (new.id, new.name, new.synopsis, new.description, new.subcategory, new.environment, new.resolution, new.cause);
    END;

    CREATE TRIGGER IF NOT EXISTS scripts_ad AFTER DELETE ON scripts BEGIN
      INSERT INTO scripts_fts(scripts_fts, rowid, name, synopsis, description, subcategory, environment, resolution, cause)
      VALUES ('delete', old.id, old.name, old.synopsis, old.description, old.subcategory, old.environment, old.resolution, old.cause);
    END;

    CREATE TRIGGER IF NOT EXISTS scripts_au AFTER UPDATE ON scripts BEGIN
      INSERT INTO scripts_fts(scripts_fts, rowid, name, synopsis, description, subcategory, environment, resolution, cause)
      VALUES ('delete', old.id, old.name, old.synopsis, old.description, old.subcategory, old.environment, old.resolution, old.cause);
      INSERT INTO scripts_fts(rowid, name, synopsis, description, subcategory, environment, resolution, cause)
      VALUES (new.id, new.name, new.synopsis, new.description, new.subcategory, new.environment, new.resolution, new.cause);
    END;
  `);
}

// --- Query helpers ---

export interface Category {
  id: number;
  slug: string;
  name: string;
  description: string | null;
  sort_order: number;
  script_count?: number;
}

export type KcsState = "draft" | "approved" | "published" | "retired";

export interface Script {
  id: number;
  category_id: number;
  name: string;
  file_path: string;
  subcategory: string | null;
  synopsis: string | null;
  description: string | null;
  supports_whatif: number;
  supports_csv_export: number;
  created_at: string | null;
  category_name?: string;
  category_slug?: string;
  // KCS fields
  kcs_state: KcsState;
  environment: string | null;
  resolution: string | null;
  cause: string | null;
  confidence: number;
  view_count: number;
  last_reviewed_at: string | null;
  author: string | null;
}

export interface Parameter {
  id: number;
  script_id: number;
  name: string;
  description: string | null;
  is_required: number;
  default_value: string | null;
}

export interface DockerComponent {
  id: number;
  name: string;
  component_type: string;
  port: string | null;
  description: string | null;
  location: string | null;
  details: string | null;
}

export interface Tag {
  id: number;
  name: string;
}

export interface Contributor {
  id: number;
  script_id: number;
  name: string;
  contribution_type: "author" | "reviewer" | "editor" | "contributor";
  contributed_at: string;
}

export function getAllCategories(): Category[] {
  const db = getDb();
  return db
    .prepare(
      `SELECT c.*, (SELECT COUNT(*) FROM scripts s WHERE s.category_id = c.id) AS script_count
       FROM categories c ORDER BY c.sort_order`
    )
    .all() as Category[];
}

export function getCategoryBySlug(slug: string): Category | undefined {
  const db = getDb();
  return db
    .prepare(
      `SELECT c.*, (SELECT COUNT(*) FROM scripts s WHERE s.category_id = c.id) AS script_count
       FROM categories c WHERE c.slug = ?`
    )
    .get(slug) as Category | undefined;
}

export function getScriptsByCategory(categoryId: number): Script[] {
  const db = getDb();
  return db
    .prepare(
      `SELECT s.*, c.name AS category_name, c.slug AS category_slug
       FROM scripts s JOIN categories c ON s.category_id = c.id
       WHERE s.category_id = ? ORDER BY s.subcategory, s.name`
    )
    .all(categoryId) as Script[];
}

export function getScriptById(id: number): Script | undefined {
  const db = getDb();
  return db
    .prepare(
      `SELECT s.*, c.name AS category_name, c.slug AS category_slug
       FROM scripts s JOIN categories c ON s.category_id = c.id
       WHERE s.id = ?`
    )
    .get(id) as Script | undefined;
}

export function getScriptByName(name: string): Script | undefined {
  const db = getDb();
  return db
    .prepare(
      `SELECT s.*, c.name AS category_name, c.slug AS category_slug
       FROM scripts s JOIN categories c ON s.category_id = c.id
       WHERE s.name = ?`
    )
    .get(name) as Script | undefined;
}

export function getParametersForScript(scriptId: number): Parameter[] {
  const db = getDb();
  return db
    .prepare(`SELECT * FROM parameters WHERE script_id = ? ORDER BY is_required DESC, name`)
    .all(scriptId) as Parameter[];
}

export function getTagsForScript(scriptId: number): Tag[] {
  const db = getDb();
  return db
    .prepare(
      `SELECT t.* FROM tags t
       JOIN script_tags st ON t.id = st.tag_id
       WHERE st.script_id = ? ORDER BY t.name`
    )
    .all(scriptId) as Tag[];
}

export function getAllDockerComponents(): DockerComponent[] {
  const db = getDb();
  return db
    .prepare(`SELECT * FROM docker_components ORDER BY name`)
    .all() as DockerComponent[];
}

export function searchScripts(query: string): Script[] {
  const db = getDb();
  if (!query.trim()) return [];
  const ftsQuery = query
    .trim()
    .split(/\s+/)
    .map((w) => `"${w}"*`)
    .join(" ");
  return db
    .prepare(
      `SELECT s.*, c.name AS category_name, c.slug AS category_slug
       FROM scripts_fts fts
       JOIN scripts s ON fts.rowid = s.id
       JOIN categories c ON s.category_id = c.id
       WHERE scripts_fts MATCH ?
       ORDER BY rank`
    )
    .all(ftsQuery) as Script[];
}

export function getAllScripts(): Script[] {
  const db = getDb();
  return db
    .prepare(
      `SELECT s.*, c.name AS category_name, c.slug AS category_slug
       FROM scripts s JOIN categories c ON s.category_id = c.id
       ORDER BY c.sort_order, s.subcategory, s.name`
    )
    .all() as Script[];
}

export function getStats() {
  const db = getDb();
  const scriptCount = (
    db.prepare(`SELECT COUNT(*) as count FROM scripts`).get() as { count: number }
  ).count;
  const categoryCount = (
    db.prepare(`SELECT COUNT(*) as count FROM categories`).get() as { count: number }
  ).count;
  const parameterCount = (
    db.prepare(`SELECT COUNT(*) as count FROM parameters`).get() as { count: number }
  ).count;
  const dockerCount = (
    db.prepare(`SELECT COUNT(*) as count FROM docker_components`).get() as {
      count: number;
    }
  ).count;
  const publishedCount = (
    db.prepare(`SELECT COUNT(*) as count FROM scripts WHERE kcs_state = 'published'`).get() as {
      count: number;
    }
  ).count;
  return { scriptCount, categoryCount, parameterCount, dockerCount, publishedCount };
}

// --- KCS helpers ---

export function getContributorsForScript(scriptId: number): Contributor[] {
  const db = getDb();
  return db
    .prepare(`SELECT * FROM contributors WHERE script_id = ? ORDER BY contributed_at DESC`)
    .all(scriptId) as Contributor[];
}

export function getScriptsByKcsState(state: KcsState): Script[] {
  const db = getDb();
  return db
    .prepare(
      `SELECT s.*, c.name AS category_name, c.slug AS category_slug
       FROM scripts s JOIN categories c ON s.category_id = c.id
       WHERE s.kcs_state = ? ORDER BY s.name`
    )
    .all(state) as Script[];
}

export function incrementViewCount(scriptId: number): void {
  const db = getDb();
  db.prepare(`UPDATE scripts SET view_count = view_count + 1 WHERE id = ?`).run(scriptId);
}

// --- RDF/JSON-LD helpers ---

export function getScriptJsonLd(script: Script, parameters: Parameter[], tags: Tag[]): object {
  return {
    "@context": {
      "@vocab": "https://schema.org/",
      dc: "http://purl.org/dc/terms/",
      skos: "http://www.w3.org/2004/02/skos/core#",
      kcs: "https://serviceinnovation.org/kcs/",
    },
    "@type": "SoftwareSourceCode",
    "@id": `urn:ms-tools:script:${script.id}`,
    name: script.name,
    description: script.description || script.synopsis,
    codeRepository: script.file_path,
    programmingLanguage: "PowerShell",
    "dc:creator": script.author || "MS Tools Team",
    "dc:subject": tags.map((t) => t.name),
    "dc:type": "AutomationScript",
    "dc:created": script.created_at ?? undefined,
    "dc:modified": script.last_reviewed_at ?? undefined,
    "skos:prefLabel": script.name,
    "skos:definition": script.synopsis,
    "skos:inScheme": {
      "@type": "skos:ConceptScheme",
      "@id": `urn:ms-tools:category:${script.category_slug}`,
      "skos:prefLabel": script.category_name,
    },
    "kcs:state": script.kcs_state,
    "kcs:confidence": script.confidence,
    "kcs:environment": script.environment,
    "kcs:resolution": script.resolution,
    "kcs:cause": script.cause,
    "kcs:viewCount": script.view_count,
    operatingSystem: script.environment || "Windows Server / Microsoft 365",
    applicationCategory: script.subcategory || script.category_name,
    hasPart: parameters.map((p) => ({
      "@type": "PropertyValue",
      name: p.name,
      description: p.description,
      defaultValue: p.default_value,
      valueRequired: p.is_required === 1,
    })),
  };
}

export function getCategoryJsonLd(category: Category): object {
  return {
    "@context": {
      "@vocab": "https://schema.org/",
      skos: "http://www.w3.org/2004/02/skos/core#",
      dc: "http://purl.org/dc/terms/",
    },
    "@type": "skos:Concept",
    "@id": `urn:ms-tools:category:${category.slug}`,
    "skos:prefLabel": category.name,
    "skos:definition": category.description,
    "skos:inScheme": {
      "@id": "urn:ms-tools:knowledge-base",
      "@type": "skos:ConceptScheme",
      "skos:prefLabel": "MS Tools Knowledge Base",
    },
    "dc:type": "ScriptCategory",
    name: category.name,
    description: category.description,
  };
}

export function getCatalogJsonLd(categories: Category[], stats: ReturnType<typeof getStats>): object {
  return {
    "@context": {
      "@vocab": "https://schema.org/",
      skos: "http://www.w3.org/2004/02/skos/core#",
      dc: "http://purl.org/dc/terms/",
      dcat: "http://www.w3.org/ns/dcat#",
      kcs: "https://serviceinnovation.org/kcs/",
    },
    "@type": ["dcat:Catalog", "skos:ConceptScheme"],
    "@id": "urn:ms-tools:knowledge-base",
    "dc:title": "Microsoft 365 & Infrastructure Automation Toolkit — Knowledge Base",
    "dc:description":
      "KCS-compliant knowledge base for PowerShell automation scripts targeting Microsoft 365, Azure, and Windows Server infrastructure.",
    "dc:publisher": "MS Tools Team",
    "dc:language": "en",
    "dc:type": "KnowledgeBase",
    "kcs:methodology": "Knowledge-Centered Service (KCS) v6",
    "dcat:themeTaxonomy": {
      "@id": "urn:ms-tools:categories",
      "@type": "skos:ConceptScheme",
      "skos:hasTopConcept": categories.map((c) => ({
        "@id": `urn:ms-tools:category:${c.slug}`,
        "@type": "skos:Concept",
        "skos:prefLabel": c.name,
      })),
    },
    numberOfItems: stats.scriptCount,
    hasPart: categories.map((c) => ({
      "@type": "dcat:Dataset",
      "@id": `urn:ms-tools:category:${c.slug}`,
      name: c.name,
      description: c.description,
    })),
  };
}
