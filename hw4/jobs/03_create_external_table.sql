CREATE DATABASE IF NOT EXISTS hw4;
DROP TABLE IF EXISTS hw4.sales_summary;

CREATE EXTERNAL TABLE hw4.sales_summary (
  sale_date DATE,
  category STRING,
  orders BIGINT,
  total_amount DECIMAL(12, 2),
  avg_amount DECIMAL(12, 2),
  max_amount DECIMAL(12, 2)
)
PARTITIONED BY (dt STRING)
STORED AS PARQUET
LOCATION 'hdfs://team-02-nn:21020/user/dpe_sevinch/hive/warehouse/hw4.db/sales_summary';

MSCK REPAIR TABLE hw4.sales_summary;

SHOW PARTITIONS hw4.sales_summary;
