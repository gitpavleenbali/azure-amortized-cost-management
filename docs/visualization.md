# Visualization Guide — Azure Workbook + Power BI with Cosmos DB

> This platform provides **two visualization tiers**: an Azure Workbook (deployed automatically) for quick operational dashboards, and Power BI connected to Cosmos DB for deep executive reporting.

---

## Tier 1: Azure Workbook (Deployed Automatically)

The Azure Workbook is deployed as part of the infrastructure (both Option 1 and Option 2). It queries `FinOpsInventory_CL` in Log Analytics and provides:

- **Compliance pie chart** — Over Budget / Warning / On Track breakdown
- **Color-coded inventory grid** — All resource groups with budget, spend, forecast, compliance
- **Spend vs Budget heatmap** — Visual hotspots for high-variance RGs
- **Alert summary** — HeadUp (60%), Warning (80%), Critical (95%) thresholds

**How to access:**
1. Go to your resource group in the Azure Portal
2. Find the **Workbook** resource (`FinOps Budget Compliance Dashboard`)
3. Click **Open Workbook**

**Data source:** Log Analytics Workspace → `FinOpsInventory_CL` custom table  
**Refresh:** Near real-time (data synced after every evaluation cycle, daily at 06:00 UTC or on-demand via `/api/evaluate`)  
**Authentication:** Azure AD (whoever has access to the resource group can view the workbook)

**Best for:** Operational teams, daily monitoring, quick compliance checks, sharing via Azure Portal links.

---

## Tier 2: Power BI with Cosmos DB (Advanced)

For executive dashboards, trend analysis, and cross-subscription reporting, connect Power BI directly to Cosmos DB — the single source of truth for all budget and spend data.

### Why Cosmos DB for Power BI?

| Feature | Azure Workbook (Tier 1) | Power BI + Cosmos DB (Tier 2) |
|---------|------------------------|-------------------------------|
| Setup | Automatic (deployed with infra) | Manual (5-10 min setup) |
| Data source | Log Analytics (synced copy) | Cosmos DB (source of truth) |
| Refresh | Near real-time | Scheduled (30 min / on-demand) |
| Sharing | Azure Portal link | Power BI Service / embedded |
| Custom visuals | KQL-based (limited) | Full Power BI visual library |
| Drill-down | Basic filtering | Cross-filter, drill-through, bookmarks |
| Trend analysis | No (point-in-time only) | Yes (historical with scheduled refresh) |
| Executive reports | No | Yes (email subscriptions, PDF export) |
| Row-level security | Azure AD (portal access) | Power BI RLS (role-based) |

### Quick Setup (5 Minutes)

#### Option A: Connect via REST API (Recommended)

Power BI connects to the Function App's REST API — no Cosmos DB keys needed.

1. **Open Power BI Desktop** → Get Data → Web
2. **Inventory endpoint:**
   ```
   https://<YOUR_FUNCTION_APP>.azurewebsites.net/api/inventory?code=<FUNCTION_KEY>
   ```
3. **Variance endpoint (optional drill-down):**
   ```
   https://<YOUR_FUNCTION_APP>.azurewebsites.net/api/variance?code=<FUNCTION_KEY>
   ```
4. **Transform Data** → Apply the Power Query M script from [`powerbi/finops-inventory.pq`](../powerbi/finops-inventory.pq)
5. **Add DAX measures** from [`powerbi/dax-measures.dax`](../powerbi/dax-measures.dax)

> Get your Function Key: Azure Portal → Function App → App Keys → default

#### Option B: Connect Directly to Cosmos DB

For maximum performance and no Function App dependency:

1. **Open Power BI Desktop** → Get Data → Azure → Azure Cosmos DB
2. **Endpoint:** `https://<YOUR_COSMOS_ACCOUNT>.documents.azure.com:443/`
3. **Database:** `finops`
4. **Container:** `inventory`
5. **Apply Power Query M script** from [`powerbi/finops-cosmos-direct.pq`](../powerbi/finops-cosmos-direct.pq)
6. **Add DAX measures** from [`powerbi/dax-measures.dax`](../powerbi/dax-measures.dax)

> Get your Cosmos DB connection details: Azure Portal → Cosmos DB Account → Keys

For the full Cosmos DB Power Query connection template, see [`dashboards/power-bi-cosmos-connection.m`](../dashboards/power-bi-cosmos-connection.m).

### Available Power Query Templates

| File | Purpose | Data Source |
|------|---------|-------------|
| [`powerbi/finops-inventory.pq`](../powerbi/finops-inventory.pq) | Main inventory data with computed columns | REST API (`/api/inventory`) |
| [`powerbi/finops-cosmos-direct.pq`](../powerbi/finops-cosmos-direct.pq) | Direct Cosmos DB connection with typed columns | Cosmos DB (SQL API) |
| [`dashboards/power-bi-cosmos-connection.m`](../dashboards/power-bi-cosmos-connection.m) | Full M script with error handling and retry | Cosmos DB (SQL API) |

### DAX Measures

The [`powerbi/dax-measures.dax`](../powerbi/dax-measures.dax) file provides ready-to-use measures:

- **KPI Cards**: Total Technical Budget, Total Finance Budget, Total Amortized Spend, Total Forecast EOM
- **Rates**: Overall Burn Rate, Budget Utilization, Forecast Accuracy
- **Compliance**: Compliance Rate, Over Budget Count, Warning Count
- **Variance**: Finance vs Technical variance, Absolute/Percentage diffs
- **Conditional Formatting**: Color rules for status indicators

### Scheduled Refresh

1. Publish report to **Power BI Service**
2. Go to **Dataset Settings** → **Scheduled Refresh**
3. Set refresh: every 30 minutes (or daily, matching the evaluation timer)
4. Credentials: Anonymous (function key embedded in URL) or Cosmos DB key

---

## Available Query Templates

For ad-hoc analysis outside Power BI:

| File | Language | Purpose |
|------|----------|---------|
| [`queries/budget-compliance.kql`](../queries/budget-compliance.kql) | KQL | Azure Resource Graph — compliance audit across subscriptions |
| [`queries/cosmos-demo-queries.sql`](../queries/cosmos-demo-queries.sql) | SQL (Cosmos) | Sample Cosmos DB queries for inventory exploration |
| [`queries/spend-vs-budget.sql`](../queries/spend-vs-budget.sql) | SQL (Cosmos) | Spend vs budget comparison with rollups |

### Example: Cosmos DB SQL Query

```sql
-- Top 10 resource groups by spend-to-budget ratio
SELECT TOP 10
    c.resourceGroup,
    c.technicalBudget,
    c.amortizedMTD,
    c.actualPct,
    c.complianceStatus
FROM c
WHERE c.technicalBudget > 0
ORDER BY c.actualPct DESC
```

### Example: KQL for Log Analytics

```kql
// Compliance summary from FinOpsInventory_CL
FinOpsInventory_CL
| summarize
    OnTrack = countif(complianceStatus_s == "on_track"),
    Warning = countif(complianceStatus_s == "warning"),
    OverBudget = countif(complianceStatus_s == "over_budget")
| extend Total = OnTrack + Warning + OverBudget
| extend ComplianceRate = round(100.0 * OnTrack / Total, 1)
```

---

## Summary

| Need | Use | Setup |
|------|-----|-------|
| Quick operational dashboard | **Azure Workbook** (Tier 1) | Automatic — deployed with infrastructure |
| Executive reporting | **Power BI + Cosmos DB** (Tier 2) | 5-10 min — follow steps above |
| Ad-hoc queries | **KQL / Cosmos SQL** | Use query templates in `queries/` folder |
| Cross-subscription view | **Power BI + REST API** | Connect multiple Function App endpoints |
