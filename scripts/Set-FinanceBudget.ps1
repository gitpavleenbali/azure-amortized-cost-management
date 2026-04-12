<#
.SYNOPSIS
    Sets finance department budget expectations in the FinOps Inventory table.

.DESCRIPTION
    Finance teams set their budget expectations (planned spend) per RG or cost center.
    These are compared against technical budgets (from Azure Consumption) and actual
    amortized spend by the FinOps Inventory Engine (Azure Function).

    The variance (Finance Budget - Amortized Spend) shows overspend or underspend
    from the finance perspective — answering the executive requirement:
    "For this business line, total budget is 250K, spend is 265K, so 15K extra."

.PARAMETER StorageAccountName
    Name of the FinOps storage account containing the inventory table.

.PARAMETER StorageAccountResourceGroup
    Resource group of the storage account.

.PARAMETER CsvPath
    Path to a CSV file with columns: SubscriptionId, ResourceGroup, FinanceBudget, CostCenter
    If not provided, interactive mode allows setting individual entries.

.PARAMETER SubscriptionId
    For single-entry mode: the subscription ID.

.PARAMETER ResourceGroupName
    For single-entry mode: the resource group name.

.PARAMETER FinanceBudget
    For single-entry mode: the finance budget amount (EUR).

.PARAMETER CostCenter
    For single-entry mode: the cost center code.

.EXAMPLE
    # Bulk import from CSV (finance team provides this)
    .\Set-FinanceBudget.ps1 -StorageAccountName "safinopsxyz" -StorageAccountResourceGroup "rg-finops-budget-mvp" -CsvPath "finance-budgets.csv"

    # Single entry
    .\Set-FinanceBudget.ps1 -StorageAccountName "safinopsxyz" -StorageAccountResourceGroup "rg-finops-budget-mvp" -SubscriptionId "209d..." -ResourceGroupName "rg-app-prod" -FinanceBudget 25000 -CostCenter "BU-Healthcare"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$CosmosEndpoint,
    [string]$CosmosDatabaseName = "finops",
    [string]$CosmosContainerName = "inventory",
    [string]$CsvPath = "",
    [string]$SubscriptionId = "",
    [string]$ResourceGroupName = "",
    [double]$FinanceBudget = 0,
    [string]$CostCenter = "",
    # Legacy params
    [string]$StorageAccountName = "",
    [string]$StorageAccountResourceGroup = "",
    [string]$TableName = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

Write-Host "`n  FinOps Finance Budget Loader (Cosmos DB)" -ForegroundColor Cyan
Write-Host "  =========================================" -ForegroundColor Cyan
Write-Host "  Endpoint: $CosmosEndpoint"

$token = (Get-AzAccessToken -ResourceUrl "https://cosmos.azure.com").Token
$headers = @{
    "Authorization" = "type=aad&ver=1.0&sig=$token"
    "Content-Type"  = "application/json"
    "x-ms-version"  = "2018-12-31"
}

$entries = @()

if ($CsvPath) {
    if (-not (Test-Path $CsvPath)) {
        Write-Host "  ERROR: CSV not found: $CsvPath" -ForegroundColor Red
        exit 1
    }
    $entries = Import-Csv -Path $CsvPath
    Write-Host "  Loaded $($entries.Count) entries from CSV" -ForegroundColor Gray
} elseif ($SubscriptionId -and $ResourceGroupName -and $FinanceBudget -gt 0) {
    $entries = @([PSCustomObject]@{
        SubscriptionId = $SubscriptionId
        ResourceGroup = $ResourceGroupName
        FinanceBudget = $FinanceBudget
        CostCenter = $CostCenter
    })
} else {
    Write-Host "  ERROR: Provide either -CsvPath or -SubscriptionId/-ResourceGroupName/-FinanceBudget" -ForegroundColor Red
    exit 1
}

$updated = 0

foreach ($entry in $entries) {
    $sub = $entry.SubscriptionId
    $rg = $entry.ResourceGroup.ToLower()
    $amount = [double]$entry.FinanceBudget
    $cc = if ($entry.PSObject.Properties["CostCenter"]) { $entry.CostCenter } else { "" }

    try {
        $docId = "$($sub)_$($rg)"
        $doc = @{
            id               = $docId
            subscriptionId   = $sub
            resourceGroup    = $rg
            financeBudget    = $amount
            costCenter       = $cc
            financeBudgetSetBy   = "finance-team"
            financeBudgetSetDate = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        } | ConvertTo-Json

        $upsertUri = "$CosmosEndpoint/dbs/$CosmosDatabaseName/colls/$CosmosContainerName/docs"
        Invoke-RestMethod -Uri $upsertUri -Method POST -Body $doc -Headers ($headers + @{ "x-ms-documentdb-is-upsert" = "true"; "x-ms-documentdb-partitionkey" = "[\`"$sub\`"]" }) -ErrorAction SilentlyContinue | Out-Null
        Write-Host "  OK: $rg = EUR $amount (CC: $cc)" -ForegroundColor Green
        $updated++
    } catch {
        Write-Host "  FAILED: $rg - $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`n  Updated $updated finance budget entries in Cosmos DB" -ForegroundColor Cyan
Write-Host "  The FinOps Inventory Engine will compare these against amortized spend at 06:00 UTC" -ForegroundColor Gray
Write-Host ""
