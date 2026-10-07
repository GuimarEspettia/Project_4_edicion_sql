# Proyecto SQL: Inventory Analysis
![imagen de baner](<Picture/SQL_BANER.png>)

## 📌Resumen (Overview)
La gerencia de una empresa distribuidora **(sector logístico)** desea optimizar su inventario, reducir los quiebres de stock y liberar capital de trabajo, pero no cuenta con una visión clara de sus datos de compras, ventas e inventario. Mi objetivo es utilizar **SQL** dentro de **Databricks** para analizar más de **2.3 millones de registros** de 2016 y proporcionar recomendaciones sobre proveedores, lead time, análisis ABC, punto de reorden y EOQ.
## Pipeline del proyecto
![imagen de baner](<Picture/PIPELINE_BANNER.png>)
Link de base de datos: https://www.kaggle.com/datasets/bhanupratapbiswas/inventory-analysis-case-study
## ⚙️ Configuración del Entorno e Ingesta de Datos (Setup)

El proceso de carga inicial (ETL) extrae los archivos CSV directamente desde Databricks Volumes, aplica transformaciones de limpieza en tiempo de ejecución y materializa las tablas en el entorno de trabajo.

**1. Configuración del catálogo y esquema (Unity Catalog)**
Se define el entorno de base de datos donde persistirán las tablas analíticas limpias.
```sql
USE CATALOG `workspace`;
USE SCHEMA `default`;
```

**2. Ingesta y creación de tablas (CTAS - Create Table As Select)**
Se leen los CSV en crudo usando `read_files` (con inferencia automática de esquemas) y se crean las tablas definitivas aplicando las reglas de limpieza: estandarización de fechas (`to_date` / `CAST`), limpieza de texto (`TRIM`) y unificación de llaves primarias.
```sql
CREATE OR REPLACE TABLE `workspace`.`default`.`SalesFINAL12312016` AS
SELECT
  InventoryId, Store, Brand, Description, Size, SalesQuantity, SalesDollars,
  to_date(SalesDate, 'M/d/yyyy') AS SalesDate,
  VendorNo AS VendorNumber,
  TRIM(VendorName) AS VendorName
FROM read_files(
  '/Volumes/workspace/default/inventory_files/SalesFINAL12312016.csv',
  format => 'csv', header => true, inferSchema => true
);
```
*(Nota: Este mismo patrón de ingesta y limpieza `CAST(...) AS DATE` y `TRIM(...)` se aplica para iterar sobre las tablas `Purchases`, `InvoicePurchases`, `BegInv`, `EndInv` y `2017PurchasePricesDec`).*

**3. Auditoría post-carga (Data Quality Check)**
Ejecución de una consulta consolidada para auditar el volumen de datos ingestados y validar los rangos de fechas operativas. Este paso fue crucial para detectar el truncamiento del archivo original de ventas por el límite físico de filas de Excel.
```sql
SELECT 'sales' AS tabla, COUNT(*) AS filas, MIN(SalesDate) AS desde, MAX(SalesDate) AS hasta FROM `workspace`.`default`.`SalesFINAL12312016`
UNION ALL 
SELECT 'purchases', COUNT(*), MIN(ReceivingDate), MAX(ReceivingDate) FROM `workspace`.`default`.`PurchasesFINAL12312016`
UNION ALL 
SELECT 'invoice_purchases', COUNT(*), MIN(InvoiceDate), MAX(InvoiceDate) FROM `workspace`.`default`.`InvoicePurchases12312016`
UNION ALL 
SELECT 'beg_inv', COUNT(*), MIN(startDate), MAX(startDate) FROM `workspace`.`default`.`BegInvFINAL12312016`
UNION ALL 
SELECT 'end_inv', COUNT(*), MIN(endDate), MAX(endDate) FROM `workspace`.`default`.`EndInvFINAL12312016`;




## 🛠️ Limpieza de Datos y Transformaciones (ETL)

**1. Estandarización de Fechas temporales**
Conversión de formatos mixtos (`M/d/yyyy` y textos ISO) a tipo `DATE` para habilitar cálculos de *Lead Time* y días de pago.
```sql
to_date(SalesDate, 'M/d/yyyy') AS SalesDate,
CAST(PODate AS DATE) AS PODate,
CAST(PayDate AS DATE) AS PayDate
```

**2. Homologación de llaves y limpieza de texto**
Renombramiento de llaves principales (`VendorNumber`) y uso de `TRIM()` junto con agrupaciones (`MAX`) para evitar duplicados por espacios o errores de tipeo.
```sql
VendorNo AS VendorNumber,
TRIM(VendorName) AS VendorName,
MAX(VendorName) AS proveedor
```

**3. Calidad de datos y prevención de errores matemáticos**
Filtros de ruido estadístico (mínimo 5 facturas para el flete) y prevención de divisiones por cero en el cálculo del EOQ.
```sql
HAVING COUNT(*) >= 5 AND SUM(Dollars) > 0
WHERE Quantity > 0 AND c.costo_unit > 0
```

**4. Modelado estocástico (Demanda y Varianza)**
Consolidación de ventas por día y cálculo robusto de la desviación estándar, usando `GREATEST` para evitar varianzas negativas por redondeos en días sin ventas.
```sql
SELECT InventoryId, SalesDate, SUM(SalesQuantity) AS q FROM sales GROUP BY InventoryId, SalesDate;

sqrt(GREATEST(SUM(d.q * d.q) / p.n_dias - pow(SUM(d.q) / p.n_dias, 2), 0)) AS sigma_diaria
```

**5. Tratamiento de nulos y cruces de auditoría**
Imputación de stock en cero para productos faltantes (`COALESCE`) y uso de `LEFT ANTI JOIN` para detectar quiebres de catálogo entre inventarios sin generar duplicados.
```sql
COALESCE(e.onHand, 0) AS onHand,
COALESCE(l.lead_dias, lg.lead_dias) AS lead_dias

SELECT b.* FROM beg_inv b LEFT ANTI JOIN end_inv e ON b.InventoryId = e.InventoryId
```
## 📊 Conclusiones y Hallazgos de Negocio

1. **Alta concentración de riesgo en proveedores:** Los 10 proveedores principales concentran el **65.3%** del gasto total ($321.9 M). *Diageo North America* por sí solo representa el **15.8%**. **Acción:** Diversificar el pool de proveedores y renegociar Acuerdos de Nivel de Servicio (SLA) para mitigar riesgos de desabastecimiento.

2. **Volatilidad en Tiempos de Entrega (Lead Time):** El promedio global es de 7.6 días (pico máximo de 14), pero **68 de los 126 proveedores** superan la media. **Acción:** El cálculo del Stock de Seguridad y ROP no debe ser estándar; requiere parametrización dinámica por proveedor.

3. **Capital inmovilizado al alza:** El valor del inventario experimentó un crecimiento del **17%** (de $68.1 M a $79.7 M), estando el **51.8%** concentrado en apenas 10 ciudades. **Acción:** Priorizar auditorías físicas y rebalanceo de stock en estas ubicaciones clave.

4. **Ineficiencia en productos Clase C (Análisis ABC):** Analizando el bimestre Ene-Feb, el **20%** de las marcas (1,503) generan el 80% de los ingresos (Clase A). Por el contrario, las 4,342 marcas **Clase C** (5% de ventas) retienen **$7.8 M (11%)** de capital inmovilizado. **Acción:** Ejecutar estrategias de liquidación o cese de reabastecimiento automático para la Clase C.

5. **Palancas de ahorro mal enfocadas:** El gasto logístico por flete representa apenas el **0.51%** de la facturación y su varianza entre proveedores es nula. **Acción:** Trasladar el esfuerzo de negociación logística hacia la optimización de plazos de pago (actualmente promediando 35 días) y el ajuste de Lotes Económicos de Compra (EOQ).

6. **Rotación crítica de catálogo:** 31,553 combinaciones tienda-marca ($7.3 M iniciales) desaparecieron al cierre del periodo, siendo sustituidas por 49,513 nuevas combinaciones. **Acción:** Investigar a nivel de piso si corresponden a quiebres de stock severos o descontinuaciones de temporada estratégicas.









