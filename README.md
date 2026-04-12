# Azure Amortized Cost Management

[![CI — Validate & Test](https://github.com/gitpavleenbali/azure-amortized-cost-management/actions/workflows/ci.yml/badge.svg)](https://github.com/gitpavleenbali/azure-amortized-cost-management/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Azure](https://img.shields.io/badge/Azure-Serverless-0078D4?logo=microsoftazure)](https://azure.microsoft.com)
[![FinOps](https://img.shields.io/badge/FinOps-Cost%20Management-green)](https://www.finops.org/)

> Enterprise-grade budget management and **amortized cost** alerting for Azure at scale.
> Bridges Azure's actual-cost-only budget limitation with amortized cost tracking for Reserved Instances and Savings Plans.

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fgitpavleenbali%2Fazure-amortized-cost-management%2Fmain%2Fazuredeploy.json)
[![Visualize](https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/1-CONTRIBUTION-GUIDE/images/visualizebutton.svg?sanitize=true)](http://armviz.io/#/?load=https%3A%2F%2Fraw.githubusercontent.com%2Fgitpavleenbali%2Fazure-amortized-cost-management%2Fmain%2Fazuredeploy.json)

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

**9 Function App endpoints** | **3 Logic Apps** | **3 Scheduled Query Rules** | **17 deployed resources**

See [Architecture Guide](docs/technical-guide.md) for the full 6-stage data flow with diagrams.

---

## Quick Start

### Option A: One-Click Deploy (Recommended)

1. Click **Deploy to Azure** above
2. Fill in 4 parameters:
   - **Email** — FinOps team email for alerts
   - **Location** — Azure region (e.g., `westeurope`)
   - **Environment** — `dev`, `staging`, or `prod`
   - **Subscription Budget** — Monthly budget amount (EUR)
3. Click **Review + Create**

### Option B: CLI Deploy

```bash
# 1. Clone the repo
git clone https://github.com/<ORG>/azure-amortized-cost-management.git
cd azure-amortized-cost-management

# 2. Edit parameters
cp parameters/template.bicepparam parameters/my-env.bicepparam
# Edit: set finopsEmail, location, subscriptionBudgetAmount

# 3. Preview
az deployment sub create \
  --location westeurope \
  --template-file infra/main.bicep \
  --parameters parameters/my-env.bicepparam \
  --what-if

# 4. Deploy
az deployment sub create \
  --location westeurope \
  --template-file infra/main.bicep \
  --parameters parameters/my-env.bicepparam
```

### Post-Deploy Setup (3 steps)

```bash
# 1. Create daily amortized cost export
.\scripts\New-AmortizedExport.ps1 \
  -StorageAccountName "<from deployment output>" \
  -StorageAccountResourceGroup "rg-finops-governance-dev"

# 2. Deploy Function App code (after cost export has 1 week of data)
cd functions/amortized-budget-engine
func azure functionapp publish <functionAppName> --python

# 3. RBAC assignment (requires Owner — run by subscription admin)
.\scripts\Enable-AdminFeatures.ps1 \
  -SubscriptionId "<your-sub-id>" \
  -ResourceGroupName "rg-finops-governance-dev"
```

---

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Azure CLI | >= 2.60 | `winget install Microsoft.AzureCLI` |
| Bicep CLI | >= 0.28 | Bundled with Azure CLI |
| PowerShell | >= 7.4 | `winget install Microsoft.PowerShell` |
| Python | >= 3.11 | `winget install Python.Python.3.11` |
| Azure Functions Core Tools | >= 4.x | `npm install -g azure-functions-core-tools@4` |

### RBAC Requirements

| Role | Scope | Why |
|------|-------|-----|
| Contributor | Subscription | Deploy resources |
| Cost Management Contributor | Subscription | Create budgets + cost exports |
| Resource Policy Contributor | Subscription | Create/assign policies |
| User Access Administrator | Subscription | Assign RBAC to Logic App managed identities |

### Resource Providers

Register these before deploying (the pipeline handles this automatically):

```bash
az provider register --namespace Microsoft.Consumption
az provider register --namespace Microsoft.CostManagement
az provider register --namespace Microsoft.CostManagementExports
az provider register --namespace Microsoft.EventGrid
az provider register --namespace Microsoft.Logic
az provider register --namespace Microsoft.Insights
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

## Project Structure

```
azure-amortized-cost-management/
├── .github/workflows/ci.yml          # GitHub Actions CI (Bicep lint + pytest)
├── infra/
│   ├── main.bicep                    # Orchestrator — deploys all 9+ modules
│   └── modules/                      # Action Group, Budget, Cosmos, Function, Logic Apps, Policy, Storage, Event Grid
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
├── docs/                             # Architecture guide + cost forecast
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
| `environment` | `dev` | `dev` / `staging` / `prod` |
| `location` | `westeurope` | Azure region |
| `finopsEmail` | *(required)* | FinOps team email for alerts |
| `defaultBudgetAmount` | `100` | Default EUR budget for new RGs |
| `subscriptionBudgetAmount` | `10000` | Monthly subscription budget (EUR) |
| `enableAmortizedPipeline` | `false` | Enable after cost export has 1 week of data |
| `enableAutoBudget` | `true` | Auto EUR 100 on new RG creation |
| `enableSelfServiceChange` | `true` | Enable self-service budget change Logic App |
| `enablePolicy` | `true` | Deploy audit policy for RGs without budgets |

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