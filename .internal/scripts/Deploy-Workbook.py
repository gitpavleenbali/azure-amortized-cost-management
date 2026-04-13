"""
Build or update the FinOps Budget & Cost Governance Azure Workbook.

Usage:
  python Deploy-Workbook.py --subscription-id <SUB> --resource-group <RG> --workbook-id <GUID>

Generates the workbook JSON and deploys via Azure REST API.
Requires: az CLI logged in with appropriate permissions.

This script is the source of truth for the workbook definition.
Edit the KQL queries here, then re-run to update the workbook in Azure.
"""

import json
import subprocess
import sys
import argparse
import uuid


def build_workbook(sub_id: str, rg: str, law_name: str = "law-finops-budget") -> dict:
    law_id = f"/subscriptions/{sub_id}/resourceGroups/{rg}/providers/Microsoft.OperationalInsights/workspaces/{law_name}"

    # externaldata preamble — all queries share this to read live from Function App API
    EXT = "let inv = externaldata(resourceGroup:string, subscriptionId:string, technicalBudget:real, financeBudget:real, amortizedMTD:real, forecastEOM:real, actualPct:real, forecastPct:real, burnRateDaily:real, complianceStatus:string, costCenter:string, ownerEmail:string, spendTier:string, technicalContact1:string, technicalContact2:string, billingContact:string, BillingElement:string, lastEvaluated:string)['https://FUNCTION_APP_PLACEHOLDER.azurewebsites.net/api/inventory?code=FUNCTION_KEY_PLACEHOLDER'] with (format='multijson');\\n"

    items = [
        {
            "type": 1,
            "content": {"json": "# FinOps Budget & Cost Governance\n---\n> **Live dashboard** \u2014 Data sourced from Cosmos DB via Function App API.  \n> **Two-layer alerting:** Native Azure budgets (actual cost, safety net) + Function App engine (amortized cost, tiered thresholds)."},
            "name": "title"
        },
        {
            "type": 3,
            "content": {
                "version": "KqlItem/1.0",
                "query": EXT + "inv\\n| summarize\\n    ['Total RGs'] = count(),\\n    ['On Track'] = countif(complianceStatus == 'on_track'),\\n    ['At Risk'] = countif(complianceStatus == 'at_risk' or complianceStatus == 'warning'),\\n    ['Over Budget'] = countif(complianceStatus == 'over_budget')\\n| extend ['Compliance %'] = round(todecimal(['On Track']) / todecimal(['Total RGs']) * 100, 1)",
                "size": 4, "title": "Budget Compliance",
                "queryType": 0, "resourceType": "microsoft.operationalinsights/workspaces",
                "crossComponentResources": [law_id],
                "visualization": "tiles", "tileSettings": {"showBorder": True}
            },
            "customWidth": "50", "name": "kpi-compliance"
        },
        {
            "type": 3,
            "content": {
                "version": "KqlItem/1.0",
                "query": EXT + "inv\\n| summarize\\n    ['Tech Budget Total'] = round(sum(technicalBudget), 0),\\n    ['Finance Budget Total'] = round(sum(financeBudget), 0),\\n    ['Amortized Spend MTD'] = round(sum(amortizedMTD), 0),\\n    ['Forecast EOM'] = round(sum(forecastEOM), 0)",
                "size": 4, "title": "Budget Totals (EUR)",
                "queryType": 0, "resourceType": "microsoft.operationalinsights/workspaces",
                "crossComponentResources": [law_id],
                "visualization": "tiles", "tileSettings": {"showBorder": True}
            },
            "customWidth": "50", "name": "kpi-totals"
        },
        {
            "type": 1,
            "content": {"json": "---\n## Compliance Status"},
            "name": "sec-compliance"
        },
        {
            "type": 3,
            "content": {
                "version": "KqlItem/1.0",
                "query": EXT + "inv\\n| summarize Count=count() by complianceStatus\\n| extend Status = case(\\n    complianceStatus == 'on_track', 'On Track',\\n    complianceStatus == 'at_risk' or complianceStatus == 'warning', 'At Risk',\\n    complianceStatus == 'over_budget', 'Over Budget',\\n    'Not Evaluated')",
                "size": 2, "title": "Compliance Breakdown",
                "queryType": 0, "resourceType": "microsoft.operationalinsights/workspaces",
                "crossComponentResources": [law_id],
                "visualization": "piechart"
            },
            "customWidth": "40", "name": "compliance-pie"
        },
        {
            "type": 3,
            "content": {
                "version": "KqlItem/1.0",
                "query": EXT + "inv\\n| where isnotempty(costCenter)\\n| summarize\\n    ['Tech Budget'] = round(sum(technicalBudget), 0),\\n    ['Finance Budget'] = round(sum(financeBudget), 0),\\n    ['Amortized MTD'] = round(sum(amortizedMTD), 0),\\n    ['Forecast EOM'] = round(sum(forecastEOM), 0)\\n  by ['Business Unit'] = costCenter\\n| extend ['Variance'] = ['Amortized MTD'] - ['Tech Budget']\\n| extend ['Variance %'] = iff(['Tech Budget'] > 0, round(todecimal(['Variance']) / todecimal(['Tech Budget']) * 100, 1), 0.0)\\n| order by ['Variance %'] desc",
                "size": 0, "title": "Finance vs Technical Variance by Business Unit",
                "queryType": 0, "resourceType": "microsoft.operationalinsights/workspaces",
                "crossComponentResources": [law_id],
                "visualization": "table",
                "gridSettings": {"formatters": [
                    {"columnMatch": "Variance %", "formatter": 8, "formatOptions": {"min": -50, "max": 50, "palette": "greenRed"}},
                    {"columnMatch": "Variance", "formatter": 0, "numberFormat": {"unit": 0, "options": {"style": "decimal", "maximumFractionDigits": 0}}}
                ]}
            },
            "customWidth": "60", "name": "bu-variance"
        },
        {
            "type": 1,
            "content": {"json": "---\n## FinOps Inventory \u2014 Full Detail\n*Amortized cost data from daily Function App evaluation. Budgets compared against amortized spend, not actual cost.*"},
            "name": "sec-inventory"
        },
        {
            "type": 3,
            "content": {
                "version": "KqlItem/1.0",
                "query": EXT + "inv\\n| project\\n    ['Resource Group'] = resourceGroup,\\n    ['Tier'] = spendTier,\\n    ['Tech Budget'] = technicalBudget,\\n    ['Finance Budget'] = financeBudget,\\n    ['Amortized MTD'] = amortizedMTD,\\n    ['Forecast EOM'] = forecastEOM,\\n    ['Actual %'] = actualPct,\\n    ['Forecast %'] = forecastPct,\\n    ['Burn/Day'] = burnRateDaily,\\n    ['Status'] = complianceStatus,\\n    ['Owner'] = ownerEmail,\\n    ['Cost Center'] = costCenter\\n| order by ['Actual %'] desc",
                "size": 0, "title": "All Resource Groups \u2014 Budget vs Amortized Spend",
                "queryType": 0, "resourceType": "microsoft.operationalinsights/workspaces",
                "crossComponentResources": [law_id],
                "visualization": "table",
                "gridSettings": {"formatters": [
                    {"columnMatch": "Actual %", "formatter": 8, "formatOptions": {"min": 0, "max": 150, "palette": "greenRed"}},
                    {"columnMatch": "Forecast %", "formatter": 8, "formatOptions": {"min": 0, "max": 150, "palette": "greenRed"}},
                    {"columnMatch": "Status", "formatter": 18, "formatOptions": {"thresholdsOptions": "icons", "thresholdsGrid": [
                        {"operator": "==", "thresholdValue": "on_track", "representation": "success", "text": "On Track"},
                        {"operator": "==", "thresholdValue": "warning", "representation": "2", "text": "At Risk"},
                        {"operator": "==", "thresholdValue": "at_risk", "representation": "2", "text": "At Risk"},
                        {"operator": "==", "thresholdValue": "over_budget", "representation": "4", "text": "Over Budget"},
                        {"operator": "Default", "representation": "unknown", "text": "{0}"}
                    ]}}
                ]}
            },
            "name": "full-inventory"
        },
        {
            "type": 1,
            "content": {"json": "---\n## Platform Components & Native Azure Budgets"},
            "name": "sec-platform"
        },
        {
            "type": 3,
            "content": {
                "version": "KqlItem/1.0",
                "query": f"resources\n| where type =~ 'microsoft.consumption/budgets'\n| where subscriptionId == '{sub_id}'\n| extend budgetAmount = toreal(properties.amount)\n| extend currentSpend = toreal(properties.currentSpend.amount)\n| extend usedPct = iff(budgetAmount > 0, round(currentSpend / budgetAmount * 100, 1), 0.0)\n| extend rgScope = iff(tostring(properties.scope) contains 'resourceGroups', tostring(split(tostring(properties.scope), '/')[4]), 'Subscription')\n| project ['Budget']=name, ['Scope']=rgScope, ['Limit']=budgetAmount, ['Spend']=currentSpend, ['Used %']=usedPct\n| order by ['Used %'] desc",
                "size": 0, "title": "Azure Native Budgets (Actual Cost \u2014 Safety Net)",
                "queryType": 1, "resourceType": "microsoft.resourcegraph/resources",
                "crossComponentResources": [f"/subscriptions/{sub_id}"],
                "visualization": "table",
                "gridSettings": {"formatters": [{"columnMatch": "Used %", "formatter": 8, "formatOptions": {"min": 0, "max": 150, "palette": "greenRed"}}]}
            },
            "customWidth": "50", "name": "native-budgets"
        },
        {
            "type": 3,
            "content": {
                "version": "KqlItem/1.0",
                "query": f"resources\n| where resourceGroup == '{rg}'\n| extend Status = case(type =~ 'microsoft.logic/workflows', tostring(properties.state), type =~ 'microsoft.web/sites', tostring(properties.state), type =~ 'microsoft.documentdb/databaseaccounts', tostring(properties.provisioningState), 'Active')\n| project ['Name']=name, ['Type']=tostring(split(type, '/')[1]), ['Status']=Status\n| order by Type asc",
                "size": 0, "title": "FinOps Platform Components",
                "queryType": 1, "resourceType": "microsoft.resourcegraph/resources",
                "crossComponentResources": [f"/subscriptions/{sub_id}"],
                "visualization": "table",
                "gridSettings": {"formatters": [{"columnMatch": "Status", "formatter": 18, "formatOptions": {"thresholdsOptions": "icons", "thresholdsGrid": [
                    {"operator": "==", "thresholdValue": "Enabled", "representation": "success", "text": "Enabled"},
                    {"operator": "==", "thresholdValue": "Running", "representation": "success", "text": "Running"},
                    {"operator": "==", "thresholdValue": "Succeeded", "representation": "success", "text": "Succeeded"},
                    {"operator": "Default", "representation": "warning", "text": "{0}"}
                ]}}]}
            },
            "customWidth": "50", "name": "platform-health"
        }
    ]

    wb_content = json.dumps({"version": "Notebook/1.0", "items": items, "isLocked": False, "fallbackResourceIds": [law_id]})
    return {
        "location": "eastus",
        "tags": {"finops-platform": "budget-alerts-automation", "managed-by": "microsoft-csa", "hidden-title": "FinOps Budget & Cost Governance"},
        "kind": "shared",
        "properties": {"displayName": "FinOps Budget & Cost Governance", "serializedData": wb_content, "version": "1.0", "sourceId": law_id, "category": "workbook"}
    }


def main():
    parser = argparse.ArgumentParser(description="Deploy FinOps Azure Workbook")
    parser.add_argument("--subscription-id", required=True)
    parser.add_argument("--resource-group", required=True)
    parser.add_argument("--workbook-id", default=str(uuid.uuid4()), help="Workbook GUID (reuse to update)")
    parser.add_argument("--law-name", default="law-finops-budget")
    parser.add_argument("--dry-run", action="store_true", help="Output JSON without deploying")
    args = parser.parse_args()

    wb = build_workbook(args.subscription_id, args.resource_group, args.law_name)

    if args.dry_run:
        print(json.dumps(wb, indent=2))
        return

    # Write to temp and deploy
    tmp = f"C:\\temp\\workbook-deploy-{args.workbook_id[:8]}.json"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(wb, f)

    url = f"/subscriptions/{args.subscription_id}/resourceGroups/{args.resource_group}/providers/Microsoft.Insights/workbooks/{args.workbook_id}?api-version=2023-06-01"
    result = subprocess.run(
        ["az", "rest", "--method", "PUT", "--url", url, "--body", f"@{tmp}", "--query", "properties.displayName", "-o", "tsv"],
        capture_output=True, text=True
    )
    if result.returncode == 0:
        print(f"OK: {result.stdout.strip()} (GUID: {args.workbook_id})")
    else:
        print(f"ERROR: {result.stderr.strip()}")
        sys.exit(1)


if __name__ == "__main__":
    main()
