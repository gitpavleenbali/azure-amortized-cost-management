<#
.SYNOPSIS
    Seeds the FinOps Inventory in Cosmos DB from existing Azure Consumption budgets.

.DESCRIPTION
    Scans all subscriptions for finops-* budgets and populates the Cosmos DB inventory.
    This is the central source of truth for the FinOps Inventory Engine.
    
    Cosmos Document Schema:
      id                = "{subscriptionId}_{rgName}"
      subscriptionId    = subscription ID (partition key)
      resourceGroup     = RG name (lowercase)
      technicalBudget   = budget amount from Azure Consumption API
      financeBudget     = 0 (set separately by finance team via Set-FinanceBudget.ps1)
      budgetName        = Azure budget resource name
      ownerEmail        = from budget notification contacts
      costCenter        = from RG tags
      amortizedMTD      = 0 (updated daily by Function)
      forecastEOM       = 0 (updated daily by Function)
      complianceStatus  = "not_evaluated" (updated daily by Function)
      lastSeeded        = timestamp

.EXAMPLE
    .\Initialize-BudgetTable.ps1 -CosmosEndpoint "https://cosmos-finops-xxx.documents.azure.com:443/" -CosmosDatabaseName "finops"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$CosmosEndpoint,
    [string]$CosmosDatabaseName = "finops",
    [string]$CosmosContainerName = "inventory",
    # Legacy params kept for backward compatibility
    [string]$StorageAccountName = "",
    [string]$StorageAccountResourceGroup = "",
    [string]$TableName = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "`n  FinOps Inventory Seed (Cosmos DB)" -ForegroundColor Cyan
Write-Host "  ==================================" -ForegroundColor Cyan
Write-Host "  Endpoint: $CosmosEndpoint"
Write-Host "  Database: $CosmosDatabaseName / $CosmosContainerName"

# Get access token for Cosmos DB
$token = (Get-AzAccessToken -ResourceUrl "https://cosmos.azure.com").Token
$headers = @{
    "Authorization" = "type=aad&ver=1.0&sig=$token"
    "Content-Type"  = "application/json"
    "x-ms-version"  = "2018-12-31"
}

$subscriptions = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" }
$seeded = 0

foreach ($sub in $subscriptions) {
    Set-AzContext -SubscriptionId $sub.Id -ErrorAction SilentlyContinue | Out-Null
    $mgmtToken = (Get-AzAccessToken -ResourceUrl "https://management.azure.com").Token
    $uri = "https://management.azure.com/subscriptions/$($sub.Id)/providers/Microsoft.Consumption/budgets?api-version=2023-11-01"

    try {
        $resp = Invoke-RestMethod -Uri $uri -Method GET -Headers @{ Authorization = "Bearer $mgmtToken" } -ErrorAction SilentlyContinue

        foreach ($budget in $resp.value) {
            $rgName = ""
            if ($budget.id -match "/resourceGroups/([^/]+)/") { $rgName = $Matches[1] }
            if (-not $rgName) { continue }

            $ownerEmail = "finops@example.com"
            $notifs = $budget.properties.notifications
            if ($notifs) {
                $first = $notifs.PSObject.Properties | Select-Object -First 1
                if ($first -and $first.Value.contactEmails) { $ownerEmail = $first.Value.contactEmails[0] }
            }

            # Get CostCenter from RG tags
            $costCenter = ""
            try {
                $rgObj = Get-AzResourceGroup -Name $rgName -ErrorAction SilentlyContinue
                if ($rgObj -and $rgObj.Tags -and $rgObj.Tags.ContainsKey("CostCenter")) {
                    $costCenter = $rgObj.Tags["CostCenter"]
                }
            } catch { }

            $doc = @{
                id               = "$($sub.Id)_$($rgName.ToLower())"
                subscriptionId   = $sub.Id
                resourceGroup    = $rgName.ToLower()
                technicalBudget  = [double]$budget.properties.amount
                financeBudget    = [double]0
                budgetName       = $budget.name
                ownerEmail       = $ownerEmail
                costCenter       = $costCenter
                amortizedMTD     = [double]0
                forecastEOM      = [double]0
                actualPct        = [double]0
                forecastPct      = [double]0
                complianceStatus = "not_evaluated"
                lastSeeded       = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
                lastEvaluated    = ""
            } | ConvertTo-Json

            try {
                $upsertUri = "$CosmosEndpoint/dbs/$CosmosDatabaseName/colls/$CosmosContainerName/docs"
                Invoke-RestMethod -Uri $upsertUri -Method POST -Body $doc -Headers ($headers + @{ "x-ms-documentdb-is-upsert" = "true"; "x-ms-documentdb-partitionkey" = "[\`"$($sub.Id)\`"]" }) -ErrorAction SilentlyContinue | Out-Null
                Write-Host "  OK: $rgName = EUR $([double]$budget.properties.amount)" -ForegroundColor Green
                $seeded++
            } catch {
                Write-Host "  FAILED: $rgName - $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    } catch { }
}

Write-Host "`n  Seeded $seeded records into Cosmos DB ($CosmosDatabaseName/$CosmosContainerName)" -ForegroundColor Cyan
Write-Host "  Next: Run Set-FinanceBudget.ps1 to add finance budget expectations" -ForegroundColor Gray
Write-Host ""
