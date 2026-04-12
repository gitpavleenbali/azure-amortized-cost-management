// FinOps Inventory — Cosmos DB Direct Connection (Power Query M)
// Use this in Power BI: Transform Data → Advanced Editor → Paste this entire script
// ═══════════════════════════════════════════════════════════════
//
// IMPORTANT: After connecting to Cosmos DB, go to Transform Data →
// click "Advanced Editor" → DELETE everything → PASTE this script → Done
//

let
    // Step 1: Connect to Cosmos DB
    Source = DocumentDB.Contents(
        "https://<YOUR_COSMOS_ACCOUNT>.documents.azure.com:443/",
        "finops",
        "inventory",
        [
            Query = "SELECT c.resourceGroup, c.subscriptionId, c.technicalBudget, c.financeBudget, c.amortizedMTD, c.forecastEOM, c.actualPct, c.forecastPct, c.burnRateDaily, c.complianceStatus, c.costCenter, c.ownerEmail, c.lastEvaluated, c.budgetName, c.financeBudgetSetBy FROM c WHERE c.subscriptionId != null ORDER BY c.resourceGroup",
            MaxItems = 5000
        ]
    ),

    // Step 2: Set column types
    Typed = Table.TransformColumnTypes(Source, {
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
        {"lastEvaluated", type text},
        {"budgetName", type text},
        {"financeBudgetSetBy", type text}
    }),

    // Step 3: Add calculated columns
    AddVariance = Table.AddColumn(Typed, "Budget Variance (EUR)", each [technicalBudget] - [amortizedMTD], type number),
    AddFinanceGap = Table.AddColumn(AddVariance, "Finance Gap (EUR)", each
        if [financeBudget] > 0 then [financeBudget] - [technicalBudget] else null, type number),
    AddStatusIcon = Table.AddColumn(AddFinanceGap, "Status", each
        if [complianceStatus] = "on_track" then "On Track"
        else if [complianceStatus] = "at_risk" or [complianceStatus] = "warning" then "At Risk"
        else if [complianceStatus] = "over_budget" then "Over Budget"
        else "Not Evaluated", type text),

    // Step 4: Rename columns for clean display
    Renamed = Table.RenameColumns(AddStatusIcon, {
        {"resourceGroup", "Resource Group"},
        {"technicalBudget", "Technical Budget (EUR)"},
        {"financeBudget", "Finance Budget (EUR)"},
        {"amortizedMTD", "Amortized MTD (EUR)"},
        {"forecastEOM", "Forecast EOM (EUR)"},
        {"actualPct", "Actual %"},
        {"forecastPct", "Forecast %"},
        {"burnRateDaily", "Burn Rate/Day (EUR)"},
        {"costCenter", "Business Unit"},
        {"ownerEmail", "Owner"},
        {"complianceStatus", "Compliance Code"}
    })
in
    Renamed
