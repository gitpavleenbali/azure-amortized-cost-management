---
description: Enterprise-grade amortized cost budget management and alerting for Azure at scale.
page_type: sample
products:
- azure
- azure-resource-manager
- azure-cost-management
- azure-functions
- azure-logic-apps
- azure-cosmos-db
urlFragment: azure-amortized-cost-management
languages:
- bicep
- json
- python
---

# Azure Amortized Cost Management

[![CI — Validate & Test](https://github.com/gitpavleenbali/azure-amortized-cost-management/actions/workflows/ci.yml/badge.svg)](https://github.com/gitpavleenbali/azure-amortized-cost-management/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Azure](https://img.shields.io/badge/Azure-Serverless-0078D4?logo=microsoftazure)](https://azure.microsoft.com)
[![FinOps](https://img.shields.io/badge/FinOps-Cost%20Management-green)](https://www.finops.org/)

> Enterprise-grade budget management and **amortized cost** alerting for Azure at scale.
> Bridges Azure's actual-cost-only budget limitation with amortized cost tracking for Reserved Instances and Savings Plans.

---

## Getting Started

Choose how you want to get started:

### Option 1: Deploy directly to Azure

Click the button below to launch a guided deployment wizard in the Azure Portal — no cloning or local tooling required.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fgitpavleenbali%2Fazure-amortized-cost-management%2Fmain%2Fazuredeploy.json/createUIDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2Fgitpavleenbali%2Fazure-amortized-cost-management%2Fmain%2FcreateUiDefinition.json)
[![Deploy To Azure US Gov](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/deploytoazuregov.svg?sanitize=true)](https://portal.azure.us/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fgitpavleenbali%2Fazure-amortized-cost-management%2Fmain%2Fazuredeploy.json/createUIDefinitionUri/https%3A%2F%2Fraw.githubusercontent.com%2Fgitpavleenbali%2Fazure-amortized-cost-management%2Fmain%2FcreateUiDefinition.json)
[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2Fgitpavleenbali%2Fazure-amortized-cost-management%2Fmain%2Fazuredeploy.json)

### Option 2: Use this template on GitHub

Click **[Use this template](https://github.com/gitpavleenbali/azure-amortized-cost-management/generate)** at the top of this repository to create your own copy. This gives you a clean repo (no fork history) that you can customise, extend, and deploy through your own CI/CD pipeline.

---

## The Problem

Azure native budgets only alert on **actual cost**. Organizations using Reserved Instances and Savings Plans see a EUR 36K spike on purchase day then nothing for 3 years — making native budget alerts useless for ongoing cost monitoring.

**Amortized cost** spreads that EUR 36K across 1,095 days (~EUR 33/day), giving you a true picture of daily consumption.

This platform uses Azure Cost Management's amortized export to track real consumption patterns and alert on meaningful spend deviations.

---

## What You Get

One deployment gives you the full FinOps cost governance stack:

| Capability | How It Works |
|-----------|-------------|
| **Subscription-level budgets** | Bicep module creates monthly budgets with 5 escalating thresholds (50/75/90/100/110%) |
| **Auto-budget on new RGs** | Event Grid + Logic App detects new resource groups, assigns EUR 100 default budget within seconds |
| **Self-service budget changes** | Logic App with HTTP endpoint — users request changes with floor (EUR 100) / cap (3x) guardrails |
| **Amortized cost alerting** | Python Azure Function reads daily amortized cost exports, compares against budgets |
| **4-tier dynamic thresholds** | Alert thresholds scale by spend bracket — low-spend RGs tolerate more variance, high-spend get tighter controls |
| **Finance vs Technical budgets** | Compare finance-approved budgets against Azure actual spend — executive variance view |
| **Configurable governance alerts** | Immediate notification when any configured tag value is detected (e.g., cost category flags) |
| **FinOps Inventory** | Cosmos DB single source of truth — budget, spend, forecast, compliance per resource group |
| **Azure Workbook dashboard** | Real-time compliance dashboard with pie charts, heatmaps, and color-coded inventory |
| **Power BI templates** | Ready-to-use Power Query + DAX for executive dashboards |
| **Audit policy** | AuditIfNotExists policy flags any RG without a budget |
| **Quarterly recalculation** | Auto-adjusts budgets based on last quarter's actuals (only if drift > 30%) |
| **REST API** | `/api/inventory` and `/api/variance` endpoints for custom integrations |

### Platform Cost

**~$2.50/month per subscription** — entirely serverless (Functions, Cosmos DB Serverless, Logic Apps Consumption). See [Cost Forecast](docs/cost-forecast.md) for detailed breakdown.

---

## Architecture

<p align="center">
  <img src="docs/ecosystem-diagram.svg" alt="Azure Amortized Cost Management — Ecosystem Architecture" width="100%" />
</p>

**9 Function App endpoints** | **3 Logic Apps** | **3 Scheduled Query Rules** | **20+ deployed resources** | **20 Bicep modules**

See [Architecture Guide](docs/technical-guide.md) for the full 6-stage data flow with diagrams.

---

## Quick Start

### Option A: One-Click Deploy (Recommended for Dev/MVP)

Best for: Quick evaluation, dev subscriptions, hands-on learning, MVP validation. No tools, no terminal, no scripts.

1. Click **Deploy to Azure** in the [Getting Started](#getting-started) section
2. Walk through the **6-tab wizard**:
   - **Basics** — Environment name, FinOps email
   - **Budget Configuration** — Subscription + RG default budget amounts
   - **Feature Toggles** — All default to Enabled
   - **Networking** — Optional VNet + private endpoints
   - **Resource Naming** — Override any resource name (or keep CAF defaults)
   - **Advanced** — Resource group name, Teams webhook, tags
3. Click **Review + Create**

**What happens automatically:**
- All resources deploy (~5 min): Function App, Cosmos DB, Log Analytics, 3 Logic Apps, 3 Alert Rules, Workbook, Storage, Action Group, Budget, Policy
- Post-deploy script runs inside the deployment:
  - Downloads Function App zip from GitHub → uploads to blob storage
  - Sets `WEBSITE_RUN_FROM_PACKAGE` to the blob URL (MI-authenticated)
  - Creates daily amortized cost export + triggers immediate run
  - Triggers `/api/backfill` (scans all RGs → Cosmos DB)
  - Triggers `/api/evaluate` (processes cost data → inventory)
  - Syncs to Log Analytics → powers Workbook + Alert Rules
- **Open the Workbook dashboard ~10 minutes after deployment completes**

> **Subscription hint**: Deploy to a dev or sandbox subscription where Azure Policies do not block storage key access. For enterprise subscriptions with strict policies, use Option B below.

#### Common Issues (Option 1 — Deploy to Azure)

| Symptom | Likely Cause | Quick Fix |
|---------|-------------|----------|
| Post-deploy script fails with `KeyBasedAuthenticationNotPermitted` | Subscription has an Azure Policy that sets `allowSharedKeyAccess=false` on all storage accounts | Use **Option B** (CI/CD) instead — the post-deploy script needs a storage account for its container, which requires key access. Production environments should use CI/CD. |
| Function App shows 0 functions after deployment | RBAC roles haven't propagated to the storage account yet | Wait 2-3 minutes, then restart the Function App: `az functionapp restart -g <rg> -n <func>`. If still empty, verify 4 RBAC roles are scoped to the storage account (see [CI/CD Guide - Troubleshooting](docs/cicd-guide.md#troubleshooting)). |
| Cosmos DB fails in East US | Regional capacity constraints for serverless accounts | Redeploy in **West US 2**, **West Europe**, or **Central US** — these regions have reliable serverless capacity. |
| Deployment times out after 30 minutes | Post-deploy script waited too long for Function App to start | The infrastructure is deployed — redeploy to retry the post-deploy script, or manually run the 3-step kickstart: upload zip to blob, trigger `/api/backfill`, trigger `/api/evaluate`. |
| Deploy button says "template not found" | GitHub CDN cache delay after a recent push | Wait 5 minutes and try again — GitHub's raw content CDN caches for a few minutes. |

> **Not seeing your issue?** Check the full [Troubleshooting table](#troubleshooting--common-deployment-issues) below, or see the [CI/CD Guide](docs/cicd-guide.md#troubleshooting) for advanced debugging.

### Option B: Clone & CI/CD Deploy (Production)

Best for: Production environments, enterprise subscriptions with security policies, teams who want full control over the deployment pipeline.

See the **[CI/CD Deployment Guide](docs/cicd-guide.md)** for complete instructions including:
- GitHub Actions and Azure DevOps pipeline templates
- Deployment Center setup (GitHub, Azure Repos)
- Manual CLI deploy steps
- Troubleshooting guide with lessons learned
- Security checklist for production
- Full RBAC reference (11 role assignments across 5 managed identities)

**Quick start:**

```bash
# 1. Clone or use template
git clone https://github.com/gitpavleenbali/azure-amortized-cost-management.git
cd azure-amortized-cost-management

# 2. Deploy infrastructure
az deployment sub create --location eastus \
  --template-file infra/main.bicep \
  --parameters parameters/template.bicepparam

# 3. Deploy Function App code (see docs/cicd-guide.md for full details)
# Build zip on Linux, upload to blob, set package URL, restart
```

> **Two-phase approach**: Infrastructure deploys via Bicep (Phase 1), then Function App code deploys via your CI/CD pipeline (Phase 2). This separation gives you full control over code lifecycle, approval gates, and staging slots.

> **Authentication flexibility (Option 2)**: When you clone the repo, you can configure the storage and Function App authentication to match your enterprise requirements — Managed Identity (default), connection strings, private endpoints, or any combination. The [CI/CD Guide](docs/cicd-guide.md) covers all approaches and explains which to use based on your subscription's security policies.

### Documentation Index

| Guide | Audience | What It Covers |
|-------|----------|---------------|
| [CI/CD Deployment Guide](docs/cicd-guide.md) | DevOps, Platform | Production deployment, GitHub Actions, Azure DevOps, troubleshooting, RBAC reference |
| [Architecture Guide](docs/technical-guide.md) | Architects, DevOps | 6-stage data flow, all 9 endpoints, Cosmos schema, Mermaid diagrams |
| [Cost Forecast](docs/cost-forecast.md) | FinOps, Finance | Per-component pricing, ~$2.50/month breakdown |
| [Naming Conventions](docs/naming-conventions.md) | DevOps, Platform | Resource naming patterns, tag schema, environment strategy |
| [Contributing](CONTRIBUTING.md) | Developers | PR workflow, code standards, test requirements |
| [Security](SECURITY.md) | Security, Compliance | Vulnerability reporting, secrets management, RBAC |
| [Support](SUPPORT.md) | All | Issue templates, troubleshooting, support channels |

---

## Prerequisites

### Option A: One-Click Deploy

No local tools required — just an Azure subscription with the RBAC roles below.

### Option B: Fork/Clone & CI/CD

| Tool | Version | Install |
|------|---------|---------|
| Azure CLI | >= 2.60 | `winget install Microsoft.AzureCLI` |
| Bicep CLI | >= 0.28 | Bundled with Azure CLI |
| PowerShell | >= 7.4 | `winget install Microsoft.PowerShell` |
| Python | >= 3.11 | `winget install Python.Python.3.11` |

### RBAC Requirements

| Role | Scope | Why |
|------|-------|-----|
| Contributor | Subscription | Deploy resources |
| Cost Management Contributor | Subscription | Create budgets + cost exports |
| Resource Policy Contributor | Subscription | Create/assign policies |
| User Access Administrator | Subscription | Assign RBAC to Logic App managed identities |

### Resource Providers

The following resource providers must be registered on your subscription. The deployment will auto-register them, but if your subscription has restrictions, register manually:

```bash
az provider register --namespace Microsoft.Consumption
az provider register --namespace Microsoft.CostManagement
az provider register --namespace Microsoft.DocumentDB
az provider register --namespace Microsoft.EventGrid
az provider register --namespace Microsoft.Logic
az provider register --namespace Microsoft.Insights
az provider register --namespace Microsoft.Web
az provider register --namespace Microsoft.OperationalInsights
az provider register --namespace Microsoft.ManagedIdentity
```

---

## Well-Architected Framework Alignment

This platform is designed following the [Azure Well-Architected Framework](https://learn.microsoft.com/azure/well-architected/) pillars:

| Pillar | How We Address It |
|--------|------------------|
| **Cost Optimization** | The platform itself runs on ~$2.50/month serverless. Cosmos DB Serverless = pay-per-request. Function App on Consumption plan. No idle compute. |
| **Operational Excellence** | IaC-only (Bicep), CI/CD pipeline, automated daily evaluation, quarterly recalculation, observability via Log Analytics + Workbook |
| **Reliability** | Idempotent deployments, timer-triggered evaluation with manual fallback, backfill Logic App as safety net, Cosmos DB automatic backup |
| **Security** | Managed Identity everywhere (no shared keys in code), RBAC least-privilege, secure parameters for secrets, audit policy for compliance |
| **Performance Efficiency** | Serverless auto-scale, Cosmos DB partition key on subscriptionId for multi-sub, async blob processing, configurable exclusion filters |

---

## Troubleshooting — Common Deployment Issues

If your deployment fails, check this table before troubleshooting further:

| Issue | Error Message | Cause | Fix |
|-------|--------------|-------|-----|
| **Cosmos DB capacity** | "high demand for zonal redundant accounts" | Region capacity constraint (common in East US) | Deploy to a different region (West US 2, West Europe) |
| **Cosmos DB stuck** | "terminal provisioning state 'Failed'" | Previous failed Cosmos account blocking redeploy | Delete the failed account: `az cosmosdb delete --name <name> -g <rg> --yes` |
| **Budget start date** | "Start date of budgets cannot be updated" | Budget already exists with a different start date | Delete the existing budget: `az consumption budget delete --budget-name <name>` |
| **Alert rules** | "Failed to resolve table FinOpsInventory_CL" | Custom log table doesn't exist yet at deploy time | Already handled via `skipQueryValidation: true` — redeploy if using old template version |
| **Storage key policy** | "Key based authentication is not permitted" | Subscription policy blocks shared key access | Deployment uses a dedicated script storage account — if still blocked, check Azure Policy |
| **Resource provider** | "ResourceProviderNotRegistered" | Required provider not registered on subscription | Run `az provider register --namespace <provider>` (see Prerequisites) |
| **RBAC insufficient** | "Authorization failed" | Deployer lacks User Access Administrator role | Set `enableRbacAssignment = Disabled` in Feature Toggles, then assign roles manually |
| **Function App empty** | Only 5 resources deployed | Feature Toggles were set to Disabled | Ensure all toggles show "Enabled" in the wizard (they default to Enabled) |
| **Event Grid webhook** | "Webhook validation handshake failed" | Event Grid requires a valid endpoint URL | Already handled — post-deploy script wires the real Logic App URL |
| **Naming collision** | "already taken" | Globally unique name conflict (Storage, Cosmos, Function App) | Use the Resource Naming tab to specify custom names |
| **Post-deploy timeout** | Deployment script exceeded 30 minutes | Function App code build took too long | Redeploy — the Function App infrastructure is already created; post-deploy will retry |

### Identity & Access Management (IAM)

This solution uses **Managed Identity** (zero shared keys) with 11 RBAC role assignments:

| Identity | Roles | How It's Set |
|----------|-------|-------------|
| Function App (System MSI) | Storage Blob Data Owner, Storage Queue Data Contributor, Storage Table Data Contributor, Storage Account Contributor, Cosmos DB SQL Data Contributor, Log Analytics Contributor, Cost Management Reader, Monitoring Metrics Publisher (DCR) | Automatic via Bicep (when `enableRbacAssignment = Enabled`) |
| Auto-Budget Logic App (System MSI) | Cost Management Contributor (subscription scope) | Automatic via Bicep |
| Budget Change Logic App (System MSI) | Cost Management Contributor (subscription scope) | Automatic via Bicep |
| Backfill Logic App (System MSI) | Reader (subscription scope) | Automatic via Bicep |
| Post-Deploy Identity (User MSI) | Contributor (RG), Cost Management Contributor (subscription) | Automatic via Bicep |

**If your organisation requires manual RBAC approval**: set `enableRbacAssignment = Disabled` during deployment, then assign the roles listed above through your ITSM/approval workflow.

**Log Analytics authentication**: The `_sync_to_law()` function supports two modes:
1. **DCR + Logs Ingestion API** (default, preferred) — uses Managed Identity via `azure-monitor-ingestion` SDK. The Bicep template deploys a Data Collection Rule (DCR) and Data Collection Endpoint (DCE) automatically. No shared keys needed.
2. **HTTP Data Collector API** (fallback) — uses a shared key, auto-detected if DCR environment variables are not set. The key is passed securely via `@secure()` Bicep parameter.

---

## Project Structure

```
azure-amortized-cost-management/
├── .github/workflows/ci.yml           # GitHub Actions CI (Bicep lint + pytest)
├── .github/workflows/deploy-function.yml  # CD — builds Linux zip, uploads to blob, restarts Function App
├── infra/
│   ├── main.bicep                    # Orchestrator — deploys all 9+ modules
│   └── modules/                      # Action Group, Budget, Cosmos, DCR, Function, Logic Apps, Policy, Storage, Event Grid, Post-Deploy
├── functions/
│   └── amortized-budget-engine/      # Python 3.11 Azure Function — 9 endpoints
├── parameters/
│   ├── template.bicepparam           # Copy this for your environment
│   ├── dev.bicepparam
│   ├── staging.bicepparam
│   └── prod.bicepparam
├── scripts/                          # Operational PowerShell + Python
├── powerbi/                          # Power Query M + DAX templates
├── dashboards/                       # Power BI Cosmos connection templates
├── queries/                          # KQL (Resource Graph) + SQL (Cosmos + Snowflake)
├── tests/                            # pytest (14 tests) + Pester (infra validation)
├── docs/                             # Architecture guide, CI/CD guide, cost forecast
├── LICENSE                           # MIT
├── CONTRIBUTING.md
├── SECURITY.md
└── CODE_OF_CONDUCT.md
```

---

## Configuration

### Parameters (.bicepparam)

| Parameter | Default | Description |
|-----------|---------|-------------|
| `environment` | `dev` | Environment name (2-10 chars, e.g. dev, staging, prod, uat, sandbox) |
| `location` | `westeurope` | Azure region for all resources |
| `finopsEmail` | *(required)* | FinOps team email(s) — comma-separated for multiple recipients |
| `defaultBudgetAmount` | `100` | Default budget for new RGs (auto-budget Logic App) |
| `subscriptionBudgetAmount` | `10000` | Monthly subscription-level budget |
| `costTrackingScope` | `both` | `resourceGroup` (per-RG only), `subscription` (sub-level only), or `both` |
| `enableAmortizedPipeline` | `true` | Deploy Function App, LAW, Alert Rules, Workbook |
| `enableAutoBudget` | `true` | Auto-assign budget on new RG creation |
| `enableSelfServiceChange` | `true` | Self-service budget change HTTP endpoint |
| `enablePolicy` | `true` | Audit policy for RGs without budgets |
| `enableRbacAssignment` | `true` | Auto-assign RBAC to managed identities |
| `enablePrivateNetworking` | `false` | VNet + private endpoints for Cosmos/Storage |
| `enablePostDeploy` | `true` | Run the post-deploy automation script (code deploy, cost export, backfill). Set to `false` for restricted subscriptions that block storage key access — use CI/CD (Option B) instead. |
| `budgetStartDate` | `2026-04-01` | Budget period start date (cannot change after creation) |

### Resource Naming

All resources use [Cloud Adoption Framework](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming) defaults. Toggle **"Use custom resource names"** in the portal wizard to override any of the 14 resource names (Action Group, Cosmos DB, Storage, Function App, 3 Logic Apps, LAW, Workbook, 3 Alert Rules, Managed Identity, and Resource Group).

### Environment Variables (Function App)

| Variable | Description |
|----------|-------------|
| `FINOPS_EMAIL` | Alert routing email |
| `GOVERNANCE_EMAIL` | Governance team email |
| `GOVERNANCE_TAG_KEY` | Tag key that triggers governance alerts (optional) |
| `GOVERNANCE_TAG_VALUE` | Tag value that triggers governance alerts (optional) |
| `EXCLUDED_RG_PREFIXES` | Comma-separated RG prefixes to skip (e.g., `MC_,FL_,NetworkWatcherRG`) |

---

## API Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/evaluate` | GET | Trigger amortized cost evaluation on-demand |
| `/api/inventory` | GET | Full FinOps inventory as JSON (filterable: `?status=over_budget`) |
| `/api/variance` | GET | Finance vs Technical budget variance report |
| `/api/update-budget` | POST | Update budget in Cosmos DB (called by Logic App) |
| `/api/backfill` | GET | Scan + create budgets for existing RGs (`?dryRun=true`) |
| `/api/recalculate` | GET | Trigger quarterly budget recalculation |

---

## Documentation

| Document | Description |
|----------|-------------|
| [Architecture Guide](docs/technical-guide.md) | Full 6-stage data flow, Cosmos DB schema, alert framework, ITSM integration patterns |
| [Cost Forecast](docs/cost-forecast.md) | Component-level pricing, scaling formula, ROI analysis |
| [Naming Conventions](docs/naming-conventions.md) | Resource naming, tags, environments, thresholds, API patterns, best practices |

---

## Running Tests

```bash
# Unit tests (no Azure connection needed)
python -m pytest tests/function/test_evaluator.py -v

# Infrastructure validation (requires Azure connection)
Invoke-Pester tests/infra/Validate-Deployment.Tests.ps1 -Output Detailed
```

---

## Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## Security

See [SECURITY.md](SECURITY.md) for vulnerability reporting.

## Code of Conduct

This project follows the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).

## License

[MIT](LICENSE) — Copyright (c) Microsoft Corporation.

## Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft trademarks or logos is subject to and must follow [Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks/usage/general). Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.

---

`Tags: finops, cost-management, azure, bicep, budget-alerts, amortized-cost, reserved-instances, savings-plans, cosmos-db, serverless, well-architected`