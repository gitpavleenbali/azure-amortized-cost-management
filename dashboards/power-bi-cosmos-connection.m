// ============================================================
// Power BI — Cosmos DB Connection for FinOps Dashboard
// ============================================================
// This file contains the M (Power Query) scripts to connect
// Power BI Desktop to the Cosmos DB FinOps Inventory.
//
// Option A: Direct Cosmos DB connector (recommended)
// Option B: Web API via Function App /api/inventory endpoint
//
// Setup: Power BI Desktop → Get Data → Azure Cosmos DB / Web
// ============================================================


// ────────────────────────────────────────────────────────────
// OPTION A: Cosmos DB NoSQL Direct Connector (Recommended)
// ────────────────────────────────────────────────────────────
// 1. Open Power BI Desktop
// 2. Get Data → Azure → Azure Cosmos DB v1 (or "Azure Cosmos DB for NoSQL")
// 3. Endpoint: https://<YOUR_COSMOS_ACCOUNT>.documents.azure.com:443/
// 4. Database: finops
// 5. Use Account Key from Azure Portal → Cosmos DB → Keys
// 6. Select the "inventory" container
// 7. Once loaded, use the M query below to expand the JSON documents


// ── M Query: FinOps Inventory (main table) ───────────────────
// Paste in Advanced Editor after connecting to Cosmos DB
//
// let
//     Source = DocumentDB.Contents(
//         "https://<YOUR_COSMOS_ACCOUNT>.documents.azure.com:443/",
//         "finops",
//         "inventory"
//     ),
//     Expanded = Table.ExpandRecordColumn(
//         Source, "Document",
//         {"id", "subscriptionId", "resourceGroup", "technicalBudget",
//          "financeBudget", "amortizedMTD", "forecastEOM", "burnRateDaily",
//          "complianceStatus", "ownerEmail", "costCenter",
//          "lastEvaluated", "financeBudgetSetBy", "costCenter"},
//         {"id", "subscriptionId", "resourceGroup", "technicalBudget",
//          "financeBudget", "amortizedMTD", "forecastEOM", "burnRateDaily",
//          "complianceStatus", "ownerEmail", "costCenter",
//          "lastEvaluated", "financeBudgetSetBy", "costCenter.1"}
//     ),
//     TypedColumns = Table.TransformColumnTypes(Expanded, {
//         {"technicalBudget", type number},
//         {"financeBudget", type number},
//         {"amortizedMTD", type number},
//         {"forecastEOM", type number},
//         {"burnRateDaily", type number}
//     }),
//     AddedVariance = Table.AddColumn(TypedColumns, "VarianceEUR",
//         each [amortizedMTD] - (if [financeBudget] > 0 then [financeBudget] else [technicalBudget]),
//         type number
//     ),
//     AddedPct = Table.AddColumn(AddedVariance, "UsagePct",
//         each if ([technicalBudget] > 0 or [financeBudget] > 0) then
//             [amortizedMTD] / (if [financeBudget] > 0 then [financeBudget] else [technicalBudget]) * 100
//         else 0,
//         type number
//     ),
//     AddedStatus = Table.AddColumn(AddedPct, "TrafficLight",
//         each if [complianceStatus] = "over_budget" then "Red"
//              else if [complianceStatus] = "warning" then "Amber"
//              else if [complianceStatus] = "on_track" then "Green"
//              else "Grey",
//         type text
//     )
// in
//     AddedStatus


// ────────────────────────────────────────────────────────────
// OPTION B: Web API Connector (Function App)
// ────────────────────────────────────────────────────────────
// 1. Power BI Desktop → Get Data → Web
// 2. URL: https://<YOUR_FUNCTION_APP>.azurewebsites.net/api/inventory?code=<YOUR_FUNCTION_KEY>
// 3. Power BI will auto-detect JSON list → convert to table


// ── M Query: Inventory via Web API ───────────────────────────
//
// let
//     Source = Json.Document(
//         Web.Contents(
//             "https://<YOUR_FUNCTION_APP>.azurewebsites.net/api/inventory",
//             [Query = [code = "<YOUR_FUNCTION_KEY>"]]
//         )
//     ),
//     AsTable = Table.FromList(Source, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
//     Expanded = Table.ExpandRecordColumn(AsTable, "Column1",
//         {"subscriptionId", "resourceGroup", "technicalBudget", "financeBudget",
//          "amortizedMTD", "forecastEOM", "complianceStatus", "ownerEmail", "costCenter"}
//     ),
//     Typed = Table.TransformColumnTypes(Expanded, {
//         {"technicalBudget", type number}, {"financeBudget", type number},
//         {"amortizedMTD", type number}, {"forecastEOM", type number}
//     })
// in
//     Typed


// ── M Query: Variance Report via Web API ─────────────────────
//
// let
//     Source = Json.Document(
//         Web.Contents(
//             "https://<YOUR_FUNCTION_APP>.azurewebsites.net/api/variance",
//             [Query = [code = "<YOUR_FUNCTION_KEY>"]]
//         )
//     ),
//     AsTable = Table.FromList(Source, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
//     Expanded = Table.ExpandRecordColumn(AsTable, "Column1",
//         {"subscriptionId", "resourceGroup", "financeBudget", "technicalBudget",
//          "amortizedMTD", "forecastEOM", "financeVariance", "technicalVariance",
//          "financeVariancePct", "status", "owner", "costCenter"}
//     ),
//     Typed = Table.TransformColumnTypes(Expanded, {
//         {"financeBudget", type number}, {"technicalBudget", type number},
//         {"amortizedMTD", type number}, {"forecastEOM", type number},
//         {"financeVariance", type number}, {"technicalVariance", type number},
//         {"financeVariancePct", type number}
//     })
// in
//     Typed


// ────────────────────────────────────────────────────────────
// RECOMMENDED DASHBOARD PAGES
// ────────────────────────────────────────────────────────────
//
// PAGE 1: Executive Overview
//   - Card: Total Budget | Total Spend | Variance | # Over Budget
//   - Donut: Compliance Status (Green/Amber/Red/Grey)
//   - Bar Chart: Top 10 RGs by spend (stacked: amortized vs budget)
//
// PAGE 2: Finance vs Technical
//   - Clustered Bar: Finance Budget vs Technical Budget vs Amortized MTD per RG
//   - Table: Resource Group | Finance | Technical | Amortized | Variance | Status
//   - KPI: Total finance variance EUR
//
// PAGE 3: Trend & Forecast
//   - Line chart: Daily burn rate per RG (if historical data available)
//   - Gauge: Forecast EOM vs Budget per RG
//   - Table: RGs projected to exceed budget
//
// PAGE 4: Ownership & Cost Center
//   - Matrix: Cost Center → RG → Budget → Spend
//   - Slicer: Owner, Cost Center, Compliance Status
//
// ────────────────────────────────────────────────────────────
// SCHEDULED REFRESH
// ────────────────────────────────────────────────────────────
// Power BI Service: Dataset Settings → Scheduled Refresh
// Frequency: Every 30 minutes (Pro license) or 15 min (Premium)
// Gateway: Not required for Cosmos DB direct / Web API (cloud-to-cloud)
//
// ────────────────────────────────────────────────────────────
// DAX MEASURES (add in Power BI Model view)
// ────────────────────────────────────────────────────────────
//
// Total Budget = SUM(Inventory[technicalBudget]) + SUM(Inventory[financeBudget])
// Total Spend = SUM(Inventory[amortizedMTD])
// Total Variance = [Total Spend] - [Total Budget]
// Over Budget Count = COUNTROWS(FILTER(Inventory, Inventory[complianceStatus] = "over_budget"))
// Avg Burn Rate = AVERAGE(Inventory[burnRateDaily])
// Forecast Overrun = COUNTROWS(FILTER(Inventory, Inventory[forecastEOM] > Inventory[technicalBudget]))
