-- ============================================================
-- FinOps Inventory Demo Queries
-- Location: Cosmos DB > Data Explorer > finops > inventory > New SQL Query
-- How to use: Select ONLY the lines of one query, then click Execute Query
--             Cosmos DB runs only the highlighted/selected text
-- ============================================================

-- Q1: Full inventory overview (run this first)
SELECT c.resourceGroup, c.costCenter, c.complianceStatus, c.technicalBudget, c.financeBudget, c.amortizedMTD, c.forecastEOM, c.actualPct, c.forecastPct FROM c ORDER BY c.actualPct DESC

-- Q2: Over-budget RGs (red alerts - select and run)
SELECT c.resourceGroup, c.costCenter, c.actualPct, c.technicalBudget, c.amortizedMTD, c.amortizedMTD - c.technicalBudget AS overageEUR FROM c WHERE c.complianceStatus = 'over_budget'

-- Q3: Finance vs Technical variance (exec view - Aniket's requirement)
SELECT c.costCenter, c.resourceGroup, c.financeBudget, c.technicalBudget, c.amortizedMTD, c.amortizedMTD - c.financeBudget AS financeVarianceEUR FROM c WHERE c.financeBudget > 0 ORDER BY (c.amortizedMTD - c.financeBudget) DESC

-- Q4: Warning RGs (forecast will breach)
SELECT c.resourceGroup, c.costCenter, c.forecastPct, c.forecastEOM, c.technicalBudget, c.forecastEOM - c.technicalBudget AS projectedOverageEUR FROM c WHERE c.complianceStatus = 'warning'

-- Q5: On-track RGs (healthy)
SELECT c.resourceGroup, c.costCenter, c.actualPct, c.technicalBudget - c.amortizedMTD AS remainingBudgetEUR FROM c WHERE c.complianceStatus = 'on_track'

-- Q6: Executive summary by Business Unit
SELECT c.costCenter, SUM(c.financeBudget) AS totalFinanceBudget, SUM(c.amortizedMTD) AS totalSpend, SUM(c.amortizedMTD) - SUM(c.financeBudget) AS totalVariance FROM c GROUP BY c.costCenter
