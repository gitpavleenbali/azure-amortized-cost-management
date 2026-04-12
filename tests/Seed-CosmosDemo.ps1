# Seed-CosmosDemo.ps1 — Insert demo data into Cosmos DB FinOps Inventory
# Requires: Az CLI logged in, Contributor on the RG

param(
    [string]$CosmosAccountName = "<YOUR_COSMOS_ACCOUNT>",
    [string]$ResourceGroupName = "<YOUR_RESOURCE_GROUP>",
    [string]$DatabaseName = "finops",
    [string]$ContainerName = "inventory"
)

$subId = "00000000-0000-0000-0000-000000000000"
$key = (az cosmosdb keys list -g $ResourceGroupName -n $CosmosAccountName --query "primaryMasterKey" -o tsv 2>$null)
$endpoint = "https://$CosmosAccountName.documents.azure.com"

function New-CosmosAuthHeader {
    param([string]$verb, [string]$resourceType, [string]$resourceLink, [string]$key, [string]$date)
    $hmacSha256 = New-Object System.Security.Cryptography.HMACSHA256
    $hmacSha256.Key = [System.Convert]::FromBase64String($key)
    $payload = "$($verb.ToLower())`n$($resourceType.ToLower())`n$resourceLink`n$($date.ToLower())`n`n"
    $hash = $hmacSha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($payload))
    $sig = [System.Convert]::ToBase64String($hash)
    return [System.Web.HttpUtility]::UrlEncode("type=master&ver=1.0&sig=$sig")
}

Add-Type -AssemblyName System.Web

$docs = @(
    @{id="${subId}_rg-imaging-prod"; subscriptionId=$subId; resourceGroup="rg-imaging-prod"; technicalBudget=15000; financeBudget=18000; budgetName="finops-rg-budget-rg-imaging-prod"; ownerEmail="imaging-lead@example.com"; costCenter="BU-Imaging"; amortizedMTD=16200; forecastEOM=19440; burnRateDaily=623; actualPct=108; forecastPct=129.6; complianceStatus="over_budget"; lastEvaluated="2026-03-26T06:00:00Z"},
    @{id="${subId}_rg-diagnostics-prod"; subscriptionId=$subId; resourceGroup="rg-diagnostics-prod"; technicalBudget=8000; financeBudget=10000; budgetName="finops-rg-budget-rg-diagnostics-prod"; ownerEmail="diag-lead@example.com"; costCenter="BU-Diagnostics"; amortizedMTD=7200; forecastEOM=8640; burnRateDaily=277; actualPct=90; forecastPct=108; complianceStatus="warning"; lastEvaluated="2026-03-26T06:00:00Z"},
    @{id="${subId}_rg-ai-research-dev"; subscriptionId=$subId; resourceGroup="rg-ai-research-dev"; technicalBudget=5000; financeBudget=5000; budgetName="finops-rg-budget-rg-ai-research-dev"; ownerEmail="ai-team@example.com"; costCenter="BU-Research"; amortizedMTD=2100; forecastEOM=2520; burnRateDaily=81; actualPct=42; forecastPct=50.4; complianceStatus="on_track"; lastEvaluated="2026-03-26T06:00:00Z"},
    @{id="${subId}_rg-ehr-platform-prod"; subscriptionId=$subId; resourceGroup="rg-ehr-platform-prod"; technicalBudget=25000; financeBudget=22000; budgetName="finops-rg-budget-rg-ehr-platform-prod"; ownerEmail="ehr-lead@example.com"; costCenter="BU-Healthcare-IT"; amortizedMTD=19500; forecastEOM=23400; burnRateDaily=750; actualPct=78; forecastPct=93.6; complianceStatus="warning"; lastEvaluated="2026-03-26T06:00:00Z"},
    @{id="${subId}_rg-data-analytics-staging"; subscriptionId=$subId; resourceGroup="rg-data-analytics-staging"; technicalBudget=3000; financeBudget=3500; budgetName="finops-rg-budget-rg-data-analytics-staging"; ownerEmail="analytics@example.com"; costCenter="BU-Analytics"; amortizedMTD=1800; forecastEOM=2160; burnRateDaily=69; actualPct=60; forecastPct=72; complianceStatus="on_track"; lastEvaluated="2026-03-26T06:00:00Z"},
    @{id="${subId}_rg-mobile-app-dev"; subscriptionId=$subId; resourceGroup="rg-mobile-app-dev"; technicalBudget=100; financeBudget=0; budgetName="finops-rg-budget-rg-mobile-app-dev"; ownerEmail="mobile-dev@example.com"; costCenter="BU-Digital"; amortizedMTD=45; forecastEOM=54; burnRateDaily=1.7; actualPct=45; forecastPct=54; complianceStatus="on_track"; lastEvaluated="2026-03-26T06:00:00Z"},
    @{id="${subId}_rg-security-tools-prod"; subscriptionId=$subId; resourceGroup="rg-security-tools-prod"; technicalBudget=12000; financeBudget=12000; budgetName="finops-rg-budget-rg-security-tools-prod"; ownerEmail="sec-ops@example.com"; costCenter="BU-Security"; amortizedMTD=11400; forecastEOM=13680; burnRateDaily=438; actualPct=95; forecastPct=114; complianceStatus="over_budget"; lastEvaluated="2026-03-26T06:00:00Z"},
    @{id="${subId}_rg-backup-infra-prod"; subscriptionId=$subId; resourceGroup="rg-backup-infra-prod"; technicalBudget=2000; financeBudget=2500; budgetName="finops-rg-budget-rg-backup-infra-prod"; ownerEmail="infra-team@example.com"; costCenter="BU-Infrastructure"; amortizedMTD=1650; forecastEOM=1980; burnRateDaily=63; actualPct=82.5; forecastPct=99; complianceStatus="warning"; lastEvaluated="2026-03-26T06:00:00Z"}
)

$seeded = 0
$resourceLink = "dbs/$DatabaseName/colls/$ContainerName"

foreach ($doc in $docs) {
    $body = $doc | ConvertTo-Json -Depth 5
    $date = [DateTime]::UtcNow.ToString("R")
    $auth = New-CosmosAuthHeader -verb "POST" -resourceType "docs" -resourceLink $resourceLink -key $key -date $date

    $headers = @{
        "Authorization"                    = $auth
        "x-ms-date"                        = $date
        "x-ms-version"                     = "2018-12-31"
        "x-ms-documentdb-is-upsert"        = "true"
        "x-ms-documentdb-partitionkey"     = "[$([char]34)$subId$([char]34)]"
        "Content-Type"                     = "application/json"
    }

    $uri = "$endpoint/$resourceLink/docs"

    try {
        $resp = Invoke-RestMethod -Uri $uri -Method POST -Headers $headers -Body $body -ErrorAction Stop
        Write-Host "OK: $($doc.resourceGroup) - $($doc.complianceStatus)" -ForegroundColor Green
        $seeded++
    } catch {
        Write-Host "FAILED: $($doc.resourceGroup) - $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`nSeeded $seeded / $($docs.Count) documents into Cosmos DB" -ForegroundColor Cyan
