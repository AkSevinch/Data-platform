export JAVA_HOME=/srv/dpe/sevinch/dist/jdk8
export HADOOP_HOME=/srv/dpe/sevinch/dist/hadoop
export HADOOP_CONF_DIR=/srv/dpe/sevinch/conf/hw2
export YARN_CONF_DIR=/srv/dpe/sevinch/conf/hw2
export HIVE_CONF_DIR=/srv/dpe/sevinch/conf/hw5

export SPARK_HOME=/srv/dpe/sevinch/dist/spark
export SPARK_CONF_DIR=/srv/dpe/sevinch/conf/hw5
export SPARK_LOG_DIR=/srv/dpe/sevinch/logs/hw5
export SPARK_PID_DIR=/srv/dpe/sevinch/pids/hw5
export SPARK_LOCAL_DIRS=/srv/dpe/sevinch/tmp/hw5
export SPARK_WORKER_DIR=/srv/dpe/sevinch/tmp/hw5
export SPARK_DAEMON_MEMORY=512m

export PYSPARK_PYTHON=/usr/bin/python3
export PYSPARK_DRIVER_PYTHON=/usr/bin/python3

export LD_LIBRARY_PATH="$HADOOP_HOME/lib/native${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
