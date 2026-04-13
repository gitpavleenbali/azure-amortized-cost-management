# dashboards/

Power BI connection templates for the Cosmos DB direct-connect approach.

| File | Purpose |
|------|---------|
| `power-bi-cosmos-connection.m` | Full Power Query M script for connecting Power BI to Cosmos DB with error handling, retry logic, and typed columns |

## Usage

1. Open **Power BI Desktop** → Get Data → Azure Cosmos DB
2. Enter your Cosmos DB endpoint and database (`finops`)
3. Go to **Transform Data** → **Advanced Editor**
4. Paste the contents of `power-bi-cosmos-connection.m`
5. Update the endpoint URL with your Cosmos account

> For the complete visualization setup guide (Workbook + Power BI), see [docs/visualization.md](../docs/visualization.md).
