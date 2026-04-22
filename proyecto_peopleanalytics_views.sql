-- ============================================================
-- VIEW 1: vw_fact_ventas
-- Granularidad: una fila por línea de pedido
-- ============================================================
CREATE OR ALTER VIEW dbo.vw_fact_ventas AS
SELECT
    od.SalesOrderID,
    oh.OrderDate,
    YEAR(oh.OrderDate) AS Year,
    MONTH(oh.OrderDate) AS Month,
    oh.CustomerID,
    oh.TerritoryID,
    od.ProductID,
    oh.OnlineOrderFlag,
    od.OrderQty,
    od.UnitPrice,
    od.LineTotal AS Revenue,
    CASE 
        WHEN pch.StandardCost > od.UnitPrice THEN od.UnitPrice * od.OrderQty
        ELSE pch.StandardCost * od.OrderQty
    END AS Cost,

    CASE 
        WHEN pch.StandardCost > od.UnitPrice 
        THEN 0
        ELSE od.LineTotal - (pch.StandardCost * od.OrderQty)
    END AS Profit,

    CASE 
        WHEN pch.StandardCost > od.UnitPrice 
        THEN 0
        ELSE CAST(
            (od.LineTotal - (pch.StandardCost * od.OrderQty))
            / NULLIF(od.LineTotal, 0) * 100
        AS DECIMAL(5,2))
    END AS ProfitMargin
FROM
    Sales.SalesOrderDetail AS od
INNER JOIN Sales.SalesOrderHeader AS oh
    ON od.SalesOrderID = oh.SalesOrderID
INNER JOIN Production.Product AS p
    ON od.ProductID = p.ProductID
INNER JOIN Production.ProductCostHistory AS pch
    ON od.ProductID = pch.ProductID
    AND pch.StartDate = (
        SELECT MAX(StartDate)
        FROM Production.ProductCostHistory
        WHERE ProductID = od.ProductID
        AND StartDate <= oh.OrderDate
    )
WHERE
    p.StandardCost > 0;

-- ============================================================
-- VIEW 2: vw_dim_producto
-- ============================================================
CREATE OR ALTER VIEW dbo.vw_dim_producto AS
SELECT
    p.ProductID,
    p.Name AS ProductName,
    sub.ProductSubcategoryID AS SubcategoryID,
    sub.Name AS Subcategory,
    cat.ProductCategoryID AS CategoryID,
    cat.Name AS Category,
    p.StandardCost
FROM
    Production.Product AS p
INNER JOIN Production.ProductSubcategory AS sub
    ON p.ProductSubcategoryID = sub.ProductSubcategoryID
INNER JOIN Production.ProductCategory AS cat
    ON sub.ProductCategoryID = cat.ProductCategoryID
WHERE
    p.StandardCost > 0;

-- ============================================================
-- VIEW 3: vw_dim_cliente
-- Incluye segmentación y métricas de valor
-- ============================================================
CREATE OR ALTER VIEW dbo.vw_dim_cliente AS
WITH base AS (
    SELECT
        CustomerID,
        MIN(OrderDate) AS PrimeraCompra,
        MAX(OrderDate) AS UltimaCompra,
        COUNT(SalesOrderID) AS NumPedidos,
        SUM(TotalDue) AS RevenueTotal
    FROM 
        Sales.SalesOrderHeader
    GROUP BY 
        CustomerID
)
SELECT
    CustomerID,
    PrimeraCompra,
    UltimaCompra,
    NumPedidos,
    CAST(RevenueTotal AS DECIMAL(10,2)) AS RevenueTotal,
    CAST(RevenueTotal / NumPedidos AS DECIMAL(10,2)) AS AOV,
    CAST(
        CASE
            WHEN DATEDIFF(DAY, PrimeraCompra, UltimaCompra) / 365.25 = 0 THEN RevenueTotal
            ELSE RevenueTotal / (DATEDIFF(DAY, PrimeraCompra, UltimaCompra) / 365.25)
        END
    AS DECIMAL(10,2))                               AS CLV,
    CASE
        WHEN NumPedidos = 1 THEN '1 compra'
        WHEN NumPedidos = 2 THEN '2 compras'
        ELSE '3+ compras'
    END AS Segmento
FROM base;

-- ============================================================
-- VIEW 4: vw_dim_territorio
-- ============================================================
CREATE OR ALTER VIEW dbo.vw_dim_territorio AS
SELECT
    TerritoryID,
    Name,
    CountryRegionCode,
    [Group]
FROM
    Sales.SalesTerritory;
