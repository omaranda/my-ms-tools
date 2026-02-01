import Database from "better-sqlite3";
import path from "path";
import fs from "fs";

const DB_PATH = path.join(__dirname, "..", "knowledge.db");

// Remove existing DB to start fresh
if (fs.existsSync(DB_PATH)) {
  fs.unlinkSync(DB_PATH);
}

const db = new Database(DB_PATH);
db.pragma("journal_mode = WAL");
db.pragma("foreign_keys = ON");

// --- Create schema ---
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

// --- Seed categories ---
const insertCategory = db.prepare(
  `INSERT INTO categories (slug, name, description, sort_order) VALUES (?, ?, ?, ?)`
);

const categories = [
  ["01-infrastructure", "Infrastructure", "Windows Server foundation — Active Directory, DNS, DHCP, File Servers, Group Policy, Print Services", 1],
  ["02-cloud-hybrid", "Cloud & Hybrid", "Microsoft 365 & Azure — Azure AD, Exchange Online, Teams, Intune device management", 2],
  ["03-security-compliance", "Security & Compliance", "Security operations — Auditing, Encryption, Defender, RBAC role management", 3],
  ["04-backup-dr", "Backup & DR", "Backup and disaster recovery automation for Azure VMs and Windows Server", 4],
  ["05-networking", "Networking", "Network diagnostics, connectivity testing, and troubleshooting", 5],
  ["06-monitoring", "Monitoring", "Health checks, performance monitoring, and Grafana dashboards", 6],
  ["07-automation", "Automation", "End-to-end workflows — user provisioning, bulk operations, license management", 7],
  ["docker", "Docker Monitoring Stack", "Grafana, Prometheus, Graph API proxy for unified infrastructure monitoring", 8],
] as const;

const categoryIds: Record<string, number> = {};
for (const [slug, name, description, order] of categories) {
  const result = insertCategory.run(slug, name, description, order);
  categoryIds[slug] = Number(result.lastInsertRowid);
}

// --- Seed scripts ---
const insertScript = db.prepare(
  `INSERT INTO scripts (category_id, name, file_path, subcategory, synopsis, description, supports_whatif, supports_csv_export, kcs_state, environment, resolution, cause, confidence, author, last_reviewed_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
);

const insertParam = db.prepare(
  `INSERT INTO parameters (script_id, name, description, is_required, default_value) VALUES (?, ?, ?, ?, ?)`
);

const insertTag = db.prepare(
  `INSERT OR IGNORE INTO tags (name) VALUES (?)`
);

const insertScriptTag = db.prepare(
  `INSERT INTO script_tags (script_id, tag_id) VALUES (?, ?)`
);

const insertContributor = db.prepare(
  `INSERT INTO contributors (script_id, name, contribution_type) VALUES (?, ?, ?)`
);

function addTag(name: string): number {
  insertTag.run(name);
  return (db.prepare(`SELECT id FROM tags WHERE name = ?`).get(name) as { id: number }).id;
}

// KCS metadata type for script seeding
interface KcsMeta {
  state?: "draft" | "approved" | "published" | "retired";
  environment?: string;
  resolution?: string;
  cause?: string;
  confidence?: number;
  author?: string;
}

function addScript(
  categorySlug: string,
  name: string,
  filePath: string,
  subcategory: string,
  synopsis: string,
  description: string,
  whatif: boolean,
  csv: boolean,
  params: [string, string, boolean, string | null][],
  tags: string[],
  kcs: KcsMeta = {}
) {
  const catId = categoryIds[categorySlug];
  const result = insertScript.run(
    catId, name, filePath, subcategory, synopsis, description,
    whatif ? 1 : 0, csv ? 1 : 0,
    kcs.state || "published",
    kcs.environment || null,
    kcs.resolution || null,
    kcs.cause || null,
    kcs.confidence ?? 80,
    kcs.author || "MS Tools Team",
    new Date().toISOString()
  );
  const scriptId = Number(result.lastInsertRowid);
  for (const [pName, pDesc, pReq, pDefault] of params) {
    insertParam.run(scriptId, pName, pDesc, pReq ? 1 : 0, pDefault);
  }
  for (const t of tags) {
    const tagId = addTag(t);
    insertScriptTag.run(scriptId, tagId);
  }
  // Add author as contributor
  if (kcs.author) {
    insertContributor.run(scriptId, kcs.author, "author");
  }
}

// ====================== 01-INFRASTRUCTURE ======================

addScript("01-infrastructure", "Get-ADUserReport",
  "01-Infrastructure/ActiveDirectory/Get-ADUserReport.ps1", "ActiveDirectory",
  "Generates comprehensive Active Directory user report",
  "Creates detailed report of AD users including account status, last logon, group memberships, password status, and mailbox information.",
  false, true,
  [
    ["ExportPath", "Path for CSV export", false, null],
    ["IncludeDisabled", "Include disabled accounts in report", false, "false"],
  ],
  ["active-directory", "reporting", "users"],
  { state: "published", environment: "Windows Server 2019+ with Active Directory Domain Services", resolution: "Run the script with appropriate AD read permissions to generate user reports. Use -ExportPath for CSV output.", cause: "Need for periodic AD user auditing and compliance reporting.", confidence: 95, author: "MS Tools Team" }
);

addScript("01-infrastructure", "New-BulkADUsers",
  "01-Infrastructure/ActiveDirectory/New-BulkADUsers.ps1", "ActiveDirectory",
  "Creates multiple Active Directory users from CSV file",
  "Bulk creates AD users with account creation, password setting, group membership, and OU placement from CSV input.",
  true, false,
  [
    ["CSVPath", "Path to CSV file with user data", true, null],
    ["DefaultPassword", "Default password for new accounts", false, null],
  ],
  ["active-directory", "bulk-operations", "users", "provisioning"],
  { state: "published", environment: "Windows Server with AD DS, PowerShell 7+", resolution: "Prepare a CSV with required columns (FirstName, LastName, Username, etc.) and run with -CSVPath. Use -WhatIf for dry run.", cause: "Bulk user creation from HR onboarding lists or migrations.", confidence: 90, author: "MS Tools Team" }
);

addScript("01-infrastructure", "Reset-ADPassword",
  "01-Infrastructure/ActiveDirectory/Reset-ADPassword.ps1", "ActiveDirectory",
  "Resets Active Directory user passwords",
  "Reset passwords for AD users with options for single/bulk resets, force password change, and unlock accounts.",
  true, false,
  [
    ["Username", "Username to reset password", false, null],
    ["NewPassword", "New password (secure string)", false, null],
    ["CSVPath", "CSV file with Username/NewPassword columns", false, null],
    ["UnlockAccount", "Unlock account if locked", false, "false"],
    ["MustChangePassword", "Force change at next logon", false, "true"],
  ],
  ["active-directory", "security", "passwords"],
  { state: "published", environment: "Windows Server with AD DS", resolution: "Provide username and new password, or use CSV for bulk resets. Use -UnlockAccount to also unlock.", cause: "Password reset requests from helpdesk or security policy enforcement.", confidence: 90, author: "MS Tools Team" }
);

addScript("01-infrastructure", "Set-ADGroupMembership",
  "01-Infrastructure/ActiveDirectory/Set-ADGroupMembership.ps1", "ActiveDirectory",
  "Manages Active Directory group memberships in bulk",
  "Add or remove users from AD groups via CSV or single user/multiple groups.",
  true, false,
  [
    ["CSVPath", "CSV with Username, GroupName, Action columns", false, null],
    ["Username", "Single username", false, null],
    ["GroupName", "Group name(s)", false, null],
    ["Action", "Add or Remove", false, "Add"],
  ],
  ["active-directory", "groups", "bulk-operations"],
  { state: "published", environment: "Windows Server with AD DS", confidence: 85 }
);

addScript("01-infrastructure", "Get-DHCPLeases",
  "01-Infrastructure/DNS-DHCP/Get-DHCPLeases.ps1", "DNS-DHCP",
  "Reports on DHCP leases and scope utilization",
  "Retrieves DHCP lease information including active leases, scope utilization percentage, expired addresses, and reserved addresses.",
  false, true,
  [
    ["ScopeId", "Specific scope ID (default: all scopes)", false, null],
    ["ShowExpired", "Include expired leases", false, "false"],
    ["ExportPath", "CSV export path", false, null],
  ],
  ["dhcp", "networking", "reporting"],
  { state: "published", environment: "Windows Server with DHCP Server role", confidence: 85 }
);

addScript("01-infrastructure", "Get-DNSRecords",
  "01-Infrastructure/DNS-DHCP/Get-DNSRecords.ps1", "DNS-DHCP",
  "Exports DNS records from Windows DNS Server",
  "Retrieves and exports DNS records for all zones or specific zone with filtering by record type.",
  false, true,
  [
    ["ZoneName", "DNS zone name (default: all zones)", false, null],
    ["RecordType", "Filter by record type (A, AAAA, CNAME, MX, NS, PTR, SRV, TXT)", false, null],
    ["ExportPath", "CSV export path", false, null],
  ],
  ["dns", "networking", "reporting"],
  { state: "published", environment: "Windows Server with DNS Server role", confidence: 85 }
);

addScript("01-infrastructure", "Get-FilePermissions",
  "01-Infrastructure/FileServers/Get-FilePermissions.ps1", "FileServers",
  "Audits NTFS and share permissions on file servers",
  "Generates comprehensive permission reports including NTFS permissions, share permissions, effective access for users, and identifies excessive permissions.",
  false, true,
  [
    ["Path", "Path to audit (UNC or local)", true, null],
    ["Recursive", "Include subfolders", false, "false"],
    ["ExportPath", "CSV export path", false, null],
  ],
  ["file-server", "security", "permissions", "auditing"],
  { state: "published", environment: "Windows Server with File Server role, NTFS volumes", confidence: 90 }
);

addScript("01-infrastructure", "Get-FileServerSpace",
  "01-Infrastructure/FileServers/Get-FileServerSpace.ps1", "FileServers",
  "Analyzes disk space usage on file servers",
  "Reports on disk space including drive utilization, folder sizes, growth trends, and low space warnings.",
  false, true,
  [
    ["ComputerName", "Server name (default: local)", false, "localhost"],
    ["Path", "Path to analyze folder sizes", false, null],
    ["TopFolders", "Number of largest folders to display", false, "10"],
  ],
  ["file-server", "disk-space", "reporting"],
  { state: "published", environment: "Windows Server with File Server role", confidence: 85 }
);

addScript("01-infrastructure", "Get-GPOReport",
  "01-Infrastructure/GroupPolicy/Get-GPOReport.ps1", "GroupPolicy",
  "Generates comprehensive Group Policy Object report",
  "Reports on all GPOs including settings, configurations, link locations, permissions, and last modification.",
  false, true,
  [
    ["ExportPath", "Path for HTML report", false, null],
  ],
  ["group-policy", "reporting", "compliance"],
  { state: "published", environment: "Windows Server with Group Policy Management", confidence: 85 }
);

addScript("01-infrastructure", "Get-PrintQueue",
  "01-Infrastructure/PrintServices/Get-PrintQueue.ps1", "PrintServices",
  "Monitors print queues and printer status",
  "Reports on print servers including printer status, print queue jobs, stuck/error jobs, and printer statistics.",
  true, true,
  [
    ["PrintServer", "Print server name (default: local)", false, "localhost"],
    ["ClearStuckJobs", "Clear jobs in error state", false, "false"],
  ],
  ["print-services", "monitoring"],
  { state: "published", environment: "Windows Server with Print and Document Services role", confidence: 80 }
);

// ====================== 02-CLOUD-HYBRID ======================

addScript("02-cloud-hybrid", "Get-InactiveUsers-SharePoint-Teams",
  "02-Cloud-Hybrid/AzureAD/Get-InactiveUsers-SharePoint-Teams.ps1", "AzureAD",
  "Finds inactive users, exports to CSV, uploads to SharePoint, sends Teams message",
  "Retrieves users inactive 90+ days, exports to CSV, uploads to SharePoint site, sends Teams notification with report link.",
  false, true,
  [
    ["InactiveDays", "Days to consider inactive", false, "90"],
    ["SharePointSiteUrl", "SharePoint site URL", false, null],
    ["SharePointFolderPath", "Folder path in SharePoint", false, null],
    ["TeamsRecipientEmail", "Email for Teams notification", false, null],
    ["LocalExportPath", "Local CSV export path", false, null],
  ],
  ["azure-ad", "users", "sharepoint", "teams", "reporting", "inactive-accounts"],
  { state: "published", environment: "Microsoft 365 E3/E5, SharePoint Online, Microsoft Teams, Microsoft Graph PowerShell SDK", resolution: "Configure Graph API permissions (User.Read.All, Sites.ReadWrite.All, Chat.Create) and run with target SharePoint site URL.", cause: "License optimization and security hygiene for inactive accounts.", confidence: 90, author: "MS Tools Team" }
);

addScript("02-cloud-hybrid", "Set-ConditionalAccessPolicy",
  "02-Cloud-Hybrid/AzureAD/Set-ConditionalAccessPolicy.ps1", "AzureAD",
  "Creates or updates Conditional Access policies in Azure AD",
  "Manages Azure AD Conditional Access policies for MFA enforcement, device compliance, location-based access, and application protection.",
  false, false,
  [
    ["PolicyName", "Name of the conditional access policy", true, null],
    ["RequireMFA", "Require multi-factor authentication", false, "false"],
    ["RequireCompliantDevice", "Require device marked as compliant", false, "false"],
    ["BlockedLocations", "Array of location names to block", false, null],
  ],
  ["azure-ad", "security", "conditional-access", "mfa"],
  { state: "published", environment: "Azure AD Premium P1/P2, Microsoft Graph PowerShell SDK", confidence: 85 }
);

addScript("02-cloud-hybrid", "Sync-ADConnect",
  "02-Cloud-Hybrid/AzureAD/Sync-ADConnect.ps1", "AzureAD",
  "Forces Azure AD Connect synchronization and monitors status",
  "Initiates full or delta sync with Azure AD Connect and provides detailed status reporting.",
  false, false,
  [
    ["SyncType", "Type of sync: Delta or Full", false, "Delta"],
    ["Wait", "Wait for sync to complete before exiting", false, "false"],
  ],
  ["azure-ad", "hybrid", "synchronization"],
  { state: "published", environment: "Azure AD Connect server, Hybrid AD environment", confidence: 90 }
);

addScript("02-cloud-hybrid", "Remove-GuestUsers",
  "02-Cloud-Hybrid/AzureAD/Remove-GuestUsers.ps1", "AzureAD",
  "List and remove guest users from Azure Active Directory",
  "Comprehensive management of Azure AD guest users including listing, filtering, interactive selection, batch deletion, and detailed logging.",
  true, true,
  [
    ["ListOnly", "List without deleting", false, "false"],
    ["Interactive", "Interactive selection mode", false, "false"],
    ["DeleteAll", "Delete all guests", false, "false"],
    ["DeleteByEmail", "Delete specific guests by email", false, null],
    ["FilterDomain", "Filter by email domain", false, null],
    ["StaleGuests", "Show stale guests (no sign-in for X days)", false, "false"],
    ["StaleDays", "Days threshold for stale", false, "90"],
    ["ExportPath", "CSV export path", false, null],
  ],
  ["azure-ad", "guests", "security", "cleanup"],
  { state: "published", environment: "Azure AD / Entra ID, Microsoft Graph PowerShell SDK", confidence: 90 }
);

addScript("02-cloud-hybrid", "Get-IntuneDeviceInventory",
  "02-Cloud-Hybrid/Intune/Get-IntuneDeviceInventory.ps1", "Intune",
  "Retrieves inventory of all Intune-managed devices",
  "Connects to Microsoft Graph and retrieves all Intune-managed devices with device name, serial number, OS, user info, last sync, enrollment date, compliance state, manufacturer, and model.",
  false, true,
  [
    ["ExportPath", "CSV export path", false, null],
    ["IncludeAllProperties", "Include all available properties", false, "false"],
    ["FilterOS", "Filter by OS (Windows, iOS, Android, macOS)", false, null],
  ],
  ["intune", "devices", "inventory", "reporting"],
  { state: "published", environment: "Microsoft Intune, Microsoft Graph PowerShell SDK", confidence: 90 }
);

addScript("02-cloud-hybrid", "Get-IntuneNonCompliantDevices",
  "02-Cloud-Hybrid/Intune/Get-IntuneNonCompliantDevices.ps1", "Intune",
  "Reports on non-compliant Intune-managed devices and emails results",
  "Retrieves non-compliant devices, groups by compliance policy, exports to CSV, and optionally emails report via Graph or SMTP.",
  false, true,
  [
    ["EmailReport", "Send report via email", false, "false"],
    ["EmailTo", "Email recipient(s)", false, null],
    ["EmailFrom", "Email sender address", false, null],
    ["SMTPServer", "SMTP server address", false, null],
    ["UseGraphEmail", "Use Microsoft Graph instead of SMTP", false, "false"],
    ["ExportPath", "CSV export path", false, null],
  ],
  ["intune", "compliance", "devices", "reporting", "email"],
  { state: "published", environment: "Microsoft Intune with compliance policies, Microsoft Graph SDK", confidence: 85 }
);

addScript("02-cloud-hybrid", "New-AndroidEnrollmentConfiguration",
  "02-Cloud-Hybrid/Intune/New-AndroidEnrollmentConfiguration.ps1", "Intune",
  "Configure Android device enrollment with role-based app assignments",
  "Automates Android Enterprise enrollment with sophisticated role-based app deployment across 5 roles (Executive, FieldTeam, Sales, IT, General).",
  false, false,
  [
    ["RoleDefinitionFile", "Path to JSON role definitions", false, null],
    ["CreateGroups", "Create Azure AD groups for roles", false, "false"],
    ["AssignApps", "Assign apps to role groups", false, "false"],
    ["DeploymentMode", "Required (auto-install) or Available (optional)", false, "Required"],
    ["ExportConfiguration", "Export config to JSON", false, "false"],
  ],
  ["intune", "android", "enrollment", "mobile"],
  { state: "published", environment: "Microsoft Intune, Android Enterprise enrollment, Microsoft Graph SDK", confidence: 85 }
);

addScript("02-cloud-hybrid", "Set-QuietHoursPolicy",
  "02-Cloud-Hybrid/Intune/Set-QuietHoursPolicy.ps1", "Intune",
  "Configure Quiet Hours policies to prevent notifications outside working hours",
  "Creates and configures policies with time zone awareness for Teams, Outlook, Windows Focus Assist, iOS, and Android.",
  false, false,
  [
    ["TimeZoneConfig", "Path to JSON timezone config", false, null],
    ["CreateGroups", "Create Azure AD groups for timezones", false, "false"],
    ["ApplyPolicies", "Apply quiet hours policies", false, "false"],
    ["WorkingHoursStart", "Start time", false, "09:00"],
    ["WorkingHoursEnd", "End time", false, "18:00"],
  ],
  ["intune", "policies", "notifications", "work-life-balance"],
  { state: "published", environment: "Microsoft Intune, Teams, Outlook, iOS/Android managed devices", confidence: 80 }
);

addScript("02-cloud-hybrid", "Set-IntuneDeviceLocalAdmin",
  "02-Cloud-Hybrid/Intune/Set-IntuneDeviceLocalAdmin.ps1", "Intune",
  "Grants local administrator rights to user on specific Intune-managed device",
  "Deploys PowerShell script via Intune to add user to local Administrators group by device serial number.",
  false, false,
  [
    ["SerialNumber", "Target device serial number", true, null],
    ["UserPrincipalName", "User email/UPN", true, null],
    ["Force", "Skip confirmation prompts", false, "false"],
  ],
  ["intune", "security", "admin-rights", "devices"],
  { state: "published", environment: "Microsoft Intune, Windows 10/11 managed devices", confidence: 85 }
);

addScript("02-cloud-hybrid", "Get-MailboxForwardingRules",
  "02-Cloud-Hybrid/Microsoft365/Get-MailboxForwardingRules.ps1", "Microsoft365",
  "Lists all mailboxes with forwarding rules in Microsoft 365",
  "Connects to Exchange Online and identifies mailboxes with SMTP forwarding and/or inbox rules that forward messages.",
  false, true,
  [
    ["ExportToCSV", "Export results to CSV", false, "false"],
    ["CSVPath", "Path for CSV export", false, null],
  ],
  ["exchange", "email", "security", "forwarding"],
  { state: "published", environment: "Exchange Online, ExchangeOnlineManagement PowerShell module", confidence: 90 }
);

addScript("02-cloud-hybrid", "Get-TeamsUsage",
  "02-Cloud-Hybrid/Microsoft365/Get-TeamsUsage.ps1", "Microsoft365",
  "Reports on Microsoft Teams usage and activity",
  "Analyzes Teams usage including active users, teams, meeting statistics, channel activity, storage usage, and external collaboration.",
  false, true,
  [
    ["Days", "Number of days to analyze", false, "30"],
    ["ExportPath", "CSV export path", false, null],
  ],
  ["teams", "reporting", "usage"],
  { state: "published", environment: "Microsoft 365 with Teams, Microsoft Graph SDK", confidence: 85 }
);

addScript("02-cloud-hybrid", "Remove-MailboxForwardingRules",
  "02-Cloud-Hybrid/Microsoft365/Remove-MailboxForwardingRules.ps1", "Microsoft365",
  "Removes specific forwarding rules from mailboxes in Microsoft 365",
  "Connects to Exchange Online and removes inbox rules or SMTP forwarding configuration from specific or all mailboxes.",
  true, true,
  [
    ["RuleName", "Name of inbox rule to remove (supports wildcards)", false, null],
    ["Mailbox", "Specific mailbox to target", false, null],
    ["RemoveSMTPForwarding", "Also remove SMTP forwarding", false, "false"],
    ["ExportLog", "Export removal log to CSV", false, "false"],
  ],
  ["exchange", "email", "security", "cleanup"],
  { state: "published", environment: "Exchange Online, ExchangeOnlineManagement module", confidence: 85 }
);

// ====================== 03-SECURITY-COMPLIANCE ======================

addScript("03-security-compliance", "Get-SecurityEventLog",
  "03-Security-Compliance/Auditing/Get-SecurityEventLog.ps1", "Auditing",
  "Analyzes Windows Security Event Logs for suspicious activities",
  "Monitors and reports on failed logins (4625), account lockouts (4740), privilege escalation (4672), user creation/deletion (4720/4726), group membership changes (4728/4732/4756), and Kerberos authentication (4768/4771).",
  false, true,
  [
    ["Hours", "Hours to look back", false, "24"],
    ["ExportPath", "CSV export path", false, null],
  ],
  ["security", "auditing", "event-logs", "compliance"],
  { state: "published", environment: "Windows Server with Security Event Log auditing enabled", resolution: "Run with appropriate security log read permissions. Adjust -Hours parameter for the time window needed.", cause: "Security monitoring and incident detection for compliance (SOC, SIEM feed).", confidence: 95, author: "MS Tools Team" }
);

addScript("03-security-compliance", "Enable-BitLocker",
  "03-Security-Compliance/Encryption/Enable-BitLocker.ps1", "Encryption",
  "Enables BitLocker encryption on specified drives with recovery key backup",
  "Enables BitLocker with TPM protection, recovery password backup to AD, optional USB key protector, and compliance reporting.",
  true, false,
  [
    ["DriveLetter", "Drive letter to encrypt", false, "C:"],
    ["BackupToAD", "Backup recovery key to Active Directory", false, "false"],
    ["SaveRecoveryKey", "Save recovery key to specified path", false, null],
  ],
  ["security", "encryption", "bitlocker", "compliance"],
  { state: "published", environment: "Windows 10/11 Pro/Enterprise with TPM 2.0", confidence: 90 }
);

addScript("03-security-compliance", "Get-DefenderStatus",
  "03-Security-Compliance/Endpoint-Security/Get-DefenderStatus.ps1", "Endpoint-Security",
  "Reports on Windows Defender status across multiple machines",
  "Checks Defender status including antivirus/antimalware status, definition versions, last scan times, threat detections, and real-time protection.",
  false, true,
  [
    ["ComputerName", "Computer name(s) to check", false, "localhost"],
    ["ExportPath", "CSV export path", false, null],
  ],
  ["security", "defender", "endpoint", "antivirus"],
  { state: "published", environment: "Windows 10/11, Windows Server 2016+ with Microsoft Defender", confidence: 85 }
);

addScript("03-security-compliance", "Get-RoleAssignments",
  "03-Security-Compliance/RBAC/Get-RoleAssignments.ps1", "RBAC",
  "Reports on Azure RBAC role assignments",
  "Generates comprehensive RBAC reports including role assignments by scope, user/group mappings, privileged roles, and custom role definitions.",
  false, true,
  [
    ["Scope", "Scope to analyze (subscription, resource group, or resource)", false, null],
    ["IncludeCustomRoles", "Include custom role definitions", false, "false"],
    ["ExportPath", "CSV export path", false, null],
  ],
  ["security", "rbac", "azure", "compliance"],
  { state: "published", environment: "Azure subscription with RBAC, Az PowerShell module", confidence: 85 }
);

addScript("03-security-compliance", "Set-BillingAccess",
  "03-Security-Compliance/RBAC/Set-BillingAccess.ps1", "RBAC",
  "Sets billing access roles for Azure subscriptions",
  "Configures billing reader or contributor roles for users requiring financial access to Azure resources.",
  true, false,
  [],
  ["security", "rbac", "azure", "billing"],
  { state: "draft", environment: "Azure subscription with billing permissions", confidence: 70 }
);

addScript("03-security-compliance", "Set-GlobalAdmin",
  "03-Security-Compliance/RBAC/Set-GlobalAdmin.ps1", "RBAC",
  "Assigns Global Administrator role in Azure AD",
  "Manages Global Administrator role assignments with safety checks and audit logging.",
  true, false,
  [],
  ["security", "rbac", "azure-ad", "admin"],
  { state: "draft", environment: "Azure AD / Entra ID with Global Admin eligibility", confidence: 75 }
);

// ====================== 04-BACKUP-DR ======================

addScript("04-backup-dr", "Start-AzureVMBackup",
  "04-Backup-DR/Azure-Backup/Start-AzureVMBackup.ps1", "Azure-Backup",
  "Initiates on-demand backup for Azure VMs",
  "Triggers backup jobs for specified Azure VMs and monitors backup status.",
  false, false,
  [
    ["ResourceGroupName", "Azure Resource Group containing VMs", true, null],
    ["VMName", "VM name or * for all VMs in RG", true, null],
    ["Wait", "Wait for backup to complete", false, "false"],
  ],
  ["azure", "backup", "virtual-machines"],
  { state: "published", environment: "Azure VMs with Azure Backup vault configured, Az PowerShell module", confidence: 85 }
);

addScript("04-backup-dr", "Start-WindowsBackup",
  "04-Backup-DR/Windows-Backup/Start-WindowsBackup.ps1", "Windows-Backup",
  "Initiates Windows Server Backup",
  "Manages Windows Server Backup including start backup jobs, monitor status, verify completion, and report backup history.",
  false, false,
  [
    ["BackupTarget", "Backup target path (disk or network)", true, null],
    ["Include", "Volumes to include", false, "C:"],
    ["BackupType", "Full or Incremental", false, "Full"],
  ],
  ["backup", "windows-server", "disaster-recovery"],
  { state: "published", environment: "Windows Server with Windows Server Backup feature", confidence: 85 }
);

// ====================== 05-NETWORKING ======================

addScript("05-networking", "Test-NetworkConnectivity",
  "05-Networking/Connectivity/Test-NetworkConnectivity.ps1", "Connectivity",
  "Tests network connectivity and diagnoses issues",
  "Comprehensive network diagnostics including ping tests, port connectivity, DNS resolution, traceroute, and network path analysis.",
  false, true,
  [
    ["Target", "Target host or IP address", true, null],
    ["Ports", "Ports to test", false, "80, 443, 3389, 445, 53, 25"],
    ["IncludeTraceroute", "Include traceroute to target", false, "false"],
  ],
  ["networking", "diagnostics", "connectivity"],
  { state: "published", environment: "Windows/macOS/Linux with PowerShell 7+, network access", confidence: 90 }
);

// ====================== 06-MONITORING ======================

addScript("06-monitoring", "Get-ServerHealth",
  "06-Monitoring/Health-Performance/Get-ServerHealth.ps1", "Health-Performance",
  "Comprehensive server health check with scoring system",
  "Monitors server health metrics including CPU/memory usage, disk space, network utilization, service status, event log errors, and uptime. Uses scoring system: Healthy (>=80), Warning (60-79), Critical (<60).",
  false, true,
  [
    ["ComputerName", "Server name(s) to check", false, "localhost"],
    ["ExportPath", "CSV export path", false, null],
  ],
  ["monitoring", "health", "performance", "reporting"],
  { state: "published", environment: "Windows Server 2016+, PowerShell 7+", resolution: "Run against target servers. Health score: Healthy (>=80), Warning (60-79), Critical (<60). Export to CSV for trending.", cause: "Proactive server health monitoring and capacity planning.", confidence: 95, author: "MS Tools Team" }
);

// ====================== 07-AUTOMATION ======================

addScript("07-automation", "Reset-BulkPasswords",
  "07-Automation/Bulk-Operations/Reset-BulkPasswords.ps1", "Bulk-Operations",
  "Bulk password reset for multiple users",
  "Resets passwords for multiple users with CSV input, generates secure random passwords, exports credentials, optional email notification, and account unlock.",
  true, true,
  [
    ["CSVPath", "CSV file with Username column", true, null],
    ["UnlockAccounts", "Unlock user accounts", false, "false"],
    ["NotifyUsers", "Send password reset notification", false, "false"],
    ["ExportPath", "Export path for new credentials", false, null],
  ],
  ["passwords", "bulk-operations", "security"],
  { state: "published", environment: "Windows Server with AD DS, PowerShell 7+", confidence: 90 }
);

addScript("07-automation", "Set-M365Licenses",
  "07-Automation/License-Management/Set-M365Licenses.ps1", "License-Management",
  "Automates Microsoft 365 license assignment and management",
  "Bulk assigns or removes Microsoft 365 licenses with license assignment based on attributes, department-based licensing, and CSV-based operations.",
  true, true,
  [
    ["CSVPath", "Path to CSV with users and licenses", false, null],
    ["LicenseSKU", "License SKU to assign", false, null],
    ["Department", "Assign licenses to all users in department", false, null],
  ],
  ["licensing", "microsoft-365", "bulk-operations"],
  { state: "published", environment: "Microsoft 365 tenant, Microsoft Graph PowerShell SDK", confidence: 90 }
);

addScript("07-automation", "Remove-UnusedLicenses",
  "07-Automation/License-Management/Remove-UnusedLicenses.ps1", "License-Management",
  "Identify and remove unused Microsoft 365 licenses",
  "Helps reclaim unused licenses by identifying inactive users, disabled accounts, and non-compliant assignments for cost optimization.",
  true, true,
  [
    ["ListOnly", "Show report without changes", false, "true"],
    ["ShowInactiveUsers", "Show users with no sign-in", false, "false"],
    ["InactiveDays", "Days threshold", false, "90"],
    ["RemoveFromInactive", "Remove licenses from inactive", false, "false"],
    ["RemoveFromDisabled", "Remove from disabled accounts", false, "false"],
  ],
  ["licensing", "microsoft-365", "cost-optimization", "cleanup"],
  { state: "published", environment: "Microsoft 365 tenant, Microsoft Graph PowerShell SDK", confidence: 85 }
);

addScript("07-automation", "Install-M365Dependencies",
  "07-Automation/License-Management/Install-M365Dependencies.ps1", "License-Management",
  "Installs all required PowerShell modules for Microsoft 365 administration",
  "Installs and updates necessary modules for Exchange, Graph, Teams, SharePoint, and Azure management.",
  false, false,
  [
    ["UpdateExisting", "Update modules to latest version", false, "false"],
    ["SkipPnP", "Skip PnP.PowerShell installation", false, "false"],
  ],
  ["setup", "dependencies", "modules"],
  { state: "published", environment: "PowerShell 7+ on Windows/macOS/Linux", confidence: 95 }
);

addScript("07-automation", "New-UserWorkflow",
  "07-Automation/User-Provisioning/New-UserWorkflow.ps1", "User-Provisioning",
  "Automated user onboarding workflow",
  "Complete 7-step user provisioning workflow: AD account creation, group membership, AD Connect sync wait, M365 license assignment, home folder creation, activity logging, and welcome email.",
  true, true,
  [
    ["FirstName", "User's first name", true, null],
    ["LastName", "User's last name", true, null],
    ["Username", "Username/SAMAccountName", true, null],
    ["Email", "Email address", true, null],
    ["Department", "Department", true, null],
    ["Manager", "Manager username", false, null],
    ["Groups", "Security groups to add", false, null],
    ["LicenseSKU", "M365 license SKU", false, null],
  ],
  ["provisioning", "onboarding", "workflow", "users"],
  { state: "published", environment: "Hybrid AD environment with Azure AD Connect, Microsoft 365, PowerShell 7+", resolution: "Provide required user details. Script orchestrates 7-step workflow: AD creation -> Groups -> AD Connect sync -> M365 license -> Home folder -> Logging -> Welcome email.", cause: "Streamlined employee onboarding across on-prem and cloud.", confidence: 95, author: "MS Tools Team" }
);

addScript("07-automation", "New-UserOnboarding",
  "07-Automation/User-Provisioning/New-UserOnboarding.ps1", "User-Provisioning",
  "Comprehensive automated user onboarding workflow",
  "End-to-end user onboarding automation handling AD creation, M365 setup, home directory, network shares, welcome email with full reporting.",
  true, true,
  [
    ["FirstName", "User's first name", true, null],
    ["LastName", "User's last name", true, null],
    ["Username", "Username (auto-generated if not provided)", false, null],
    ["Email", "Email address (auto-generated if not provided)", false, null],
    ["Department", "Department", true, null],
    ["Title", "Job title", false, null],
    ["Manager", "Manager's username", false, null],
    ["Office", "Office location", false, null],
    ["PhoneNumber", "Office phone number", false, null],
  ],
  ["provisioning", "onboarding", "workflow", "users"],
  { state: "published", environment: "Hybrid AD environment with Azure AD Connect, Microsoft 365", confidence: 90, author: "MS Tools Team" }
);

addScript("07-automation", "Remove-UserSilent",
  "07-Automation/User-Provisioning/Remove-UserSilent.ps1", "User-Provisioning",
  "Silently removes user from all systems",
  "Offboarding automation that removes user accounts from Active Directory and Microsoft 365 without interactive prompts.",
  true, false,
  [],
  ["offboarding", "users", "cleanup"],
  { state: "published", environment: "AD DS, Microsoft 365, PowerShell 7+", confidence: 80 }
);

addScript("07-automation", "Remove-M365Users",
  "07-Automation/User-Provisioning/Remove-M365Users.ps1", "User-Provisioning",
  "Removes users from Microsoft 365",
  "Bulk removes user accounts from Microsoft 365, revoking licenses and disabling access.",
  true, false,
  [],
  ["offboarding", "users", "microsoft-365", "cleanup"],
  { state: "draft", environment: "Microsoft 365, Microsoft Graph PowerShell SDK", confidence: 75 }
);

addScript("07-automation", "Restore-M365User",
  "07-Automation/User-Provisioning/Restore-M365User.ps1", "User-Provisioning",
  "Restores deleted Microsoft 365 users",
  "Recovers soft-deleted Microsoft 365 user accounts within the retention period.",
  false, false,
  [],
  ["users", "microsoft-365", "disaster-recovery", "restore"],
  { state: "draft", environment: "Microsoft 365, Microsoft Graph PowerShell SDK", confidence: 70 }
);

// ====================== AUTH ======================

addScript("07-automation", "Connect-M365Persistent",
  "07-Automation/Auth/Connect-M365Persistent.ps1", "Auth",
  "Persistent authentication to Microsoft 365 services — certificate-based or cached interactive",
  "Establishes connections to Microsoft Graph, Exchange Online, Azure, and SharePoint using certificate-based (Service Principal) or interactive cached authentication. Checks existing sessions before re-authenticating. Supports selective module connection via -Modules parameter.",
  false, false,
  [
    ["UseCertificate", "Use certificate-based authentication (Service Principal)", false, "false"],
    ["TenantId", "Azure AD Tenant ID (GUID)", false, null],
    ["ClientId", "Azure AD Application (Client) ID", false, null],
    ["CertificateThumbprint", "Certificate thumbprint for authentication", false, null],
    ["Organization", "Organization domain (e.g., contoso.onmicrosoft.com)", false, null],
    ["Modules", "Which modules to connect: MgGraph, ExchangeOnline, Az, PnP", false, "MgGraph, ExchangeOnline"],
    ["Force", "Force re-authentication even if already connected", false, "false"],
    ["ConfigPath", "Path to auth config JSON file", false, "~/.ms-tools/auth-config.json"],
  ],
  ["authentication", "microsoft-365", "automation", "security"],
  { state: "published", environment: "PowerShell 7+, Microsoft Graph SDK, ExchangeOnlineManagement, Az, PnP.PowerShell", resolution: "Run once at session start or at top of automation scripts. Use -UseCertificate for fully non-interactive auth. Without it, authenticates interactively on first run and caches tokens.", cause: "Eliminate repeated browser-based login prompts across M365 PowerShell scripts.", confidence: 95, author: "MS Tools Team" }
);

addScript("07-automation", "New-M365AuthCertificate",
  "07-Automation/Auth/New-M365AuthCertificate.ps1", "Auth",
  "Generates self-signed certificate and config for non-interactive M365 authentication",
  "Creates a self-signed certificate for Azure AD App Registration, exports public key for upload, and saves configuration to ~/.ms-tools/auth-config.json. Cross-platform: uses New-SelfSignedCertificate on Windows, openssl on macOS/Linux.",
  false, false,
  [
    ["TenantId", "Azure AD Tenant ID (required)", true, null],
    ["ClientId", "Azure AD App Client ID (if already created)", false, null],
    ["Organization", "Organization domain (e.g., contoso.onmicrosoft.com)", false, null],
    ["CertificateName", "Certificate common name", false, "MSToolsAuth"],
    ["ValidityYears", "Certificate validity in years", false, "2"],
    ["OutputPath", "Directory for certificate files", false, "~/.ms-tools"],
  ],
  ["authentication", "certificates", "setup", "security"],
  { state: "published", environment: "PowerShell 7+ on Windows/macOS/Linux, Azure AD App Registration", resolution: "Run once during initial setup. Follow the printed instructions to create/configure the Azure AD App Registration and upload the certificate. Then use Connect-M365Persistent.ps1 -UseCertificate for non-interactive auth.", cause: "One-time setup for certificate-based authentication to avoid browser prompts.", confidence: 90, author: "MS Tools Team" }
);

// ====================== DOCKER COMPONENTS ======================

const insertDocker = db.prepare(
  `INSERT INTO docker_components (name, component_type, port, description, location, details) VALUES (?, ?, ?, ?, ?, ?)`
);

insertDocker.run("Grafana", "Dashboard", "3000",
  "Monitoring and observability dashboard with pre-configured panels for Windows servers, M365 metrics, and Azure resources.",
  "docker/grafana/",
  "Access: http://localhost:3000 (admin/admin). Supports Windows infrastructure, Microsoft 365, and Azure resource monitoring through multiple data sources."
);

insertDocker.run("Prometheus", "Metrics Store", "9090",
  "Time-series database for collecting and storing metrics from WMI Exporter and Graph API Proxy.",
  "docker/prometheus/",
  "Scrape interval: 15 seconds. Targets: windows-servers (WMI Exporter port 9182), graph-api-proxy (port 3001), self-monitoring. Alert rules in prometheus/rules/alerts.yml."
);

insertDocker.run("Alertmanager", "Alert Router", "9093",
  "Routes and manages alerts from Prometheus with grouping, aggregation, inhibition, and silencing.",
  "docker/alertmanager/",
  "Receives alerts from Prometheus based on PromQL rules. Supports alert grouping, notification routing, and silence management."
);

insertDocker.run("Graph API Proxy", "API Translation Layer", "3001",
  "Custom Node.js application translating Microsoft Graph API responses to Grafana JSON datasource format.",
  "docker/graph-api-proxy/",
  "OAuth2 client credentials flow with token caching. Endpoints: /search, /query, /health. Metrics: users.count, users.active, teams.count, licenses.assigned. Requires Azure AD app registration."
);

insertDocker.run("WMI Exporter", "Metrics Collector", "9182",
  "Windows Management Instrumentation exporter for Prometheus, installed on monitored Windows servers.",
  "External (Windows servers)",
  "Must be installed on each monitored Windows server. Exposes Windows metrics (CPU, memory, disk, network, services) in Prometheus format."
);

insertDocker.run("monitoring-stack.sh", "Management Script", null,
  "Wrapper script for managing the entire Docker monitoring stack lifecycle.",
  "docker/monitoring-stack.sh",
  "Commands: start, stop, status, logs [service], backup, add-server, restart [service]. Handles Docker Compose orchestration and stack health checks."
);

db.close();
console.log("Database seeded successfully at:", DB_PATH);
