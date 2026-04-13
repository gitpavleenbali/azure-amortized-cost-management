# CI/CD Deployment Guide (Option 2)

> For teams deploying to **production or security-restricted environments** where you need full control over the deployment pipeline, security policies, and code lifecycle.

---

## When to Use This Guide

| Scenario | Use |
|----------|-----|
| Quick evaluation / dev / MVP | **Option 1** — [Deploy to Azure](../README.md#option-a-one-click-deploy-recommended) button |
| Production / enterprise / restricted subscriptions | **Option 2** — This guide |
| Subscription has `allowSharedKeyAccess` deny policy | **Option 2** — This guide |
| You need approval gates, staging slots, or custom pipelines | **Option 2** — This guide |

---

## Architecture: Two-Phase Deployment

The platform separates **infrastructure** from **application code** — a standard Microsoft best practice:

```
Phase 1: Infrastructure (Bicep)          Phase 2: Code (CI/CD)
┌──────────────────────────┐             ┌──────────────────────────┐
│ az deployment sub create │             │ Upload zip → blob storage│
│  ↳ Resource Group        │             │ Set WEBSITE_RUN_FROM_    │
│  ↳ Storage Account       │    then     │   PACKAGE → blob URL     │
│  ↳ Function App (empty)  │ ─────────►  │ Restart Function App     │
│  ↳ Cosmos DB             │             │ Trigger backfill/evaluate│
│  ↳ Log Analytics + more  │             │ 9 functions load ✓       │
└──────────────────────────┘             └──────────────────────────┘
```

---

## Step 1: Clone and Configure

```bash
# Clone or use template
git clone https://github.com/gitpavleenbali/azure-amortized-cost-management.git
cd azure-amortized-cost-management

# Create your environment parameters
cp parameters/template.bicepparam parameters/prod.bicepparam
# Edit: finopsEmail, location, subscriptionBudgetAmount, costTrackingScope
```

## Step 2: Deploy Infrastructure

```bash
az deployment sub create \
  --location westus2 \
  --template-file infra/main.bicep \
  --parameters parameters/prod.bicepparam
```

All resources deploy in ~5 minutes: Function App (empty), Cosmos DB, Storage, Log Analytics, Logic Apps, Alert Rules, Workbook, Budget, Policy.

## Step 3: Deploy Function App Code

### Option A: Azure Portal — Deployment Center (Recommended for GitHub)

1. Open your Function App in the Azure Portal
2. Go to **Deployment** → **Deployment Center**
3. Select **Source**: GitHub
4. Authenticate with your GitHub account
5. Select your **Organization**, **Repository**, and **Branch** (main)
6. Azure auto-creates a GitHub Actions workflow that deploys on every push
7. Save — first deployment triggers automatically

### Option B: GitHub Actions Workflow (Included)

The repository includes a ready-to-use workflow at `.github/workflows/deploy-function.yml` that:
- Triggers automatically after CI passes on `main` branch, or manually via `workflow_dispatch`
- Builds the zip with Linux-compatible dependencies on `ubuntu-latest`
- Uploads the zip to your storage account's `function-releases` container via MI auth
- Sets `WEBSITE_RUN_FROM_PACKAGE` to the blob URL
- Restarts the Function App and verifies 9 functions loaded
- Triggers the initial backfill + evaluate pipeline

**Setup**: Set the `AZURE_CREDENTIALS` secret on your GitHub repo (service principal with Contributor + Storage Blob Data Contributor on the resource group). Then either push to `main` or trigger the workflow manually with your resource group name.\n\nSee the full workflow: [`.github/workflows/deploy-function.yml`](../.github/workflows/deploy-function.yml)

```yaml
name: Deploy Function App Code

on:
  push:
    branches: [main]
    paths: ['functions/**']
  workflow_dispatch:

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Setup Python
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install dependencies (Linux)
        run: |
          cd functions/amortized-budget-engine
          pip install -r requirements.txt --target .python_packages/lib/site-packages

      - name: Build zip package
        run: |
          cd functions/amortized-budget-engine
          zip -r ../../engine.zip function_app.py host.json requirements.txt .python_packages/

      - name: Upload to blob storage
        uses: azure/login@v2
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}
      - run: |
          RG="<your-resource-group>"
          SA=$(az storage account list -g $RG --query "[0].name" -o tsv)
          az storage container create --name function-releases --account-name $SA --auth-mode login || true
          az storage blob upload --container-name function-releases --name engine.zip \
            --file engine.zip --account-name $SA --auth-mode login --overwrite

      - name: Set package URL and restart
        run: |
          RG="<your-resource-group>"
          SA=$(az storage account list -g $RG --query "[0].name" -o tsv)
          FUNC=$(az functionapp list -g $RG --query "[0].name" -o tsv)
          BLOB_URL="https://${SA}.blob.core.windows.net/function-releases/engine.zip"
          az functionapp config appsettings set -g $RG -n $FUNC \
            --settings "WEBSITE_RUN_FROM_PACKAGE=$BLOB_URL" -o none
          az functionapp restart -g $RG -n $FUNC
```

### Option C: Azure DevOps Pipeline

```yaml
trigger:
  branches:
    include: [main]
  paths:
    include: ['functions/*']

pool:
  vmImage: ubuntu-latest

steps:
  - task: UsePythonVersion@0
    inputs:
      versionSpec: '3.11'

  - script: |
      cd functions/amortized-budget-engine
      pip install -r requirements.txt --target .python_packages/lib/site-packages
      zip -r $(Build.ArtifactStagingDirectory)/engine.zip function_app.py host.json requirements.txt .python_packages/
    displayName: Build Function App Package

  - task: AzureCLI@2
    inputs:
      azureSubscription: 'your-service-connection'
      scriptType: bash
      scriptLocation: inlineScript
      inlineScript: |
        RG="your-resource-group"
        SA=$(az storage account list -g $RG --query "[0].name" -o tsv)
        FUNC=$(az functionapp list -g $RG --query "[0].name" -o tsv)
        az storage container create --name function-releases --account-name $SA --auth-mode login || true
        az storage blob upload --container-name function-releases --name engine.zip \
          --file $(Build.ArtifactStagingDirectory)/engine.zip --account-name $SA --auth-mode login --overwrite
        BLOB_URL="https://${SA}.blob.core.windows.net/function-releases/engine.zip"
        az functionapp config appsettings set -g $RG -n $FUNC --settings "WEBSITE_RUN_FROM_PACKAGE=$BLOB_URL" -o none
        az functionapp restart -g $RG -n $FUNC
    displayName: Deploy to Blob and Restart
```

### Option D: Manual CLI Deploy

```bash
# Build the zip (do this on Linux/WSL for correct binaries)
cd functions/amortized-budget-engine
pip install -r requirements.txt --target .python_packages/lib/site-packages
zip -r ../../engine.zip function_app.py host.json requirements.txt .python_packages/
cd ../..

# Upload to storage and set package URL
RG="your-resource-group"
SA=$(az storage account list -g $RG --query "[0].name" -o tsv)
FUNC=$(az functionapp list -g $RG --query "[0].name" -o tsv)

az storage container create --name function-releases --account-name $SA --auth-mode login
az storage blob upload --container-name function-releases --name engine.zip \
  --file engine.zip --account-name $SA --auth-mode login --overwrite

BLOB_URL="https://${SA}.blob.core.windows.net/function-releases/engine.zip"
az functionapp config appsettings set -g $RG -n $FUNC \
  --settings "WEBSITE_RUN_FROM_PACKAGE=$BLOB_URL" -o none
az functionapp restart -g $RG -n $FUNC
```

## Step 4: Verify Functions Loaded

```bash
# Should show 9 functions
az functionapp function list -g $RG -n $FUNC --query "[].name" -o tsv
```

Expected output:
```
backfill_existing_rgs
evaluate_amortized_budgets
get_inventory
get_variance
ingest_finance_budget
manual_evaluate
manual_recalculate
quarterly_recalculate
update_budget
```

## Step 5: Initial Data Pipeline

After functions are loaded, trigger the initial data flow:

```bash
FUNC_KEY=$(az functionapp keys list -g $RG -n $FUNC --query "functionKeys.default" -o tsv)
HOST=$(az functionapp show -g $RG -n $FUNC --query "defaultHostName" -o tsv)

# 1. Backfill — scan all resource groups into Cosmos DB inventory
curl -s "https://$HOST/api/backfill?code=$FUNC_KEY"

# 2. Evaluate — process cost data, update compliance status
curl -s "https://$HOST/api/evaluate?code=$FUNC_KEY"

# 3. Open your Workbook in Azure Portal — data should appear within minutes
```

---

## Deployment Pattern: Why Blob URL + MI Auth?

This platform uses **WEBSITE_RUN_FROM_PACKAGE** with a blob URL and **managed identity authentication** — here's why this is the most stable approach:

| Approach | Result | Why |
|----------|--------|-----|
| GitHub raw URL as WEBSITE_RUN_FROM_PACKAGE | Functions never load | Azure Function host cannot reliably read from `raw.githubusercontent.com` |
| Connection string (AzureWebJobsStorage) | Blocked by policy | Enterprise subscriptions often have `allowSharedKeyAccess=false` via Azure Policy |
| config-zip with `--build-remote` | Works but fragile | Depends on Kudu SCM availability and network access |
| **Blob URL + MI auth** | **Stable** | Function App's managed identity reads the zip from its own storage account — no keys, no SAS, no external URLs |

### How It Works

```
Storage Account (MI auth)
  └── function-releases/
       └── engine.zip          ← CI/CD uploads here
            ↕ (MI reads)
Function App
  ├── AzureWebJobsStorage__accountName = <storage>  (MI-based)
  ├── WEBSITE_RUN_FROM_PACKAGE = https://<storage>.blob.core.windows.net/function-releases/engine.zip
  └── 9 functions loaded ✓
```

The Function App's system-assigned managed identity has **Storage Blob Data Owner** on the storage account. This grants it permission to read the zip package — no connection strings or SAS tokens needed.

---

## Troubleshooting

### Functions show 0/0 after deployment

**Root Cause**: RBAC not propagated or not scoped to storage account.

**Fix**:
```bash
# Check RBAC assignments on storage
FUNC_MI=$(az functionapp show -g $RG -n $FUNC --query "identity.principalId" -o tsv)
SA_ID=$(az storage account show -g $RG -n $SA --query "id" -o tsv)
az role assignment list --assignee $FUNC_MI --scope $SA_ID -o table

# Should have: Storage Blob Data Owner, Storage Queue Data Contributor,
#              Storage Table Data Contributor, Storage Account Contributor
# If missing, assign them:
az role assignment create --assignee $FUNC_MI --role "Storage Blob Data Owner" --scope $SA_ID
az role assignment create --assignee $FUNC_MI --role "Storage Queue Data Contributor" --scope $SA_ID
az role assignment create --assignee $FUNC_MI --role "Storage Table Data Contributor" --scope $SA_ID
az role assignment create --assignee $FUNC_MI --role "Storage Account Contributor" --scope $SA_ID

# Restart after RBAC propagation (~60 seconds)
az functionapp restart -g $RG -n $FUNC
```

### Post-deploy script fails (restricted subscriptions)

**Root Cause**: Azure Policy blocks `allowSharedKeyAccess` on all storage accounts, including the deployment script's auto-created storage.

**Fix**: Use CI/CD (this guide) instead of the Deploy to Azure button. The post-deploy script is designed for dev/MVP environments. For production environments with restrictive policies, deploy infrastructure first, then deploy code separately via your pipeline.

### Zip has wrong OS binaries

**Root Cause**: Python packages compiled on Windows contain `.pyd` files that don't work on Linux Function Apps.

**Fix**: Always build the zip on **Linux** (or GitHub Actions with `ubuntu-latest`):
```bash
# On Linux/WSL:
pip install -r requirements.txt --target .python_packages/lib/site-packages
# Verify: should have .so files, NOT .pyd files
find .python_packages -name "*.pyd" | wc -l   # Should be 0
find .python_packages -name "*.so" | wc -l    # Should be > 0
```

### Function App host shows "Error" state

**Root Cause**: `AuthorizationPermissionMismatch` — the managed identity can't access blob storage.

**Fix**: Ensure all 4 storage RBAC roles are assigned **scoped to the storage account** (not the resource group). Re-run the RBAC commands above.

### WEBSITE_RUN_FROM_PACKAGE blob URL returns 404

**Root Cause**: The `function-releases` container or `engine.zip` blob doesn't exist yet.

**Fix**: Upload the zip to blob storage (see Step 3 above). The container is auto-created during post-deploy or you can create it manually.

---

## Security Checklist for Production

- [ ] Function App uses **system-assigned managed identity** (auto-created by Bicep)
- [ ] Storage uses **MI-based auth** (`AzureWebJobsStorage__accountName`, no connection strings)
- [ ] Cosmos DB uses **SQL RBAC** (not master keys)
- [ ] All RBAC follows **least-privilege** — 11 role assignments across 5 managed identities
- [ ] `allowBlobPublicAccess: false` on storage account
- [ ] `minimumTlsVersion: 'TLS1_2'` on storage
- [ ] Optional: Enable **private networking** toggle for VNet + private endpoints
- [x] DCR + Logs Ingestion API deployed for LAW (MI-authenticated, no shared keys)

---

## RBAC Reference

The platform creates these role assignments automatically:

| Identity | Role | Scope | Purpose |
|----------|------|-------|---------|
| Function App MI | Storage Blob Data Owner | Storage Account | Read cost exports, read zip package |
| Function App MI | Storage Queue Data Contributor | Storage Account | Function runtime (triggers) |
| Function App MI | Storage Table Data Contributor | Storage Account | Read/write budget table |
| Function App MI | Storage Account Contributor | Storage Account | File share management |
| Function App MI | Cosmos DB Data Contributor | Cosmos DB Account | Read/write inventory |
| Function App MI | Cost Management Reader | Subscription | Read cost/usage data |
| Function App MI | Log Analytics Contributor | Resource Group | Write to LAW for workbook |
| Auto-Budget Logic App MI | Contributor | Subscription | Create budgets on new RGs |
| Budget Change Logic App MI | Contributor | Subscription | Modify budgets on request |
| Backfill Logic App MI | Reader | Subscription | Enumerate resource groups |
| Post-Deploy MI | Contributor | Resource Group | Deploy code, manage settings |
