# infra/

Bicep Infrastructure as Code — deploys the entire FinOps platform via a single subscription-scoped orchestrator.

## Entry Point

- **`main.bicep`** — The orchestrator. Deploys all 20 modules with conditional feature toggles.
- **`main.json`** — Pre-compiled ARM template (use `azuredeploy.json` at repo root for Deploy to Azure).

## Modules (`modules/`)

| Module | Resource | Purpose |
|--------|----------|---------|
| `action-group.bicep` | Action Group | Email + Teams alert routing |
| `alert-rules.bicep` | Scheduled Query Rules (x3) | HeadUp 60%, Warning 80%, Critical 95% |
| `budget.bicep` | Consumption Budget | Subscription-level monthly budget |
| `cosmos-db.bicep` | Cosmos DB (Serverless) | FinOps Inventory — single source of truth |
| `data-collection-rule.bicep` | DCR + DCE | MI-authenticated log ingestion (replaces shared key) |
| `event-grid.bicep` | Event Grid Subscription | Triggers auto-budget on new RG creation |
| `function-app.bicep` | Function App + Plan | 9-endpoint Python evaluation engine + RBAC |
| `log-analytics.bicep` | Log Analytics Workspace | Powers Workbook + Alert Rules |
| `logic-app-auto-budget.bicep` | Logic App | Auto-assigns budget to new RGs |
| `logic-app-backfill.bicep` | Logic App | Daily safety-net scan of all RGs |
| `logic-app-budget-change.bicep` | Logic App | Self-service budget change with guardrails |
| `networking.bicep` | VNet + Private Endpoints | Optional private networking |
| `policy-definition.bicep` | Policy Definition | AuditIfNotExists for RGs without budgets |
| `policy-assignment.bicep` | Policy Assignment | Assigns policy to subscription |
| `post-deploy.bicep` | Deployment Script | Auto-deploys code, creates cost export, triggers pipeline |
| `storage-account.bicep` | Storage Account | Blob (exports, releases), Table (inventory) |
| `workbook.json` | Azure Workbook | Compliance dashboard (KQL-based) |
| `*-sub-roles.bicep` | RBAC (subscription scope) | Cost Management Reader, Backfill Reader |

## Deployment

```bash
az deployment sub create --location westus2 --template-file infra/main.bicep --parameters parameters/dev.bicepparam
```
