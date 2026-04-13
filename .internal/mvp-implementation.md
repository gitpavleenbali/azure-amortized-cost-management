# MVP Implementation Strategy — Budget Alerts Automation

> **Current Role:** Contributor (subscription-level)  
> **Date:** March 2026  

---

## 1. Strategy Overview

### The Handover Model

```mermaid
%%{init:{"theme":"base","themeVariables":{"primaryColor":"#1B2A4A","primaryTextColor":"#FFFFFF","lineColor":"#64748B","background":"transparent","mainBkg":"transparent","edgeLabelBackground":"transparent"}}}%%
flowchart TB
    subgraph P1[\" PHASE 1 — Platform Team Builds MVP \"]
        P1A["Deploy into QA sandbox"] --> P1B["Validate all modules E2E"] --> P1C["Document + hand over clean"]
    end
    subgraph P2[" PHASE 2 — Team Takes Ownership "]
        P2A["Review + test in QA"] --> P2B["Adjust params for staging/prod"] --> P2C["Promote via CI/CD"]
    end
    subgraph P3[" PHASE 3 — Production Rollout "]
        P3A["Deploy to prod subs"] --> P3B["Enable amortized pipeline"] --> P3C["Backfill 8 000 RGs"]
    end
    P1 --> P2 --> P3

    style P1 fill:#064E3B,stroke:#34D399,stroke-width:2px,color:#ECFDF5
    style P2 fill:#1E3A5F,stroke:#60A5FA,stroke-width:2px,color:#F0F9FF
    style P3 fill:#2E1065,stroke:#A78BFA,stroke-width:2px,color:#F5F3FF
    style P1A fill:#064E3B,stroke:#34D399,color:#ECFDF5
    style P1B fill:#064E3B,stroke:#34D399,color:#ECFDF5
    style P1C fill:#064E3B,stroke:#34D399,color:#ECFDF5
    style P2A fill:#1E3A5F,stroke:#60A5FA,color:#F0F9FF
    style P2B fill:#1E3A5F,stroke:#60A5FA,color:#F0F9FF
    style P2C fill:#1E3A5F,stroke:#60A5FA,color:#F0F9FF
    style P3A fill:#2E1065,stroke:#A78BFA,color:#F5F3FF
    style P3B fill:#2E1065,stroke:#A78BFA,color:#F5F3FF
    style P3C fill:#2E1065,stroke:#A78BFA,color:#F5F3FF
```

### Why Sandbox-First

| Reason | Detail |
|--------|--------|
| **No production risk** | QA subscription has no business-critical workloads |
| **Contributor is sufficient** | We can create RGs, deploy resources, set budgets, assign policies |
| **Validates real tenant** | Same Entra ID, same policies, same provider registrations |
| **Clean handover artifact** | Team gets a working deployment + parameter files they just re-point |

---

## 2. Resource Group & Naming Convention

### Naming Standard

All resources follow your organization's existing naming convention combined with Azure Well-Architected naming:

| Resource | Name | Rationale |
|----------|------|-----------|
| **Resource Group** | `rg-finops-budget-mvp` | Clear purpose, `mvp` suffix signals throwaway/promotable |
| **Action Group** | `ag-finops-budget-alerts-mvp` | Matches existing naming pattern |
| **Storage Account** | `stfinopsbudgetmvp` | 3-24 chars, lowercase, globally unique |
| **Logic App (Auto-Budget)** | `la-finops-auto-budget-mvp` | Descriptive, dash-delimited |
| **Logic App (Budget Change)** | `la-finops-budget-change-mvp` | Descriptive, dash-delimited |
| **Function App** | `func-finops-amortized-mvp` | Azure Functions naming convention |
| **App Service Plan** | `asp-finops-amortized-mvp` | Consumption plan for Function |
| **Subscription Budget** | `finops-sub-budget-dev` | Budget name (not a resource, but named) |
| **Policy Definition** | `finops-audit-rg-without-budget-dev` | Policy definition at subscription scope |
| **Event Grid Subscription** | `evgs-finops-new-rg-mvp` | Event Grid system topic subscription |

### Tags (Applied to All Resources)

```json
{
  "finops-platform": "budget-alerts-automation",
  "managed-by": "platform-team",
  "environment": "mvp",
  "Owner": "Platform Team",
  "CostCenter": "HybridCloud-FinOps",
  "Purpose": "platform-deployment",
  "DecommissionAfter": "2026-06-30"
}
```

The `DecommissionAfter` tag signals the team to either promote or delete this RG by end of Q3.

### Location

**`eastus`** — Matches the majority of existing RGs in this QA subscription. No reason to introduce a new region for the MVP.

> **Note for production:** Production environments should switch to `westeurope` or `germanywestcentral` for EU data residency compliance. The `prod.bicepparam` file already has `westeurope`.

---

## 3. RBAC Assessment

### What We Have

| Role | Scope | Status |
|------|-------|--------|
| **Contributor** | Subscription | ✅ Confirmed |

### What We Need vs. What Contributor Covers

| Action | Required Role | Contributor Covers? | Blocker? |
|--------|--------------|--------------------|----|
| Create Resource Group | Contributor | ✅ Yes | No |
| Deploy Logic Apps | Contributor | ✅ Yes | No |
| Deploy Storage Account | Contributor | ✅ Yes | No |
| Deploy Function App | Contributor | ✅ Yes | No |
| Create Event Grid Subscription | Contributor | ✅ Yes | No |
| Create/Update Budgets | Cost Management Contributor | ⚠️ Contributor includes this | No |
| Create Policy Definition | Resource Policy Contributor | ⚠️ Contributor includes this at sub scope | No |
| Assign Policy | Resource Policy Contributor | ⚠️ Contributor includes this | No |
| Assign RBAC to Logic App MI | User Access Administrator | ❌ **Not included** | **Yes — workaround below** |

### RBAC Gap: Logic App Managed Identity

The auto-budget Logic App needs `Cost Management Contributor` on the subscription so it can create budgets. Assigning that role requires `User Access Administrator` or `Owner`, which we don't have.

**MVP Workaround Options:**

1. **Ask subscription admin** to pre-create the role assignment after we deploy the Logic App (1 CLI command)
2. **Deploy without Event Grid trigger** — test the Logic App manually via HTTP trigger instead
3. **Request temporary UAA** — scoped only to the finops RG, time-limited

**Recommended:** Option 1. We deploy everything, then provide the subscription admin the exact command:

```bash
# Subscription admin runs this after deployment (needs Owner/UAA):
principalId=$(az logic workflow show -g rg-finops-budget-mvp -n la-finops-auto-budget-mvp --query "identity.principalId" -o tsv)
az role assignment create \
  --assignee-object-id $principalId \
  --role "434105ed-43f6-45c7-a02f-909b2ba83430" \
  --scope "/subscriptions/<YOUR_SUBSCRIPTION_ID>"
```

---

## 4. MVP Parameter File

We'll create a new `parameters/mvp.bicepparam` specifically for this deployment:

```bicep
using '../infra/main.bicep'

param environment = 'dev'                              // Bicep only allows dev/staging/prod
param location = 'eastus'                              // Match existing QA subscription region
param resourceGroupName = 'rg-finops-budget-mvp'       // Dedicated MVP resource group
param finopsEmail = 'your-finops-team@example.com'     // FinOps team email for alerts
param defaultBudgetAmount = 100                        // EUR 100 default for new RGs
param subscriptionBudgetAmount = 5000                  // EUR 5000 sub-level (QA is low spend)
param enableAmortizedPipeline = false                  // Enable AFTER cost export has 1 week of data
param enableAutoBudget = true                          // Core MVP feature
param enableSelfServiceChange = true                   // Core MVP feature
param tags = {
  'finops-platform': 'budget-alerts-automation'
  'managed-by': 'platform-team'
  environment: 'mvp'
  Owner: 'Platform Team'
  CostCenter: 'HybridCloud-FinOps'
  Purpose: 'platform-deployment'
  DecommissionAfter: '2026-06-30'
}
```

---

## 5. Deployment Phases (Step-by-Step)

### Phase 1: Pre-Flight Checks (5 min)

| # | Action | Command | Status |
|---|--------|---------|--------|
| 1.1 | Verify login context | `az account show -o table` | ✅ Done |
| 1.2 | Verify Contributor role | `az role assignment list --all --query "[?principalName=='<YOUR_UPN>']"` | ✅ Done |
| 1.3 | Check resource providers | See Section 6 below | ✅ 5/6 registered |
| 1.4 | Register missing provider | `az provider register --namespace Microsoft.CostManagementExports` | 🔲 To do |
| 1.5 | Verify Bicep CLI | `az bicep version` | 🔲 To do |

### Phase 2: Infrastructure Deployment (10 min)

| # | Action | What It Creates |
|---|--------|----------------|
| 2.1 | **Bicep lint + build** | Validates all 9 modules compile cleanly |
| 2.2 | **What-If preview** | Shows exactly what will be created — review before applying |
| 2.3 | **Deploy** | Creates RG + all 8 resources inside it |
| 2.4 | **Capture outputs** | Store storage account name, Logic App URLs, Action Group ID |

```powershell
# 2.1 — Validate
az bicep build --file infra/main.bicep

# 2.2 — Preview
az deployment sub create `
  --location eastus `
  --template-file infra/main.bicep `
  --parameters parameters/mvp.bicepparam `
  --what-if

# 2.3 — Deploy
az deployment sub create `
  --location eastus `
  --template-file infra/main.bicep `
  --parameters parameters/mvp.bicepparam `
  --name "finops-budget-mvp-deploy"

# 2.4 — Capture outputs
az deployment sub show --name "finops-budget-mvp-deploy" --query "properties.outputs" -o json
```

### Phase 3: Post-Deployment Configuration (10 min)

| # | Action | Detail |
|---|--------|--------|
| 3.1 | **RBAC for Logic App MI** | Ask subscription admin or use workaround (see Section 3) |
| 3.2 | **Event Grid wiring** | Update Event Grid subscription with actual Logic App callback URL |
| 3.3 | **Seed budget table** | Run `Initialize-BudgetTable.ps1` against the new storage account |
| 3.4 | **Register cost export provider** | `az provider register --namespace Microsoft.CostManagementExports` |

```powershell
# 3.2 — Wire Event Grid to Logic App
$callbackUrl = az logic workflow show -g rg-finops-budget-mvp -n la-finops-auto-budget-mvp --query "accessEndpoint" -o tsv
az eventgrid event-subscription create `
  --name "evgs-finops-new-rg-mvp" `
  --source-resource-id "/subscriptions/<YOUR_SUBSCRIPTION_ID>" `
  --endpoint $callbackUrl `
  --included-event-types "Microsoft.Resources.ResourceWriteSuccess" `
  --advanced-filter data.operationName StringContains "Microsoft.Resources/subscriptions/resourceGroups/write"

# 3.3 — Seed budget table
.\scripts\Initialize-BudgetTable.ps1 `
  -StorageAccountName "<from deployment output>" `
  -StorageAccountResourceGroup "rg-finops-budget-mvp"
```

### Phase 4: Validation & Smoke Tests (15 min)

| # | Test | How | Expected Result |
|---|------|-----|----------------|
| 4.1 | **Subscription budget exists** | Portal → Cost Management → Budgets | Budget with 5 thresholds visible |
| 4.2 | **Policy compliance** | Portal → Policy → Compliance → filter `finops` | Policy assigned, shows compliant/non-compliant RGs |
| 4.3 | **Auto-budget trigger** | Create a test RG → check Logic App run history | Logic App fires, creates €100 budget on new RG |
| 4.4 | **Self-service endpoint** | POST to budget-change Logic App trigger URL | Returns 200, budget updated |
| 4.5 | **Action Group** | Portal → Monitor → Action Groups | Email receiver configured |
| 4.6 | **Storage table** | Portal → Storage Account → Tables → `budgets` | Table exists with seeded rows |
| 4.7 | **Backfill dry-run** | `.\scripts\Invoke-BudgetBackfill.ps1 -DryRun` | Lists RGs that would get budgets (skips MC_, NetworkWatcher, etc.) |

### Phase 5: FinOps Inventory & Amortized Pipeline (Week 2)

#### Architecture Decision: Option C — FinOps Inventory

Three approaches were evaluated for the amortized alerting requirement:

| Option | Approach | Scalability | Data Accuracy | Dashboard | Verdict |
|--------|----------|-------------|---------------|-----------|---------|
| **A** | Azure Function + simple budget table | Good | Good (CSV) | Poor — single-purpose | Too limited |
| **B** | Log Analytics + Scheduled Query Rules | Great | Great (KQL) | Great (Workbooks) | Expensive — ingestion cost per GB |
| **C** | **FinOps Inventory (Cosmos DB + enhanced Function)** | **Great** | **Great** | **Great (REST API + Power BI)** | **SELECTED** |

**Why Option C wins:**
- **Single source of truth** — one Cosmos DB container holds technical budget, finance budget, amortized MTD, forecast, variance, compliance status
- **Finance vs Technical comparison** — executive requirement: "total budget is 250K, spend is 265K, so 15K extra"
- **Dashboard-ready** — Function exposes 9 REST endpoints for Power BI / dashboards
- **Near-zero cost** — Cosmos DB Serverless at 8,000 documents costs ~$1/month
- **Extensible** — add columns for tags, cost center roll-ups, quarterly trends without changing architecture

#### FinOps Inventory Table Schema

```
Database: finops / Container: inventory
Partition Key    = subscriptionId
Document ID      = {subscriptionId}_{rgName}
──────────────────────────────────────────
TechnicalBudget  = from Azure Consumption API (3-month avg + 10%)
FinanceBudget    = from finance department (Set-FinanceBudget.ps1)
BudgetName       = Azure budget resource name
OwnerEmail       = from RG Owner tag / budget contacts
CostCenter       = from RG CostCenter tag
──────────────────────────────────────────
AmortizedMTD     = month-to-date amortized cost (updated daily by Function)
ForecastEOM      = end-of-month forecast (burn rate extrapolation)
BurnRateDaily    = daily burn rate
ActualPct        = AmortizedMTD / Budget * 100
ForecastPct      = ForecastEOM / Budget * 100
ComplianceStatus = on_track | warning | over_budget | no_budget
──────────────────────────────────────────
LastSeeded       = when Initialize-BudgetTable.ps1 ran
LastEvaluated    = when Function last evaluated (daily)
```

#### API Endpoints (Azure Function)

| Endpoint | Method | Purpose | Consumer |
|----------|--------|---------|----------|
| `/api/evaluate` | GET | Manual trigger for amortized evaluation | Ops / testing |
| `/api/inventory` | GET | Full inventory as JSON (filterable by sub/status) | Power BI, dashboards |
| `/api/variance` | GET | Finance vs Technical budget variance report | Executive dashboards |

#### Deployment Sequence

| # | Action | When |
|---|--------|------|
| 5.1 | Create amortized cost export | Day 1 (starts collecting data) |
| 5.2 | Seed inventory table | Day 1 (`Initialize-BudgetTable.ps1`) |
| 5.3 | Load finance budgets | Day 1-3 (`Set-FinanceBudget.ps1` from CSV) |
| 5.4 | Wait for export data | Day 1-7 |
| 5.5 | Re-deploy with `enableAmortizedPipeline = true` | Day 8+ |
| 5.6 | Publish Function code | `func azure functionapp publish` |
| 5.7 | Validate: call `/api/evaluate` manually | Verify inventory updates |
| 5.8 | Validate: call `/api/variance` | Verify finance vs technical report |

```powershell
# 5.1 -- Create cost export
.\scripts\New-AmortizedExport.ps1 `
  -StorageAccountName "<from deployment output>" `
  -StorageAccountResourceGroup "rg-finops-budget-mvp"

# 5.2 -- Seed inventory from existing Azure budgets
.\scripts\Initialize-BudgetTable.ps1 `
  -StorageAccountName "<from deployment output>" `
  -StorageAccountResourceGroup "rg-finops-budget-mvp"

# 5.3 -- Load finance budgets (CSV from finance team)
.\scripts\Set-FinanceBudget.ps1 `
  -StorageAccountName "<from deployment output>" `
  -StorageAccountResourceGroup "rg-finops-budget-mvp" `
  -CsvPath "finance-budgets.csv"
```

---

### Phase 6: Budget at RG Creation — What Azure Supports

**Question:** Can you set a budget during RG creation in the Azure portal?

**Answer:** **No.** The Azure portal RG creation flow has: Subscription, RG Name, Region, Tags, Review + Create. There is no budget field. Azure Budgets are a separate Consumption API resource — they can only be created after the RG exists.

**Our solution:** Event Grid + Logic App (`la-finops-auto-budget`) detects `Microsoft.Resources.ResourceWriteSuccess` events and auto-creates a EUR 100 default budget within seconds of RG creation. This is the correct workaround per Framework SS6.2.

**For Service Catalog-created RGs:** The Service Catalog will add a "Monthly Budget" field. Post-provisioning Logic App reads it and creates a custom budget. This is a mid-term roadmap item (6-month Service Catalog build).

### Phase 7: Existing RGs Without Budgets — Scanner

The backfill script (`Invoke-BudgetBackfill.ps1`) already handles this:
1. Scans all enabled subscriptions for RGs
2. Skips excluded prefixes (MC_, FL_, NetworkWatcherRG, etc.)
3. Calculates 3-month avg spend + 10% buffer (min EUR 100)
4. Extracts `Owner` and `BillingContact` from RG tags for per-threshold routing
5. Creates budget via REST API with 3 thresholds (90%, 100%, 110%)
6. Supports `-DryRun`, `-Top N`, `-ExportCsv` for staged rollout

**Access control:** The backfill script runs with a service principal or CSA credentials. For self-service by RG owners, the `la-finops-budget-change` Logic App validates that the requestor email matches the RG's Owner tag before allowing budget modification.

### Phase 8: Finance vs Technical Budget Comparison

This is built into the FinOps Inventory:

| Concept | Source | Column |
|---------|--------|--------|
| **Finance Budget** | Finance department CSV or manual entry | `FinanceBudget` |
| **Technical Budget** | Azure Consumption API (3-month avg + 10%) | `TechnicalBudget` |
| **Amortized Spend** | Daily cost export (amortized, not actual) | `AmortizedMTD` |
| **Finance Variance** | AmortizedMTD - FinanceBudget | Calculated by Function |
| **Technical Variance** | AmortizedMTD - TechnicalBudget | Calculated by Function |

**Executive view (stakeholder requirement):**

```mermaid
%%{init:{"theme":"base","themeVariables":{"primaryColor":"#1B2A4A","primaryTextColor":"#FFFFFF","lineColor":"#64748B","background":"transparent","mainBkg":"transparent","edgeLabelBackground":"transparent"}}}%%
flowchart LR
    BU["BU: Healthcare Imaging"] --> FIN["Finance Budget<br/>EUR 250 000"]
    BU --> SPEND["Amortized MTD<br/>EUR 265 000"]
    FIN & SPEND --> VAR["Variance<br/>+EUR 15 000 = 6% over"]
    VAR --> STATUS["OVER BUDGET"]

    style BU fill:#1E3A5F,stroke:#60A5FA,color:#F0F9FF
    style FIN fill:#064E3B,stroke:#34D399,color:#ECFDF5
    style SPEND fill:#7C2D12,stroke:#FB923C,color:#FFF7ED
    style VAR fill:#7F1D1D,stroke:#EF4444,color:#FEF2F2
    style STATUS fill:#4C0519,stroke:#F43F5E,color:#FFF1F2
```

The `/api/variance` endpoint returns this data grouped by CostCenter for Power BI consumption.

---

## 6. Resource Provider Status

Checked against the target subscription:

| Provider | Status | Action |
|----------|--------|--------|
| `Microsoft.Consumption` | ✅ Registered | None |
| `Microsoft.CostManagement` | ✅ Registered | None |
| `Microsoft.EventGrid` | ✅ Registered | None |
| `Microsoft.Logic` | ✅ Registered | None |
| `Microsoft.Storage` | ✅ Registered | None |
| `Microsoft.Web` | ✅ Registered | None |
| `Microsoft.CostManagementExports` | ❌ Not Registered | `az provider register --namespace Microsoft.CostManagementExports` |
| `Microsoft.Insights` | ⚠️ Not checked | `az provider register --namespace Microsoft.Insights` |

---

## 7. What Gets Deployed (9 Modules)

```mermaid
%%{init:{"theme":"base","themeVariables":{"primaryColor":"#1B2A4A","primaryTextColor":"#FFFFFF","lineColor":"#64748B","background":"transparent","mainBkg":"transparent","clusterBkg":"#0F172A22","clusterBorder":"#334155","edgeLabelBackground":"transparent"}}}%%
flowchart TB
    subgraph RG[" rg-finops-budget-mvp — eastus "]
        AG["Action Group<br/>ag-finops-budget-alerts"]
        SA["Storage Account<br/>safinops..."]
        COSMOS[("Cosmos DB<br/>cosmos-finops...")]
        LA1["Logic App<br/>la-finops-auto-budget"]
        LA2["Logic App<br/>la-finops-budget-change"]
        LA3["Logic App<br/>la-finops-backfill"]
        FUNC["Function App — 9 endpoints<br/>func-finops-amortized..."]
        EG["Event Grid Subscription"]
        DASH["Azure Dashboard"]
    end

    subgraph SUB[" Subscription-level "]
        BUDGET["Budget EUR 5 000<br/>finops-sub-budget-dev"]
        POLICY["Audit Policy<br/>finops-audit-rg-without-budget"]
    end

    style RG fill:#0D1B2A,stroke:#3B82F6,stroke-width:2px,color:#E2E8F0
    style SUB fill:#0F172A,stroke:#8B5CF6,stroke-width:2px,color:#E2E8F0
    style AG fill:#451A03,stroke:#FBBF24,color:#FFFBEB
    style SA fill:#2E1065,stroke:#A78BFA,color:#F5F3FF
    style COSMOS fill:#2E1065,stroke:#A78BFA,color:#F5F3FF
    style LA1 fill:#064E3B,stroke:#34D399,color:#ECFDF5
    style LA2 fill:#064E3B,stroke:#34D399,color:#ECFDF5
    style LA3 fill:#064E3B,stroke:#34D399,color:#ECFDF5
    style FUNC fill:#064E3B,stroke:#34D399,color:#ECFDF5
    style EG fill:#1E3A5F,stroke:#60A5FA,color:#F0F9FF
    style DASH fill:#451A03,stroke:#FBBF24,color:#FFFBEB
    style BUDGET fill:#1E3A5F,stroke:#60A5FA,color:#F0F9FF
    style POLICY fill:#1E3A5F,stroke:#60A5FA,color:#F0F9FF
```

---

## 8. Post-Deployment Checklist

When the MVP is validated, the platform team hands over to the FinOps team:

| # | Artifact | Location | Action for SHS |
|---|----------|----------|----------------|
| 1 | **Working MVP in QA** | Azure Portal → `rg-finops-budget-mvp` | Inspect, test, validate |
| 2 | **Code repository** | This `code-base/budget-alerts-automation/` folder | Fork/copy to your DevOps repo |
| 3 | **Parameter files** | `parameters/staging.bicepparam`, `parameters/prod.bicepparam` | Update emails, budget amounts, location |
| 4 | **CI/CD pipeline** | `pipelines/azure-pipelines.yml` | Configure service connection, environments |
| 5 | **Framework document** | `ms-delivery/budget-alerts-automation/budget-alert-framework.md` | Reference for architecture decisions |
| 6 | **RBAC commands** | Section 3 of this document | Subscription owner runs role assignments |
| 7 | **Decommission MVP** | Delete `rg-finops-budget-mvp` after promoting to staging | `az group delete -n rg-finops-budget-mvp` |

### SHS Promotion Path

```mermaid
%%{init:{"theme":"base","themeVariables":{"primaryColor":"#1B2A4A","primaryTextColor":"#FFFFFF","lineColor":"#64748B","background":"transparent","mainBkg":"transparent","edgeLabelBackground":"transparent"}}}%%
flowchart LR
    MVP["MVP<br/>QA sub, eastus"] -- copy params --> STG["Staging<br/>westeurope"]
    STG -- approval gate --> PROD["Production<br/>westeurope<br/>8 000 RG rollout"]

    style MVP fill:#064E3B,stroke:#34D399,color:#ECFDF5
    style STG fill:#1E3A5F,stroke:#60A5FA,color:#F0F9FF
    style PROD fill:#2E1065,stroke:#A78BFA,color:#F5F3FF
```

---

## 9. Risk Register

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Contributor can't assign RBAC to Logic App MI** | Logic App can't create budgets autonomously | SHS admin runs 1 CLI command (Section 3) |
| **CostManagementExports not registered** | Cost export creation fails | Register provider before Phase 5 |
| **QA subscription has low/no spend** | Budget alerts won't fire naturally | Manually trigger Function via HTTP; set budget to €1 for testing |
| **Tag policies on subscription** | Deployment rejected if required tags missing | MVP tags include all standard organization tags (Section 2) |
| **Event Grid subscription needs callback URL** | Can't be set during initial Bicep deploy | Post-deployment script wires it (Phase 3) |

---

## 10. Quick Command Reference

```powershell
# ── Set isolated Azure context (run once per terminal session) ──
$env:AZURE_CONFIG_DIR = "$env:USERPROFILE\.azure-finops"

# ── Navigate to code ──
cd "code-base/budget-alerts-automation"

# ── Pre-flight ──
az account show -o table
az bicep version
az provider register --namespace Microsoft.CostManagementExports
az provider register --namespace Microsoft.Insights

# ── Deploy ──
az bicep build --file infra/main.bicep
az deployment sub create --location eastus --template-file infra/main.bicep --parameters parameters/mvp.bicepparam --what-if
az deployment sub create --location eastus --template-file infra/main.bicep --parameters parameters/mvp.bicepparam --name "finops-budget-mvp-deploy"

# ── Post-deploy ──
az deployment sub show --name "finops-budget-mvp-deploy" --query "properties.outputs" -o json

# ── Validate ──
.\scripts\Invoke-BudgetBackfill.ps1 -DryRun

# ── Tear down (when done) ──
# az group delete -n rg-finops-budget-mvp --yes --no-wait
```

---

## 11. Future Implementation — Scaling from MVP to Production

### Phase 9: Automated Finance Budget Ingestion

**Current:** Finance provides CSV → ops runs script manually.

**Target:** Finance drops CSV into blob → auto-ingests to Cosmos DB.

| Step | What to Build | Effort |
|------|--------------|--------|
| 9.1 | Create `finance-budgets/` container in storage account | 5 min |
| 9.2 | Add Blob-triggered Function to parse CSV and upsert Cosmos DB | 2 hours |
| 9.3 | Grant Finance team `Storage Blob Data Contributor` on that container | 5 min |
| 9.4 | Test: drop CSV → verify Cosmos DB updated → dashboard reflects | 30 min |

Alternative: SharePoint folder trigger via Logic App if finance prefers SharePoint.

### Phase 10: CI/CD Pipeline

| Step | What to Build | Effort |
|------|--------------|--------|
| 10.1 | Azure DevOps service connection with Owner/UAA | 30 min |
| 10.2 | Pipeline YAML (already exists: `pipelines/azure-pipelines.yml`) | Ready |
| 10.3 | Environment gates: dev (auto), staging (manual), prod (approval) | 1 hour |
| 10.4 | Function code publish stage (zip deploy in pipeline) | 1 hour |
| 10.5 | Cosmos DB seed stage (optional, for new environments) | 30 min |

### Phase 11: Multi-Subscription Rollout

| Step | What to Build | Effort |
|------|--------------|--------|
| 11.1 | Create `parameters/sub-{name}.bicepparam` per subscription | 15 min each |
| 11.2 | Pipeline parameter matrix for multi-sub deployment | 2 hours |
| 11.3 | Cost export per subscription → shared blob container | 30 min each |
| 11.4 | Function App handles multi-sub CSVs (already coded — partition key = subscriptionId) | Ready |
| 11.5 | Dashboard aggregates all subscriptions (Cosmos DB queries work cross-partition) | Ready |

### Phase 12: Quarterly Automation

| Step | What to Build | Effort |
|------|--------------|--------|
| 12.1 | Timer-triggered Function for quarterly budget recalculation | 2 hours |
| 12.2 | Reads last 3 months of amortized data from Cosmos DB history | Built into engine |
| 12.3 | Updates technicalBudget if drift > 30% | Already in `Invoke-QuarterlyRecalc.ps1` logic |
| 12.4 | Sends summary report to FinOps team | 1 hour |

### Phase 13: Self-Service Budget Change — Teams & Power Apps UI

**Current:** Budget changes via Logic App HTTP trigger with JSON payload (Azure Portal or API call).  
**Target:** End users change budgets through Teams or Power Apps — no Azure Portal access needed.

| Step | What to Build | Effort | Prerequisites |
|------|--------------|--------|---------------|
| 13.1 | **Teams Adaptive Card** — form with RG dropdown, budget amount slider, reason text field | 2 hours | Teams bot registration or Power Automate |
| 13.2 | **Power Automate flow** — receives card submission, calls `la-finops-budget-change` HTTP trigger | 1 hour | Power Automate premium (HTTP connector) |
| 13.3 | **Result card** — posts success/failure back to Teams channel with old vs new budget | 1 hour | — |
| 13.4 | **OR: Power Apps canvas app** — form reads current budget from Cosmos DB, submits change to Logic App, shows confirmation | 4 hours | Power Apps license, Cosmos DB connector |
| 13.5 | **RG dropdown populated from Cosmos DB** — user picks from their owned RGs only (filtered by email = Owner tag) | 2 hours | Cosmos DB connector in Power Apps or Power Automate |

**Architecture:**
```
Teams Adaptive Card / Power Apps Form
  → Power Automate (HTTP action)
  → la-finops-budget-change (existing Logic App)
  → Owner validation (Get_RG_Tags → Validate_Owner)
  → Update Azure Budget + Cosmos DB
  → Teams notification
```

**Why this works:** The Logic App already has full validation (owner check, EUR 100 floor, 3x cap), Teams notification, and budget update logic. The frontend (Teams card or Power Apps) is just a friendly UI wrapper — zero backend changes needed.

**Recommended: Teams Adaptive Card** — lower effort, no extra licensing, meets users where they already work. Power Apps is better if your organization wants a richer self-service portal with budget history and approval workflows.

### Phase 14: Private Endpoints & Network Security

**Current:** Function App and Cosmos DB are on public endpoints (auth via function key / account key).  
**Target:** All data-plane traffic over private endpoints within VNet.

| Step | What to Build | Effort |
|------|--------------|--------|
| 14.1 | VNet + subnet for Function App VNet integration | 1 hour |
| 14.2 | Private endpoint for Cosmos DB | 1 hour |
| 14.3 | Private endpoint for Storage Account | 1 hour |
| 14.4 | Update Function App to use VNet integration | 30 min |
| 14.5 | Disable public access on Cosmos DB + Storage | 30 min |
| 14.6 | Update Power BI to use on-premises data gateway for Cosmos DB | 2 hours |

---

### Phase 15: Budget Alert Notification Framework (Implemented)

**Status:** Code deployed, live in production.

The notification framework replaces static thresholds with dynamic tiered alerting based on 3-month average spend.

| Step | What Was Built | Status |
|------|---------------|--------|
| 15.1 | `SPEND_TIERS` definition — 4 brackets ($0-1K, $1K-5K, $5K-10K, $10K+) with HeadUp/Warning/Critical thresholds | Done |
| 15.2 | `_classify_spend_tier(budget)` — classifies each RG into a tier | Done |
| 15.3 | `_read_rg_tags(sub, rg)` — reads Owner, TechnicalContact1/2, BillingContact, BillingElement from ARM API | Done |
| 15.4 | Tag-based `_dispatch()` — routes alerts by severity (HeadUp → Owner+TC1+TC2, Warning → +BillingContact, Critical → +Governance) | Done |
| 15.5 | Governance alert — immediate notification when `BillingElement` matches a flagged value | Done |
| 15.6 | New Cosmos DB fields: `spendTier`, `technicalContact1`, `technicalContact2`, `billingContact`, `billingElement` | Done |
| 15.7 | LAW sync updated with new fields | Done |

**CI/CD requirement:** Deploy via `func azure functionapp publish <app-name> --python` (remote build). Do NOT use `az functionapp deployment source config-zip` or Kudu zipdeploy — they don't work reliably for Python Linux Consumption plans.

---

### Phase 16: Real Data Pipeline (Implemented)

**Status:** Live — real amortized cost data flowing end-to-end.

| Step | What Was Done | Status |
|------|--------------|--------|
| 16.1 | Cost Management Export `finops-daily-amortized` verified Active — daily AmortizedCost CSV to `amortized-cost-exports/` blob container | Done |
| 16.2 | Fixed CSV column name mismatch — export uses `resourceGroupName` (camelCase), code was reading `ResourceGroupName` (PascalCase). Same for `costInBillingCurrency` | Done |
| 16.3 | Cleaned Cosmos DB — removed 67 demo documents, seeded 32 real RGs from cost export | Done |
| 16.4 | Ran backfill — 58 RGs already had native Azure budgets, 1 new budget created | Done |
| 16.5 | Evaluation produces real metrics — example RG at EUR 326 (326% of EUR 100 budget = `over_budget`) | Done |
| 16.6 | LAW sync from HTTP evaluate endpoint — added `_sync_inventory_to_law()` call to `/api/evaluate` | Done |

**CI/CD requirement:** The `seed_real.py` script (seeding from CSV) is a one-time operation. Daily operations are fully automated via the timer trigger at 06:00 UTC.

**Important:** The Function App reads the **latest single CSV** by `last_modified` date. RGs with zero spend in the current month won't appear until they have cost data.

---

### Phase 17: Azure Workbook Dashboard (Implemented)

**Status:** Live — `FinOps Budget & Cost Governance` workbook deployed.

**Architecture:** Cosmos DB → Function App (`_sync_inventory_to_law()`) → Log Analytics (`FinOpsInventory_CL` table) → Workbook KQL queries.

Do NOT use `externaldata` to call Function App API directly from workbooks — it causes tile escaping issues, API key exposure, and cold start delays.

| Step | What Was Built | Status |
|------|---------------|--------|
| 17.1 | Budget Compliance summary (table) | Done |
| 17.2 | Budget Totals EUR (table) | Done |
| 17.3 | Compliance Breakdown (pie chart — green/pink) | Done |
| 17.4 | Top 15 RGs by Spend (bar chart) | Done |
| 17.5 | Full Inventory Detail (table with green-red heatmap color bars + status icons) | Done |
| 17.6 | Azure Native Budgets (Azure Resource Graph query — actual cost safety net) | Done |
| 17.7 | FinOps Platform Components (Azure Resource Graph — resource health) | Done |

**Source of truth for workbook definition:** `scripts/Deploy-Workbook.py` → generates JSON → deploys via `az rest --method PUT`.

**CI/CD requirement:** Workbook deployment goes through `Deploy-Workbook.py` script. Pipeline step:
```yaml
- script: |
    python scripts/Deploy-Workbook.py \
      --subscription-id $(subscriptionId) \
      --resource-group $(resourceGroup) \
      --workbook-id $(workbookGuid)
  displayName: 'Deploy Workbook'
```

**Known issue:** Finance vs Technical Variance by Business Unit shows empty until `costCenter` tags are set on RGs or finance CSV is uploaded.

---

### Phase 18: Azure DevOps CI/CD (Planned)

**Prerequisites:** Project Administrator role in Azure DevOps (for repo creation, service connection, pipelines).

| Step | What to Build | Effort |
|------|--------------|--------|
| 18.1 | Create Git repository in Azure DevOps | 15 min |
| 18.2 | Push codebase (`code-base/budget-alerts-automation/`) to repo | 15 min |
| 18.3 | Create service connection (SPN) to the QA subscription | 30 min |
| 18.4 | Configure `azure-pipelines.yml` (already exists in `pipelines/`) | 30 min |
| 18.5 | Test pipeline: Validate → Deploy Dev → Deploy Function → Test → Deploy Prod | 1 hour |
| 18.6 | Add workbook deployment step to pipeline | 15 min |
| 18.7 | Add branch policies (PR required, build validation) | 15 min |

**Pipeline stages (from `pipelines/azure-pipelines.yml`):**
1. **Validate** — `az bicep build` + `az deployment sub what-if`
2. **Deploy Dev** — Bicep deployment + backfill (top 20)
3. **Deploy Function** — `func azure functionapp publish --python` (remote build)
4. **Test** — Pester verification tests
5. **Deploy Prod** — Manual approval gate, main branch only

**Deployment method for Function App:** Must use `func azure functionapp publish --python` with remote Oryx build. This is the ONLY reliable method for Python Linux Consumption plans. Kudu zipdeploy and `config-zip` produce 503 errors or stale code.

---

### Operational Notes (Lessons Learned)

**Function App Deployment:**
- Python Linux Consumption plan REQUIRES remote build via `func azure functionapp publish --python`
- `WEBSITE_RUN_FROM_PACKAGE=1` with local packages causes 503 — don't use it
- `az functionapp deployment source config-zip` creates blob URLs that can be corrupt (30 bytes)
- Kudu zipdeploy writes to a package location that the runtime doesn't read without RFP
- Always verify deployment: call `/api/inventory` and check for expected fields

**Cost Export CSV:**
- Column names are camelCase: `resourceGroupName`, `costInBillingCurrency`
- Code must try camelCase first, then PascalCase, then legacy names
- Export covers current month MTD — RGs with zero spend don't appear

**Log Analytics Sync:**
- Data Collector API (`_sync_inventory_to_law()`) returns HTTP 200 immediately but ingestion takes 5-20 minutes
- Custom log table: `FinOpsInventory_CL` with `_s` (string), `_d` (double), `_t` (datetime) suffixes
- Workbook queries must use `arg_max(TimeGenerated, *)` to dedup across daily syncs
- The `ResourceGroup` field (no suffix) is auto-mapped from the JSON key

**Workbook:**
- Use Log Analytics queries (`FinOpsInventory_CL`), NOT `externaldata` from Function App API
- Tiles visualization requires complex column mappings — use table visualization instead
- Deploy workbook via `Deploy-Workbook.py` (source of truth), not manual portal edits
- The `Deploy-Workbook.py` `--dry-run` flag outputs JSON without deploying (for review)

**Cosmos DB:**
- Backup before any deletions: `/api/inventory` → save JSON locally
- Serverless — no idle cost, scales automatically
- Partition key: `subscriptionId`
- Document ID format: `{subscriptionId}_{resourceGroupName}`

---

---

### Phase 19: Azure Monitor Alert Rules — Tiered Notification (Implemented)

**Status:** Live — 3 Scheduled Query Rules deployed, firing through Action Group.

**Architecture:**
```
Function App (06:00 UTC) → evaluates amortized cost → classifies complianceStatus per tier
    → syncs to LAW (FinOpsInventory_CL)
Azure Monitor Scheduled Query Rules (every 1 hour) → checks LAW for status changes
    → HeadUp / Warning / Critical rules fire independently
    → Action Group → emails to FinOps team
```

**Why this approach (not Function App _dispatch):**
- Action Groups are Azure-native — no webhook URLs, no API keys
- Alert rules run independently of Function App (no cold start dependency)
- Supports future expansion: add SMS, Teams channel, Logic App, ITSM connector to Action Group
- Alert history visible in Azure Monitor → Alerts blade
- No custom code needed for dispatch

| Alert Rule | Severity | Fires When | LAW Query |
|-----------|----------|-----------|-----------|
| `finops-alert-headup` | Sev 3 (Info) | `complianceStatus_s == 'at_risk'` | HeadUp threshold crossed |
| `finops-alert-warning` | Sev 2 (Warning) | `complianceStatus_s == 'warning'` | Warning threshold crossed |
| `finops-alert-critical` | Sev 1 (Error) | `complianceStatus_s == 'over_budget'` | Critical threshold crossed |

**How tiered thresholds work end-to-end:**

1. Function App reads the latest amortized cost export CSV
2. For each RG, calculates `actualPct` = amortizedMTD / technicalBudget × 100
3. Classifies `spendTier` based on budget amount ($0-1K, $1K-5K, $5K-10K, $10K+)
4. Looks up tier-specific thresholds (e.g. $0-1K: HeadUp=200%, Warning=250%, Critical=300%)
5. Sets `complianceStatus` = `at_risk` / `warning` / `over_budget` / `on_track`
6. Syncs to LAW
7. Azure Monitor queries LAW hourly, fires matching alert rule → Action Group → email

**Action Group:** `ag-finops-budget-alerts`

| Receiver | Email |
|----------|-------|
| finops-team | your-finops-team@example.com |
| finops-lead | your-finops-lead@example.com |

**Future: Per-RG recipient routing (Phase 20 — Planned)**

Currently all 3 alert rules fire through the same Action Group (same recipients). The technical guide's recipient escalation (HeadUp → Owner+TC1+TC2 only, Warning → +BillingContact, Critical → +Governance) requires per-RG Action Groups or a Logic App intermediary that reads the owner/contact tags and routes accordingly. Options:

| Option | How | Effort |
|--------|-----|--------|
| A. Logic App intermediary | Alert rule triggers Logic App → reads RG tags → sends email to matching contacts | 2 hours |
| B. Dynamic Action Groups | Create Action Groups per cost center/BU, assign to different alert rules | 3 hours |
| C. Function App email dispatch | Function App calls Microsoft Graph API to send email per recipient per severity | 4 hours |

**Recommendation:** Option A (Logic App intermediary) — the alert rule fires a Logic App instead of email, the Logic App queries Cosmos for owner/contact info and sends targeted emails.

---

---

### Phase 20: Power BI Dashboard from Cosmos DB (Planned)

**Status:** Planned — old semantic model needs recreation due to schema change.

**Why:** Not all stakeholders have Azure Portal access. Power BI provides a shareable, embeddable dashboard with the same data as the Workbook.

| Step | What to Do | Effort |
|------|-----------|--------|
| 20.1 | Delete old Power BI semantic model + report (schema changed) | 5 min |
| 20.2 | Create new semantic model from Cosmos DB (`finops/inventory` container) | 10 min |
| 20.3 | Build 4 visuals: compliance donut, budget total cards, inventory table, top-15 bar chart | 30 min |
| 20.4 | Set scheduled refresh (daily after 06:30 UTC) | 5 min |
| 20.5 | Share report with stakeholders | 5 min |

**Connection details:**
- Endpoint: `https://<YOUR_COSMOS_ACCOUNT>.documents.azure.com:443/`
- Database: `finops`, Container: `inventory`
- Auth: Account key (from Portal → Cosmos DB → Keys)

---

### Code Audit Results (April 8, 2026)

| # | Severity | Issue | Status |
|---|----------|-------|--------|
| 1 | 🔴 Fixed | `complianceStatus: "Within Budget"` in `/api/update-budget` → changed to `"not_evaluated"` | Fixed |
| 2 | 🔴 Open | Function App host key hardcoded in `Deploy-Workbook.py` — must be parameterized or rotated | Open |
| 3 | 🟡 Open | `functionAppName` + `functionAppKey` not passed to `logic-app-budget-change` module in `main.bicep` | Open |
| 4 | 🟡 Open | No Cosmos client caching — creates new `CosmosClient` per call | Open |
| 5 | 🟡 Open | No RG tag caching — creates new `DefaultAzureCredential` per RG per evaluation | Open |
| 6 | 🟡 Open | Pipeline subscription ID hardcoded — must be parameterized | Open |
| 7 | 🟡 Open | Pipeline Test stage depends on `DeployDev`, should depend on `DeployFunction` | Open |
| 8 | 🟡 Open | `Seed-CosmosDemo.ps1` writes to production container — add safeguard or separate database | Open |
| 9 | 🟢 Open | `requirements.txt` has no version pinning | Open |
| 10 | 🟢 Open | `infra/modules/workbook.json` is orphaned (not referenced by main.bicep) | Open |

**Amortized cost logic verification:** ✅ Confirmed correct.
- Export type is `AmortizedCost` (not ActualCost)
- CSV reads camelCase columns first (`resourceGroupName`, `costInBillingCurrency`)
- Blob path `amortized/` matches export root folder
- Spend tier classification, threshold matrix, and compliance status logic all verified correct

---

*Azure Amortized Cost Management — Deployment Guide. Updated April 8, 2026 with Phases 15-20, code audit results, and operational lessons learned.*
