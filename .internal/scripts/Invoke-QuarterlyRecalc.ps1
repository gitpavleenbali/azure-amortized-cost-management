<#
.SYNOPSIS
    Quarterly budget recalculation - updates RG budgets based on last quarter's actuals.

.DESCRIPTION
    Reads actual spend for all RGs, recalculates budget as avg + 10% buffer (min EUR 100).
    Only updates if budget has drifted more than the threshold (default ±30%).
    Prevents churn on stable workloads while catching spend pattern changes.

.PARAMETER DriftThreshold
    Percentage change required before updating. Default: 30%.

.PARAMETER DryRun
    Preview mode - shows what would change without applying.

.EXAMPLE
    .\Invoke-QuarterlyRecalc.ps1 -DryRun
    .\Invoke-QuarterlyRecalc.ps1
    .\Invoke-QuarterlyRecalc.ps1 -DriftThreshold 20
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [int]$DriftThreshold = 30,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"
$minBudget = 100; $bufferPct = 0.10

Write-Host "`n  Quarterly Budget Recalculation" -ForegroundColor Cyan
Write-Host "  ==============================" -ForegroundColor Cyan
Write-Host "  Drift threshold: ±$DriftThreshold% | Min: EUR $minBudget | Buffer: $([int]($bufferPct*100))%"
if ($DryRun) { Write-Host "  Mode: DRY RUN" -ForegroundColor DarkYellow }
Write-Host ""

$subscriptions = Get-AzSubscription | Where-Object { $_.State -eq "Enabled" }
$updated = 0; $unchanged = 0; $failed = 0
$token = (Get-AzAccessToken -ResourceUrl "https://management.azure.com").Token

foreach ($sub in $subscriptions) {
    Set-AzContext -SubscriptionId $sub.Id -ErrorAction SilentlyContinue | Out-Null

    $budgetUri = "https://management.azure.com/subscriptions/$($sub.Id)/providers/Microsoft.Consumption/budgets?api-version=2023-11-01"
    try {
        $budgetResp = Invoke-RestMethod -Uri $budgetUri -Method GET -Headers @{ Authorization = "Bearer $token" } -ErrorAction SilentlyContinue
    } catch { continue }

    foreach ($budget in $budgetResp.value) {
        if ($budget.name -notlike "finops-rg-budget-*") { continue }

        $rgName = ""
        if ($budget.id -match "/resourceGroups/([^/]+)/") { $rgName = $Matches[1] }
        if (-not $rgName) { continue }

        $currentBudget = $budget.properties.amount
        $endDate = (Get-Date).ToString("yyyy-MM-dd")
        $startDate = (Get-Date).AddMonths(-3).ToString("yyyy-MM-dd")
        $totalCost = 0

        try {
            $usage = Get-AzConsumptionUsageDetail -ResourceGroup $rgName -StartDate $startDate -EndDate $endDate -ErrorAction SilentlyContinue
            $totalCost = ($usage | Measure-Object -Property PretaxCost -Sum).Sum
            if (-not $totalCost) { $totalCost = 0 }
        } catch { $totalCost = 0 }

        $monthlyAvg = [math]::Round($totalCost / 3, 2)
        $newBudget = [math]::Max([math]::Ceiling($monthlyAvg * (1 + $bufferPct)), $minBudget)

        $drift = if ($currentBudget -gt 0) { [math]::Abs(($newBudget - $currentBudget) / $currentBudget * 100) } else { 100 }

        Write-Host "  [$rgName] " -NoNewline

        if ($drift -lt $DriftThreshold) {
            Write-Host "STABLE ($([math]::Round($drift,1))% < $DriftThreshold%) EUR $currentBudget" -ForegroundColor DarkGray
            $unchanged++; continue
        }

        if ($DryRun) {
            Write-Host "WOULD: EUR $currentBudget → EUR $newBudget ($([math]::Round($drift,1))%)" -ForegroundColor DarkYellow
            $updated++; continue
        }

        try {
            $updateUri = "https://management.azure.com$($budget.id)?api-version=2023-11-01"
            $budget.properties.amount = $newBudget
            $body = @{ properties = $budget.properties } | ConvertTo-Json -Depth 10

            Invoke-RestMethod -Uri $updateUri -Method PUT -Body $body `
                -Headers @{ Authorization = "Bearer $token"; "Content-Type" = "application/json" } `
                -ErrorAction Stop | Out-Null

            Write-Host "UPDATED: EUR $currentBudget → EUR $newBudget ($([math]::Round($drift,1))%)" -ForegroundColor Green
            $updated++
        } catch {
            Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
            $failed++
        }
    }
}

Write-Host "`n  Results: $updated updated | $unchanged stable | $failed failed" -ForegroundColor Cyan
Write-Host ""
