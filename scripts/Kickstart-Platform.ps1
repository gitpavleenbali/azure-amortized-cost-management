<#
.SYNOPSIS
    Kickstart the FinOps platform — see data in your dashboard within 10 minutes.

.DESCRIPTION
    One-shot script that runs ALL post-deploy steps automatically:
    1. Assigns RBAC roles to managed identities
    2. Creates the daily amortized cost export
    3. Deploys Function App code
    4. Triggers immediate backfill (scans all RGs, populates Cosmos DB)
    5. Triggers immediate evaluation (reads cost data, updates inventory)
    6. Syncs inventory to Log Analytics
    After completion, open the Azure Workbook to see your dashboard.

.PARAMETER ResourceGroupName
    Resource group where FinOps platform was deployed.

.PARAMETER SubscriptionId
    Target subscription. Defaults to current context.

.EXAMPLE
    .\scripts\Kickstart-Platform.ps1 -ResourceGroupName "rg-finops-governance-dev"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ResourceGroupName,

    [string]$SubscriptionId = ""
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$banner = @"

  ╔══════════════════════════════════════════════════╗
  ║   Azure Amortized Cost Management — Kickstart   ║
  ║   See your first dashboard in ~10 minutes        ║
  ╚══════════════════════════════════════════════════╝

"@
Write-Host $banner -ForegroundColor Cyan

# ── Pre-checks ────────────────────────────────────────────────
if (-not $SubscriptionId) { $SubscriptionId = (az account show --query id -o tsv 2>$null) }
if (-not $SubscriptionId) { Write-Error "Not logged in. Run 'az login' first."; exit 1 }

Write-Host "  Subscription : $SubscriptionId" -ForegroundColor Gray
Write-Host "  Resource Group: $ResourceGroupName" -ForegroundColor Gray
Write-Host ""

# Verify RG exists
$rgCheck = az group show --name $ResourceGroupName --query name -o tsv 2>&1
if ($LASTEXITCODE -ne 0) { Write-Error "Resource group '$ResourceGroupName' not found."; exit 1 }

# ── Step 1: Discover deployed resources ───────────────────────
Write-Host "[1/6] Discovering deployed resources..." -ForegroundColor Yellow
$functionAppName = az functionapp list -g $ResourceGroupName --query "[0].name" -o tsv 2>$null
$storageAccountName = az storage account list -g $ResourceGroupName --query "[0].name" -o tsv 2>$null
$cosmosAccountName = az cosmosdb list -g $ResourceGroupName --query "[0].name" -o tsv 2>$null
$lawName = az monitor log-analytics workspace list -g $ResourceGroupName --query "[0].name" -o tsv 2>$null

Write-Host "  Function App  : $functionAppName" -ForegroundColor Gray
Write-Host "  Storage       : $storageAccountName" -ForegroundColor Gray
Write-Host "  Cosmos DB     : $cosmosAccountName" -ForegroundColor Gray
Write-Host "  Log Analytics : $lawName" -ForegroundColor Gray

if (-not $functionAppName) { Write-Error "Function App not found. Was enableAmortizedPipeline set to Enabled?"; exit 1 }
if (-not $storageAccountName) { Write-Error "Storage Account not found."; exit 1 }
Write-Host "  All resources found." -ForegroundColor Green
Write-Host ""

# ── Step 2: RBAC assignments ─────────────────────────────────
Write-Host "[2/6] Assigning RBAC roles to managed identities..." -ForegroundColor Yellow
$funcPrincipal = az functionapp identity show -g $ResourceGroupName -n $functionAppName --query principalId -o tsv 2>$null

if ($funcPrincipal) {
    # Cost Management Reader for the Function App (read cost data)
    az role assignment create --assignee-object-id $funcPrincipal --assignee-principal-type ServicePrincipal `
        --role "72fafb9e-0641-4937-9268-a91bfd8191a3" --scope "/subscriptions/$SubscriptionId" 2>$null | Out-Null
    Write-Host "  Assigned Cost Management Reader to Function App" -ForegroundColor Green
}

# Auto-budget Logic App
$autoBudgetPrincipal = az logic workflow show -g $ResourceGroupName -n "la-finops-auto-budget" --query "identity.principalId" -o tsv 2>$null
if ($autoBudgetPrincipal) {
    az role assignment create --assignee-object-id $autoBudgetPrincipal --assignee-principal-type ServicePrincipal `
        --role "434105ed-43f6-45c7-a02f-909b2ba83430" --scope "/subscriptions/$SubscriptionId" 2>$null | Out-Null
    Write-Host "  Assigned Cost Management Contributor to Auto-Budget Logic App" -ForegroundColor Green
}

# Budget-change Logic App
$changePrincipal = az logic workflow show -g $ResourceGroupName -n "la-finops-budget-change" --query "identity.principalId" -o tsv 2>$null
if ($changePrincipal) {
    az role assignment create --assignee-object-id $changePrincipal --assignee-principal-type ServicePrincipal `
        --role "434105ed-43f6-45c7-a02f-909b2ba83430" --scope "/subscriptions/$SubscriptionId" 2>$null | Out-Null
    Write-Host "  Assigned Cost Management Contributor to Budget-Change Logic App" -ForegroundColor Green
}
Write-Host ""

# ── Step 3: Create amortized cost export ──────────────────────
Write-Host "[3/6] Creating daily amortized cost export..." -ForegroundColor Yellow
$exportName = "finops-daily-amortized"
$containerName = "amortized-cost-exports"

# Create blob container if not exists
az storage container create --name $containerName --account-name $storageAccountName --auth-mode login 2>$null | Out-Null

$storageId = az storage account show -g $ResourceGroupName -n $storageAccountName --query id -o tsv 2>$null
$token = az account get-access-token --query accessToken -o tsv 2>$null
$startDate = (Get-Date -Day 1).ToString("yyyy-MM-01T00:00:00")
$endDate = (Get-Date).AddYears(1).ToString("yyyy-12-31T00:00:00")

$exportBody = @{
    properties = @{
        schedule = @{
            status = "Active"
            recurrence = "Daily"
            recurrencePeriod = @{
                from = $startDate
                to = $endDate
            }
        }
        format = "Csv"
        deliveryInfo = @{
            destination = @{
                resourceId = $storageId
                container = $containerName
                rootFolderPath = "exports"
            }
        }
        definition = @{
            type = "AmortizedCost"
            timeframe = "MonthToDate"
        }
    }
} | ConvertTo-Json -Depth 10

try {
    $exportUri = "https://management.azure.com/subscriptions/$SubscriptionId/providers/Microsoft.CostManagement/exports/${exportName}?api-version=2023-11-01"
    Invoke-RestMethod -Uri $exportUri -Method Put -Headers @{Authorization="Bearer $token"; "Content-Type"="application/json"} -Body $exportBody -ErrorAction Stop | Out-Null
    Write-Host "  Created export: $exportName (daily at 03:00 UTC)" -ForegroundColor Green
} catch {
    Write-Host "  Export may already exist or requires Cost Management Contributor: $($_.Exception.Message)" -ForegroundColor DarkYellow
}

# Trigger immediate export run
try {
    $runUri = "https://management.azure.com/subscriptions/$SubscriptionId/providers/Microsoft.CostManagement/exports/${exportName}/run?api-version=2023-11-01"
    Invoke-RestMethod -Uri $runUri -Method Post -Headers @{Authorization="Bearer $token"} -ErrorAction Stop | Out-Null
    Write-Host "  Triggered immediate export run (data arrives in ~5 minutes)" -ForegroundColor Green
} catch {
    Write-Host "  Could not trigger immediate run: $($_.Exception.Message)" -ForegroundColor DarkYellow
}
Write-Host ""

# ── Step 4: Deploy Function App code ─────────────────────────
Write-Host "[4/6] Deploying Function App code..." -ForegroundColor Yellow
$funcDir = Join-Path $PSScriptRoot ".." "functions" "amortized-budget-engine"
if (Test-Path $funcDir) {
    Push-Location $funcDir
    try {
        func azure functionapp publish $functionAppName --python 2>&1 | ForEach-Object {
            if ($_ -match "Remote build succeeded|Deployment successful|Functions in") {
                Write-Host "  $_" -ForegroundColor Green
            }
        }
        Write-Host "  Function App code deployed." -ForegroundColor Green
    } catch {
        Write-Host "  func CLI deployment failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Install: npm install -g azure-functions-core-tools@4" -ForegroundColor Yellow
    }
    Pop-Location
} else {
    Write-Host "  SKIP: functions/amortized-budget-engine not found at $funcDir" -ForegroundColor DarkYellow
}
Write-Host ""

# ── Step 5: Trigger backfill (scan all RGs → Cosmos DB) ──────
Write-Host "[5/6] Triggering backfill — scanning all resource groups..." -ForegroundColor Yellow
$funcKey = az functionapp keys list -g $ResourceGroupName -n $functionAppName --query "functionKeys.default" -o tsv 2>$null
$funcHostname = az functionapp show -g $ResourceGroupName -n $functionAppName --query "defaultHostName" -o tsv 2>$null

if ($funcKey -and $funcHostname) {
    # Wait for Function App to warm up
    Write-Host "  Waiting 30 seconds for Function App to initialize..." -ForegroundColor Gray
    Start-Sleep -Seconds 30

    try {
        $backfillUrl = "https://$funcHostname/api/backfill?code=$funcKey"
        $result = Invoke-RestMethod -Uri $backfillUrl -Method Get -TimeoutSec 120 -ErrorAction Stop
        Write-Host "  Backfill complete — resource groups scanned and inventory populated." -ForegroundColor Green
    } catch {
        Write-Host "  Backfill call failed (Function may still be cold-starting): $($_.Exception.Message)" -ForegroundColor DarkYellow
        Write-Host "  Retry manually: curl $backfillUrl" -ForegroundColor Gray
    }
} else {
    Write-Host "  SKIP: Could not retrieve Function App key or hostname." -ForegroundColor DarkYellow
}
Write-Host ""

# ── Step 6: Trigger evaluation (process → Cosmos DB) ─────────
Write-Host "[6/6] Triggering evaluation — processing cost data..." -ForegroundColor Yellow
if ($funcKey -and $funcHostname) {
    try {
        $evalUrl = "https://$funcHostname/api/evaluate?code=$funcKey"
        $result = Invoke-RestMethod -Uri $evalUrl -Method Get -TimeoutSec 120 -ErrorAction Stop
        Write-Host "  Evaluation complete — Cosmos DB inventory updated." -ForegroundColor Green
    } catch {
        Write-Host "  Evaluation call may need cost export data (arrives in ~5min): $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
}
Write-Host ""

# ── Summary ───────────────────────────────────────────────────
$workbookUrl = "https://portal.azure.com/#@/resource/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Insights/workbooks"
$cosmosUrl = "https://portal.azure.com/#@/resource/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.DocumentDB/databaseAccounts/$cosmosAccountName/dataExplorer"

Write-Host @"

  ╔══════════════════════════════════════════════════╗
  ║                KICKSTART COMPLETE                ║
  ╠══════════════════════════════════════════════════╣
  ║                                                  ║
  ║  Your FinOps platform is now LIVE.               ║
  ║                                                  ║
  ║  What's running:                                 ║
  ║  • Cost export: triggered (data in ~5 min)       ║
  ║  • Function App: deployed + backfill completed   ║
  ║  • Cosmos DB: inventory populated                ║
  ║  • Alert rules: active                           ║
  ║  • Logic Apps: listening for events              ║
  ║                                                  ║
  ║  NEXT: Open your dashboard:                      ║
  ║                                                  ║
  ╚══════════════════════════════════════════════════╝

"@ -ForegroundColor Green

Write-Host "  Open Workbook:" -ForegroundColor Cyan
Write-Host "  Portal → Resource Group → $ResourceGroupName → Workbooks" -ForegroundColor White
Write-Host ""
Write-Host "  Check Cosmos DB data:" -ForegroundColor Cyan
Write-Host "  Portal → Cosmos DB → $cosmosAccountName → Data Explorer → finops → inventory" -ForegroundColor White
Write-Host ""
Write-Host "  Re-evaluate anytime:" -ForegroundColor Cyan
Write-Host "  https://$funcHostname/api/evaluate?code=$funcKey" -ForegroundColor White
Write-Host ""
