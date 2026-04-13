# Open-Source Strategy — Azure Amortized Cost Management

> **Goal:** Transform this customer-specific FinOps solution into a public GitHub Accelerator template that any Azure user can deploy with one click.  
> **Repo rename:** `azure-amortised-cost-analysis` → `azure-amortized-cost-management`  
> **License:** MIT  
> **Target:** GitHub public repository with "Deploy to Azure" button  

---

## 0. Best Practices Adopted from Microsoft Official Repositories

This project follows patterns from the best Microsoft open-source repositories:

### From `microsoft/finops-toolkit` (543 stars, official FinOps accelerator)
- MIT License + CODE_OF_CONDUCT + CONTRIBUTING + SECURITY + SUPPORT files
- Emoji section headers in README
- `Tags:` metadata line at bottom for discoverability
- Trademarks section
- all-contributors recognition
- GitHub topic tags: `azure`, `finops`, `cost-management`

### From `Azure/azure-quickstart-templates` (14k+ stars)
- "Deploy to Azure" + "Visualize" buttons at top of README
- `azuredeploy.json` + `azuredeploy.parameters.json` + `metadata.json` pattern
- `createUiDefinition.json` for Azure Portal guided deployment
- Best Practice badges (CI status, credential scan, Bicep version)
- No external links policy (all assets self-contained)
- Contribution guide with PR template

### Azure Well-Architected Framework Alignment
The platform maps to all 5 pillars:

| Pillar | Implementation |
|--------|---------------|
| **Cost Optimization** | Platform runs on ~$2.50/month serverless; monitors customer cost |
| **Operational Excellence** | IaC-only Bicep, CI/CD, automated evaluation, observability |
| **Reliability** | Idempotent deploys, timer + manual fallback, backfill safety net |
| **Security** | Managed Identity, RBAC least-privilege, no secrets in code, audit policy |
| **Performance Efficiency** | Serverless auto-scale, Cosmos DB partitioned by subscriptionId |

### What We Still Need
- [ ] `SUPPORT.md` — how to get help (GitHub Issues + Discussions)
- [ ] `azuredeploy.parameters.json` — example parameters file for Deploy to Azure
- [ ] `metadata.json` — for Azure Quickstart Templates gallery submission
- [ ] `createUiDefinition.json` — for Azure Marketplace portal form
- [ ] GitHub topic tags configured on repo settings
- [ ] Trademarks section in README (done)

---

## 1. Sanitization Checklist — Remove All Customer-Specific Content (COMPLETED)

Every file below contains customer names, personal emails, subscription IDs, tenant IDs, or internal project references that **must** be removed or replaced before going public.

### 1.1 Code Files (breaking if not fixed)

| File | What to Remove/Replace | Replace With |
|------|----------------------|--------------|
| `functions/amortized-budget-engine/function_app.py` L41 | `finops@siemens-healthineers.com` default | `""` (empty — require env var) |
| `functions/amortized-budget-engine/function_app.py` L42 | `governance@siemens-healthineers.com` default | `""` (empty — require env var) |
| `functions/amortized-budget-engine/function_app.py` L13 | `Aniket's exec view` comment | `Executive variance view` |
| `functions/amortized-budget-engine/function_app.py` L221,238,243,350,677 | `SHS_Billing_Element` / `shsBillingElement` / IT.76 logic | **Generalize:** rename to `GOVERNANCE_TAG_KEY` + `GOVERNANCE_TAG_VALUE` env vars. Keep the governance alert feature but make the tag name/value configurable. |
| `pipelines/azure-pipelines.yml` L35 | Hardcoded `subscriptionId: '37ffd444-...'` | `'<YOUR_SUBSCRIPTION_ID>'` |
| `pipelines/azure-pipelines.yml` L33 | `shs-finops-service-connection` | `'<YOUR_SERVICE_CONNECTION>'` |
| `scripts/config.json` contacts | `pavleenbali@microsoft.com` | `your-finops-team@example.com` |
| `scripts/sample-finance-budgets.csv` | All 7 rows with real sub ID `209d1618-...` | Replace with `00000000-0000-0000-0000-000000000000` placeholder |
| `scripts/Enable-AdminFeatures.ps1` L7-8 | Example sub ID `209d1618-...` | `<YOUR_SUBSCRIPTION_ID>` placeholder |
| `parameters/mvp.bicepparam` | All 18 SHS-specific tags, `pavleenbali@microsoft.com`, `DecommissionAfter` | **Delete this file** — it's MVP-specific. Keep `template.bicepparam` as the starter. |
| `parameters/template.bicepparam` L13 | `pavleenbali@microsoft.com` | `your-finops-team@example.com` |
| `parameters/dev.bicepparam` | `pavleenbali@microsoft.com` | `your-finops-team@example.com` |
| `parameters/prod.bicepparam` | `finops@siemens-healthineers.com` | `your-finops-team@example.com` |
| `parameters/staging.bicepparam` | `finops@siemens-healthineers.com` | `your-finops-team@example.com` |
| `tests/Seed-CosmosDemo.ps1` | Hardcoded sub ID, Cosmos name `cosmos-finops-r3s3hu4dmpfkg`, all `@shs.com` emails | Make all parameterized; replace emails with `user@example.com` |
| `tests/function/test_evaluator.py` | `@shs.com` emails (L98-100, 115-117, 149) | `@example.com` |
| `logic-apps/budget-change/teams-adaptive-card.json` L37 | Placeholder GUID `37ffd444-...` | `00000000-0000-0000-0000-000000000000` |

### 1.2 Power BI / Dashboard Files

| File | What to Remove/Replace |
|------|----------------------|
| `powerbi/README.md` | Hardcoded `func-finops-amortized-r3s3hu4dmpfkg` URLs, `cosmos-finops-r3s3hu4dmpfkg` endpoint |
| `powerbi/finops-cosmos-direct.pq` | Hardcoded `cosmos-finops-r3s3hu4dmpfkg` endpoint |
| `powerbi/finops-inventory.pq` | Hardcoded Function App URL + **leaked function key** `gujHN7swJAWn...` |
| `dashboards/power-bi-cosmos-connection.m` | Hardcoded Cosmos + Function App URLs |

**Action:** Replace all hardcoded URLs with `<YOUR_FUNCTION_APP>.azurewebsites.net` and `<YOUR_COSMOS_ACCOUNT>.documents.azure.com` placeholders. Remove the leaked function key entirely.

### 1.3 Documentation (customer references)

| File | Items to Sanitize |
|------|------------------|
| `README.md` | L91: `shs-finops-service-connection`, L446: `SHS admin`, L497: `Built by Microsoft CSA Pavleen Bali for Siemens Healthineers...` |
| `mvp-implementation.md` | **Entire file is customer-specific.** Move to `docs/examples/` as `example-mvp-deployment.md` or delete. Contains: SHS sub/tenant IDs, Aniket's requirements, Pavleen's email, SARP/SHARP references, SHS naming conventions, handover checklist. |
| `blueprint-strategy.md` (root + docs/) | **Same as above** — customer-specific delivery document. Move to `docs/examples/` or delete. |
| `docs/azure-devops-plan.md` | SHS DevOps org, Aniket/Jürgen names, sub IDs, `shs-finops-service-connection`, `a0072_SHSQA` references |
| `docs/cost-forecast.md` | Mostly generic — just replace `pavleenbali@microsoft.com` and `kumar.aniket@siemens-healthineers.com` with generic emails |
| `docs/iteration_01.md` | All "Kumar, Aniket" quotes, SHARP/SARP references, AWS billing reference specific to SHS |
| `docs/technical-guide.md` | SHS-specific Cosmos name/URLs, `pavleenbali@microsoft.com`, `kumar.aniket@siemens-healthineers.com`, SHARP integration section (keep but generalize to "ITSM Integration") |

### 1.4 SHS-Specific Features to Generalize

| Feature | Current (SHS-specific) | Open-Source Version |
|---------|----------------------|---------------------|
| IT.76 Governance Alert | Hardcoded `SHS_Billing_Element == "IT.76"` | Configurable env vars: `GOVERNANCE_TAG_KEY` + `GOVERNANCE_TAG_VALUE` |
| SHS mandatory tags | 18 SHS-specific tags in mvp.bicepparam | Remove — users set their own tags in their bicepparam |
| SHARP/ServiceNow integration | Detailed SHARP-specific integration | Rename to "ITSM Integration Guide" — keep as generic webhook/API patterns |
| `a0072_` naming prefix | SHS naming convention | Remove — platform uses `finops-` prefix which is already generic |

---

## 2. Repository Restructure for Open Source

### 2.1 New Repository Name & Structure

```
azure-amortized-cost-management/
├── .github/
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug_report.md
│   │   └── feature_request.md
│   └── workflows/
│       └── ci.yml                          # GitHub Actions CI (replaces azure-pipelines.yml)
├── README.md                               # Rewritten — professional open-source README
├── LICENSE                                 # MIT License
├── CONTRIBUTING.md                         # Contribution guidelines
├── CODE_OF_CONDUCT.md                      # Microsoft Open Source CoC
├── SECURITY.md                             # Security reporting
├── azuredeploy.json                        # ARM template for "Deploy to Azure" button
├── infra/
│   ├── main.bicep                          # Unchanged (already generic)
│   └── modules/                            # Unchanged
├── functions/
│   └── amortized-budget-engine/            # Sanitized function_app.py
├── parameters/
│   ├── template.bicepparam                 # Renamed from template, serves as starter
│   └── example.bicepparam                  # Single example file (was dev.bicepparam)
├── scripts/                                # Sanitized scripts
├── powerbi/                                # Sanitized PQ/DAX templates
├── dashboards/                             # Sanitized M scripts
├── queries/                                # Unchanged (already generic)
├── tests/                                  # Sanitized tests
├── docs/
│   ├── architecture.md                     # Rewritten from technical-guide.md (generic)
│   ├── deployment-guide.md                 # Rewritten from blueprint-strategy.md (generic)
│   ├── cost-forecast.md                    # Sanitized
│   ├── ci-cd-guide.md                      # Rewritten from azure-devops-plan.md (generic)
│   ├── itsm-integration.md                 # Rewritten from SHARP sections (generic)
│   └── examples/
│       └── enterprise-deployment.md        # Sanitized version of mvp-implementation.md
└── bicepconfig.json                        # Unchanged
```

### 2.2 Files to Delete (not needed in open source)

| File | Reason |
|------|--------|
| `mvp-implementation.md` (root) | Customer-specific delivery doc — move sanitized version to `docs/examples/` |
| `blueprint-strategy.md` (root) | Duplicate of `docs/blueprint-strategy.md` |
| `parameters/mvp.bicepparam` | Customer-specific with 18 SHS tags |
| `infra/main.json` | Compiled ARM output — regenerate from Bicep |
| `docs/architecture_diagram.svg` | Empty Excalidraw placeholder |

### 2.3 Files to Add

| File | Purpose |
|------|---------|
| `LICENSE` | MIT license text |
| `CONTRIBUTING.md` | How to contribute, PR process, code standards |
| `CODE_OF_CONDUCT.md` | Microsoft Open Source Code of Conduct |
| `SECURITY.md` | Vulnerability reporting process |
| `.github/workflows/ci.yml` | GitHub Actions: Bicep lint + build + pytest |
| `azuredeploy.json` | ARM template for one-click Deploy to Azure button |
| `.gitignore` | Proper gitignore for Python + Bicep + PowerShell |

---

## 3. GitHub Accelerator Template — One-Click Deploy

### 3.1 "Deploy to Azure" Button

Add to README.md:

```markdown
[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2F<ORG>%2Fazure-amortized-cost-management%2Fmain%2Fazuredeploy.json)
```

### 3.2 What the One-Click Deploy Does

The `azuredeploy.json` (generated from `main.bicep`) deploys the full stack into a single subscription:

1. Creates resource group `rg-finops-governance-{env}`
2. Deploys all 9+ modules: Action Group, Budget, Policy, Storage, Cosmos DB, 3 Logic Apps, Event Grid, Function App
3. User provides only 4 required inputs via the Azure Portal form:
   - **Email** (for alerts)
   - **Location** (Azure region)
   - **Environment** (dev/staging/prod)
   - **Subscription Budget** (monthly EUR amount)

### 3.3 Generate azuredeploy.json

```bash
az bicep build --file infra/main.bicep --outfile azuredeploy.json
```

This compiles Bicep to ARM JSON, which is what the "Deploy to Azure" button requires.

### 3.4 Post-Deploy Setup (documented in README)

After one-click deploy, 3 manual steps:

1. **Create amortized cost export:** `.\scripts\New-AmortizedExport.ps1`
2. **Deploy Function App code:** `func azure functionapp publish <app-name> --python`
3. **RBAC assignment** (if deployer doesn't have Owner): `.\scripts\Enable-AdminFeatures.ps1`

### 3.5 GitHub Template Repository

Mark the repo as a **template repository** in GitHub settings:
- Settings → General → Template repository ✓
- Users click "Use this template" → creates a copy in their own GitHub org
- They edit `parameters/template.bicepparam` with their values and deploy

---

## 4. README.md Rewrite — Open-Source Version

The new README should follow the standard open-source pattern:

```
# Azure Amortized Cost Management

> Enterprise-grade budget management and amortized cost alerting for Azure.
> Bridges Azure's actual-cost-only budget limitation with amortized cost tracking.

[![Deploy to Azure](button)](link)

## The Problem
Azure native budgets only alert on actual cost. Organizations using Reserved Instances
and Savings Plans see a EUR 36K spike on purchase day, then nothing for 3 years.
This platform uses Azure Cost Management's amortized export to spread costs daily
and alert on real consumption patterns.

## What You Get (one-click deploy)
- Subscription + RG-level budgets with 5 escalating thresholds
- Auto-budget on new resource groups (EUR 100 default via Event Grid)
- Self-service budget changes (Logic App with floor/cap guardrails)
- Amortized cost alerting (Python Function reads daily exports)
- Finance vs Technical budget comparison
- 4-tier dynamic alert thresholds based on spend brackets
- Azure Workbook dashboard + Power BI templates
- Audit policy flagging RGs without budgets
- Quarterly automatic budget recalculation

## Quick Start
1. Click "Deploy to Azure" above
2. Fill in 4 parameters (email, region, environment, budget amount)
3. Run post-deploy setup (cost export + function publish)

## Architecture
[diagram]

## Cost
~$2.50/month per subscription (serverless, consumption-based)

## Documentation
- [Deployment Guide](docs/deployment-guide.md)
- [Architecture](docs/architecture.md)
- [Cost Forecast](docs/cost-forecast.md)
- [CI/CD Guide](docs/ci-cd-guide.md)

## Contributing
See [CONTRIBUTING.md](CONTRIBUTING.md)

## License
MIT
```

---

## 5. Execution Plan — Phased Approach

### Phase 1: Sanitize (Day 1)

| # | Task | Files Affected | Risk |
|---|------|---------------|------|
| 1.1 | Replace all `@siemens-healthineers.com` emails | function_app.py, params, docs | Low |
| 1.2 | Replace all `@microsoft.com` emails | params, docs, config.json | Low |
| 1.3 | Replace all hardcoded subscription/tenant IDs | docs, scripts, pipeline, tests, params | Low |
| 1.4 | Replace hardcoded Cosmos/Function URLs | powerbi/, dashboards/ | Low |
| 1.5 | Remove leaked function key from `finops-inventory.pq` | powerbi/ | **Critical** |
| 1.6 | Generalize SHS_Billing_Element to configurable governance tag | function_app.py | Medium |
| 1.7 | Replace all `Aniket`/`Kumar`/`Pavleen`/`Jürgen` name references | docs/ | Low |
| 1.8 | Replace all `Siemens`/`SHS`/`Healthineers` references | all docs, tests, function | Low |
| 1.9 | Replace `SHARP`/`SARP` with generic `ITSM` | docs/ | Low |
| 1.10 | Replace `@shs.com` test emails with `@example.com` | tests/ | Low |

### Phase 2: Restructure (Day 2)

| # | Task |
|---|------|
| 2.1 | Delete `mvp-implementation.md` (root), `blueprint-strategy.md` (root), `parameters/mvp.bicepparam`, `infra/main.json`, `docs/architecture_diagram.svg` |
| 2.2 | Rename repo to `azure-amortized-cost-management` |
| 2.3 | Rewrite `README.md` as professional open-source README |
| 2.4 | Rewrite `docs/technical-guide.md` → `docs/architecture.md` (remove customer context) |
| 2.5 | Rewrite `docs/blueprint-strategy.md` → `docs/deployment-guide.md` (generic) |
| 2.6 | Rewrite `docs/azure-devops-plan.md` → `docs/ci-cd-guide.md` (add GitHub Actions) |
| 2.7 | Create `docs/itsm-integration.md` from SHARP sections (generic patterns) |
| 2.8 | Move sanitized MVP doc to `docs/examples/enterprise-deployment.md` |

### Phase 3: GitHub Setup (Day 3)

| # | Task |
|---|------|
| 3.1 | Add `LICENSE` (MIT) |
| 3.2 | Add `CONTRIBUTING.md` |
| 3.3 | Add `CODE_OF_CONDUCT.md` |
| 3.4 | Add `SECURITY.md` |
| 3.5 | Add `.gitignore` |
| 3.6 | Add `.github/workflows/ci.yml` (GitHub Actions: Bicep lint + pytest) |
| 3.7 | Generate `azuredeploy.json` from `main.bicep` |
| 3.8 | Add "Deploy to Azure" button to README |
| 3.9 | Create GitHub repo, push, mark as template repository |
| 3.10 | Add issue templates (bug report + feature request) |

### Phase 4: Validate (Day 4)

| # | Task |
|---|------|
| 4.1 | Run `grep -ri "siemens\|shs\|healthineers\|aniket\|pavleen\|kumar"` — must return 0 results |
| 4.2 | Run `grep -ri "209d1618\|37ffd444\|4417d3fe\|a0072\|r3s3hu4dmpfkg\|gujHN7"` — must return 0 results |
| 4.3 | Run `az bicep build --file infra/main.bicep` — must compile cleanly |
| 4.4 | Run `python -m pytest tests/function/ -v` — all 14 tests must pass |
| 4.5 | Test "Deploy to Azure" button with azuredeploy.json in a test subscription |
| 4.6 | Review every file one more time for any remaining PII or customer data |

---

## 6. GitHub Actions CI/CD (replaces Azure Pipelines for open source)

```yaml
# .github/workflows/ci.yml
name: CI — Validate & Test

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  validate-bicep:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install Bicep
        run: az bicep install
      - name: Bicep Build
        run: az bicep build --file infra/main.bicep
      - name: Bicep Lint
        run: az bicep lint --file infra/main.bicep

  test-python:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      - name: Install dependencies
        run: pip install -r functions/amortized-budget-engine/requirements.txt pytest
      - name: Run tests
        run: python -m pytest tests/function/ -v

  generate-arm:
    runs-on: ubuntu-latest
    needs: validate-bicep
    if: github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v4
      - name: Generate ARM template
        run: az bicep build --file infra/main.bicep --outfile azuredeploy.json
      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: arm-template
          path: azuredeploy.json
```

---

## 7. Security Considerations for Open Source

| Item | Action |
|------|--------|
| **Leaked function key** | `gujHN7swJAWn...` in `finops-inventory.pq` — **MUST rotate immediately** and remove from code |
| **Git history** | If repo is forked from a private repo, the git history may contain secrets. **Start fresh** with `git init` or use BFG Repo-Cleaner |
| **No secrets in code** | All secrets must be environment variables or Key Vault references |
| **Dependency scanning** | Enable Dependabot for Python packages |
| **Code scanning** | Enable GitHub Advanced Security / CodeQL for Python |

---

## 8. Naming & Branding

| Current | Open Source |
|---------|------------|
| `azure-amortised-cost-analysis` | `azure-amortized-cost-management` |
| "FinOps Budget Alerts Automation Platform" | "Azure Amortized Cost Management" |
| "Budget Alerts Automation" | "Amortized Cost Management" |
| `shs-finops-service-connection` | `finops-service-connection` |
| `code-base/budget-alerts-automation/` path refs | Root-level (it IS the repo now) |

---

## 9. Distribution Channels — How Customers Can Plug It In

### Channel 1: GitHub "Deploy to Azure" Button (Ready Now)

The simplest path. One click → Azure Portal → fill 4 fields → deploy.

```markdown
[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2F<ORG>%2Fazure-amortized-cost-management%2Fmain%2Fazuredeploy.json)
```

**User experience:**
1. Click button → Azure Portal opens
2. Select subscription, region, environment, email
3. Click "Review + Create" → full stack deployed in ~5 minutes
4. 3 post-deploy steps (cost export, function publish, RBAC)

**Effort:** Generate `azuredeploy.json` from Bicep. Already supported.

### Channel 2: GitHub Template Repository

Mark the repo as a **template** in GitHub settings. Users click "Use this template" to create their own copy instantly, then customize parameters and push to their own CI/CD.

**Best for:** Teams that want to customize the platform, add their own modules, or integrate with existing pipelines.

### Channel 3: Azure Marketplace — Managed Application

Publish as an **Azure Managed Application** on the Azure Marketplace. Customers find it by searching "amortized cost management" in the Portal.

**How it works:**
1. Package the Bicep/ARM template + createUiDefinition.json (the portal form)
2. Publish via Partner Center as a Solution Template (free) or Managed App
3. Customers deploy from Marketplace with guided UI — no GitHub needed

**createUiDefinition.json** defines the portal form:
```json
{
  "steps": [
    {
      "name": "basics",
      "elements": [
        { "name": "finopsEmail", "type": "Microsoft.Common.TextBox", "label": "FinOps Team Email" },
        { "name": "subscriptionBudget", "type": "Microsoft.Common.Slider", "label": "Monthly Subscription Budget (EUR)", "min": 1000, "max": 500000, "defaultValue": 10000 },
        { "name": "enableAmortized", "type": "Microsoft.Common.CheckBox", "label": "Enable Amortized Cost Pipeline", "defaultValue": false }
      ]
    }
  ]
}
```

**Effort:** Medium. Need Partner Center account + createUiDefinition.json + marketplace listing.

**Best for:** Enterprise customers who want a supported, discoverable solution.

### Channel 4: Azure Quickstart Templates Gallery

Submit as an official **Azure Quickstart Template** at [github.com/Azure/azure-quickstart-templates](https://github.com/Azure/azure-quickstart-templates).

**Requirements:**
- ARM/Bicep template passes Azure best practices validation
- Includes `azuredeploy.json`, `azuredeploy.parameters.json`, `metadata.json`
- Passes CI validation (template analyzer)
- PR reviewed by Azure team

**Effort:** Low-medium. Mostly formatting + metadata.

**Best for:** Visibility in the official Azure template gallery.

### Channel 5: Azure CLI Extension (future)

Package as an `az finops` CLI extension:
```bash
az extension add --name finops
az finops deploy --location westeurope --email finops@company.com --budget 10000
az finops status --subscription <subId>
az finops evaluate --now
```

**Effort:** High. Requires Python CLI extension development.

**Best for:** DevOps teams who prefer CLI over Portal.

### Channel 6: FinOps Foundation Ecosystem

Register with the [FinOps Foundation](https://www.finops.org/) as a community tool:
- Listed in FinOps Landscape / Tool Registry
- Potential FOCUS spec certification
- Presented at FinOps X conference

**Effort:** Low (registration + documentation).

### Recommended Launch Order

| Phase | Channel | Effort | Reach |
|-------|---------|--------|-------|
| **Week 1** | GitHub + Deploy to Azure button | Low | Developers, CSAs |
| **Week 2** | GitHub Template Repository | Zero | Teams wanting customization |
| **Month 1** | Azure Quickstart Templates | Medium | Azure Portal search |
| **Month 2** | Azure Marketplace (Solution Template) | Medium | Enterprise buyers |
| **Month 3** | FinOps Foundation listing | Low | FinOps community |
| **Future** | `az finops` CLI extension | High | CLI power users |

---

## 10. Future Enhancements (post-launch)

| # | Enhancement | Value |
|---|-------------|-------|
| 1 | **Terraform module** alongside Bicep | Reach Terraform users (larger community) |
| 2 | **Management Group scope** deployment option | Enterprise customers with dozens of subscriptions |
| 3 | **Grafana dashboard** templates | Alternative to Azure Workbook for multi-cloud teams |
| 4 | **FinOps Framework alignment** | Badge + documentation per FinOps Foundation FOCUS spec |
| 5 | **GitHub Marketplace listing** | Discoverability via marketplace |
| 6 | **Azure Verified Module (AVM)** submission | Official Microsoft endorsement |
| 7 | **Multi-cloud extension** | AWS Cost Explorer + GCP Billing integration |
| 8 | **Slack + PagerDuty integration** | Alternative to Teams for alert routing |
| 9 | **Budget recommendation engine** | ML-based budget suggestions from historical spend |

---

*Strategy authored April 2026. Ready for execution.*
