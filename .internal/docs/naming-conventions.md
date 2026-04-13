# Naming Convention & Best Practices

> Follow these conventions when deploying Azure Amortized Cost Management into your subscription.
> Aligned with [Azure Cloud Adoption Framework naming rules](https://learn.microsoft.com/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming).

---

## Resource Naming Convention

All resources deployed by this platform follow a consistent pattern:

```
{resource-type-prefix}-finops-{function}-{environment}
```

### Resource Names

| Resource | Naming Pattern | Example (dev) | Example (prod) |
|----------|---------------|---------------|----------------|
| **Resource Group** | `rg-finops-governance-{env}` | `rg-finops-governance-dev` | `rg-finops-governance-prod` |
| **Function App** | `func-finops-{uniqueString}` | `func-finops-abc123xyz` | Auto-generated via `uniqueString(rg.id)` |
| **Cosmos DB** | `cosmos-finops-{uniqueString}` | `cosmos-finops-abc123xyz` | Auto-generated via `uniqueString(rg.id)` |
| **Storage Account** | `safinops{uniqueString}` | `safinopsabc123xyz` | Auto-generated (3-24 chars, lowercase) |
| **Log Analytics** | `law-finops-{env}` | `law-finops-dev` | `law-finops-prod` |
| **Action Group** | `ag-finops-budget-alerts` | Same across environments | Same across environments |
| **Logic App (auto-budget)** | `la-finops-auto-budget` | Same across environments | Same across environments |
| **Logic App (budget-change)** | `la-finops-budget-change` | Same across environments | Same across environments |
| **Logic App (backfill)** | `la-finops-backfill` | Same across environments | Same across environments |
| **Alert Rules** | `finops-alert-{severity}` | `finops-alert-critical` | `finops-alert-critical` |
| **Workbook** | `FinOps Budget & Cost Governance` | Same across environments | Same across environments |
| **Cost Export** | `finops-daily-amortized` | Same across environments | Same across environments |
| **Subscription Budget** | `finops-sub-budget-{env}` | `finops-sub-budget-dev` | `finops-sub-budget-prod` |
| **RG Budgets** | `finops-rg-budget-{rg-name}` | `finops-rg-budget-rg-app-prod` | Auto-generated per RG |
| **Policy Definition** | `finops-audit-rg-without-budget` | Same across environments | Same across environments |

> `uniqueString(rg.id)` generates a deterministic 13-character hash from the resource group ID. This ensures globally unique names per subscription without manual naming.

---

## Tag Convention

### Required Tags (set in your .bicepparam file)

| Tag Key | Purpose | Example Value |
|---------|---------|---------------|
| `finops-platform` | Identifies platform resources | `budget-alerts-automation` |
| `managed-by` | Who manages these resources | `finops-iac` |
| `environment` | Deployment environment | `dev` / `staging` / `prod` |
| `Owner` | Responsible team or person | `FinOps-Team` |
| `CostCenter` | Billing allocation | `HybridCloud-FinOps` |

### Optional Tags (recommended for enterprise)

| Tag Key | Purpose | Used By |
|---------|---------|---------|
| `TechnicalContact1` | Primary tech contact email | Alert routing (HeadUp+) |
| `TechnicalContact2` | Secondary tech contact email | Alert routing (HeadUp+) |
| `BillingContact` | Billing responsible email | Alert routing (Warning+) |
| `CostCenter` | Business unit for cost grouping | Dashboard grouping |

### Governance Tag (optional — triggers immediate alerts)

Configure via Function App environment variables:

```
GOVERNANCE_TAG_KEY=CostCategory
GOVERNANCE_TAG_VALUE=Restricted
```

Any resource group with this tag key/value combination triggers an immediate governance notification to `GOVERNANCE_EMAIL`.

---

## Environment Strategy

| Environment | Purpose | Budget Scale | Region |
|-------------|---------|-------------|--------|
| `dev` | Development and testing | EUR 5,000 sub budget | Any (match your dev region) |
| `staging` | Pre-production validation | EUR 25,000 sub budget | Same as prod region |
| `prod` | Production monitoring | EUR 50,000+ sub budget | Primary business region |

### Parameter File Convention

```
parameters/
├── template.bicepparam     # Copy this for new environments
├── dev.bicepparam          # Development
├── staging.bicepparam      # Staging / pre-production
└── prod.bicepparam         # Production
```

For multi-subscription deployments:
```
parameters/
├── prod-subscription-a.bicepparam
├── prod-subscription-b.bicepparam
└── prod-subscription-c.bicepparam
```

---

## Cosmos DB Schema Convention

| Field | Naming | Type | Example |
|-------|--------|------|---------|
| Document ID | `{subscriptionId}_{rgName}` | string | `abc-123_rg-app-prod` |
| Partition Key | `subscriptionId` | string | `abc-123-def-456` |
| Budget fields | camelCase | number | `technicalBudget`, `financeBudget` |
| Metric fields | camelCase | number | `amortizedMTD`, `forecastEOM`, `burnRateDaily` |
| Percentage fields | camelCase + Pct | number | `actualPct`, `forecastPct` |
| Status fields | camelCase | string | `complianceStatus`: `on_track` / `at_risk` / `warning` / `over_budget` |
| Contact fields | camelCase + Email | string | `ownerEmail`, `billingContact` |
| Timestamp fields | camelCase | ISO 8601 | `lastEvaluated`, `lastSeeded` |

---

## Budget Threshold Convention

### Native Azure Budgets (actual cost safety net)

| Threshold | Type | Contacts | Action Group |
|-----------|------|----------|-------------|
| 50% | Actual | Owner only | None |
| 75% | Actual | Owner + BU Lead | Yes |
| 90% | Forecasted | All contacts | Yes |
| 100% | Actual | All contacts | Yes |
| 110% | Forecasted | All contacts | Yes |

### Amortized Cost Alerts (tiered by spend bracket)

| Spend Tier (3-month avg) | HeadUp | Warning | Critical |
|--------------------------|--------|---------|----------|
| $0 – $1K | 200% | 250% | 300% |
| $1K – $5K | 150% | 200% | 250% |
| $5K – $10K | 125% | 150% | 200% |
| Above $10K | 100% | 125% | 150% |

---

## API Endpoint Convention

All Function App endpoints follow this pattern:

```
https://{functionAppName}.azurewebsites.net/api/{endpoint}?code={functionKey}
```

| Endpoint | Method | Auth | Purpose |
|----------|--------|------|---------|
| `/api/evaluate` | GET | Function key | Trigger amortized cost evaluation |
| `/api/inventory` | GET | Function key | Read FinOps inventory (filterable) |
| `/api/variance` | GET | Function key | Finance vs Technical variance |
| `/api/update-budget` | POST | Function key | Update budget in Cosmos DB |
| `/api/backfill` | GET | Function key | Scan + create budgets for existing RGs |
| `/api/recalculate` | GET | Function key | Quarterly budget recalculation |

---

## RG Exclusion Convention

System resource groups to exclude from budget creation (configured in `scripts/config.json`):

```json
{
  "exclusions": {
    "rgPrefixes": [
      "MC_",
      "FL_",
      "MA_",
      "NetworkWatcherRG",
      "DefaultResourceGroup",
      "LogAnalyticsDefault",
      "cloud-shell-storage",
      "Default-ActivityLogAlerts"
    ]
  }
}
```

Or via Function App environment variable:
```
EXCLUDED_RG_PREFIXES=MC_,FL_,NetworkWatcherRG,DefaultResourceGroup
```
