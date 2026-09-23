# Data-platform

Практическое задание №1: автоматизированное развертывание кластера HDFS
(NameNode + SecondaryNameNode + 3 DataNode) на изолированной общей инфраструктуре team-02

## Архитектура кластера

| Роль | Узел | Примечание |
|---|---|---|
| NameNode | team-02-nn (10.2.0.11) | метаданные |
| SecondaryNameNode | team-02-nn (10.2.0.11) | checkpoint (fsimage + edits) |
| DataNode 1 | team-02-nn (10.2.0.11) | третий DataNode рядом с NN, физических датанод две |
| DataNode 2 | team-02-00 (10.2.0.12) | |
| DataNode 3 | team-02-01 (10.2.0.13) | |

Версии: Apache Hadoop 3.3.6, Temurin JDK 8 (8u412). Java и Hadoop установлены
локально под участника, не в общую систему, чтобы не ломать окружение
других участников team-02

## Изоляция участника sevinch

- Linux-пользователь: `dpe_sevinch`
- Базовый каталог: `/srv/dpe/sevinch`
- Диапазон портов: `21000-21999`
- Все данные, конфиги, логи, PID лежат только внутри `/srv/dpe/sevinch/`

Назначенные порты (записаны в `/srv/dpe/sevinch/PORTS.md`):

| Сервис | Порт |
|---|---|
| NameNode RPC | 21020 |
| NameNode HTTP (UI) | 21970 |
| SecondaryNameNode RPC | 21069 |
| SecondaryNameNode HTTP | 21968 |
| DataNode IPC | 21064 |
| DataNode transfer | 21066 |
| DataNode HTTP | 21964 |

## Структура каталогов

```
/srv/dpe/sevinch/
├── dist/
├── conf/hw1/            конфиги кластера
├── data/hw1/namenode    метаданные NameNode (только на team-02-nn)
├── data/hw1/namesecondary, чекпоинты SecondaryNameNode (только на team-02-nn)
├── data/hw1/datanode    блоки DataNode (на каждой датаноде)
├── logs/hw1/
├── pids/hw1/
├── tmp/hw1/
└── homeworks/hw1/
```

## Развертывание

Все скрипты в каталоге `scripts/`. Вход с локальной машины на edge,
затем с edge на внутренние ноды:

```bash
ssh -i ~/.ssh/id_ed25519 team@111.88.128.191
ssh -i ~/.ssh/team_internal team@team-02-nn
```

### Создание пользователя и каталогов (выполняется как `team` на каждой ноде)

```bash
bash scripts/01_create_user.sh
```

Создаёт пользователя `dpe_sevinch`, каталоги `/srv/dpe/sevinch/...`,
`.dpe_env` (переменные окружения) и файл `PORTS.md`

### Установка JDK 8 и Hadoop (выполняется как `team`, демоны будут в `dpe_sevinch`)

```bash
bash scripts/02_install_software.sh
```

Скачивает Temurin JDK 8 и Hadoop 3.3.6 и распаковывает в `/srv/dpe/sevinch/dist/`

### Раскатка конфигов (как `team`)

```bash
bash scripts/03_apply_config.sh
```

Копирует `conf/` в `/srv/dpe/sevinch/conf/hw1/` на все узлы

### Формат NameNode (только на team-02-nn, от `dpe_sevinch`)

```bash
sudo -iu dpe_sevinch bash -lc 'hdfs namenode -format -force'
```

Перед форматированием скрипт `04_format_namenode.sh` проверяет, что
`dfs.namenode.name.dir` указывает строго на `/srv/dpe/sevinch/data/hw1/namenode`

### Запуск кластера

```bash
bash scripts/05_start.sh
```

Поузловый запуск демонов от `dpe_sevinch`:
- team-02-nn: `hdfs --daemon start namenode`, `secondarynamenode`, `datanode`
- team-02-00: `hdfs --daemon start datanode`
- team-02-01: `hdfs --daemon start datanode`

### Проверка целостности кластера

```bash
bash scripts/07_verify.sh
```

- `hdfs dfsadmin -report` → 3 живых DataNode, `Decommission Status: Normal`
- веб-интерфейс http://10.2.0.11:21970/ (HTTP 200)
- логи без критических ошибок (`grep ERROR` = 0)

### Остановка

```bash
bash scripts/06_stop.sh
```

Останавливает только демоны пользователя `dpe_sevinch` (через `--daemon stop`),
не затрагивая другие процессы

## Ключевые конфиги

В конфиге `conf/hdfs-site.xml` самое важное:

- `dfs.namenode.rpc-address` = `team-02-nn:21020`
- `dfs.namenode.http-address` = `team-02-nn:21970`
- `dfs.namenode.secondary.http-address` = `team-02-nn:21968`
- `dfs.namenode.name.dir` = `/srv/dpe/sevinch/data/hw1/namenode`
- `dfs.datanode.data.dir` = `/srv/dpe/sevinch/data/hw1/datanode`
- `dfs.replication` = 3
- `dfs.namenode.{rpc,http,https}-bind-host` = `0.0.0.0` (обязательно,
  иначе NameNode слушает только `127.0.1.1`, и датаноды других нод не смогут подключиться)

`conf/core-site.xml`: `fs.defaultFS` = `hdfs://team-02-nn:21020`,
`hadoop.tmp.dir` = `/srv/dpe/sevinch/tmp/hw1`

## Нюансы

- После перезапуска NameNode в логах DataNode может появиться единичный
  `EOFException`/`Connection refused`, это транзиентная ошибка на время рестарта,
  нода успешно переподключается (в логе `Successfully sent block report`)
- При изменении конфигов HDFS выполняйте переформатирование только осознанно,
  данные при этом теряются