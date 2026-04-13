# Budget & Alert Automation Framework

## 1. What is this framework about?

This framework defines a governed, automated system to control and monitor cloud spending using budgets and alerts across the organization.

It ensures:

- Every resource group and subscription has a budget
- Users are alerted before overspending
- Costs are tracked using both actual and amortized views
- Budget management is automated and scalable (8,000+ RGs)

## 2. Key Problem Statements

The framework addresses these major gaps:

❌ **No budgets across most resource groups**
- Thousands of RGs exist without cost control

❌ **No enforcement during creation**
- Users can create resource groups without budgets

❌ **Azure limitation: only actual cost**
- Azure budgets track actual cost, but business needs amortized cost

❌ **No self-service**
- Budget changes require manual intervention

❌ **No visibility dashboard**
- No unified "Spend vs Budget" view

## 3. Core Design Principles

🔹 **1. Multi-level budgeting**

Budgets are applied at:

- Subscription level → strategic control
- Resource Group level → operational control

🔹 **2. Automation-first approach**

Everything is automated:

- Budget creation
- Alerts
- Enforcement
- Updates (Tag Owner can access control)

🔹 **4. Proactive alerts (not reactive)**

Alerts trigger at: (custom amortized cost)

- 50% → Awareness (Tag Contact Tec rep1 n 2)
- 75% → Warning (Tag Contact Tec rep1 n 2 + Owner)
- 90% → Critical (Tag Contact Tec rep1 n 2 + Owner)
- 100% → Breach (Tag Contact Tec rep1 n 2 + Owner + Billing Contact)
- 110% → Forecasted overspend

> **Stakeholder feedback:** Spend grouping should be considered.
>
> **Stakeholder feedback:** A base budget should be kept for RGs between $0 to $100.

## 4. Budgeting Model (Conceptual)

📊 **Existing Resource Groups**

Budget is based on past usage:

👉 Average of last 3 months

📊 **New Resource Groups**

Two scenarios:

| Scenario | Budget |
|----------|--------|
| Created via standard process (Service Catalog) | User-defined |
| Created manually | Default $100 |

Users can create resource groups without budgets

**Solution:**

- Detect new RG creation
- Automatically assign a budget

> **Stakeholder feedback:** The ITSM Team should modify the RG creation form to assign the budget to the RG.
>
> **Stakeholder feedback:** Can this be handled via Policy?

## 5. Self-Service Budget Management

Instead of manual processes:

Users can:

- Request budget increase
    - Provide justification
    - Get approval if needed

Controls:

- Minimum budget limit
- Maximum increase limit
- Approval for large changes

> **Stakeholder feedback:** This should be done under the Service Catalog.
>
> **Stakeholder feedback:** Budget changes should not be allowed directly from the portal.
>
> **Stakeholder feedback:** Service Catalog integration can be phased in later.

## 6. Dashboard Concept

A centralized dashboard shows:

- Spend vs Budget
- Over-budget resources
- Under-utilized budgets
- Business unit performance

---

## Requirements for Service Catalog – RG Budget Management

### 1. Budget Field Integration in Service Catalog

- Introduce a new mandatory field **"Monthly Budget"** for all Resource Groups (RGs).
- This field must be captured during:
    - New RG creation via Service Catalog
    - VM provisioning requests that result in a new RG
- The captured budget must be synchronized with the Azure Budget service at the RG level.

---

### 2. Budget Sync for Existing Resource Groups

- Add the **Monthly Budget** field to all existing RGs in ITSM CMDB.
- Perform an initial data sync to populate budgets from Azure where available.
- Ensure ongoing synchronization:
    - Any budget updates made in Azure should automatically reflect in the ITSM system via event-driven updates.

> **Stakeholder feedback:** If there is an existing mapping from the ITSM system to Azure, this step can be skipped and budgets can be read/written directly to the portal.

---

### 3. Budget Change Request Workflow

- Create a new Service Catalog form to allow RG owners to request changes to the monthly budget.
- The form should capture:
    - RG details (pre-filled/selectable)
    - Current budget (read-only)
    - Requested budget
    - Justification (if required)
- Upon submission:
    - Notify FinOps team, RG Owner, Billing Contact, and Tech Rep 1
    - Trigger approval workflow (if applicable)
    - Update both Azure and the ITSM system upon approval

---

## The open question is:

- RG created manually can be forced by policy to provide the budget OR a policy can identify RG with no budget and again default budget as 100

- RG which has spend in the bracket of $0 to $100 can be should be assigned the budget as $100 and monitored against that OR we should approach this with customized budget logic using Budget alert Notification improvisation.xlsx

- We are storing the RG budget amount in Azure RG "budget". Do we need to store the same in the ITSM CMDB too to make dashboard or reports and in that way also use it in Budget change request catalog form to showcase the current budget assigned?

---

## Budget Alert Notification Improvisation

Alert thresholds are **not fixed** — they scale dynamically based on the RG's 3-month average spend tier. Smaller RGs get higher thresholds (more tolerance), larger RGs get tighter thresholds (less tolerance). Each tier defines three severity levels with escalating recipients.

**Scope:**
- AWS Account
- Azure Resource Group with Tag Value as Billing level = RG
- Azure Subscription with Tag Value as Billing level = SUB

**Phase:** All regions and business units

### Tier 1: Last 3-month Avg Spend $0 – $1K

| HeadUp Alert | Warning Alert | Critical Alert |
|-------------|--------------|----------------|
| **Recipients:** Owner, TR1 and TR2 | **Recipients:** Owner, TR1 and TR2, Billing Contact | **Recipients:** Owner, TR1 and TR2, Billing Contact, Governance |
| **Threshold:** 200% | **Threshold:** 250% | **Threshold:** 300% |

### Tier 2: Last 3-month Avg Spend $1K – $5K

| HeadUp Alert | Warning Alert | Critical Alert |
|-------------|--------------|----------------|
| **Recipients:** Owner, TR1 and TR2 | **Recipients:** Owner, TR1 and TR2, Billing Contact | **Recipients:** Owner, TR1 and TR2, Billing Contact, Governance |
| **Threshold:** 150% | **Threshold:** 200% | **Threshold:** 250% |

### Tier 3: Last 3-month Avg Spend $5K – $10K

| HeadUp Alert | Warning Alert | Critical Alert |
|-------------|--------------|----------------|
| **Recipients:** Owner, TR1 and TR2 | **Recipients:** Owner, TR1 and TR2, Billing Contact | **Recipients:** Owner, TR1 and TR2, Billing Contact, Governance |
| **Threshold:** 125% | **Threshold:** 150% | **Threshold:** 200% |

### Tier 4: Last 3-month Avg Spend Above $10K

| HeadUp Alert | Warning Alert | Critical Alert |
|-------------|--------------|----------------|
| **Recipients:** Owner, TR1 and TR2 | **Recipients:** Owner, TR1 and TR2, Billing Contact | **Recipients:** Owner, TR1 and TR2, Billing Contact, Governance |
| **Threshold:** 100% | **Threshold:** 125% | **Threshold:** 150% |

### Summary Matrix

| Spend Tier | HeadUp | Warning | Critical |
|-----------|--------|---------|----------|
| $0 – $1K | 200% | 250% | 300% |
| $1K – $5K | 150% | 200% | 250% |
| $5K – $10K | 125% | 150% | 200% |
| Above $10K | 100% | 125% | 150% |

**Key design insight:** Low-spend RGs ($0–$1K) only alert at 200%+ because a $50 RG hitting $100 is noise, not risk. High-spend RGs ($10K+) alert at 100% because a $10K overrun is material.

### IT.76 Alert — Special Request

Any new RG/SUB/Account created with `Billing_Element` = IT.76, send notification to Governance.

Any existing RG/SUB/Account where `Billing_Element` value is modified from anything else to IT.76 — also send notification to Governance.

### Current Budget Alert Process (Reference — AWS Side)

> AWS Billing Alert automation compares current cost of AWS account with average of previous three months bills. This automation sends maximum of three alerts to the technical responsible for account and cli owner. The notification will be triggered, if current cost exceeds the average of three months' bills by:
>
> 1. 100%
> 2. 150%
> 3. 300%
> 4. 500%

**Example alert (AWS):**

> **Subject:** AWS Billing - Alert for Account - 918154264068
>
> Hi,
>
> Current cost of the account 918154264068 (Noona) is $2124.06 (without any discounts or refunds) and is exceeding 100% of average bill of previous three months.
>
> Please review your account for any unusual activities.
>
> For any clarification please contact
> cloud-ops@example.com or
> cloud-team@example.com.
>
> Thanks & Regards

### Alert Email Template (Azure — Proposed)

The following template applies to all three severity levels (HeadUp, Warning, Critical). The subject line and tone change per severity.

```
[Name]
Dear [Owner],

As part of our ongoing commitment to transparency and effective
cloud cost management, we wanted to provide you with an update
on your cloud spend for the [Month].

Current Cloud Expenditure: [Amount Spent]

As of [Date], your total cloud expenditure for the current
[Month] is [Amount Spent]. You have crossed [Percentage]% of
last 3 month Avg spend.
```

**Template variables:**

| Variable | Source |
|----------|--------|
| `[Owner]` | RG tag: `Owner` |
| `[Month]` | Current calendar month |
| `[Amount Spent]` | Cosmos DB: `amortizedMTD` |
| `[Date]` | Current evaluation date |
| `[Percentage]` | Cosmos DB: `actualPct` |
| `[Name]` | Derived from Owner tag or recipient list |