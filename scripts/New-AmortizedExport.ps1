<#
.SYNOPSIS
    Creates a daily amortized cost export from Azure Cost Management.

.DESCRIPTION
    Sets up a scheduled Cost Management export for amortized cost data.
    Prerequisite for the amortized budget alerting pipeline (LT-01).
    Exports to the FinOps storage account blob container in FOCUS-compatible format.

.PARAMETER SubscriptionId
    Target subscription ID. Defaults to current context.

.PARAMETER StorageAccountResourceGroup  
    Resource group containing the storage account.

.PARAMETER StorageAccountName
    Name of the storage account.

.EXAMPLE
    .\New-AmortizedExport.ps1 -StorageAccountName "safinopsxyz" -StorageAccountResourceGroup "rg-finops-governance-dev"
#>

[CmdletBinding()]
param(
    [string]$SubscriptionId = "",
    [Parameter(Mandatory)]
    [string]$StorageAccountResourceGroup,
    [Parameter(Mandatory)]
    [string]$StorageAccountName,
    [string]$ContainerName = "amortized-cost-exports",
    [string]$ExportName = "finops-daily-amortized"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not $SubscriptionId) { $SubscriptionId = (Get-AzContext).Subscription.Id }

Write-Host "`n  Amortized Cost Export Setup" -ForegroundColor Cyan
Write-Host "  ==========================" -ForegroundColor Cyan

# Ensure container exists
$sa = Get-AzStorageAccount -ResourceGroupName $StorageAccountResourceGroup -Name $StorageAccountName
try {
    New-AzStorageContainer -Name $ContainerName -Context $sa.Context -ErrorAction SilentlyContinue | Out-Null
} catch { }

Write-Host "  Storage: $StorageAccountName/$ContainerName" -ForegroundColor Gray

# Create export via REST API
$token = (Get-AzAccessToken -ResourceUrl "https://management.azure.com").Token
$uri = "https://management.azure.com/subscriptions/$SubscriptionId/providers/Microsoft.CostManagement/exports/${ExportName}?api-version=2023-11-01"

$body = @{
    properties = @{
        schedule = @{
            status = "Active"
            recurrence = "Daily"
            recurrencePeriod = @{
                from = (Get-Date -Day 1).ToString("yyyy-MM-01T00:00:00Z")
                to = "2027-03-31T00:00:00Z"
            }
        }
        format = "Csv"
        deliveryInfo = @{
            destination = @{
                resourceId = $sa.Id
                container = $ContainerName
                rootFolderPath = "amortized"
            }
        }
        definition = @{
            type = "AmortizedCost"
            timeframe = "MonthToDate"
            dataSet = @{
                granularity = "Daily"
                grouping = @(
                    @{ type = "Dimension"; name = "ResourceGroup" }
                    @{ type = "Dimension"; name = "SubscriptionId" }
                    @{ type = "Dimension"; name = "ResourceType" }
                )
            }
        }
    }
} | ConvertTo-Json -Depth 10

try {
    Invoke-RestMethod -Uri $uri -Method PUT -Body $body `
        -Headers @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" } `
        -ErrorAction Stop | Out-Null

    Write-Host "  Export '$ExportName' created (AmortizedCost, Daily, MTD)" -ForegroundColor Green
    Write-Host "  Data arrives in ~24 hours.`n" -ForegroundColor Yellow
} catch {
    Write-Error "Failed: $($_.Exception.Message)"
}
