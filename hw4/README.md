# ДЗ 4: Apache Spark on YARN с записью в Hive

## Архитектура

| Компонент | Узел | Назначение |
|---|---|---|
| Spark SQL client / driver | team-02-nn (10.2.0.11) | запуск задания, Spark UI |
| YARN ResourceManager | team-02-nn (10.2.0.11) | выделение контейнеров |
| YARN NodeManager | team-02-nn, team-02-00, team-02-01 | executor-контейнеры |
| Hive Metastore | team-02-00 (10.2.0.12) | метаданные таблицы `hw4.sales_summary` |
| HDFS | team-02-nn | исходный CSV и warehouse |

Версии: Apache Spark 3.5.1 (`bin-hadoop3`), Apache Hadoop 3.3.6,
Apache Hive 4.0.0-alpha-2 и Temurin JDK 8 из предыдущих ДЗ

Spark установлен только на `team-02-nn`. Задание работает в режиме
`yarn` / `client`, executor-контейнеры запускаются на доступных
NodeManager-нодах. JAR-файлы Spark раздаются через
`spark.yarn.archive`, поэтому копировать `dist/spark` на все ноды не нужно

## Поток данных

```
HDFS CSV (hw3/staging/sales.csv)
        │
        ▼
Spark temporary view sales_raw
        │  CAST, to_date, фильтр amount > 0
        ▼
Spark temporary view sales_clean
        │  GROUP BY sale_date, category, dt
        ▼
hw4.sales_summary
  Parquet, PARTITIONED BY (dt)
  3 партиции, 9 строк
        │
        ▼
Hive Metastore + beeline-проверка
```

Источник -- CSV, предварительно загруженный в HDFS в ДЗ 3. Это позволяет
Spark не зависеть от чтения таблицы `hw3.sales_part`, созданной Hive 4,
исходный CSV содержит 36 строк за три дня

## Порты

| Сервис | Порт |
|---|---|
| Spark UI | 21404 |

Порты HDFS, YARN и Hive из ДЗ 1--3 не меняются. Диапазон `21000-21999`,
запись HW4 добавлена в `PORTS.md`

## Структура каталогов

```
/srv/dpe/sevinch/
├── dist/spark/              Apache Spark 3.5.1
├── conf/hw4/                spark-defaults.conf, spark-env.sh, hive-site.xml
├── logs/hw4/                spark_ctas.log, spark_parquet.log, hive_ddl.log
├── pids/hw4/
├── tmp/hw4/                 scratch и локальные файлы Spark
└── homeworks/hw4/           jobs/, mode.txt, verify.txt
```

HDFS:

- `/user/dpe_sevinch/hw3/staging/sales.csv` -- исходные данные
- `/user/dpe_sevinch/spark/spark-libs.zip` -- archive с JAR-файлами Spark
- `/user/dpe_sevinch/hive/warehouse/hw4.db/sales_summary` -- таблица и партиции

## Предпосылки

- HDFS из ДЗ 1 запущен
- YARN из ДЗ 2 запущен, все три NodeManager в состоянии `RUNNING`
- HiveServer2 и Metastore из ДЗ 3 запущены, `hw3.sales_part` доступна
- скрипты запускаются с edge-машины, где есть `~/.ssh/team_internal`
- каталог `hw4` скопирован на edge, например в `/home/team/sevinch-hw4`

## Скрипты

Все команды выполняются с edge-машины из каталога с `hw4`

### 01_preflight.sh

```bash
bash hw4/scripts/01_preflight.sh
```

Создаёт каталоги HW4 на трёх нодах, проверяет JDK 8, Hadoop, свободную
память и диск на `team-02-nn`, доступность Spark 3.5.1, порт `21404`,
живость HDFS, наличие 36 строк в CSV, три `RUNNING` NodeManager и порты
Hive. Дописывает секцию HW4 в `PORTS.md`

### 02_install_spark.sh

```bash
bash hw4/scripts/02_install_spark.sh
```

Скачивает `spark-3.5.1-bin-hadoop3.tgz` и распаковывает его в
`dist/spark` только на `team-02-nn`. Существующий каталог `dist/spark`
автоматически не удаляется

### 03_apply_config.sh

```bash
bash hw4/scripts/03_apply_config.sh
```

Копирует конфиги в `conf/hw4` на `team-02-nn`, подставляет IP
`team-02-00` вместо `__HIVE_HOST__`, собирает `spark-libs.zip` из
`dist/spark/jars` и кладёт архив в HDFS

### 04_run_spark.sh

```bash
bash hw4/scripts/04_run_spark.sh
```

Копирует SQL-задания в `homeworks/hw4/jobs` и запускает
`01_sales_summary_ctas.sql` через `spark-sql` на YARN. При успехе
пишет `spark_ctas` в `mode.txt`

Если CTAS не удался, автоматически используется fallback:

1. `02_sales_summary_parquet.sql` пишет партиционированный Parquet
   через `INSERT OVERWRITE DIRECTORY`
2. `03_create_external_table.sql` создаёт внешнюю Hive-таблицу и
   выполняет `MSCK REPAIR TABLE`
3. в `mode.txt` пишется `external_parquet`

### 05_verify.sh

```bash
bash hw4/scripts/05_verify.sh
```

Проверяет HDFS-каталог, наличие таблицы в metastore, три партиции,
9 строк, 3 дня, агрегаты по дням, содержимое и описание таблицы,
результат пишется в `homeworks/hw4/verify.txt`. При успехе последняя
строка -- `VERIFY: OK`

## Результаты проверки

Задание выполнено в режиме `spark_ctas`:

- Spark application `application_1793399358845_0002`
- таблица `hw4.sales_summary` создана
- HDFS-каталоги: `dt=2026-10-20`, `dt=2026-10-21`, `dt=2026-10-22`
- партиций: 3
- строк: 9 (3 дня × 3 категории)
- `VERIFY: OK`

Агрегаты по дням:

| dt | orders | total_amount |
|---|---:|---:|
| 2026-10-20 | 12 | 672.00 |
| 2026-10-21 | 12 | 690.00 |
| 2026-10-22 | 12 | 708.00 |

Содержимое таблицы:

| dt | category | orders | total_amount | avg_amount | max_amount |
|---|---|---:|---:|---:|---:|
| 2026-10-20 | books | 4 | 232.00 | 58.00 | 84.50 |
| 2026-10-20 | food | 4 | 194.00 | 48.50 | 89.50 |
| 2026-10-20 | tech | 4 | 246.00 | 61.50 | 94.50 |
| 2026-10-21 | books | 4 | 208.00 | 52.00 | 78.50 |
| 2026-10-21 | food | 4 | 260.00 | 65.00 | 99.50 |
| 2026-10-21 | tech | 4 | 222.00 | 55.50 | 88.50 |
| 2026-10-22 | books | 4 | 184.00 | 46.00 | 72.50 |
| 2026-10-22 | food | 4 | 236.00 | 59.00 | 93.50 |
| 2026-10-22 | tech | 4 | 288.00 | 72.00 | 98.50 |

Полный вывод сохранён в `hw4/homeworks/verify.txt`, режим -- в
`hw4/homeworks/mode.txt`

## Ключевые конфиги

`hw4/conf/spark-defaults.conf`

- `spark.master=yarn`, `spark.submit.deployMode=client`
- `spark.yarn.archive` указывает на `spark-libs.zip` в HDFS
- `spark.sql.catalogImplementation=hive`
- `spark.hadoop.hive.metastore.uris=thrift://10.2.0.12:21053`
- `spark.sql.warehouse.dir` указывает на HDFS warehouse
- driver и executor: 512 МБ + 256 МБ overhead, по одному core
- `spark.sql.shuffle.partitions=2`, AQE отключён
- Spark UI на `21404`

`hw4/conf/spark-env.sh` задаёт `JAVA_HOME`, `HADOOP_HOME`,
`HADOOP_CONF_DIR`/`YARN_CONF_DIR` из ДЗ 2, `SPARK_CONF_DIR`,
каталоги логов, PID и локального scratch, а также native-библиотеки Hadoop

`hw4/conf/hive-site.xml` содержит адрес внешнего metastore и HDFS
scratch-каталоги. Проверка версии схемы metastore отключена, потому что
Spark 3.5.1 и Hive 4.0.0-alpha-2 используют разные версии Hive-клиентов

## Нюансы

- Spark и Hive -- разные версии. Совместимость проверена на реальном
  CTAS. Если CTAS перестанет работать, `04_run_spark.sh` переключится
  на Parquet + внешнюю Hive-таблицу
- В `05_verify.sh` для вывода содержимого используется
  `hive.fetch.task.conversion=more` и нет `ORDER BY`: иначе Hive
  запускает MapReduce-задание, хотя таблица содержит всего 9 строк
- Первый запуск YARN-задания дольше последующих: ResourceManager
  поднимает контейнеры и раскладывает `spark-libs.zip`
- Скрипты идемпотентны там, где это безопасно: `CREATE DATABASE IF NOT EXISTS`,
  `DROP TABLE IF EXISTS`, `INSERT OVERWRITE`, `MSCK REPAIR TABLE`,
  Spark не переустанавливается, если `dist/spark/bin/spark-sql` уже есть
