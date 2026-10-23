# ДЗ 3: развёртывание Apache Hive с внешним metastore

## Архитектура Hive

| Компонент | Узел | Назначение |
|---|---|---|
| Derby Network Server | team-02-00 (10.2.0.12) | база метаданных, сетевой режим |
| Hive Metastore | team-02-00 (10.2.0.12) | общий thrift-метастор |
| HiveServer2 | team-02-00 (10.2.0.12) | thrift-сервер для клиентов |
| Hive-клиент (beeline) | все три ноды | клиенты подключаются к HiveServer2 |

Версии: Apache Hive 4.0.0-alpha-2, Apache Derby 10.14.2.0,
Apache Hadoop 3.3.6 и Temurin JDK 8 (8u412) из ДЗ 1 и ДЗ 2

Metastore не embedded: HiveServer2, Metastore и Derby это три отдельных
процесса, поэтому одновременно могут работать несколько клиентов.
Metastore хранит данные в Derby Network Server на team-02-00, а не в
локальном каталоге внутри процесса Hive

## Порты HW3 (диапазон 21000-21999, записаны в `PORTS.md`)

| Сервис | Порт |
|---|---|
| HiveServer2 thrift | 21050 |
| HiveServer2 Web UI | 21051 |
| Hive Metastore thrift | 21053 |
| Derby Network Server | 21059 |

Порты HDFS и YARN из ДЗ 1 и ДЗ 2 остаются на месте, их демоны не трогаются

## Структура каталогов

```
/srv/dpe/sevinch/
├── dist/hive/           Apache Hive 4.0.0-alpha-2
├── dist/derby/          Apache Derby 10.14.2.0
├── conf/hw3/            hive-site.xml, hive-env.sh, hive-log4j2.properties
├── data/hw3/derby/      файлы базы metastore_sevinch_hw3
├── logs/hw3/            логи Derby, Metastore, HiveServer2
│   └── prev/            логи прошлого запуска (архивирует 10_stop_hive.sh)
├── pids/hw3/            PID-файлы
├── tmp/hw3/             scratch и downloaded resources
└── homeworks/hw3/       результаты проверок и загрузки
```

Каталоги в HDFS: `/user/dpe_sevinch/hive/warehouse` (склад),
`/user/dpe_sevinch/hive/scratch` (scratch, права 777),
`/user/dpe_sevinch/hw3/staging` (исходный CSV)

## Предпосылки

- HDFS из ДЗ 1 запущен: `bash hw1/scripts/07_verify.sh`
- YARN из ДЗ 2 запущен, все три ноды RUNNING: `bash hw2/scripts/04_verify.sh`
- Скрипты лежат в `hw3/` и запускаются с edge-машины,
  там есть ключ `~/.ssh/team_internal`

## Скрипты

Всё в каталоге `hw3/scripts/`, порядок запуска от 01 до 08,
публикация UI отдельно, остановка отдельно

## Результаты проверки

Проверено на трёх нодах после восстановления `team-02-nn`:

- `06_verify.sh`: `VERIFY: OK`, все четыре порта слушают, metastore внешний
- `07_load_data.sh`: 3 партиции, 3 каталога HDFS, 36 строк, `dt=dt` отсутствует
- `08_multiclient.sh`: `OVERLAP: YES`, `MULTICLIENT: OK`, клиент B на `team-02-nn`
- Результаты лежат в `homeworks/`: `load_result.txt`, `verify.txt`,
  `multiclient_result.txt`

### 01_preflight.sh

```bash
bash hw3/scripts/01_preflight.sh
```

Создаёт каталоги на всех нодах, проверяет свободность портов 21050,
21051, 21053, 21059, наличие JDK и Hadoop, свободную память на team-02-00
(нужно не меньше 1500 МБ), живость HDFS и YARN, дописывает секцию HW3
в `PORTS.md`

### 02_install.sh

```bash
bash hw3/scripts/02_install.sh
```

Скачивает Hive 4.0.0-alpha-2 и Derby 10.14.2.0 в `dist/downloads`,
распаковывает в `dist/hive` и `dist/derby` на всех трёх нодах,
кладёт `derbyclient.jar` в `dist/hive/lib`

Отдельно решается конфликт guava: Hive 4 собран с guava 19, а Hadoop 3.3.6
использует guava 27. Старая guava из Hive lib убирается в `lib/disabled`,
на её место кладётся `guava-27.0-jre.jar` из Hadoop. Это локальная
установка участника, общие каталоги не затрагиваются

### 03_apply_config.sh

```bash
bash hw3/scripts/03_apply_config.sh
```

Копирует `hive-site.xml`, `hive-env.sh`, `hive-log4j2.properties` в
`conf/hw3` на все ноды и подставляет IP team-02-00 вместо `__HIVE_HOST__`.
Создаёт каталоги Hive в HDFS и выставляет на scratch права 777,
иначе HiveServer2 отказывается стартовать

### 04_init_schema.sh

```bash
bash hw3/scripts/04_init_schema.sh
```

Запускает Derby Network Server на team-02-00 (порт 21059) и инициализирует
схему metastore через `schematool -dbType derby -initSchema`.
Повторный запуск безопасен: если `schematool -info` уже отдаёт версию
схемы, инициализация пропускается

### 05_start_hive.sh

```bash
bash hw3/scripts/05_start_hive.sh
```

Запускает по порядку Derby, Hive Metastore (21053) и HiveServer2
(21050 и 21051), ждёт открытия портов. Уже запущенные процессы
не перезапускаются

### 06_verify.sh

```bash
bash hw3/scripts/06_verify.sh
```

Шесть проверок:

1. все четыре порта HW3 слушают
2. процессы Derby, Metastore и HiveServer2 принадлежат только `dpe_sevinch`
3. beeline подключается к HiveServer2, видит базу `default`
   и удалённый `hive.metastore.uris=thrift://10.2.0.12:21053`
4. HiveServer2 Web UI отдаёт HTTP 200
5. в логах нет `FATAL`, `NoSuchMethodError`, `ClassNotFoundException`,
   `NoClassDefFoundError`
6. metastore не embedded: JDBC URL сетевой, Derby Network Server запущен

### 07_load_data.sh

```bash
bash hw3/scripts/07_load_data.sh
```

Генерирует CSV с продажами за три дня (36 строк), кладёт его в HDFS,
создаёт внешнюю таблицу `hw3.sales_staging` и партиционированную
таблицу `hw3.sales_part` (ORC, партиция по `dt`). Затем выполняет
`INSERT OVERWRITE ... PARTITION(dt)` с динамическими партициями,
печатает `SHOW PARTITIONS` и агрегаты по дням

Проверяет, что получилось ровно 3 партиции, 3 каталога в HDFS и 36 строк.
Запрос выполняется движком MapReduce на YARN из ДЗ 2 с контейнерами по 512 МБ

### 08_multiclient.sh

```bash
bash hw3/scripts/08_multiclient.sh
```

Запускает два клиента одновременно:

- клиент A на team-02-00 выполняет долгий запрос
  `reflect('java.lang.Thread','sleep',25000L)`, аргумент передаётся как
  `long`, иначе Hive ищет `Thread.sleep(int)` и падает с `NoSuchMethodException`
- клиент B на team-02-nn в это время подключается к тому же HiveServer2,
  выполняет `SELECT current_user(), current_database()` и `SHOW PARTITIONS`
- клиента B можно переопределить: `CLIENT2=team-02-01 bash hw3/scripts/08_multiclient.sh`

Скрипт проверяет, что клиент B завершился, пока клиент A ещё работал.
Это и есть доказательство одновременной работы более одного клиента.
Результат пишется в `/tmp/hw3_multiclient_result.txt` на edge-машине

### 09_publish_ui.sh (запускается с локальной машины, не с edge)

```bash
bash hw3/scripts/09_publish_ui.sh
```

Открывает SSH-туннель через edge и печатает URL:

| Демон | URL с локальной машины |
|---|---|
| HiveServer2 Web UI | http://localhost:21051/ |

Наружу открыт только порт 22, поэтому UI публикуется туннелем

Остановка туннеля:

```bash
pkill -f "21051:10.2.0.12:21051"
```

Ключ SSH задаётся переменной, если он не в `~/.ssh/id_ed25519`:

```bash
SSH_KEY=~/.ssh/my_key bash hw3/scripts/09_publish_ui.sh
```

### 10_stop_hive.sh

```bash
bash hw3/scripts/10_stop_hive.sh
```

Останавливает HiveServer2 и Metastore по процессам пользователя
`dpe_sevinch`, затем корректно гасит Derby через `NetworkServerControl
shutdown`, архивирует логи в `logs/hw3/prev/` и проверяет, что порты
21050, 21051, 21053, 21059 закрыты. YARN и HDFS не трогаются

## Ключевые конфиги

`hw3/conf/hive-site.xml`

- `hive.metastore.uris` = `thrift://10.2.0.12:21053`, HiveServer2 ходит
  в отдельный Metastore, а не создаёт его внутри себя
- `javax.jdo.option.ConnectionURL` =
  `jdbc:derby://10.2.0.12:21059/metastore_sevinch_hw3;create=true`
- `javax.jdo.option.ConnectionDriverName` =
  `org.apache.derby.jdbc.ClientDriver`, то есть сетевой драйвер Derby
- `datanucleus.connectionPoolingType` = `None`, чтобы не тянуть лишние
  пулы соединений в простом стенде
- `hive.metastore.warehouse.dir` =
  `hdfs://team-02-nn:21020/user/dpe_sevinch/hive/warehouse`
- `hive.server2.thrift.port` = `21050`,
  `hive.server2.webui.port` = `21051`,
  `hive.metastore.port` = `21053`
- `hive.execution.engine` = `mr`, используется YARN из ДЗ 2
- `hive.exec.dynamic.partition` = `true`,
  `hive.exec.dynamic.partition.mode` = `nonstrict`
- `hive.create.as.acid` = `false`, чтобы таблица была обычной, без
  транзакционного движка, который не нужен для MR
- `hive.metastore.event.db.notification.api.auth` = `false`,
  иначе HiveServer2 при старте получает отказ на
  `get_current_notificationEventId`

`hw3/conf/hive-env.sh`: JAVA_HOME, HADOOP_HOME, `HADOOP_CONF_DIR` из ДЗ 2,
HIVE_HOME, HIVE_CONF_DIR, HIVE_LOG_DIR, HIVE_PID_DIR, память Hive 512 МБ

## Нюансы

- Derby Network Server запускается отдельным Java-процессом с
  `-Dderby.system.home=/srv/dpe/sevinch/data/hw3/derby`; база
  `metastore_sevinch_hw3` создаётся при первом `schematool -initSchema`
- HiveServer2 проверяет права на `hive.exec.scratchdir`; каталог в HDFS
  должен быть доступен на запись, поэтому ему выставлены права 777
- В логах beeline видны предупреждения SLF4J о нескольких binding
  (log4j-slf4j-impl из Hive и slf4j-reload4j из Hadoop). Это не ошибка,
  фактически используется binding Hive
- Hive 4.0.0-alpha-2 собран с Hadoop 3.3.1, стенд использует Hadoop 3.3.6;
  связка проверена тестовым MR-джобом и загрузкой партиций
- При остановке сначала гасятся HiveServer2 и Metastore, затем Derby;
  скрипт не делает `pkill java`, чтобы не задеть YARN и HDFS

