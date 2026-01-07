# Android Device Enrollment with Role-Based App Deployment

Automated configuration of Android Enterprise enrollment in Microsoft Intune with sophisticated role-based app assignments.

## Overview

This solution automates the entire Android device management lifecycle in Intune:

1. **Role Definition** - Define organizational roles with specific app requirements
2. **Group Creation** - Automatically create Azure AD groups for each role
3. **App Assignment** - Deploy apps based on role with three modes:
   - **Required**: Auto-installed on enrollment
   - **Available**: User can install from Company Portal
   - **Blocked**: Prevented from installation
4. **Configuration Policies** - Pre-configure apps with organization settings

## Quick Start

### Prerequisites

1. **Intune Setup**
   - Microsoft Intune subscription
   - Android Enterprise binding configured
   - Managed Google Play connected

2. **PowerShell Modules**
   ```powershell
   Install-Module Microsoft.Graph -Scope CurrentUser -Force
   ```

3. **Permissions Required**
   - Global Administrator OR
   - Intune Administrator + Groups Administrator

### Basic Usage

```powershell
# 1. Create role groups and assign apps
./New-AndroidEnrollmentConfiguration.ps1 -CreateGroups -AssignApps

# 2. Use custom role configuration
./New-AndroidEnrollmentConfiguration.ps1 -RoleDefinitionFile "./android-roles-custom.json" -CreateGroups -AssignApps

# 3. Preview changes without applying
./New-AndroidEnrollmentConfiguration.ps1 -CreateGroups -AssignApps -WhatIf

# 4. Export current configuration
./New-AndroidEnrollmentConfiguration.ps1 -ExportConfiguration -ExportPath "./my-config.json"
```

## Role Configuration

### Default Roles

The script includes 5 pre-configured roles:

#### 1. **Executive** (C-Level, Directors)
**Apps Installed Automatically:**
- Microsoft Teams (configured)
- Microsoft Outlook (configured)
- WhatsApp Business
- Microsoft Word
- Microsoft Excel
- Microsoft PowerPoint
- Microsoft OneDrive (configured)
- Power BI

**Available in Company Portal:**
- Microsoft SharePoint
- LinkedIn

**Key Features:**
- WhatsApp Business access (restricted to executives only)
- Full M365 suite
- Business intelligence tools

---

#### 2. **Field Team** (Field Workers, Technicians)
**Apps Installed Automatically:**
- Microsoft Teams (configured)
- Microsoft Outlook (configured)
- **AudioMoth** (specialized field app)
- **Field Service Mobile** (Dynamics 365)
- Microsoft OneDrive

**Available in Company Portal:**
- Microsoft Word
- Microsoft Excel
- Adobe Acrobat Reader

**Blocked Apps:**
- WhatsApp (personal version)
- Facebook

**Key Features:**
- Specialized field apps (AudioMoth for acoustic monitoring)
- Dynamics 365 Field Service integration
- Social media restrictions for security

---

#### 3. **Sales** (Sales Team, Account Managers)
**Apps Installed Automatically:**
- Microsoft Teams (configured)
- Microsoft Outlook (configured)
- Dynamics 365 Sales
- LinkedIn Sales Navigator
- Microsoft OneDrive

**Available in Company Portal:**
- Microsoft Word
- Microsoft Excel
- Microsoft PowerPoint

**Key Features:**
- CRM integration
- LinkedIn Sales Navigator for prospecting
- Full productivity suite

---

#### 4. **IT** (IT Staff, Administrators)
**Apps Installed Automatically:**
- Microsoft Teams (configured)
- Microsoft Outlook (configured)
- Microsoft Intune Company Portal
- Microsoft Remote Desktop (configured)
- Microsoft Authenticator
- Microsoft OneDrive

**Available in Company Portal:**
- Microsoft Word
- Microsoft Excel
- Azure Mobile App

**Key Features:**
- Remote management tools
- Azure administration
- Enhanced security tools

---

#### 5. **General** (All Other Staff)
**Apps Installed Automatically:**
- Microsoft Teams (configured)
- Microsoft Outlook (configured)
- Microsoft Word
- Microsoft Excel
- Microsoft OneDrive

**Available in Company Portal:**
- Microsoft PowerPoint
- Microsoft SharePoint
- Adobe Acrobat Reader

**Key Features:**
- Standard M365 productivity apps
- Essential collaboration tools

## Customizing Roles

### Method 1: Edit the JSON Template

1. Copy the template:
   ```bash
   cp android-roles-template.json my-roles.json
   ```

2. Edit `my-roles.json` to add/remove apps or roles:
   ```json
   {
     "CustomRole": {
       "GroupName": "Android-Custom-Team",
       "Description": "Custom team description",
       "RequiredApps": [
         {
           "Name": "App Display Name",
           "PackageId": "com.example.app",
           "ConfigPolicy": true
         }
       ],
       "AvailableApps": [...],
       "BlockedApps": [...]
     }
   }
   ```

3. Run with custom config:
   ```powershell
   ./New-AndroidEnrollmentConfiguration.ps1 -RoleDefinitionFile "./my-roles.json" -CreateGroups -AssignApps
   ```

### Method 2: Edit Script Defaults

Modify the `$defaultRoleConfiguration` hashtable in the script (lines 70-180).

## Finding App Package IDs

### Common Microsoft Apps
| App Name | Package ID |
|----------|------------|
| Microsoft Teams | `com.microsoft.teams` |
| Microsoft Outlook | `com.microsoft.office.outlook` |
| Microsoft Word | `com.microsoft.office.word` |
| Microsoft Excel | `com.microsoft.office.excel` |
| Microsoft PowerPoint | `com.microsoft.office.powerpoint` |
| Microsoft OneDrive | `com.microsoft.skydrive` |
| Microsoft SharePoint | `com.microsoft.sharepoint` |
| Microsoft OneNote | `com.microsoft.office.onenote` |
| Microsoft To Do | `com.microsoft.todos` |
| Microsoft Authenticator | `com.azure.authenticator` |
| Microsoft Remote Desktop | `com.microsoft.rdc.androidx` |
| Microsoft Intune Company Portal | `com.microsoft.windowsintune.companyportal` |
| Power BI | `com.microsoft.powerbim` |

### Dynamics 365 Apps
| App Name | Package ID |
|----------|------------|
| Dynamics 365 Sales | `com.microsoft.dynamics.crm.phone` |
| Dynamics 365 Field Service | `com.microsoft.dynamics.fieldservice` |
| Dynamics 365 Customer Service | `com.microsoft.dynamics.customerservice` |

### Third-Party Apps
| App Name | Package ID |
|----------|------------|
| WhatsApp | `com.whatsapp` |
| WhatsApp Business | `com.whatsapp.w4b` |
| LinkedIn | `com.linkedin.android` |
| LinkedIn Sales Navigator | `com.linkedin.android.salesnavigator` |
| Adobe Acrobat Reader | `com.adobe.reader` |
| Slack | `com.slack` |
| Zoom | `us.zoom.videomeetings` |
| AudioMoth | `org.openacousticdevices.audiomoth` |

### How to Find Package IDs

**Method 1: Google Play Store**
1. Open app in Google Play Store in browser
2. Look at URL: `https://play.google.com/store/apps/details?id=**com.example.app**`
3. The ID after `id=` is the package ID

**Method 2: On Android Device**
```bash
adb shell pm list packages | grep appname
```

**Method 3: From Intune Portal**
1. Go to Apps → Android apps in Intune
2. Click on app → Properties
3. Look for "Package ID" field

## Deployment Workflow

### Step 1: Sync Apps from Google Play

Before running the script, sync required apps from Managed Google Play:

1. Go to **Microsoft Intune Admin Center**
2. Navigate to **Apps** → **Android**
3. Click **Managed Google Play Store**
4. Search and approve apps:
   - Microsoft Teams
   - Microsoft Outlook
   - WhatsApp Business (for Executive role)
   - AudioMoth (for Field Team)
   - Other required apps
5. Click **Sync** to sync apps to Intune

### Step 2: Run Configuration Script

```powershell
# Create groups and assign apps
./New-AndroidEnrollmentConfiguration.ps1 -CreateGroups -AssignApps
```

**What happens:**
- ✓ Creates 5 Azure AD security groups
- ✓ Assigns apps to groups with appropriate intent (Required/Available)
- ✓ Creates app configuration policies for pre-configured apps
- ✓ Sets up app blocking (via compliance policies)

### Step 3: Add Users to Groups

Add users to the appropriate role groups in Azure AD:

**Via Azure Portal:**
1. Go to **Azure AD** → **Groups**
2. Select group (e.g., "Android-Executive-Users")
3. Click **Members** → **Add members**
4. Search and add users

**Via PowerShell:**
```powershell
# Add user to Executive group
$userId = (Get-MgUser -Filter "userPrincipalName eq 'john.doe@contoso.com'").Id
$groupId = (Get-MgGroup -Filter "displayName eq 'Android-Executive-Users'").Id
New-MgGroupMember -GroupId $groupId -DirectoryObjectId $userId
```

### Step 4: Enroll Devices

Users can now enroll their Android devices:

**Work Profile Enrollment (Recommended):**
1. Install **Intune Company Portal** from Play Store
2. Sign in with work account
3. Follow enrollment wizard
4. Apps will install automatically based on role

**Fully Managed Devices:**
1. Factory reset device
2. During setup, enter work email
3. Download Intune app when prompted
4. Complete enrollment
5. Apps deploy automatically

### Step 5: Monitor Deployment

Check deployment status in Intune:

1. **Apps** → **Monitor** → **App install status**
2. Filter by app or group
3. View success/pending/failed installations

## App Deployment Modes

### Required Apps
- **Install**: Automatic on device enrollment
- **Update**: Automatic when available
- **Uninstall**: User cannot uninstall
- **Status**: Tracked and enforced by Intune

**Best for:** Essential business apps (Teams, Outlook, Authenticator)

### Available Apps
- **Install**: User chooses from Company Portal
- **Update**: Automatic after user installs
- **Uninstall**: User can uninstall
- **Status**: Optional

**Best for:** Optional productivity tools (PowerPoint, OneNote, SharePoint)

### Blocked Apps
- **Install**: Prevented by compliance policy
- **Existing**: User warned to uninstall
- **Compliance**: Device marked non-compliant if installed

**Best for:** Social media restrictions, personal versions of business apps

## App Configuration Policies

Apps marked with `ConfigPolicy: true` can be pre-configured with organization settings.

### Example: Outlook Configuration
```json
{
  "Name": "Microsoft Outlook",
  "PackageId": "com.microsoft.office.outlook",
  "ConfigPolicy": true,
  "ConfigSettings": {
    "com.microsoft.outlook.EmailProfile.EmailAddress": "{{mail}}",
    "com.microsoft.outlook.EmailProfile.EmailUPN": "{{userprincipalname}}",
    "com.microsoft.intune.mam.managedbrowser.disableShareToThirdParty": true
  }
}
```

### Supported Configuration Keys

**Teams:**
- Auto sign-in
- Default tenant
- Disable guest access

**Outlook:**
- Email account setup
- Signature configuration
- S/MIME settings

**OneDrive:**
- Auto-mount
- Known folder move
- Files on-demand

## Troubleshooting

### Apps Not Showing in Script

**Problem:** App found in Intune but script can't find it

**Solution:**
1. Verify app is synced: **Apps** → **Android** → **Managed Google Play apps**
2. Check package ID matches exactly
3. Ensure app is published (not draft)

### App Assignment Fails

**Problem:** Error when assigning app to group

**Solution:**
1. Verify group exists and ID is correct
2. Check you have permission to assign apps
3. Ensure app supports group assignment (some system apps don't)

### Users Not Getting Apps

**Problem:** User enrolled but apps not installing

**Solution:**
1. Verify user is member of correct Azure AD group
2. Check device is enrolled (appears in Intune devices)
3. Sync device: **Devices** → select device → **Sync**
4. Check app install status: **Apps** → **Monitor** → **App install status**

### WhatsApp Only for Executives Not Working

**Problem:** Non-executives can still install WhatsApp

**Solution:**
The script assigns WhatsApp Business to executives, but blocking personal WhatsApp requires:

1. **Create App Protection Policy:**
   ```powershell
   # This would be added to the script
   $blockPolicy = @{
       displayName = "Block Personal WhatsApp"
       targetedAppManagementLevels = "unmanaged"
       apps = @(@{packageId = "com.whatsapp"})
   }
   ```

2. **Use Compliance Policy:**
   - Go to **Devices** → **Compliance policies**
   - Create Android policy
   - Add "Restricted apps" with package ID `com.whatsapp`
   - Assign to all users EXCEPT Executive group

## Advanced Scenarios

### Dynamic Group Membership

Instead of manually adding users to groups, use dynamic groups:

```powershell
# Create dynamic group for executives
$groupParams = @{
    DisplayName = "Android-Executive-Users"
    GroupTypes = @("DynamicMembership")
    MembershipRule = '(user.jobTitle -contains "Director") -or (user.jobTitle -contains "VP") -or (user.jobTitle -contains "Chief")'
    MembershipRuleProcessingState = "On"
}
```

### Conditional App Deployment

Deploy apps based on multiple conditions:

```json
{
  "FieldTeam-GPS-Enabled": {
    "GroupName": "Android-Field-GPS-Devices",
    "MembershipRule": "(device.deviceOSType -eq 'Android') -and (device.enrollmentProfileName -eq 'FieldWorker')",
    "RequiredApps": [
      {"Name": "GPS Tracker", "PackageId": "com.company.gpstracker"}
    ]
  }
}
```

### Different Configs per Region

```json
{
  "Sales-EMEA": {
    "GroupName": "Android-Sales-EMEA",
    "RequiredApps": [
      {"Name": "Teams", "PackageId": "com.microsoft.teams"},
      {"Name": "WhatsApp Business", "PackageId": "com.whatsapp.w4b", "ConfigPolicy": true}
    ]
  },
  "Sales-Americas": {
    "GroupName": "Android-Sales-Americas",
    "RequiredApps": [
      {"Name": "Teams", "PackageId": "com.microsoft.teams"},
      {"Name": "Slack", "PackageId": "com.slack"}
    ]
  }
}
```

## Best Practices

1. **Start Small**: Test with one role/group before deploying to all
2. **Use Available First**: Deploy new apps as "Available" to test before making "Required"
3. **Monitor Compliance**: Check app install rates and device compliance regularly
4. **Update Regularly**: Keep app lists current as business needs change
5. **Document Changes**: Use git to track role configuration changes
6. **Test Blocking**: Verify blocked apps actually prevent installation
7. **Configure Essential Apps**: Use configuration policies for Teams, Outlook to streamline user experience

## Security Considerations

- **Blocked Apps**: Use compliance policies for enforcement
- **App Protection Policies**: Add MAM policies for data protection
- **Conditional Access**: Require compliant devices for corporate access
- **Regular Reviews**: Audit group membership quarterly
- **Least Privilege**: Only give required apps, use Available for optional ones

## Support

For issues or questions:
- Review Intune deployment logs
- Check Microsoft Intune admin center for errors
- Verify prerequisites are met
- Test with WhatIf flag first

---

**Script Location:** `02-Cloud-Hybrid/Intune/New-AndroidEnrollmentConfiguration.ps1`
**Template Location:** `02-Cloud-Hybrid/Intune/android-roles-template.json`
