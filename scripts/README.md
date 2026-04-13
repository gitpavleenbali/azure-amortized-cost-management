# scripts/

Admin scripts for **Option 2 (CI/CD)** and manual operations. These are NOT needed for Option 1 (Deploy to Azure) — everything is automated.

| File | Purpose |
|------|---------|
| `config.json` | Default configuration: thresholds, exclusion prefixes, contact info |
| `Enable-AdminFeatures.ps1` | Elevate RBAC permissions for governance features (requires Owner or UAA role) |
| `sample-finance-budgets.csv` | Template CSV for finance budget uploads — drop into the `finance-budgets` blob container to auto-ingest |
| `Set-FinanceBudget.ps1` | Upload finance budget CSV to the storage account's `finance-budgets` container |

> **Note:** 7 scripts that were previously here have been automated into the Bicep modules and Function App. They are archived in `.internal/scripts/` for reference.
