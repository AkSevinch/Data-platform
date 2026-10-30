CREATE DATABASE IF NOT EXISTS hw4;
DROP TABLE IF EXISTS hw4.sales_summary;

CREATE OR REPLACE TEMPORARY VIEW sales_raw
USING csv
OPTIONS (
  path 'hdfs://team-02-nn:21020/user/dpe_sevinch/hw3/staging/sales.csv',
  header 'false'
);

CREATE OR REPLACE TEMPORARY VIEW sales_clean AS
SELECT
  CAST(_c0 AS INT) AS id,
  _c1 AS category,
  CAST(_c2 AS DECIMAL(12, 2)) AS amount,
  to_date(_c3, 'yyyy-MM-dd') AS sale_date,
  _c3 AS dt
FROM sales_raw
WHERE CAST(_c2 AS DECIMAL(12, 2)) > 0;

CREATE TABLE hw4.sales_summary
USING parquet
PARTITIONED BY (dt)
AS
SELECT
  sale_date,
  category,
  count(*) AS orders,
  CAST(round(sum(amount), 2) AS DECIMAL(12, 2)) AS total_amount,
  CAST(round(avg(amount), 2) AS DECIMAL(12, 2)) AS avg_amount,
  CAST(round(max(amount), 2) AS DECIMAL(12, 2)) AS max_amount,
  dt
FROM sales_clean
GROUP BY sale_date, category, dt;

SELECT 'CTAS_OK' AS status;
