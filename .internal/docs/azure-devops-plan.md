# Azure DevOps CI/CD Plan — FinOps Budget Alert Automation

> **Purpose:** Make the FinOps platform deployable via a single pipeline run to any target subscription.
> **Current state:** Deployed manually via terminal commands, scripts, and REST API calls.
> **Target state:** Git push → pipeline → validated → deployed → tested → live.

---

## Phase 0: Code Preparation for DevOps (Completed April 8, 2026)

All items below have been completed to make the codebase DevOps-ready.

| # | Item | What was done | Status |
|---|------|--------------|--------|
| 1 | **Remove hardcoded Function App key** | Replaced function key (rotated) in `Deploy-Workbook.py` with `FUNCTION_KEY_PLACEHOLDER` | ✅ Done |
| 2 | **Remove hardcoded key from powerbi/README.md** | Replaced with `<FUNCTION_APP_KEY>` placeholder | ✅ Done |
| 3 | **Fix pipeline YAML** | Replaced hardcoded sub ID with variable group `finops-config`, fixed `AzureFunctionApp@2` to `func publish --python`, fixed location `eastus2` → `eastus`, fixed Test stage dependency | ✅ Done |
| 4 | **Create .gitignore** | Excludes `local.settings.json`, `.env`, `.python_packages/`, `__pycache__/`, `*.zip`, `.vscode/` | ✅ Done |
| 5 | **Move demo script** | `Seed-CosmosDemo.ps1` moved from `scripts/` to `tests/` (prevents accidental production data overwrite) | ✅ Done |
| 6 | **Fix function_app.py docstring** | Changed "Central Table Storage" to "Cosmos DB" in module docstring | ✅ Done |
| 7 | **Pin requirements.txt** | All packages pinned to specific versions (azure-functions==1.24.0, azure-cosmos==4.15.0, etc.) | ✅ Done |
| 8 | **Security scan** | Full codebase scanned for hardcoded keys/secrets — all removed or replaced with placeholders | ✅ Done |

### Remaining items for DevOps onboarding (not code changes):

| # | Item | Who | When |
|---|------|-----|------|
| 1 | Request Project Administrator role in Azure DevOps | Platform team → DevOps team | Before repo creation |
| 2 | Create SPN with 4 RBAC roles | Platform team | During setup |
| 3 | Create variable group `finops-config` in Azure DevOps | Platform team | During setup |
| 4 | Configure environment approval gates | Platform team + FinOps lead | During setup |
| 5 | Pass `functionAppName` and `functionAppKey` to `logic-app-budget-change` in `main.bicep` | Platform team | Before first pipeline run |
| 6 | Rotate the Function App key (since old one was in git history) | Platform team | After first DevOps deploy |

---

---

## Phase 0b: Scale Preparation for 300 Subscriptions (Completed)

### Naming Convention

All resource names follow a deterministic pattern — no manual naming:

| Resource | Name Pattern | Example (QA) |
|----------|-------------|--------------|
| Resource Group | `rg-finops-budget-{env}` | `rg-finops-budget-qa` |
| Function App | `func-finops-{uniqueString(rg.id)}` | `<YOUR_FUNCTION_APP>` |
| Cosmos DB | `cosmos-finops-{uniqueString(rg.id)}` | `<YOUR_COSMOS_ACCOUNT>` |
| Storage | `safinops{uniqueString(rg.id)}` | `<YOUR_STORAGE_ACCOUNT>` |
| LAW | `law-finops-{env}` | `law-finops-budget` |
| Action Group | `ag-finops-budget-alerts` | Same per sub |
| Logic Apps | `la-finops-{function}` | `la-finops-auto-budget` |
| Alert Rules | `finops-alert-{severity}` | `finops-alert-critical` |
| Workbook | `FinOps Budget & Cost Governance` | Same per sub |
| Cost Export | `finops-daily-amortized` | Same per sub |
| Policy | `finops-audit-rg-without-budget` | Same per sub |

`uniqueString(rg.id)` ensures globally unique names per subscription without manual input.

### What Was Fixed for Scale

| # | Item | What was done |
|---|------|--------------|
| 1 | **main.bicep** — added `functionAppKey` param | Budget-change Logic App now receives Function App key for Cosmos sync |
| 2 | **template.bicepparam** — created | Reusable parameter template for new subscriptions (copy + rename) |
| 3 | **Pipeline uses variable groups** | No hardcoded subscription IDs — all from `finops-config` variable group |
| 4 | **Per-subscription isolation** | Each sub gets its own RG with full stack (Function, Cosmos, LAW, Logic Apps) |

### How to Onboard a New Subscription

```bash
# 1. Copy the template
cp parameters/template.bicepparam parameters/prod-newsubname.bicepparam

# 2. Edit: set environment, location, finopsEmail, subscriptionBudgetAmount

# 3. Add to pipeline matrix (azure-pipelines.yml):
#    NewSubName:
#      subscriptionId: 'xxxxxxxx-...'
#      paramFile: 'parameters/prod-newsubname.bicepparam'
#      environment: 'finops-prod'

# 4. Push to dev branch → pipeline deploys automatically
git add . && git commit -m "Add NewSubName subscription" && git push
```

**Time to onboard a new subscription: ~5 minutes** (copy template, edit 3 values, push).

### 300-Subscription Deployment Strategy

| Approach | How | Timeline |
|----------|-----|----------|
| **Wave 1 (5 subs)** | QA + 4 pilot subscriptions | Week 1 |
| **Wave 2 (20 subs)** | High-spend production subs | Week 2-3 |
| **Wave 3 (100 subs)** | All HC subscriptions | Week 4-6 |
| **Wave 4 (175 subs)** | Additional business units | Week 7-10 |
| **Wave 5 (remaining)** | Remaining regions + edge cases | Week 11-12 |

Each wave uses the same pipeline with a growing parameter matrix. Failures in one subscription don't block others (matrix parallelism).

---

## Phase 1: Repository Setup

### 1.1 Request Access

Ask your DevOps team for **Project Administrator** role. This covers repo creation, service connections, and pipeline setup.

> "Hi, could you please assign me the Project Administrator role in Azure DevOps for our FinOps project? I need to create a Git repository, set up a service connection to the Azure subscription, and configure CI/CD pipelines with approval gates."

### 1.2 Create Repository

```
Organization: (Your Azure DevOps org)
Project:      FinOps-Governance (or existing project)
Repository:   finops-budget-alerts
```

### 1.3 Push Codebase

```bash
cd code-base/budget-alerts-automation
git init
git remote add origin https://dev.azure.com/{org}/{project}/_git/finops-budget-alerts
git add .
git commit -m "Initial commit — FinOps Budget Alert Automation MVP"
git push -u origin main
git checkout -b dev
git push -u origin dev
```

### 1.4 Repository Structure (what gets pushed)

```
finops-budget-alerts/
├── functions/
│   └── amortized-budget-engine/
│       ├── function_app.py          # 9 endpoints, 855 lines
│       ├── host.json
│       └── requirements.txt
├── infra/
│   ├── main.bicep                   # 9 modules, subscription-scoped
│   └── modules/
│       ├── action-group.bicep
│       ├── cosmos-db.bicep
│       ├── event-grid.bicep
│       ├── function-app.bicep
│       ├── logic-app-auto-budget.bicep
│       ├── logic-app-backfill.bicep
│       ├── logic-app-budget-change.bicep
│       ├── policy-definition.bicep
│       ├── storage-account.bicep
│       └── subscription-budget.bicep
├── parameters/
│   ├── dev.bicepparam
│   ├── staging.bicepparam
│   └── prod.bicepparam
├── pipelines/
│   └── azure-pipelines.yml
├── scripts/
│   ├── Deploy-Workbook.py
│   ├── Enable-AdminFeatures.ps1
│   ├── Initialize-BudgetTable.ps1
│   ├── Invoke-BudgetBackfill.ps1
│   ├── Invoke-QuarterlyRecalc.ps1
│   ├── New-AmortizedExport.ps1
│   └── config.json
├── tests/
│   ├── function/
│   └── infra/
│       └── Validate-Deployment.Tests.ps1
├── queries/
│   ├── budget-compliance.kql
│   └── spend-vs-budget.sql
└── docs/
    ├── technical-guide.md
    ├── mvp-implementation.md
    ├── cost-forecast.md
    └── iteration_01.md
```

### 1.5 Files to EXCLUDE (add to .gitignore)

```gitignore
# Secrets — NEVER commit
**/local.settings.json
**/*.env
C:\temp\

# Build artifacts
**/.python_packages/
**/__pycache__/
*.pyc
*.zip

# Orphaned files (not used in pipeline)
infra/modules/workbook.json
scripts/Seed-CosmosDemo.ps1
```

### 1.6 Security Pre-Flight

Before pushing to the repo, fix these:

| # | Action | File | What to do |
|---|--------|------|-----------|
| 1 | **Rotate Function App key** | `scripts/Deploy-Workbook.py` L25 | Function key is hardcoded. Replace with `--function-key` CLI parameter |
| 2 | **Remove hardcoded sub ID** | `pipelines/azure-pipelines.yml` L35 | Replace hardcoded subscription ID with pipeline variable `$(subscriptionId)` |
| 3 | **Remove demo script** | `scripts/Seed-CosmosDemo.ps1` | Writes fake data to production Cosmos. Delete or move to `tests/` |

---

## Phase 2: Service Connection

### 2.1 Create Service Principal

```bash
az ad sp create-for-rbac \
  --name "sp-finops-cicd" \
  --role Contributor \
  --scopes /subscriptions/<YOUR_SUBSCRIPTION_ID> \
  --sdk-auth
```

### 2.2 Additional RBAC for the SPN

The SPN needs more than Contributor:

| Role | Scope | Why |
|------|-------|-----|
| **Contributor** | Subscription | Deploy resources |
| **User Access Administrator** | Subscription | Assign RBAC to managed identities |
| **Cost Management Contributor** | Subscription | Create budgets + cost exports |
| **Monitoring Contributor** | Resource Group | Create alert rules + action groups |

### 2.3 Register in Azure DevOps

Project Settings → Service connections → New → Azure Resource Manager → Service principal (manual)
- Name: `finops-service-connection`
- Subscription ID: `<YOUR_SUBSCRIPTION_ID>`
- Paste SPN credentials

---

## Phase 3: Pipeline Configuration

### 3.1 Fix the Existing Pipeline

The current `azure-pipelines.yml` needs these changes:

| # | Current | Fix |
|---|---------|-----|
| 1 | Hardcoded `subscriptionId` value | Use variable group: `$(subscriptionId)` |
| 2 | `location: 'eastus2'` in validate | Match actual: `'eastus'` |
| 3 | Test stage depends on `DeployDev` | Should depend on `DeployFunction` |
| 4 | `AzureFunctionApp@2` task for deployment | Change to `func azure functionapp publish --python` (only reliable method) |
| 5 | No workbook deployment step | Add `Deploy-Workbook.py` step |
| 6 | No alert rules deployment step | Add alert rules creation step |
| 7 | No cost export creation step | Add `New-AmortizedExport.ps1` step |
| 8 | No Cosmos seeding step | Add `Initialize-BudgetTable.ps1` for fresh deploys |

### 3.2 Variable Groups

Create a variable group `finops-config` in Azure DevOps:

| Variable | Value | Secret? |
|----------|-------|---------|
| `subscriptionId` | `<YOUR_SUBSCRIPTION_ID>` | No |
| `resourceGroupName` | `rg-finops-budget-mvp` | No |
| `location` | `eastus` | No |
| `functionAppName` | (set after first deploy) | No |
| `cosmosAccountName` | (set after first deploy) | No |
| `storageAccountName` | (set after first deploy) | No |
| `lawWorkspaceId` | (set after first deploy) | No |
| `lawSharedKey` | (set after first deploy) | Yes |
| `cosmosKey` | (set after first deploy) | Yes |
| `functionAppKey` | (set after first deploy) | Yes |
| `finopsEmail` | `your-finops-team@example.com` | No |
| `approverEmail` | `finops-lead@example.com` | No |

### 3.3 Target Pipeline Stages (7 stages)

```
┌─────────────┐
│  1. Validate │  Bicep lint + What-If preview
└──────┬──────┘
       │
┌──────▼──────┐
│  2. Infra   │  Deploy Bicep (RG, Storage, Cosmos, LAW, Logic Apps, Event Grid, Policy, Budget)
└──────┬──────┘
       │
┌──────▼──────┐
│  3. Config  │  Set Function App settings, create Cost Export, RBAC assignments
└──────┬──────┘
       │
┌──────▼──────┐
│  4. Function│  func azure functionapp publish --python (remote build)
└──────┬──────┘
       │
┌──────▼──────┐
│  5. Post    │  Workbook deploy, Alert Rules deploy, Backfill (seed Cosmos), LAW sync
└──────┬──────┘
       │
┌──────▼──────┐
│  6. Test    │  Pester: verify resources, hit /api/inventory, check Cosmos count
└──────┬──────┘
       │
┌──────▼──────┐
│  7. Prod    │  Manual approval → deploy to production subscription
└─────────────┘
```

### 3.4 Stage Details

**Stage 1: Validate**
```yaml
- az bicep build --file infra/main.bicep
- az deployment sub what-if --template-file infra/main.bicep --parameters parameters/dev.bicepparam
```
Quality gate: Bicep must compile, What-If must show no destructive changes.

**Stage 2: Deploy Infrastructure**
```yaml
- az deployment sub create --template-file infra/main.bicep --parameters parameters/dev.bicepparam
```
Creates: RG, Storage, Cosmos, LAW, 3 Logic Apps, Event Grid, Action Group, Policy, Budget.

**Stage 3: Configure**
```yaml
- Enable-AdminFeatures.ps1   # RBAC for Function MI + Logic App MIs
- New-AmortizedExport.ps1     # Create daily AmortizedCost export
- Set Function App settings:  COSMOS_ENDPOINT, COSMOS_KEY, STORAGE_ACCOUNT_NAME,
                               LAW_WORKSPACE_ID, LAW_SHARED_KEY, FINOPS_EMAIL,
                               GOVERNANCE_EMAIL, ACTION_GROUP_ID, SUBSCRIPTION_ID
```
Quality gate: All settings verified non-empty.

**Stage 4: Deploy Function App**
```yaml
- cd functions/amortized-budget-engine
- func azure functionapp publish $(functionAppName) --python
```
**CRITICAL:** Must use `func publish --python` with remote Oryx build. Do NOT use `AzureFunctionApp@2` task or `az functionapp deployment source config-zip` — they produce 503 errors on Python Linux Consumption plans.

```yaml
- task: AzureCLI@2
  displayName: 'Deploy Function App (Remote Build)'
  inputs:
    azureSubscription: $(azureServiceConnection)
    scriptType: bash
    scriptLocation: inlineScript
    inlineScript: |
      npm install -g azure-functions-core-tools@4 --unsafe-perm true
      cd $(workingDirectory)/functions/amortized-budget-engine
      func azure functionapp publish $(functionAppName) --python
```

Quality gate: `/api/inventory` returns HTTP 200.

**Stage 5: Post-Deployment**
```yaml
# Deploy Workbook
- python scripts/Deploy-Workbook.py --subscription-id $(subscriptionId) --resource-group $(resourceGroupName) --workbook-id $(workbookGuid)

# Create 3 Alert Rules
- az rest --method PUT ... finops-alert-headup
- az rest --method PUT ... finops-alert-warning
- az rest --method PUT ... finops-alert-critical

# Backfill existing RGs (seed Cosmos from subscription)
- curl /api/backfill?subscriptionId=$(subscriptionId)&dryRun=false

# Trigger first evaluation + LAW sync
- curl /api/evaluate
```

**Stage 6: Test**
```yaml
# Verify Function App responds
- curl /api/inventory → HTTP 200, JSON array, count > 0

# Verify Cosmos has documents
- az cosmosdb sql query --query "SELECT VALUE COUNT(1) FROM c" → > 0

# Verify LAW has data (may need 15 min delay)
- az monitor log-analytics query --analytics-query "FinOpsInventory_CL | count"

# Verify Alert Rules exist
- az rest --method GET .../scheduledQueryRules → 3 rules

# Verify Action Group
- az monitor action-group show → 2 email receivers
```

**Stage 7: Deploy Production**
- Requires manual approval (Azure DevOps environment approval gate)
- Uses `parameters/prod.bicepparam`
- Same stages 2-6 but with production parameters
- Approvers: Designated FinOps lead(s)

---

## Phase 4: Quality Gates & Safety

### 4.1 Branch Policies

| Policy | Setting |
|--------|---------|
| Require PR for `main` | Yes — no direct pushes |
| Minimum 1 reviewer | Yes |
| Build validation | Pipeline must pass on PR |
| Comment resolution | All comments must be resolved |
| Linked work items | Optional but recommended |

### 4.2 Environment Approvals

| Environment | Approval |
|-------------|----------|
| `finops-dev` | Auto-deploy on `dev` branch push |
| `finops-staging` | 1 approver (platform team) |
| `finops-prod` | 2 approvers (FinOps lead + platform team) |

### 4.3 What-If Preview

Every deployment runs `az deployment sub what-if` first. If the diff shows:
- **Delete** of any existing resource → pipeline FAILS (manual review required)
- **Modify** of secrets/keys → pipeline WARNS
- **Create** of new resources → pipeline PROCEEDS

### 4.4 Rollback Plan

| Scenario | Action |
|----------|--------|
| Function App broken | Redeploy previous git commit: `func publish` from that commit |
| Cosmos data corrupted | Restore from backup: `C:\temp\cosmos-backup-*.json` (or periodic backup in Cosmos) |
| Wrong budgets created | Run backfill with `dryRun=true` first, verify, then `dryRun=false` |
| Alert rules misconfigured | Delete + recreate via pipeline (idempotent PUT) |
| Workbook broken | Re-run `Deploy-Workbook.py` from git (source of truth) |

---

## Phase 5: Multi-Subscription Deployment

### 5.1 Parameter Matrix

Each subscription gets its own parameter file:

```
parameters/
├── qa.bicepparam        # your-qa-subscription (current MVP)
├── staging.bicepparam   # your-staging-subscription
├── prod-hc.bicepparam   # Primary production
├── prod-main.bicepparam # Main production
├── prod-bu2.bicepparam  # Additional business unit
└── prod-regional.bicepparam # Regional deployment
```

### 5.2 Pipeline Matrix Strategy

```yaml
strategy:
  matrix:
    QA:
      subscriptionId: '<YOUR_SUBSCRIPTION_ID>'
      paramFile: 'parameters/qa.bicepparam'
      environment: 'finops-qa'
    Staging:
      subscriptionId: 'xxxxxxxx-...'
      paramFile: 'parameters/staging.bicepparam'
      environment: 'finops-staging'
    ProdHC:
      subscriptionId: 'yyyyyyyy-...'
      paramFile: 'parameters/prod-hc.bicepparam'
      environment: 'finops-prod'
```

### 5.3 Per-Subscription Resources (created by pipeline)

Each subscription gets:
- `rg-finops-budget-{env}` (resource group)
- Function App + Cosmos DB + Storage + LAW (full stack)
- 3 Logic Apps + Event Grid + Action Group
- 3 Alert Rules + Workbook
- Cost Export + Policy + Subscription Budget

---

## Phase 6: Operational Runbook

### 6.1 Day-2 Operations (automated)

| What | When | How |
|------|------|-----|
| Cost export | Daily ~03:00 UTC | Azure Cost Management (auto) |
| Evaluation + LAW sync | Daily 06:00 UTC | Function App timer trigger |
| Backfill safety net | Daily 07:30 UTC | Logic App timer |
| Alert rule check | Hourly | Azure Monitor Scheduled Query Rules |
| Quarterly recalc | 1st of Jan/Apr/Jul/Oct | Function App timer trigger |

### 6.2 Day-2 Operations (manual/on-demand)

| What | How |
|------|-----|
| Force evaluation | `GET /api/evaluate` |
| Check inventory | `GET /api/inventory` |
| Add finance budgets | Drop CSV in `finance-budgets/` blob container |
| Change a budget | `POST` to `la-finops-budget-change` HTTP trigger |
| Redeploy Function | `git push` → pipeline runs automatically |
| Update Workbook | Edit `Deploy-Workbook.py` → `git push` → pipeline deploys |

### 6.3 Monitoring the Platform Itself

| What to monitor | Where |
|----------------|-------|
| Function App execution | Portal → Function App → Monitor |
| Alert rule firing | Portal → Monitor → Alerts |
| LAW ingestion | Portal → LAW → Usage and estimated costs |
| Cosmos DB RU usage | Portal → Cosmos DB → Metrics → Total Request Units |
| Pipeline runs | Azure DevOps → Pipelines → Runs |

---

## Checklist: Ready to Push

| # | Item | Status |
|---|------|--------|
| 1 | Function App key removed from `Deploy-Workbook.py` | ⬜ |
| 2 | Pipeline `subscriptionId` parameterized (not hardcoded) | ⬜ |
| 3 | `Seed-CosmosDemo.ps1` deleted or moved to `tests/` | ⬜ |
| 4 | `.gitignore` excludes secrets, build artifacts, temp files | ⬜ |
| 5 | `local.settings.json` excluded from repo | ⬜ |
| 6 | Service connection created in Azure DevOps | ⬜ |
| 7 | Variable group `finops-config` created with secrets | ⬜ |
| 8 | Branch policies enabled on `main` | ⬜ |
| 9 | Environment approval gates configured | ⬜ |
| 10 | Pipeline YAML updated with all 7 stages | ⬜ |
| 11 | Pipeline tested with `dev` branch first | ⬜ |
| 12 | Function App deploy uses `func publish --python` (not AzureFunctionApp@2) | ⬜ |

---

*Azure Amortized Cost Management — CI/CD Guide*
