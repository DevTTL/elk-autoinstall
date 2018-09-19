#!/usr/bin/env bash

dir_name=""
# 取得软件的安装目录名字
function get_dir_name(){
    dir_name=$(ls | grep -v tar.gz | grep $1)
}

# 各个软件的安装目录
get_dir_name "logstash"
logstash_home=/opt/${dir_name}
get_dir_name "elasticsearch"
elasticsearch_home=/opt/${dir_name}
get_dir_name "kibana"
kibana_home=/opt/${dir_name}
get_dir_name "kafka"
kafka_home=/opt/${dir_name}

# 关闭防火墙和selinux
systemctl stop firewalld || service firewalld stop
setenforce 0

sysctl -w vm.max_map_count=262144

# 启动所有
${kafka_home}/bin/kafka-server-start.sh ${kafka_home}/config/server.properties &
${kafka_home}/bin/zookeeper-server-start.sh ${kafka_home}/config/zookeeper.properties &
su elk -l -c "${elasticsearch_home}/bin/elasticsearch &"
su elk -l -c "${logstash_home}/bin/logstash -f ${logstash_home}/config/conf.d/io.conf &"
su elk -l -c "${kibana_home}/bin/kibana &"

# 关闭全部
#ps -aux | grep beat | grep -v grep | awk '{print $2}' | xargs -I {} kill -9 {} ; \
#ps -aux | grep elast | grep -v grep | awk '{print $2}' | xargs -I {} kill -9 {} ; \
#ps -aux | grep logstash | grep -v grep | awk '{print $2}' | xargs -I {} kill -9 {} ;\
#ps -aux | grep kibana | grep -v grep | awk '{print $2}' | xargs -I {} kill -9 {}

#current_public_ip=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d '/')
#
## 查看所有topic
#bin/kafka-topics.sh --list --zookeeper ${current_public_ip}:2181
## 创建消费者
#bin/kafka-console-consumer.sh --bootstrap-server ${current_public_ip}:9092 --topic logstash_kafka_topic --from-beginning
#bin/kafka-console-producer.sh --broker-list ${current_public_ip}:9092 --topic logstash_kafka_topic

#./bin/zookeeper-server-start.sh config/zookeeper.properties &&
# bin/kafka-server-start.sh config/server.properties



