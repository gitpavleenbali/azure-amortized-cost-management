# Power BI — FinOps Budget Dashboard

## Quick Setup (5 minutes)

### Step 1: Open Power BI Desktop
1. Open Power BI Desktop
2. Click **Get Data** → **Web**

### Step 2: Connect to the FinOps Inventory API

**Inventory (main data):**
```
https://<YOUR_FUNCTION_APP>.azurewebsites.net/api/inventory?code=<FUNCTION_APP_KEY>
```

**Variance (drill-down):**
```
https://<YOUR_FUNCTION_APP>.azurewebsites.net/api/variance?code=<FUNCTION_APP_KEY>
```

### Step 3: Transform Data (Power Query)
Click **Transform Data** and apply the M query below.

### Step 4: Build Visuals
Use the report layout guide in `powerbi-setup.pq` comments.

---

## Alternative: Direct Cosmos DB Connection

If you prefer direct Cosmos DB access:
1. **Get Data** → **Azure** → **Azure Cosmos DB**
2. Endpoint: `https://<YOUR_COSMOS_ACCOUNT>.documents.azure.com:443/`
3. Database: `finops`
4. Container: `inventory`
5. Use the account key from Azure Portal

**Advantage:** No function app dependency, Power BI pulls directly from Cosmos.  
**Disadvantage:** Need to manage key rotation.

---

## Scheduled Refresh

1. Publish to Power BI Service
2. Go to Dataset Settings → Scheduled Refresh
3. Set refresh frequency: **Every 30 minutes** (or on-demand)
4. Data source credentials: **Anonymous** (the function key is in the URL)

---

## Data Dictionary

| Column | Type | Description |
|--------|------|-------------|
| resourceGroup | text | Resource group name |
| subscriptionId | text | Azure subscription ID |
| technicalBudget | number | Azure budget amount (EUR) |
| financeBudget | number | Finance-approved budget (EUR) |
| amortizedMTD | number | Month-to-date amortized cost |
| forecastEOM | number | End-of-month forecast |
| actualPct | number | Actual spend vs budget (%) |
| forecastPct | number | Forecast vs budget (%) |
| burnRateDaily | number | Daily burn rate (EUR/day) |
| complianceStatus | text | on_track / at_risk / over_budget / not_evaluated |
| costCenter | text | Business unit / cost center |
| ownerEmail | text | RG owner email |
| lastEvaluated | datetime | Last evaluation timestamp |
