<#
.SYNOPSIS
    Production-grade RG budget backfill - creates budgets at scale via REST API.

.DESCRIPTION
    Calculates budget as 3-month avg + buffer (min EUR 100). Uses REST API for
    per-threshold contact routing. Supports dry-run, top-N, CSV export, and
    exclusion patterns. Designed for 8000+ RGs at enterprise scale.

.PARAMETER Top
    Process only top N RGs by spend. Use -Top 20 for quick-win pass.

.PARAMETER ConfigPath
    Path to config.json with defaults, exclusions, contacts.

.PARAMETER ActionGroupId
    Optional: Action Group resource ID for alert routing.

.PARAMETER DryRun
    Preview mode - shows what would be created. No changes made.

.PARAMETER ExportCsv
    Export calculated budgets to CSV for review before applying.

.EXAMPLE
    .\Invoke-BudgetBackfill.ps1 -Top 20 -DryRun
    .\Invoke-BudgetBackfill.ps1 -ExportCsv "budgets-preview.csv"
    .\Invoke-BudgetBackfill.ps1 -Top 20
    .\Invoke-BudgetBackfill.ps1
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [int]$Top = 0,
    [string]$ConfigPath = (Join-Path $PSScriptRoot "config.json"),
    [string]$ActionGroupId = "",
    [switch]$DryRun,
    [string]$ExportCsv = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# ── Load config ───────────────────────────────────────────────
$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$minBudget      = $config.defaults.minBudget
$bufferPct      = $config.defaults.bufferPercent / 100
$months         = $config.defaults.monthsForAverage
$budgetEnd      = $config.defaults.budgetEndDate
$budgetPrefix   = $config.defaults.budgetNamePrefix
$finopsEmail    = $config.contacts.finopsEmail
$fallbackEmail  = $config.contacts.fallbackOwnerEmail
$excludedPrefixes = $config.exclusions.rgPrefixes

Write-Host ""
Write-Host "  FinOps Budget Backfill Engine" -ForegroundColor Cyan
Write-Host "  =============================" -ForegroundColor Cyan
Write-Host "  Config: Min EUR $minBudget | Buffer $($config.defaults.bufferPercent)% | History ${months}mo"
Write-Host "  Exclusions: $($excludedPrefixes.Count) prefix patterns"
if ($Top -gt 0) { Write-Host "  Scope: Top $Top RGs by spend" -ForegroundColor Yellow }
if ($DryRun) { Write-Host "  Mode: DRY RUN (no changes)" -ForegroundColor DarkYellow }
Write-Host ""

# ── Collect RG spend data ─────────────────────────────────────
$subscriptions = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" }
$allRgData = [System.Collections.Generic.List[object]]::new()

foreach ($sub in $subscriptions) {
    Set-AzContext -SubscriptionId $sub.Id -ErrorAction SilentlyContinue | Out-Null
    $rgs = Get-AzResourceGroup -ErrorAction SilentlyContinue

    foreach ($rg in $rgs) {
        $rgName = $rg.ResourceGroupName

        # Skip excluded
        $skip = $false
        foreach ($p in $excludedPrefixes) { if ($rgName -like "$p*") { $skip = $true; break } }
        if ($skip) { continue }

        # Calculate avg spend
        $endDate = (Get-Date).ToString("yyyy-MM-dd")
        $startDate = (Get-Date).AddMonths(-$months).ToString("yyyy-MM-dd")
        $totalCost = 0

        try {
            $usage = Get-AzConsumptionUsageDetail -ResourceGroup $rgName -StartDate $startDate -EndDate $endDate -ErrorAction SilentlyContinue
            $totalCost = ($usage | Measure-Object -Property PretaxCost -Sum).Sum
            if (-not $totalCost) { $totalCost = 0 }
        } catch { $totalCost = 0 }

        $monthlyAvg = [math]::Round($totalCost / $months, 2)
        $budgetAmount = [math]::Max([math]::Ceiling($monthlyAvg * (1 + $bufferPct)), $minBudget)

        # Extract tag contacts
        $ownerEmail = $fallbackEmail
        $buLeadEmail = ""
        if ($rg.Tags) {
            if ($rg.Tags.ContainsKey("Owner") -and $rg.Tags["Owner"] -match "@") { $ownerEmail = $rg.Tags["Owner"] }
            if ($rg.Tags.ContainsKey("BillingContact") -and $rg.Tags["BillingContact"] -match "@") { $buLeadEmail = $rg.Tags["BillingContact"] }
        }

        $allRgData.Add([PSCustomObject]@{
            SubscriptionId   = $sub.Id
            SubscriptionName = $sub.Name
            ResourceGroup    = $rgName
            MonthlyAvgSpend  = $monthlyAvg
            BudgetAmount     = $budgetAmount
            OwnerEmail       = $ownerEmail
            BuLeadEmail      = $buLeadEmail
        })
    }
}

# Sort and filter
$allRgData = $allRgData | Sort-Object -Property MonthlyAvgSpend -Descending
if ($Top -gt 0) { $allRgData = $allRgData | Select-Object -First $Top }

Write-Host "  RGs to process: $($allRgData.Count)" -ForegroundColor Gray

# Export CSV if requested
if ($ExportCsv) {
    $allRgData | Export-Csv -Path $ExportCsv -NoTypeInformation -Encoding UTF8
    Write-Host "  Exported: $ExportCsv - review then re-run without -ExportCsv" -ForegroundColor Green
    return
}

# ── Create budgets via REST API ───────────────────────────────
$token = (Get-AzAccessToken -ResourceUrl "https://management.azure.com").Token
$success = 0; $failed = 0; $skipped = 0

foreach ($item in $allRgData) {
    $budgetName = "$budgetPrefix-$($item.ResourceGroup)"
    if ($budgetName.Length -gt 63) { $budgetName = $budgetName.Substring(0, 63) }

    Write-Host "  [$($item.ResourceGroup)] " -NoNewline

    # Check existing
    $checkUri = "https://management.azure.com/subscriptions/$($item.SubscriptionId)/resourceGroups/$($item.ResourceGroup)/providers/Microsoft.Consumption/budgets?api-version=2023-11-01"
    try {
        $existing = Invoke-RestMethod -Uri $checkUri -Method GET -Headers @{ Authorization = "Bearer $token" } -ErrorAction SilentlyContinue
        if ($existing.value.Count -gt 0) {
            Write-Host "EXISTS (EUR $($existing.value[0].properties.amount))" -ForegroundColor DarkGray
            $skipped++; continue
        }
    } catch { }

    if ($DryRun) {
        Write-Host "DRY RUN: EUR $($item.BudgetAmount) (avg: EUR $($item.MonthlyAvgSpend))" -ForegroundColor DarkYellow
        $skipped++; continue
    }

    # Build contacts
    $contacts90 = @($item.OwnerEmail, $finopsEmail) | Select-Object -Unique
    if ($item.BuLeadEmail) { $contacts90 = @($item.OwnerEmail, $item.BuLeadEmail, $finopsEmail) | Select-Object -Unique }
    $agArray = if ($ActionGroupId) { @($ActionGroupId) } else { @() }

    $body = @{
        properties = @{
            category = "Cost"; amount = $item.BudgetAmount; timeGrain = "Monthly"
            timePeriod = @{ startDate = (Get-Date -Day 1).ToString("yyyy-MM-01T00:00:00Z"); endDate = "${budgetEnd}T00:00:00Z" }
            notifications = @{
                Forecasted_90 = @{ enabled=$true; operator="GreaterThan"; threshold=90; thresholdType="Forecasted"; contactEmails=$contacts90; contactGroups=$agArray }
                Actual_100 = @{ enabled=$true; operator="GreaterThan"; threshold=100; thresholdType="Actual"; contactEmails=$contacts90; contactGroups=$agArray }
                Forecasted_110 = @{ enabled=$true; operator="GreaterThan"; threshold=110; thresholdType="Forecasted"; contactEmails=$contacts90; contactGroups=$agArray }
            }
        }
    } | ConvertTo-Json -Depth 10

    $uri = "https://management.azure.com/subscriptions/$($item.SubscriptionId)/resourceGroups/$($item.ResourceGroup)/providers/Microsoft.Consumption/budgets/${budgetName}?api-version=2023-11-01"

    try {
        Invoke-RestMethod -Uri $uri -Method PUT -Body $body -Headers @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" } -ErrorAction Stop | Out-Null
        Write-Host "OK EUR $($item.BudgetAmount) (avg: EUR $($item.MonthlyAvgSpend))" -ForegroundColor Green
        $success++
    } catch {
        Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
        $failed++
    }
}

Write-Host ""
Write-Host "  Results: $success created | $failed failed | $skipped skipped" -ForegroundColor Cyan
Write-Host ""
