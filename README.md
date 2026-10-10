# Proyecto SQL: Analisis de Inventario Logístico
![imagen de baner](<Picture/SQL_BANER.png>)

## 📌Resumen (Overview)
La gerencia de una empresa distribuidora **(sector logístico)** desea optimizar su inventario, reducir los quiebres de stock y liberar capital de trabajo, pero no cuenta con una visión clara de sus datos de compras, ventas e inventario. Mi objetivo es utilizar **SQL** dentro de **Databricks** para analizar cerca de **3.9 millones de registros** (compras y facturas de 2016, ventas de enero–febrero de 2016, inventarios inicial y final, y lista de precios 2017) mediante **10 preguntas de negocio de dificultad progresiva** (básica, intermedia y avanzada), y proporcionar recomendaciones sobre **proveedores, compras, flete, lead time, margen y clasificación ABC** de productos.

<p align="center">
 <a href="https://www.linkedin.com/in/guimar-espettia">
    <img src="https://img.shields.io/badge/LinkedIn-0077B5?style=flat-square&logo=linkedin&logoColor=white" />

## Pipeline del proyecto
![imagen de baner](<Picture/PIPELINE_BANNER.png>)
Link de base de datos: https://www.kaggle.com/datasets/bhanupratapbiswas/inventory-analysis-case-study
## ⚙️ Configuración del Entorno e Ingesta de Datos (Setup)

El proceso de carga inicial  extrai los archivos CSV de Kaggle hacia directamente a Databricks Volumes, aplique las transformaciones de limpieza  y hize las tablas en el query.

**1. Configuración del catálogo y esquema**
Se define el entorno de base de datos donde persistirán las tablas analíticas limpias.
```sql
USE CATALOG `workspace`;
USE SCHEMA `default`;
```

**2. Ingesta y creación de tablas (CTAS - Create Table As Select)**
Se leen los CSV en crudo usando `read_files` y se crean las tablas definitivas aplicando las reglas de limpieza: estandarización de fechas (`to_date`), limpieza de texto (`TRIM`) y unificación de llaves primarias.
```sql
CREATE OR REPLACE TABLE `workspace`.`default`.`SalesFINAL12312016` AS
SELECT
  InventoryId, Store, Brand, Description, Size, SalesQuantity, SalesDollars,
  to_date(SalesDate, 'M/d/yyyy') AS SalesDate,
  VendorNo AS VendorNumber,
  TRIM(VendorName) AS VendorName
FROM read_files(
  '/Volumes/workspace/default/inventory_files/SalesFINAL12312016.csv',
);
```
(Nota: Utilize este mismo patron para las demas tablas).


## 🛠️ Limpieza de Datos y Transformaciones 

**1. Estandarización de Fechas temporales**
Conversión de formatos mixtos (`M/d/yyyy` y textos ISO) a tipo `DATE` para habilitar cálculos de *Lead Time* y días de pago.
```sql
to_date(SalesDate, 'M/d/yyyy') AS SalesDate,
CAST(PODate AS DATE) AS PODate,
CAST(PayDate AS DATE) AS PayDate
```


**2. Homologación de llaves y limpieza de texto**
Renombramiento de llaves principales (`VendorNumber`) y uso de `TRIM()` junto con agrupaciones para evitar duplicados por espacios o errores de tipeo.
```sql
VendorNo AS VendorNumber,
TRIM(VendorName) AS VendorName,
```

 
**3. Calidad de datos y prevención de errores matemáticos**
Filtro de precios en cero para evitar divisiones por cero en el cálculo del margen (Esto lo aplique en la pregunta 07 ), y `LEFT JOIN` con `COALESCE` para  evitar los `null` y conservar productos sin stock colocandole `0` en el reporte ABC (Esto lo aplique en la pregunta 08).
```sql
-- P07
WHERE Price > 0

-- P08
COALESCE(i.stock_final_unid, 0) AS stock_final_unid
```


## Pregunta #1: ¿Cuáles son los 10 productos más vendidos por unidades?
 
Aquí, sumé las unidades vendidas por marca y descripción, y ordené de mayor a menor para quedarme con los 10 primeros.
 
```sql
-- Top 10 productos por unidades vendidas --
 
SELECT Brand, Description, SUM(SalesQuantity) AS Unidades_Vendidas
FROM ventas
GROUP BY Brand, Description
ORDER BY Unidades_Vendidas DESC
LIMIT 10;
```
 
**Top 10 productos por unidades vendidas**
 
Hallazgos: 

![Imagen de query](<Picture/P1_sql.png>)
 

 
---
 
## Pregunta #2: ¿Cuántas facturas y cuánto flete total se registran cada mes?
 
Aquí, agrupé las facturas de compra por mes (formato `yyyy-MM`), conté las facturas y sumé el flete en dólares.
 
```sql
-- Cantidad de facturas y flete total por mes --
 
SELECT date_format(InvoiceDate, 'yyyy-MM') AS Mes,
       COUNT(*) AS facturas,
       ROUND(SUM(Freight), 0) AS Flete_USD
FROM facturas_compra
GROUP BY mes
ORDER BY mes;
```
 
**Facturas y flete total por mes**
 
Hallazgos: 

![Imagen de query](<Picture/P2_sql.png>)
 
 
 
---
 
## Pregunta #3: ¿Quiénes son los 10 principales proveedores por monto comprado en 2016 y qué porcentaje del total representan?
 
Aquí, sumé el monto y las unidades compradas por proveedor, y calculé su participación sobre el total con una función de ventana (`SUM(SUM(Dollars)) OVER ()`).
 
```sql
-- Top 10 proveedores por monto comprado en 2016 y % del total --
 
SELECT
  VendorNumber, VendorName AS proveedor,
  ROUND(SUM(Dollars), 2) AS total_comprado,
  SUM(Quantity)      AS unidades,
  ROUND(100 * SUM(Dollars) / SUM(SUM(Dollars)) OVER (), 2) AS porcentaje_total
FROM compras
GROUP BY VendorNumber, VendorName
ORDER BY total_comprado DESC
LIMIT 10;
```
 
**Top 10 proveedores por monto comprado**
 
Hallazgos:

 ![Imagen de query](<Picture/P3_sql.png>)
 

 
---
 
## Pregunta #4: ¿Cómo evolucionan las compras mensuales y cuánto cambian frente al mes anterior?
 
Aquí, calculé el total comprado por mes desde enero de 2016 en una CTE, y luego usé `LAG` para obtener la diferencia contra el mes anterior.
 
```sql
-- Compras por mes y cambio contra el mes anterior --
 
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
```
 
**Compras mensuales y variación contra el mes anterior**
 
Hallazgos: 

![Imagen de query](<Picture/P4_sql.png>)
 

 
---
 
## Pregunta #5: ¿Cómo se comportan las unidades, las ventas y el precio promedio por mes y tipo de producto?
 
Aquí, agrupé las ventas por mes y clasificación (1 = Licor, 2 = Vino), y calculé unidades, ventas en dólares y precio promedio.
 
```sql
-- Unidades y dólares vendidos por mes y clasificación --
 
SELECT
  date_format(SalesDate, 'yyyy-MM') AS mes,
  CASE Classification WHEN 1 THEN 'Licor' WHEN 2 THEN 'Vino' END AS tipo_producto,
  SUM(SalesQuantity) AS unidades_vendidas,
  ROUND(SUM(SalesDollars), 2) AS ventas_usd,
  ROUND(SUM(SalesDollars) / SUM(SalesQuantity), 2) AS precio_promedio
FROM ventas
GROUP BY date_format(SalesDate, 'yyyy-MM'), Classification
ORDER BY mes, tipo_producto;
```
 
**Ventas por mes y tipo de producto**
 
Hallazgos: ![Imagen de query](<Picture/P5_sql.png>)
 

 
---
 
## Pregunta #6: ¿Cuál es el lead time promedio de cada proveedor (recepción menos orden de compra)?
 
Aquí, calculé la diferencia en días entre la fecha de recepción y la fecha de la orden de compra, y obtuve el promedio y el máximo por proveedor, junto con el número de órdenes, las unidades y el monto comprado.
 
```sql
-- Lead time promedio por proveedor (Recepción - PO) --
 
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
```
 
**Lead time promedio por proveedor**
 
Hallazgos: ![Imagen de query](<Picture/P6_sql.png>)
 
 

 
---
 
## Pregunta #7: ¿Cuál es el margen promedio por tipo de producto (precio de venta vs. precio de compra)?
 
Aquí, usé la lista de precios 2017 para comparar el precio de compra con el de venta, y calculé el margen porcentual promedio por tipo de producto, excluyendo los precios en cero.
 
```sql
-- Margen promedio por tipo de producto (precio de venta vs precio de compra) --
 
SELECT CASE Classification WHEN 1 THEN 'Licor' WHEN 2 THEN 'Vino' END AS tipo_producto,
       COUNT(*)                                                  AS productos,
       ROUND(AVG(PurchasePrice), 2)                              AS precio_compra_prom,
       ROUND(AVG(Price), 2)                                      AS precio_venta_prom,
       ROUND(100 * AVG((Price - PurchasePrice) / Price), 1)      AS margen_prom_pct
FROM lista_precios_2017
WHERE Price > 0
GROUP BY Classification
ORDER BY tipo_producto;
```
 
**Margen promedio por tipo de producto**
 
Hallazgos: ![Imagen de query](<Picture/P7_sql.png>)
 

 
---
 
## Pregunta #8: ¿Cómo se clasifican los productos según el análisis ABC?
 
Aquí, primero creé una vista temporal que acumula el porcentaje de ventas por producto y asigna la clase: **A** (hasta el 80 % acumulado), **B** (hasta el 95 %) y **C** (el resto). Después armé el reporte final, agregando el stock final de cada producto.
 
### Paso 1: Vista temporal con la clasificación ABC
 
```sql
-- Vista temporal: cálculo estricto de clasificación ABC --
 
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
```
 
### Paso 2: Reporte de clasificación ABC final
 
```sql
-- Reporte de clasificación ABC final --
 
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
```
 
**Clasificación ABC de productos**
 
_Hallazgos: ![Imagen de query](<Picture/P8_sql.png>)


 
---
 
## Pregunta #9: ¿Cuántos productos tiene cada clase ABC y qué porcentaje de las ventas y del capital en inventario concentra?
 
Aquí, usé la vista `abc_productos` y la uní con el inventario final valorizado (`onHand * Price`), para comparar el peso de cada clase en ventas contra su peso en capital inmovilizado.
 
```sql
-- Por clase ABC: cuántos productos, % de ventas y % del capital en inventario --
 
SELECT a.clase,
       COUNT(*) AS productos,
       ROUND(100 * SUM(a.ventas) / SUM(SUM(a.ventas)) OVER (), 1) AS pct_ventas,
       ROUND(100 * SUM(i.valor) / SUM(SUM(i.valor)) OVER (), 1)   AS pct_capital_inventario
FROM abc_productos a
LEFT JOIN (SELECT Brand, SUM(onHand * Price) AS valor FROM inventario_final GROUP BY Brand) i ON a.sku = i.Brand
GROUP BY a.clase
ORDER BY a.clase;
```
 
**Productos, % de ventas y % del capital en inventario por clase ABC**
 
Hallazgos:

![Imagen de query](<Picture/P9_sql.png>)
 

 
---
 
## Pregunta #10: ¿Qué proveedores concentran más ventas de productos clase A (dependencia de proveedores)?
 
Aquí, uní los productos clase A con la lista de precios para identificar a su proveedor, y calculé cuántos productos aporta cada uno, sus ventas y qué porcentaje representan dentro de la clase A.
 
```sql
-- Top 10 proveedores por ventas de productos clase A (dependencia de proveedores) --
 
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
```
 
**Top 10 proveedores por ventas de productos clase A**
 
Hallazgos:![Imagen de query](<Picture/P10_sql.png>)
 


## 📊 Conclusiones y Hallazgos de Negocio

1. **Concentración de proveedores:** Los 10 principales concentran el 65.3% de los $321.9 M comprados, y solo Diageo North America el 15.8%. En los productos clase A el peso crece: los 10 principales proveedores llegan al 68.7% de las ventas y Diageo al 17.3%.

2. **Compras al alza, con volatilidad:** Pasan de $19.1 M en enero a un máximo de $32.2 M en julio. El mayor salto fue en mayo (+$6.9 M, +32%) y las mayores caídas en septiembre (−$3.9 M) y noviembre (−$4.6 M).

3. **Flete creciente:** Sube de $105 K en enero a un máximo de $176 K en agosto, y el total supera los $1.6 M. Aun así, equivale solo al 0.5% de lo comprado.

4. **Pocos productos concentran las ventas:** 1,503 de 7,658 productos (19.6%) generan el 80% de las ventas, y la demanda está fragmentada: el líder, Smirnoff 80 Proof, vende 28,544 unidades y los 10 primeros suman solo el 7.0%. En el otro extremo, los 4,342 productos clase C aportan el 5% de las ventas pero retienen $7.8 M (11%) del inventario.

5. **Margen por tipo:** El vino deja un margen promedio de 36.0% frente a 26.8% del licor, aunque su precio promedio es menor ($32.42 vs $53.83) y tiene muchos más productos (8,693 vs 3,566).

6. **Demanda fragmentada:** el producto líder, Smirnoff 80 Proof, vendió 28,544 unidades, y los 10 primeros en total suman solo el 7.0% de las unidades en general.

## 📊 Recomendaciones
1. **Dependencia de pocos proveedores:**
Negociar contratos de volumen y mejores condiciones de pago con los 3 primeros proveedores, que suman cerca de un tercio de las compras. En paralelo, identificar proveedores alternos para las marcas clase A, para no quedar expuestos si un proveedor falla o sube precios.

2. **Compras con picos y caídas bruscas:** Pasar de compras reactivas a un plan mensual basado en el pronóstico de demanda, con topes de compra por mes. Así se evita acumular inventario en los picos y quedarse corto después. Antes de fijar los topes, validar con las ventas del año completo.

3. **Flete creciente, pero no es la palanca principal:** 
 Consolidar pedidos pequeños de un mismo proveedor en menos facturas, para reducir el flete sin aumentar el inventario. Cada 10% de ahorro equivale a unos $164 K al año. Es una mejora útil, pero secundaria frente a la gestión del inventario.

4. **Lead time desigual entre proveedores:** Calcular el stock de seguridad por proveedor y no con un plazo único. Dar prioridad a los proveedores lentos que además tienen alto volumen de compra, para renegociar plazos o adelantar sus órdenes.

5. **Pocos productos generan casi todas las ventas, y la cola inmoviliza capital:** Gestionar cada clase con una regla distinta.

   - Clase A: inventario de seguridad alto y revisión frecuente. Hay 35 productos A sin stock al cierre, y conviene confirmar si son quiebres reales para reponerlos primero.

    - Clase C: reducir las órdenes de reposición, liquidar los de menor movimiento y depurar el catálogo. Recortar un 20% de ese stock liberaría cerca de $1.6 M de capital de trabajo.







