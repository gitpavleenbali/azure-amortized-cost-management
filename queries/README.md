# queries/

Ad-hoc query templates for exploring FinOps data outside Power BI or the Azure Workbook.

| File | Language | Purpose |
|------|----------|---------|
| `budget-compliance.kql` | KQL (Kusto) | Azure Resource Graph query — audit budget compliance across all subscriptions |
| `cosmos-demo-queries.sql` | SQL (Cosmos DB) | Sample Cosmos DB SQL queries for exploring the `finops.inventory` container |
| `spend-vs-budget.sql` | SQL (Cosmos DB) | Spend vs budget comparison with rollups, top spenders, and variance analysis |

## Usage

- **KQL**: Run in Azure Portal → Resource Graph Explorer, or in Log Analytics
- **Cosmos SQL**: Run in Azure Portal → Cosmos DB → Data Explorer → New SQL Query

> For full visualization setup, see the [Visualization Guide](../docs/visualization.md).
