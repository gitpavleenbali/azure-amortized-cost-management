# Cost Forecast — FinOps Budget Alert Automation Platform

> Estimated monthly Azure consumption for operating the platform per subscription.
> All prices sourced from [Azure Pricing Calculator](https://azure.microsoft.com/en-us/pricing/calculator/) (April 2026, West Europe region, USD pay-as-you-go).
> Actual costs may vary based on EA/MCA agreement discounts and reserved capacity.

---

## Executive Summary

The FinOps Budget Alert Automation Platform runs entirely on **serverless and consumption-based** Azure services. There are no fixed VMs, no reserved capacity requirements, and no idle compute charges. The platform monitors amortized cost across all resource groups in a subscription, automates budget creation and alerting, and provides real-time dashboards.

**Estimated monthly cost per subscription: $3 – $8 USD**

At scale across 20 subscriptions with 160,000 resource groups, the total centralised platform cost is estimated at **$40 – $75 USD/month**.

---

## Workload Assumptions (Single Subscription)

| Parameter | Value | Notes |
|-----------|-------|-------|
| Resource groups monitored | 8,000 | Typical large enterprise subscription footprint |
| Daily evaluation cycle | 1× at 06:00 UTC | Timer-triggered Function App |
| Avg Cosmos document size | ~1.5 KB | Budget, spend, compliance per RG |
| Daily cost export CSV | ~100–200 MB | Azure Cost Management AmortizedCost type |
| New RG creations per day | ~5–10 | Event Grid → Logic App auto-budget |
| Self-service budget changes per month | ~10–20 | Logic App HTTP trigger |
| Dashboard/API queries per day | ~50–100 | Workbook + Power BI + ad-hoc |
| Finance CSV uploads per month | ~1–2 | Blob trigger ingestion |
| Diagnostic log volume | ~500 MB/month | Function App + 3 Logic Apps |

---

## Component-Level Cost Breakdown

### 1. Azure Functions — Consumption Plan

**Role:** FinOps Inventory Engine — 9 endpoints (daily evaluation, inventory API, variance, backfill, finance ingestion, quarterly recalc, manual triggers, update-budget)

| Metric | Calculation | Monthly |
|--------|-------------|---------|
| Executions | 30 timer + ~3,000 API + ~5 blob triggers = **~3,035** | Free (1M free/month) |
| Execution time | Daily eval: 30 × 120s × 0.5 GB = 1,800 GB-s | — |
| | API calls: 3,000 × 2s × 0.25 GB = 1,500 GB-s | — |
| | **Total: ~3,300 GB-s** | Free (400K free/month) |
| **Function App total** | | **$0.00** |

> **Pricing source:** [Azure Functions Pricing](https://azure.microsoft.com/en-us/pricing/details/functions/) — Consumption plan includes 1M executions and 400,000 GB-s free per subscription per month. Our workload is well within the free tier.

---

### 2. Azure Cosmos DB — Serverless (NoSQL API)

**Role:** FinOps Inventory — single source of truth for budgets, amortized spend, compliance status

| Metric | Calculation | Monthly |
|--------|-------------|---------|
| **Storage** | 8,000 docs × 1.5 KB = 12 MB (~0.012 GB) | $0.003 |
| **Request Units (RU)** | | |
| — Daily evaluation reads | 8,000 × 5 RU = 40,000 RU/day | — |
| — Daily evaluation writes | 8,000 × 10 RU = 80,000 RU/day | — |
| — API/dashboard reads | 100 × 50 RU = 5,000 RU/day | — |
| — Budget changes | 20 × 10 RU = 200 RU/month | — |
| — **Monthly total** | (125,000 RU/day × 30) + 200 = **~3.75M RU** | $0.94 |
| **Backup** | 2 periodic copies (default) | Free |
| **Cosmos DB total** | | **~$0.94** |

> **Pricing source:** [Cosmos DB Serverless Pricing](https://azure.microsoft.com/en-us/pricing/details/cosmos-db/serverless/) — $0.25 per 1M RU; $0.25/GB/month storage; 2 backup copies free.

---

### 3. Azure Blob Storage — LRS Hot Tier

**Role:** Stores daily amortized cost export CSVs and finance department budget CSVs

| Metric | Calculation | Monthly |
|--------|-------------|---------|
| **Data stored** | 200 MB/day × 30 days = 6 GB (with 30-day lifecycle) | $0.11 |
| **Write operations** | ~30 writes/month (daily export + finance) | < $0.01 |
| **Read operations** | ~30 reads/month (Function App reads CSV) | < $0.01 |
| **Storage total** | | **~$0.13** |

> **Pricing source:** [Blob Storage Pricing](https://azure.microsoft.com/en-us/pricing/details/storage/blobs/) — LRS Hot: $0.018/GB/month (first 50 TB); write ops: $0.065/10K; read ops: $0.005/10K.

*Recommendation:* Apply a lifecycle management policy to move CSVs older than 30 days to Cool tier ($0.01/GB) and delete after 90 days to keep costs flat.

---

### 4. Azure Logic Apps — Consumption Plan (×3)

**Role:** Workflow automation — auto-budget on new RGs, self-service budget changes, daily backfill safety net

| Logic App | Triggers/month | Actions per run | Total actions/month | Cost |
|-----------|---------------|----------------|-------------------|------|
| `la-finops-auto-budget` | ~300 (10 RG creates/day) | 7 (parse, extract, check, create, cosmos, notify, respond) | 2,100 | $0.05 |
| `la-finops-budget-change` | ~20 (self-service) | 9 (tags, validate owner, floor, cap, budget, cosmos, notify, respond) | 180 | < $0.01 |
| `la-finops-backfill` | 30 (daily timer) | 4 (scan, check, execute, respond) | 120 | < $0.01 |
| **Logic Apps total** | | | **~2,400 actions** | **~$0.06** |

> **Pricing source:** [Logic Apps Pricing](https://azure.microsoft.com/en-us/pricing/details/logic-apps/) — Consumption plan: built-in actions ~$0.000025/execution; standard connector (HTTP) actions ~$0.000125/execution.

---

### 5. Azure Event Grid — Basic Tier (System Topic)

**Role:** Detects new resource group creation events → triggers auto-budget Logic App

| Metric | Calculation | Monthly |
|--------|-------------|---------|
| Events published | ~300/month (RG writes) | Free (100K free/month) |
| **Event Grid total** | | **$0.00** |

> **Pricing source:** [Event Grid Pricing](https://azure.microsoft.com/en-us/pricing/details/event-grid/) — Basic tier: $0.60/million operations; first 100,000 operations/month free.

---

### 6. Azure Monitor — Log Analytics Workspace

**Role:** Workbook data source (FinOpsInventory_CL table synced from Cosmos DB) + diagnostic logs from Function App and Logic Apps

| Metric | Calculation | Monthly |
|--------|-------------|--------|
| **Data ingestion — diagnostics** | ~500 MB/month (Function App + Logic App logs) | $1.15 |
| **Data ingestion — FinOpsInventory_CL** | 32 RGs × 1.5 KB/doc × 30 days = ~1.4 MB (negligible) | < $0.01 |
| **Retention** | 90 days configured; first 31 free | |
| — Extended retention (59 days) | 0.5 GB × $0.10/GB/month | $0.05 |
| **Log Analytics total** | | **~$1.20** |

> **Pricing source:** [Azure Monitor Pricing](https://azure.microsoft.com/en-us/pricing/details/monitor/) — Analytics Logs: $2.30/GB ingestion. FinOpsInventory_CL sync adds negligible data (∼1 KB per RG per day). At 8,000 RGs: ~8 MB/day = ~240 MB/month additional ingestion = ~$0.55 extra.

> **Pricing source:** [Azure Monitor Pricing](https://azure.microsoft.com/en-us/pricing/details/monitor/) — Analytics Logs: $2.30/GB ingestion; interactive retention beyond 31 days: $0.10/GB/month. *Note: First 5 GB/month per billing account is free for data ingestion. If this is the only workspace, 0.5 GB is within the free allowance, bringing the cost to $0.05.

---

### 7. Azure Monitor — Action Group

**Role:** Routes threshold breach alerts to configured email recipients

| Metric | Calculation | Monthly |
|--------|-------------|--------|
| Email notifications | ~50/month (threshold breaches) | Free (first 1,000/month free) |
| **Action Group total** | | **$0.00** |

> **Pricing source:** [Azure Monitor Notifications](https://azure.microsoft.com/en-us/pricing/details/monitor/) — 1,000 emails/month included free.

---

### 7a. Azure Monitor — Scheduled Query Rules (3 Alert Rules)

**Role:** Hourly KQL queries against LAW to detect HeadUp/Warning/Critical amortized budget breaches and fire Action Group

| Metric | Calculation | Monthly |
|--------|-------------|--------|
| 3 alert rules × hourly evaluation | $0.10/rule/month (frequency ≤ 5 min) | $0.30 |
| **Alert Rules total** | | **~$0.30** |

> **Pricing source:** [Azure Monitor Pricing](https://azure.microsoft.com/en-us/pricing/details/monitor/) — Scheduled Query Rules: ~$0.10/rule/month for hourly evaluation.

---

### 8. Cost Management Export

**Role:** Daily automated export of amortized cost data to Blob Storage

| Metric | Monthly |
|--------|---------|
| Export schedule | Daily AmortizedCost type | **$0.00** |

> Azure Cost Management exports are a **free** feature of Azure Cost Management. No additional charges.

---

### 9. Azure Policy — Audit Assignment

**Role:** Flags resource groups without a budget in the compliance dashboard

| Metric | Monthly |
|--------|---------|
| Policy audit evaluation | **$0.00** |

> Azure Policy audit/deny assignments are **free** for Azure resources. No per-evaluation charge.

---

### 10. Azure Subscription Budget (Native)

**Role:** Safety-net actual cost alerting at subscription level (EUR 5,000 with 5 thresholds)

| Metric | Monthly |
|--------|---------|
| Budget configuration | **$0.00** |

> Native Azure Budgets in Cost Management are **free**.

---

### 11. Azure Workbook

**Role:** Real-time compliance dashboard in Azure Portal (queries FinOpsInventory_CL in LAW)

| Metric | Monthly |
|--------|--------|
| Workbook (KQL queries against LAW) | **$0.00** |

> Azure Workbooks are a **free** portal feature. KQL queries against Analytics Logs are free (no query charge).

---

## Total Monthly Cost — Single Subscription (8,000 RGs)

| Component | Unit Price Reference | Monthly Cost (USD) |
|-----------|---------------------|-------------------|
| Azure Functions (Consumption) | 1M exec + 400K GB-s free | $0.00 |
| Cosmos DB (Serverless) | $0.25/M RU + $0.25/GB | $0.94 |
| Blob Storage (LRS Hot) | $0.018/GB + ops | $0.13 |
| Logic Apps × 3 (Consumption) | ~$0.000025–$0.000125/action | $0.06 |
| Event Grid (Basic) | 100K ops/month free | $0.00 |
| Log Analytics (90-day retention) | $2.30/GB ingestion | $1.20 |
| Scheduled Query Rules (3 alerts) | ~$0.10/rule/month | $0.30 |
| Action Group | 1,000 emails/month free | $0.00 |
| Cost Management Export | Free | $0.00 |
| Azure Policy Audit | Free | $0.00 |
| Native Budget | Free | $0.00 |
| Workbook | Free | $0.00 |
| | | |
| **Total (single subscription)** | | **~$2.63** |

> **With Log Analytics free tier (5 GB/month, first workspace): ~$1.48/month**

---

## Multi-Subscription Scaling Forecast

The platform uses a **per-subscription architecture**: each subscription gets its own FinOps resource group with Function App, Cosmos DB, LAW, Action Group, Alert Rules, and Workbook.

| Scale | RGs | Cosmos RU/month | Cosmos Storage | LAW Ingestion | Blob Storage | Functions | Total/month |
|-------|-----|----------------|---------------|--------------|-------------|-----------|-------------|
| **1 subscription** | 8,000 | 3.75M | 12 MB | 0.5 GB | 6 GB | Free tier | **~$2.33** |
| **5 subscriptions** | 40,000 | 18.75M | 60 MB | 2 GB | 30 GB | Free tier | **~$7.73** |
| **10 subscriptions** | 80,000 | 37.5M | 120 MB | 4 GB | 60 GB | Free tier | **~$14.53** |
| **20 subscriptions** | 160,000 | 75M | 240 MB | 8 GB | 120 GB | Free tier | **~$27.78** |
| **50 subscriptions** | 400,000 | 187.5M | 600 MB | 20 GB | 300 GB | Consider Premium¹ | **~$68.10** |

¹ At 50+ subscriptions, daily evaluation may exceed 5 minutes per run. Consider upgrading Function App to **Premium plan (EP1)** at ~$175/month for warm instances and VNet integration, bringing 50-sub total to ~$243/month.

### Scaling Cost Formula

$$C_{monthly} = \underbrace{0.25 \times \frac{RU_{total}}{1{,}000{,}000}}_{\text{Cosmos DB}} + \underbrace{0.018 \times GB_{blob}}_{\text{Storage}} + \underbrace{2.30 \times GB_{logs}}_{\text{Log Analytics}} + \underbrace{0.000125 \times Actions}_{\text{Logic Apps}}$$

---

## 12-Month Total Cost of Ownership

| Scenario | Monthly | Annual | Notes |
|----------|---------|--------|-------|
| Single subscription (MVP) | $2.33 | **$27.96** | Current QA deployment |
| 5 subscriptions (pilot) | $7.73 | **$92.76** | Phase 2 rollout |
| 20 subscriptions (production) | $27.78 | **$333.36** | Full enterprise coverage |
| 20 subs + Premium Functions | $202.78 | **$2,433.36** | With warm instances + VNet |

---

## What Is Free

| Feature | Why Free |
|---------|---------|
| Azure Functions (Consumption) | 1M executions + 400K GB-s included/month/subscription |
| Event Grid (Basic) | First 100K operations/month included |
| Action Group emails | First 1,000 emails/month included |
| Azure Cost Management Export | Built into Azure Cost Management |
| Azure Policy audit | No charge for policy evaluation |
| Azure Budgets (native) | Built into Azure Cost Management |
| Azure Dashboard | Free portal feature |
| Azure Workbook | Free portal feature |
| Managed Identities | No charge for identity itself |
| RBAC role assignments | No charge |

---

## Cost Optimisation Recommendations

| # | Recommendation | Savings |
|---|---------------|---------|
| 1 | **Enable Cosmos DB free tier** on one account — 1,000 RU/s provisioned + 25 GB storage free for the lifetime of the account. If applicable, this eliminates Cosmos DB cost entirely for up to ~20 subscriptions. | Up to 100% of Cosmos DB |
| 2 | **Apply blob lifecycle policy** — move cost export CSVs to Cool tier after 30 days, delete after 90 days. | ~40% of Storage |
| 3 | **Use Log Analytics free tier** — first 5 GB/month ingestion free (per billing account). Diagnostic volume of 0.5 GB/sub is within free allowance for small deployments. | Up to 100% of LAW |
| 4 | **Reduce LAW retention** from 90 to 31 days if Workbook uses `externaldata` from Function API (no LAW dependency for dashboards). | ~$0.05/sub/month |
| 5 | **Use EA/MCA pricing** — enterprise agreements typically include 10–20% discount on pay-as-you-go rates. | 10–20% across all |

---

## Comparison: Platform Cost vs Budget Waste Prevented

| Metric | Value |
|--------|-------|
| Monthly platform cost (20 subs) | ~$28 |
| Average overspend caught per RG per month (at 5% overrun on EUR 1,000 avg budget) | EUR 50 |
| RGs flagged as over_budget (conservative 2%) | 160,000 × 2% = 3,200 RGs |
| **Monthly waste prevented** | **3,200 × EUR 50 = EUR 160,000** |
| **ROI** | **EUR 160,000 saved / $28 cost = ~5,700:1** |

> Even at a conservative 0.1% catch rate with EUR 200 average overrun, the platform prevents EUR 32,000/month in undetected amortized cost overruns — a **1,143:1 ROI**.

---

## Pricing Sources

| Component | URL |
|-----------|-----|
| Azure Functions | https://azure.microsoft.com/en-us/pricing/details/functions/ |
| Cosmos DB Serverless | https://azure.microsoft.com/en-us/pricing/details/cosmos-db/serverless/ |
| Blob Storage | https://azure.microsoft.com/en-us/pricing/details/storage/blobs/ |
| Logic Apps | https://azure.microsoft.com/en-us/pricing/details/logic-apps/ |
| Event Grid | https://azure.microsoft.com/en-us/pricing/details/event-grid/ |
| Azure Monitor | https://azure.microsoft.com/en-us/pricing/details/monitor/ |
| Pricing Calculator | https://azure.microsoft.com/en-us/pricing/calculator/ |

---

## Disclaimer

Prices are estimates based on publicly available Azure pay-as-you-go rates as of April 2026 (West Europe region, USD). Actual costs depend on Enterprise Agreement (EA) or Microsoft Customer Agreement (MCA) pricing, negotiated discounts, Azure Hybrid Benefit, and actual usage patterns. This document is provided for planning purposes. Validate estimates in the [Azure Pricing Calculator](https://azure.microsoft.com/en-us/pricing/calculator/) with your specific agreement rates.

---

*Azure Amortized Cost Management — Cost Forecast. April 2026.*
