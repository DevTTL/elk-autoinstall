#!/usr/bin/env bash

# 添加DNS和备用DNS
echo > /etc/solve
echo "nameserver 223.6.6.6" >> /etc/solve
echo "nameserver 114.114.114.114" >> /etc/solve

# 替换源
mv /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.backup
# 阿里云源
# curl -o /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo

# 清华
sudo tee /etc/yum.repos.d/CentOS-Base.repo <<-'EOF'
# CentOS-Base.repo
#
# The mirror system uses the connecting IP address of the client and the
# update status of each mirror to pick mirrors that are updated to and
# geographically close to the client.  You should use this for CentOS updates
# unless you are manually picking other mirrors.
#
# If the mirrorlist= does not work for you, as a fall back you can try the
# remarked out baseurl= line instead.
#
#

[base]
name=CentOS-$releasever - Base
baseurl=https://mirrors.tuna.tsinghua.edu.cn/centos/$releasever/os/$basearch/
#mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=os
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

#released updates
[updates]
name=CentOS-$releasever - Updates
baseurl=https://mirrors.tuna.tsinghua.edu.cn/centos/$releasever/updates/$basearch/
#mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=updates
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

#additional packages that may be useful
[extras]
name=CentOS-$releasever - Extras
baseurl=https://mirrors.tuna.tsinghua.edu.cn/centos/$releasever/extras/$basearch/
#mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=extras
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7

#additional packages that extend functionality of existing packages
[centosplus]
name=CentOS-$releasever - Plus
baseurl=https://mirrors.tuna.tsinghua.edu.cn/centos/$releasever/centosplus/$basearch/
#mirrorlist=http://mirrorlist.centos.org/?release=$releasever&arch=$basearch&repo=centosplus
gpgcheck=1
enabled=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
EOF

yum makecache
yum -y update
yum -y install wget vim screen

# 修改vim配置
echo "set ts=4" >> /etc/vimrc

# 下载软件包
cd /opt
wget $1 # java 的下载地址会失效，所以需要再第一个参数指定地址
wget https://artifacts.elastic.co/downloads/kibana/kibana-6.4.0-linux-x86_64.tar.gz
wget https://artifacts.elastic.co/downloads/logstash/logstash-6.4.0.tar.gz
wget https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-6.4.0.tar.gz
wget https://mirrors.tuna.tsinghua.edu.cn/apache/kafka/2.0.0/kafka_2.11-2.0.0.tgz

# 给jdk改名字
ls | grep jdk | xargs -I {} mv {} jdk.tar.gz

# 解压全部后把源码挪走
ls | xargs -I {} tar xzvf {}
mkdir src && ls *.tar.gz | xargs -I {} mv {} ./src && ls *.tgz | xargs -I {} mv {} ./src

# 添加用户并授权
useradd elk
chown -R elk:elk ./*

dir_name=""
# 取得软件的安装目录名字
function get_dir_name(){
    dir_name=$(ls | grep -v tar.gz | grep $1)
}

# 各个软件的安装目录
get_dir_name "jdk"
jdk_home=/opt/${dir_name}
get_dir_name "logstash"
logstash_home=/opt/${dir_name}
get_dir_name "elasticsearch"
elasticsearch_home=/opt/${dir_name}
get_dir_name "kibana"
kibana_home=/opt/${dir_name}
get_dir_name "kafka"
kafka_home=/opt/${dir_name}

# JAVA环境变量
echo "export JAVA_HOME=$jdk_home" >> /etc/bashrc
echo "export CLASSPATH=$JAVA_HOME/lib/" >> /etc/bashrc
echo "export PATH=$PATH:$JAVA_HOME/bin" >> /etc/bashrc
source /etc/bashrc

# 当前公网IP
current_public_ip=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1 -d '/')

# 安装es

# 替换集群名称
sed -i "s/#cluster.name:\ my-application/cluster.name:\ es-cluster/" ${elasticsearch_home}/config/elasticsearch.yml
# 替换节点名称
sed -i "s/#node.name:\ node-1/node.name:\ node-1/" ${elasticsearch_home}/config/elasticsearch.yml
# 替换数据和日志目录为数据盘
sed -i "s/#path.data:\ \/path\/to\/data/path.data:\ \/es-data\/data/" ${elasticsearch_home}/config/elasticsearch.yml
sed -i "s/#path.logs:\ \/path\/to\/logs/path.logs:\ \/es-data\/logs/" ${elasticsearch_home}/config/elasticsearch.yml

# 替换监听的IP地址
sed -i "s/#network.host:/network.host:/" ${elasticsearch_home}/config/elasticsearch.yml
sed -i "s/:\ 192.168.0.1/:\ ${current_public_ip}/" ${elasticsearch_home}/config/elasticsearch.yml

sysctl -w vm.max_map_count=262144
echo "elk        hard    nofile           262144" >> /etc/security/limits.conf
echo "elk        soft    nofile           262144" >> /etc/security/limits.conf

# 安装logstash

# 更新 logstash-kafka 输入输出插件到最新
${logstash_home}/bin/logstash-plugin update logstash-output-kafka

# 创建目录 ，写入配置文件
mkdir -p ${logstash_home}/config/conf.d
sudo tee ${logstash_home}/config/conf.d/io.conf <<-'EOF'
input {
    tcp{
        port => 5044
        mode => server
        codec  => json
    }
}
output{
    kafka{
        topic_id => "logstash_kafka_topic"
        bootstrap_servers => "current_public_ip:9092"
        codec => "json"
    }
}
EOF

sed -i "s/current_public_ip/${current_public_ip}/" ${logstash_home}/config/conf.d/io.conf

# 安装kibana

sed -i "s/#elasticsearch.url:\ \"http:\/\/localhost:9200\"/elasticsearch.url:\ \"http:\/\/${current_public_ip}:9200\"/" ${kibana_home}/config/kibana.yml
sed -i "s/#server.host:\ \"localhost\"/server.host:\ \"${current_public_ip}\"/" ${kibana_home}/config/kibana.yml

# 安装kafka
sed -i "s/#listeners=PLAINTEXT:\/\/:9092/listeners=PLAINTEXT:\/\/${current_public_ip}:9092/" ${kafka_home}/config/server.properties

# 关闭防火墙和selinux
systemctl stop firewalld || service firewalld stop
setenforce 0

# 数据目录授权
chmod -R 755 /es-data/
chown -R elk:elk /es-data/

# 启动所有
${kafka_home}/bin/kafka-server-start.sh ${kafka_home}/config/server.properties & >> /dev/null
${kafka_home}/bin/zookeeper-server-start.sh ${kafka_home}/config/zookeeper.properties & >> /dev/null
su elk -l -c "${elasticsearch_home}/bin/elasticsearch & >> /dev/null"
su elk -l -c "${logstash_home}/bin/logstash -f ${logstash_home}/config/conf.d/io.conf & >> /dev/null"
su elk -l -c "${kibana_home}/bin/kibana & >> /dev/null"
