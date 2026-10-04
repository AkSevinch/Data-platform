# ДЗ 2: развёртывание YARN и публикация веб-интерфейсов

## Архитектура YARN

| Демон | Узел | Назначение |
|---|---|---|
| ResourceManager | team-02-nn (10.2.0.11) | планирование приложений |
| NodeManager | team-02-nn (10.2.0.11) | исполнение контейнеров |
| NodeManager | team-02-00 (10.2.0.12) | исполнение контейнеров |
| NodeManager | team-02-01 (10.2.0.13) | исполнение контейнеров |
| JobHistoryServer | team-02-nn (10.2.0.11) | история MapReduce-джобов |
| TimelineServer | team-02-nn (10.2.0.11) | история приложений YARN |

Версии те же, что в ДЗ 1: Apache Hadoop 3.3.6, Temurin JDK 8 (8u412)

## Порты HW2 (диапазон 21000-21999, записаны в `PORTS.md`)

| Сервис | Порт |
|---|---|
| ResourceManager scheduler RPC | 21030 |
| ResourceManager resource-tracker RPC | 21031 |
| ResourceManager client RPC | 21032 |
| ResourceManager admin RPC | 21033 |
| ResourceManager Web UI | 21088 |
| NodeManager localizer | 21040 |
| NodeManager RPC | 21041 |
| NodeManager Web UI | 21042 |
| NodeManager shuffle | 21045 |
| JobHistoryServer RPC | 21120 |
| JobHistoryServer Web UI | 21888 |
| TimelineServer Web UI | 21188 |

Порты HDFS из ДЗ 1 (21020, 21970, 21069, 21968, 21064, 21066, 21964)
остаются на месте, демоны HDFS при работе с YARN не трогаются

## Структура каталогов

```
/srv/dpe/sevinch/
├── conf/hw2/            конфиги YARN (yarn-site, mapred-site и остальные)
├── logs/hw2/            логи демонов YARN
│   └── prev/            логи прошлого запуска (архивирует 06_stop_yarn.sh)
├── logs/hw2/nm/         логи контейнеров
├── pids/hw2/            PID-файлы
├── tmp/hw2/             hadoop.tmp.dir и local-dirs NodeManager
└── homeworks/hw2/       результаты проверок
```

Каталоги в HDFS: `/yarn/app-logs` (агрегация логов),
`/user/dpe_sevinch/mapred/done` и `done_intermediate` (JobHistory)

## Предпосылки

- HDFS из ДЗ 1 запущен и здоров (`bash hw1/scripts/07_verify.sh` из корня репо)
- Конфиги и скрипты лежат в `hw2/`, запуск с edge-машины
  (там есть ключ `~/.ssh/team_internal` для входа на внутренние ноды)

## Скрипты

Всё в каталоге `hw2/scripts/`, порядок запуска от 01 до 06

### 01_preflight.sh

```bash
bash hw2/scripts/01_preflight.sh
```

Создаёт каталоги `conf/hw2`, `logs/hw2`, `pids/hw2`, `tmp/hw2` на всех нодах,
проверяет, что порты YARN свободны, что HDFS жив, и дописывает
секцию HW2 в `PORTS.md`

### 02_apply_config.sh

```bash
bash hw2/scripts/02_apply_config.sh
```

Копирует конфиги из `hw2/conf/` в `/srv/dpe/sevinch/conf/hw2/` на все ноды,
подставляя в `yarn.nodemanager.hostname` имя текущей ноды,
плюс штатные `capacity-scheduler.xml` и `log4j.properties` из дистрибутива

### 03_start_yarn.sh

```bash
bash hw2/scripts/03_start_yarn.sh
```

- создаёт HDFS-каталоги для агрегации логов и JobHistory
- запускает ResourceManager на team-02-nn
- запускает NodeManager на всех трёх нодах и ждёт, пока все
  три зарегистрируются (`yarn node -list` = 3 RUNNING)
- запускает JobHistoryServer и TimelineServer, ждёт их порты

Скрипт идемпотентный: уже запущенные демоны не перезапускаются

### 04_verify.sh

```bash
bash hw2/scripts/04_verify.sh
```

Шесть проверок:

1. процессы YARN только от `dpe_sevinch` на всех нодах
2. все 12 портов HW2 слушают
3. три ноды в статусе RUNNING
4. тестовый MapReduce-джоб: `hadoop-mapreduce-examples pi 2 10`
   (в выводе `completed successfully` и `Estimated value of Pi`)
5. HTTP 200 на всех 11 веб-интерфейсах (NN, SNN, 3 DN, RM, 3 NM, JH, Timeline)
6. ноль критических ошибок в логах `logs/hw2/`

### 05_publish_ui.sh (запускается с локальной машины, не с edge)

```bash
bash hw2/scripts/05_publish_ui.sh
```

Открывает SSH-туннели через edge (111.88.128.191, порт 22) и печатает
таблицу доступных интерфейсов:

| Демон | URL с локальной машины |
|---|---|
| NameNode | http://localhost:21970/ |
| SecondaryNameNode | http://localhost:21968/ |
| DataNode team-02-nn | http://localhost:21964/ |
| DataNode team-02-00 | http://localhost:21965/ |
| DataNode team-02-01 | http://localhost:21966/ |
| ResourceManager | http://localhost:21088/ |
| NodeManager team-02-nn | http://localhost:21042/ |
| NodeManager team-02-00 | http://localhost:21043/ |
| NodeManager team-02-01 | http://localhost:21044/ |
| JobHistoryServer | http://localhost:21888/ |
| TimelineServer | http://localhost:21188/ |

Наружу из-под файрвола открыт только порт 22, поэтому UI публикуется
туннелями, а не прокси-сервером: одно SSH-соединение, много `-L`

Остановка туннелей с локальной машины:

```bash
pkill -f "21970:10.2.0.11:21970"
```

Ключ SSH задаётся переменной, если он не в `~/.ssh/id_ed25519`:

```bash
SSH_KEY=~/.ssh/my_key bash hw2/scripts/05_publish_ui.sh
```

### 06_stop_yarn.sh

```bash
bash hw2/scripts/06_stop_yarn.sh
```

Останавливает только демоны YARN пользователя `dpe_sevinch`
(JobHistory, Timeline, ResourceManager, все NodeManager),
архивирует их логи в `logs/hw2/prev/` и проверяет, что процессов не осталось
Демоны HDFS из ДЗ 1 продолжают работать

## Ключевые конфиги

`hw2/conf/yarn-site.xml` самое важное

- `yarn.resourcemanager.hostname` = `team-02-nn`, адреса RM привязаны
  к портам 21030-21033 и 21088 через `${yarn.resourcemanager.hostname}`
- `yarn.resourcemanager.bind-host` = `0.0.0.0`
- `yarn.nodemanager.hostname` = имя ноды (подставляет `02_apply_config.sh`),
  адреса NM 21040-21042 через `${yarn.nodemanager.hostname}`
- `yarn.nodemanager.bind-host` = `0.0.0.0`, обязательно:
  иначе NodeManager слушает `127.0.1.1` (так резолвится имя ноды
  в `/etc/hosts`), ResourceManager не сможет отправлять контейнеры,
  и веб-интерфейс NM будет недоступен снаружи
- `yarn.nodemanager.aux-services.mapreduce_shuffle.port` = `21045`,
  штатный порт shuffle 13562 выходит за диапазон участника
- `yarn.log-aggregation-enable` = `true`,
  `yarn.nodemanager.remote-app-log-dir` = `/yarn/app-logs`
- `yarn.timeline-service.enabled` = `true`, порт 21188
- `yarn.application.classpath` и `mapreduce.application.classpath`
  заданы абсолютными путями `/srv/dpe/sevinch/dist/hadoop/share/hadoop/...`,
  чтобы контейнеры получили классы без подстановки переменных окружения

`hw2/conf/mapred-site.xml`

- `mapreduce.framework.name` = `yarn`
- `mapreduce.jobhistory.address` = `team-02-nn:21120`,
  `mapreduce.jobhistory.webapp.address` = `team-02-nn:21888`
- каталоги JobHistory в HDFS: `/user/dpe_sevinch/mapred/done` и `done_intermediate`

`hw2/conf/core-site.xml`: `fs.defaultFS` = `hdfs://team-02-nn:21020`
(тот же кластер), `hadoop.tmp.dir` = `/srv/dpe/sevinch/tmp/hw2`

## Нюансы

- При первом запуске в логи могли попасть ошибки от остановки демонов
  (`RECEIVED SIGNAL 15: SIGTERM`), `06_stop_yarn.sh` архивирует логи
  при остановке, поэтому после цикла `06 -> 03 -> 04` проверка чистая
- `04_verify.sh` дополнительно фильтрует шум остановки:
  `SIGTERM` и `InterruptedException`
- Интерфейсы внутри UI ResourceManager (ссылки на ноды с FQDN
  `team-02-00.hse.c.mws`) открываются изнутри кластера,
  с локальной машины пользуйтесь таблицей URL выше
