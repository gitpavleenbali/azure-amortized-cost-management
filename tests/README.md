# tests/

Automated tests for validating the FinOps platform — run via `pytest` (Python) and `Pester` (PowerShell).

## Structure

| Path | Framework | What It Tests |
|------|-----------|---------------|
| `function/test_evaluator.py` | pytest | Function App evaluation logic: threshold calculation, compliance status, spend tiers, budget guardrails, variance computation |
| `infra/Validate-Deployment.Tests.ps1` | Pester | Post-deployment infrastructure validation: resource existence, RBAC assignments, app settings, Cosmos DB connectivity |
| `Seed-CosmosDemo.ps1` | PowerShell | Seeds Cosmos DB with sample inventory data for demo/testing purposes (not an automated test — run manually) |

## Running Tests

```bash
# Python unit tests (from repo root)
pytest tests/function/ -v

# PowerShell infra validation (after deployment)
Invoke-Pester tests/infra/Validate-Deployment.Tests.ps1 -Output Detailed
```

> Tests run automatically in CI via `.github/workflows/ci.yml` on every push to `main`.
