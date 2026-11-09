# ДЗ 5: оркестрация Prefect для Spark поверх YARN

## Архитектура

| Компонент | Узел | Назначение |
|---|---|---|
| Prefect flow | team-02-nn (10.2.0.11) | оркестрация задач обработки |
| Spark driver / Spark SQL | team-02-nn (10.2.0.11) | чтение HDFS CSV и запись результата |
| YARN ResourceManager | team-02-nn (10.2.0.11) | выделение контейнеров |
| YARN NodeManager | team-02-nn, team-02-00, team-02-01 | executor-контейнеры |
| Hive Metastore | team-02-00 (10.2.0.12) | метаданные таблицы `hw5.sales_summary` |
| HDFS | team-02-nn | исходный CSV и warehouse |

Версии: Prefect 3.9.2, Apache Spark 3.5.1, Apache Hadoop 3.3.6,
Apache Hive 4.0.0-alpha-2 и Temurin JDK 8 из предыдущих ДЗ

Prefect запускается как локальный flow на `team-02-nn`. Клиент автоматически
поднимает временный Prefect API на `127.0.0.1` и останавливает его после
завершения flow, поэтому постоянный сервер и отдельный фиксированный порт
не используются. В этом запуске временный API слушал `127.0.0.1:8146`,
наружу порт не публикуется

Spark работает в режиме `yarn` / `client`. JAR-файлы раздаются через
`spark.yarn.archive` из ДЗ 4, поэтому копировать `dist/spark` на все ноды
не нужно

## Поток данных

```
Prefect flow sevinch-hw5-sales-pipeline
        |
        v
check_cluster
  HDFS: 3 DataNode
  YARN: 3 NodeManager RUNNING
  HDFS CSV: 36 строк
  Hive: 21050, 21051, 21053, 21059
        |
        v
run_spark
  spark-submit --master yarn --deploy-mode client
  SparkSession с Hive support
  HDFS CSV -> CAST, to_date, фильтр amount > 0
        |
        v
verify_table
  beeline: таблица, партиции, строки, агрегаты
  HDFS: каталоги dt=
        |
        v
hw5.sales_summary
  Parquet, PARTITIONED BY (dt)
  3 партиции, 9 строк
```

Источник - CSV `/user/dpe_sevinch/hw3/staging/sales.csv`, загруженный в HDFS
в ДЗ 3. CSV содержит 36 строк за три дня. Результат агрегируется по
`sale_date`, `category` и `dt`, как в ДЗ 4, но запись выполняется из PySpark
через `saveAsTable`

## Порты

| Сервис | Порт |
|---|---|
| Spark UI | 21405 |
| HiveServer2 thrift | 21050 |
| HiveServer2 Web UI | 21051 |
| Hive Metastore thrift | 21053 |
| Derby Network Server | 21059 |

Порты HDFS, YARN и Hive из ДЗ 1-3 не меняются. Диапазон `21000-21999`,
запись HW5 добавлена в `PORTS.md`. Временный Prefect API использует
случайный локальный порт и не является постоянным сервисом

## Структура каталогов

```
/srv/dpe/sevinch/
├── venv/hw5/                 Prefect 3.9.2 и pip
├── conf/hw5/                 spark-defaults.conf, spark-env.sh, hive-site.xml, prefect.env
├── data/hw5/prefect/         PREFECT_HOME и локальная SQLite
├── logs/hw5/                 flow.log, spark_submit.log
├── pids/hw5/
├── tmp/hw5/                  scratch, pip-cache, get-pip.py
└── homeworks/hw5/            flows/, jobs/, flow_result.json, verify.txt
```

HDFS:

- `/user/dpe_sevinch/hw3/staging/sales.csv` - исходные данные
- `/user/dpe_sevinch/spark/spark-libs.zip` - archive с JAR-файлами Spark
- `/user/dpe_sevinch/hive/warehouse/hw5.db/sales_summary` - таблица и партиции

## Предпосылки

- HDFS из ДЗ 1 запущен
- YARN из ДЗ 2 запущен, все три NodeManager в состоянии `RUNNING`
- HiveServer2 и Metastore из ДЗ 3 запущены
- Spark 3.5.1 и `spark-libs.zip` из ДЗ 4 доступны
- скрипты запускаются с edge-машины, где есть `~/.ssh/team_internal`
- каталог `hw5` скопирован на edge, например в `/home/team/sevinch-hw5`

## Скрипты

Все команды выполняются с edge-машины из каталога с `hw5`

### 01_preflight.sh

```bash
bash hw5/scripts/01_preflight.sh
```

Создаёт каталоги HW5 на `team-02-nn`, проверяет Python 3.12, доступность
`venv`, `curl` и `get-pip.py`, свободную память, диск и порт `21405`,
наличие Spark 3.5.1, живость HDFS, 36 строк в CSV, три `RUNNING`
NodeManager, порты Hive и HDFS-архив Spark. Дописывает секцию HW5
в `PORTS.md`

### 02_install_prefect.sh

```bash
bash hw5/scripts/02_install_prefect.sh
```

Создаёт `venv/hw5` без системного `pip`, bootstrap-ит pip через
`get-pip.py` и устанавливает `prefect==3.9.2`. Повторный запуск
проверяет версию и не переустанавливает Prefect

### 03_apply_config.sh

```bash
bash hw5/scripts/03_apply_config.sh
```

Копирует конфиги, flow и Spark job в `conf/hw5` и `homeworks/hw5`,
подставляет IP `team-02-00` вместо `__HIVE_HOST__`, проверяет HDFS-архив
Spark. Если архива нет, собирает его из `dist/spark/jars`

### 04_run_flow.sh

```bash
bash hw5/scripts/04_run_flow.sh
```

Запускает Prefect flow на `team-02-nn`. Flow выполняет `check_cluster`,
`run_spark` и `verify_table`. Логи пишутся в `logs/hw5/flow.log`,
результат - в `homeworks/hw5/flow_result.json`, проверка - в
`homeworks/hw5/verify.txt`. Скрипт копирует результаты на edge

### 05_verify.sh

```bash
bash hw5/scripts/05_verify.sh
```

Повторно проверяет результат через beeline и HDFS: наличие таблицы,
три партиции, 9 строк, 3 дня, агрегаты, содержимое и описание таблицы
Проверяет `flow_result.json` и маркер `HW5_RESULT=` в логе Spark
При успехе последняя строка - `VERIFY: OK`

## Результаты проверки

Flow выполнен в Prefect 3.9.2:

- flow run: `simple-raven`
- Spark application: `application_1793399358845_0012`
- таблица: `hw5.sales_summary`
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

Полный вывод сохранён в `hw5/homeworks/verify.txt`, результат flow -
в `hw5/homeworks/flow_result.json`, лог Spark - в
`hw5/homeworks/spark_submit.log`

## Ключевые конфиги

`hw5/conf/spark-defaults.conf`

- `spark.master=yarn`, `spark.submit.deployMode=client`
- `spark.yarn.archive` указывает на `spark-libs.zip` в HDFS
- `spark.sql.catalogImplementation=hive`
- `spark.hadoop.hive.metastore.uris=thrift://10.2.0.12:21053`
- `spark.sql.warehouse.dir` указывает на HDFS warehouse
- driver и executor: 512 МБ + 256 МБ overhead, по одному core
- `spark.sql.shuffle.partitions=2`, AQE отключён
- Spark UI на `21405`

`hw5/conf/spark-env.sh` задаёт `JAVA_HOME`, `HADOOP_HOME`,
`HADOOP_CONF_DIR`/`YARN_CONF_DIR` из ДЗ 2, `SPARK_CONF_DIR`,
каталоги логов, PID и локального scratch, а также `PYSPARK_PYTHON`

`hw5/conf/hive-site.xml` содержит адрес внешнего metastore и HDFS
scratch-каталоги. Проверка версии схемы metastore отключена, потому что
Spark 3.5.1 и Hive 4.0.0-alpha-2 используют разные версии Hive-клиентов

`hw5/conf/prefect.env` задаёт `PREFECT_HOME`, уровень логирования и
отключение аналитики. Постоянный `PREFECT_API_URL` не задан, поэтому
Prefect использует временный локальный API

## Нюансы

- На нодах нет системного `pip` и `ensurepip`. `02_install_prefect.sh`
  создаёт venv через `python3 -m venv --without-pip`, затем ставит pip
  через официальный `get-pip.py`
- Prefect 3.9.2 требует Python `>=3.11,<3.16`, на `team-02-nn`
  используется Python 3.12.3
- PySpark 3.5.1 на Python 3.12.3 проверен реальным YARN-заданием
- Временный Prefect API занимает случайный локальный порт. Это не
  постоянный сервис, порт не резервируется в `PORTS.md`
- В логе Spark есть предупреждение о `SET hive.exec.dynamic.partition.mode`
  - Spark не меняет эту настройку динамически, но запись партиций
  выполнена через `saveAsTable(partitionBy)`, и результат корректен
- Скрипты идемпотентны там, где это безопасно: Prefect не
  переустанавливается при совпадении версии, HDFS-архив не пересобирается,
  таблица пересоздаётся через `DROP TABLE IF EXISTS` и `saveAsTable`
- Глобальные настройки, `/etc/hosts` и чужие процессы не изменяются
  Все действия выполняются в `/srv/dpe/sevinch` и в диапазоне
  портов `21000-21999`
