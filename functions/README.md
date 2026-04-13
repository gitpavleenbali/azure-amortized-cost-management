# functions/

Python 3.11 Azure Function App — the core FinOps evaluation engine with **9 endpoints**.

## Endpoints

| Function | Trigger | Route | Purpose |
|----------|---------|-------|---------|
| `evaluate_amortized_budgets` | Timer (06:00 UTC daily) | — | Reads amortized cost CSV, calculates MTD spend, sets compliance status |
| `manual_evaluate` | HTTP GET | `/api/evaluate` | On-demand trigger for the same evaluation logic |
| `get_inventory` | HTTP GET | `/api/inventory` | Returns full FinOps inventory as JSON (filterable: `?status=over_budget`) |
| `get_variance` | HTTP GET | `/api/variance` | Finance vs Technical budget variance report |
| `update_budget` | HTTP POST | `/api/update-budget` | Updates a budget in Cosmos DB (called by Logic App) |
| `backfill_existing_rgs` | HTTP GET | `/api/backfill` | Scans all RGs, creates budget + Cosmos doc for untracked ones |
| `ingest_finance_budget` | Blob trigger | `finance-budgets/{name}` | Auto-ingests finance CSV uploads from blob container |
| `quarterly_recalculate` | Timer (quarterly) | — | Adjusts budgets from last quarter actuals (if drift > 30%) |
| `manual_recalculate` | HTTP GET | `/api/recalculate` | On-demand quarterly recalculation |

## Source Files

| File | Purpose |
|------|---------|
| `amortized-budget-engine/function_app.py` | All 9 endpoints in a single v2 programming model file |
| `amortized-budget-engine/host.json` | Function host configuration + extension bundle |
| `amortized-budget-engine/requirements.txt` | Python dependencies (7 packages, all pinned) |

## Authentication

- **Storage**: Managed Identity (`AzureWebJobsStorage__accountName`)
- **Cosmos DB**: MI via SQL RBAC
- **Log Analytics**: DCR + Logs Ingestion API (MI) with shared key fallback
- **Cost Management API**: MI with Cost Management Reader role
