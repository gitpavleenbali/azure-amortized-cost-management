// FinOps Budget Inventory — Power Query M Script
// Import this in Power BI: Transform Data → Advanced Editor → Paste
// ═══════════════════════════════════════════════════════════════

// === TABLE 1: FinOps Inventory ===
// Create a new query named "FinOps_Inventory" and paste:

let
    ApiUrl = "https://<YOUR_FUNCTION_APP>.azurewebsites.net/api/inventory?code=<YOUR_FUNCTION_KEY>",
    Source = Json.Document(Web.Contents(ApiUrl)),
    AsTable = Table.FromList(Source, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
    Expanded = Table.ExpandRecordColumn(AsTable, "Column1", {
        "resourceGroup", "subscriptionId", "technicalBudget", "financeBudget",
        "amortizedMTD", "forecastEOM", "actualPct", "forecastPct",
        "burnRateDaily", "complianceStatus", "costCenter", "ownerEmail",
        "lastEvaluated", "budgetName"
    }),
    // Type conversions
    Typed = Table.TransformColumnTypes(Expanded, {
        {"resourceGroup", type text},
        {"subscriptionId", type text},
        {"technicalBudget", type number},
        {"financeBudget", type number},
        {"amortizedMTD", type number},
        {"forecastEOM", type number},
        {"actualPct", type number},
        {"forecastPct", type number},
        {"burnRateDaily", type number},
        {"complianceStatus", type text},
        {"costCenter", type text},
        {"ownerEmail", type text},
        {"lastEvaluated", type datetimezone},
        {"budgetName", type text}
    }),
    // Calculated columns
    AddVariance = Table.AddColumn(Typed, "budgetVariance", each [technicalBudget] - [amortizedMTD], type number),
    AddFinanceGap = Table.AddColumn(AddVariance, "financeGap", each 
        if [financeBudget] > 0 then [financeBudget] - [technicalBudget] else null, type number),
    AddDaysRemaining = Table.AddColumn(AddFinanceGap, "daysRemaining", each 
        Duration.Days(Date.EndOfMonth(DateTime.Date(DateTime.LocalNow())) - DateTime.Date(DateTime.LocalNow())), Int64.Type),
    AddStatusIcon = Table.AddColumn(AddDaysRemaining, "statusIcon", each 
        if [complianceStatus] = "on_track" then "🟢"
        else if [complianceStatus] = "at_risk" then "🟡"
        else if [complianceStatus] = "over_budget" then "🔴"
        else "⚪", type text)
in
    AddStatusIcon


// === TABLE 2: Variance Details ===
// Create a new query named "FinOps_Variance" and paste:
/*
let
    ApiUrl = "https://<YOUR_FUNCTION_APP>.azurewebsites.net/api/variance?code=<YOUR_FUNCTION_KEY>",
    Source = Json.Document(Web.Contents(ApiUrl)),
    AsTable = Table.FromList(Source, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
    Expanded = Table.ExpandRecordColumn(AsTable, "Column1", {
        "resourceGroup", "technicalBudget", "financeBudget", "amortizedMTD",
        "forecastEOM", "technicalVariance", "financeVariance", "variancePct",
        "recommendation"
    }),
    Typed = Table.TransformColumnTypes(Expanded, {
        {"resourceGroup", type text},
        {"technicalBudget", type number},
        {"financeBudget", type number},
        {"amortizedMTD", type number},
        {"forecastEOM", type number},
        {"technicalVariance", type number},
        {"financeVariance", type number},
        {"variancePct", type number},
        {"recommendation", type text}
    })
in
    Typed
*/

// ═══════════════════════════════════════════════════════════════
// REPORT LAYOUT GUIDE
// ═══════════════════════════════════════════════════════════════
//
// PAGE 1: "Executive Overview"
// ─────────────────────────────
//   Top Row (KPI Cards):
//     • Total Technical Budget  = SUM(technicalBudget)
//     • Total Finance Budget    = SUM(financeBudget)
//     • Total Amortized Spend   = SUM(amortizedMTD)
//     • Overall Compliance %    = COUNTROWS(FILTER(FinOps_Inventory, complianceStatus="on_track")) / COUNTROWS(FinOps_Inventory)
//
//   Middle:
//     • Donut Chart: complianceStatus count (🟢🟡🔴)
//     • Clustered Bar: technicalBudget vs amortizedMTD by costCenter
//     • Stacked Bar: financeBudget vs technicalBudget by resourceGroup (top 10 by spend)
//
//   Bottom:
//     • Table: resourceGroup | statusIcon | amortizedMTD | technicalBudget | actualPct | forecastPct | ownerEmail
//
// PAGE 2: "Finance vs Technical"
// ──────────────────────────────
//     • Scatter: X=technicalBudget, Y=financeBudget, Size=amortizedMTD, Color=complianceStatus
//     • Table: RGs where financeGap <> 0 (budget misalignment)
//     • KPI: Count of RGs where finance > technical (under-budgeted)
//
// PAGE 3: "Burn Rate & Forecast"
// ──────────────────────────────
//     • Line Chart: burnRateDaily by resourceGroup (top 10)
//     • Waterfall: forecastEOM breakdown by costCenter
//     • Table: RGs where forecastPct > 100 (projected overrun)
//
// ═══════════════════════════════════════════════════════════════
