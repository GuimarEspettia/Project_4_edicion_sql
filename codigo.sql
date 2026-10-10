USE CATALOG workspace;
USE SCHEMA default;

CREATE OR REPLACE TABLE ventas AS
SELECT
  InventoryId, Store, Brand, Description, Size,
  SalesQuantity, SalesDollars, SalesPrice,
  to_date(SalesDate, 'M/d/yyyy') AS SalesDate,
  Volume, Classification, ExciseTax,
  VendorNo AS VendorNumber,
  TRIM(VendorName) AS VendorName
FROM read_files('/Volumes/workspace/default/inventory_files/SalesFINAL12312016.csv');

CREATE OR REPLACE TABLE compras AS
SELECT
  InventoryId, Store, Brand, Description, Size,
  VendorNumber, TRIM(VendorName) AS VendorName, PONumber,
  CAST(PODate AS DATE)        AS PODate,
  CAST(ReceivingDate AS DATE) AS ReceivingDate,
  CAST(InvoiceDate AS DATE)   AS InvoiceDate,
  CAST(PayDate AS DATE)       AS PayDate,
  PurchasePrice, Quantity, Dollars, Classification
FROM read_files('/Volumes/workspace/default/inventory_files/PurchasesFINAL12312016.csv');

CREATE OR REPLACE TABLE facturas_compra AS
SELECT
  VendorNumber, TRIM(VendorName) AS VendorName,
  CAST(InvoiceDate AS DATE) AS InvoiceDate,
  PONumber,
  CAST(PODate AS DATE)  AS PODate,
  CAST(PayDate AS DATE) AS PayDate,
  Quantity, Dollars, Freight
FROM read_files('/Volumes/workspace/default/inventory_files/InvoicePurchases12312016.csv');

CREATE OR REPLACE TABLE inventario_inicial AS
SELECT InventoryId, Store, TRIM(City) AS City, Brand, Description, Size,
       onHand, Price, CAST(startDate AS DATE) AS startDate
FROM read_files('/Volumes/workspace/default/inventory_files/BegInvFINAL12312016.csv');

CREATE OR REPLACE TABLE inventario_final AS
SELECT InventoryId, Store, TRIM(City) AS City, Brand, Description, Size,
       onHand, Price, CAST(endDate AS DATE) AS endDate
FROM read_files('/Volumes/workspace/default/inventory_files/EndInvFINAL12312016.csv');

CREATE OR REPLACE TABLE lista_precios_2017 AS
SELECT Brand, Description, Price, Size, Volume, Classification,
       PurchasePrice, VendorNumber, TRIM(VendorName) AS VendorName
FROM read_files('/Volumes/workspace/default/inventory_files/2017PurchasePricesDec.csv');

-- Q01. Top 10 productos por unidades vendidas
SELECT Brand, Description, SUM(SalesQuantity) AS Unidades_Vendidas
FROM ventas
GROUP BY Brand, Description
ORDER BY Unidades_Vendidas DESC
LIMIT 10;

-- Q02. Cantidad de Facturas y Flete total por mes
SELECT date_format(InvoiceDate, 'yyyy-MM') AS Mes,
       COUNT(*) AS facturas,
       ROUND(SUM(Freight), 0) AS Flete_USD
FROM facturas_compra
GROUP BY mes
ORDER BY mes;


-- Q03. Top 10 proveedores por monto comprado en 2016 y % del total
SELECT
  VendorNumber, VendorName AS proveedor,
  ROUND(SUM(Dollars), 2) AS total_comprado,
  SUM(Quantity)      AS unidades,
  ROUND(100 * SUM(Dollars) / SUM(SUM(Dollars)) OVER (), 2) AS porcentaje_total
FROM compras
GROUP BY VendorNumber, VendorName
ORDER BY total_comprado DESC
LIMIT 10;


-- Q04. Compras por mes y cambio contra el mes anterior
WITH mensual AS (
  SELECT date_format(PODate, 'yyyy-MM') AS mes,
         ROUND(SUM(Dollars), 0) AS compras_usd
  FROM compras
  WHERE PODate >= '2016-01-01'
  GROUP BY mes
)
SELECT mes, compras_usd,
       compras_usd - LAG(compras_usd) OVER (ORDER BY mes) AS cambio_usd
FROM mensual
ORDER BY mes;


-- Q05. Unidades y dolares vendidos por mes y clasificacion
SELECT
  date_format(SalesDate, 'yyyy-MM') AS mes,
  CASE Classification WHEN 1 THEN 'Licor' WHEN 2 THEN 'Vino' END AS tipo_producto,
  SUM(SalesQuantity) AS unidades_vendidas,
  ROUND(SUM(SalesDollars), 2) AS ventas_usd,
  ROUND(SUM(SalesDollars) / SUM(SalesQuantity), 2) AS precio_promedio
FROM ventas
GROUP BY date_format(SalesDate, 'yyyy-MM'), Classification
ORDER BY mes, tipo_producto;


-- Q6. Lead time promedio por proveedor (Recepcion - PO)
SELECT
  VendorNumber AS VendorID,
  VendorName AS proveedor,
  COUNT(DISTINCT PONumber) AS ordenes_compra,
  SUM(Quantity) AS unidades_recibidas,
  ROUND(SUM(Dollars), 2) AS monto_comprado,
  ROUND(AVG(datediff(ReceivingDate, PODate)), 2) AS lead_time_prom_dias,
  MAX(datediff(ReceivingDate, PODate)) AS lead_time_max_dias
FROM compras
GROUP BY VendorNumber, VendorName
ORDER BY lead_time_prom_dias ASC;

-- Q07. Margen promedio por tipo de producto (precio de venta vs precio de compra)
SELECT CASE Classification WHEN 1 THEN 'Licor' WHEN 2 THEN 'Vino' END AS tipo_producto,
       COUNT(*)                                                  AS productos,
       ROUND(AVG(PurchasePrice), 2)                              AS precio_compra_prom,
       ROUND(AVG(Price), 2)                                      AS precio_venta_prom,
       ROUND(100 * AVG((Price - PurchasePrice) / Price), 1)      AS margen_prom_pct
FROM lista_precios_2017
WHERE Price > 0
GROUP BY Classification
ORDER BY tipo_producto;


-- Q08. Vista temporal: Cálculo estricto de clasificación ABC

CREATE OR REPLACE TEMP VIEW abc_productos AS
WITH ventas_producto AS (
  SELECT Brand AS sku, Description AS descripcion,
         SUM(SalesQuantity) AS unidades_vendidas,
         SUM(SalesDollars)  AS ventas
  FROM ventas
  GROUP BY Brand, Description
),
acum AS (
  SELECT *,
         ventas / SUM(ventas) OVER () AS pct,
         SUM(ventas) OVER (ORDER BY ventas DESC, sku) / SUM(ventas) OVER () AS pct_acum
  FROM ventas_producto
)
SELECT *,
       CASE WHEN pct_acum - pct < 0.80 THEN 'A'
            WHEN pct_acum - pct < 0.95 THEN 'B'
            ELSE 'C' END AS clase
FROM acum;

-- Q08 REPORTE DE CLASIFICACIÓN ABC FINAL 
SELECT a.sku,
       a.descripcion,
       a.unidades_vendidas,
       ROUND(a.ventas / a.unidades_vendidas, 2) AS precio_unitario,
       ROUND(a.ventas, 2)                       AS ventas_usd,
       ROUND(100 * a.pct, 2)                    AS pct_participacion,
       ROUND(100 * a.pct_acum, 2)               AS pct_acumulado,
       a.clase                                  AS categoria_abc,
       COALESCE(i.stock_final_unid, 0)          AS stock_final_unid
FROM abc_productos a
LEFT JOIN (SELECT Brand, SUM(onHand) AS stock_final_unid
           FROM inventario_final GROUP BY Brand) i ON a.sku = i.Brand
ORDER BY a.ventas DESC;


-- Q09. Por clase ABC: cuantos productos, % de ventas y % del capital en inventario
SELECT a.clase,
       COUNT(*) AS productos,
       ROUND(100 * SUM(a.ventas) / SUM(SUM(a.ventas)) OVER (), 1) AS pct_ventas,
       ROUND(100 * SUM(i.valor) / SUM(SUM(i.valor)) OVER (), 1)   AS pct_capital_inventario
FROM abc_productos a
LEFT JOIN (SELECT Brand, SUM(onHand * Price) AS valor FROM inventario_final GROUP BY Brand) i ON a.sku = i.Brand
GROUP BY a.clase
ORDER BY a.clase;

-- Q10. Top 10 proveedores por ventas de productos clase A (Dependencia de proovedores)
SELECT p.VendorName AS proveedor,
       COUNT(*) AS productos_clase_a,
       ROUND(SUM(a.ventas), 2) AS ventas_usd,
       ROUND(100 * SUM(a.ventas) / SUM(SUM(a.ventas)) OVER (), 1) AS pct_ventas_proveedores_top
FROM abc_productos a
JOIN lista_precios_2017 p ON a.sku = p.Brand
WHERE a.clase = 'A'
GROUP BY p.VendorName
ORDER BY ventas_usd DESC
LIMIT 10;