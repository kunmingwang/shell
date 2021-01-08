#!/bin/bash
# 
# wkm@20210108 auto_testmysql.sh 
# www.gongyuenet.cn
# 使用sysbench自动压测MySQL
# 压测前准备：
# 1、参考使用tar包安装配置MySQL, 初始化数据库完成之后，创建压测的sysbench数据库，然后将数据目录完整拷贝一份出去，如: cp -r /vdb/mysqldata/data/* /root/sysbench/data/
# 2、开始压测，并将压测结果输入文件
# 3、压测结束，直接清理数据目录，并使用初始拷贝出去的还原
# 4、刷新数据，清理buffer cache，清理swap
#


SYSBENCH="`which sysbench`"
MYSQL="`which mysql`"
RESULE_PATH="/root/sysbench/result/"
LOGFILE="/root/sysbench/sysbench.log"
MYSQLDATA_PATH="/mysqldata/data"
NEWDATA="/root/sysbench/data"
MYSQL_HOST="localhost"
MYSQL_USER="root"
MYSQL_PASSWORD="mypassword"
MYSQL_SOCKET="/mysqldata/data/mysql.sock"
threads=(5 10 20 30 40 50 60 70 80 90 100 150 300 500)
OLTP_LUA_PATH="/usr/share/sysbench/tests/include/oltp_legacy/oltp.lua"
# 真实测试环境仅进行120s是不够的，应增加压测时间
RUN_TIME=120
# 需要初始化表的个数和大小，尽可能适应设置的buffer pool大小
INIT_TABLE_COUNT=10
INIT_TABLE_SIZE=1000
VERBOSE="true"


trap _exit SIGHUP SIGINT SIGTERM


mode=$1    # start or stop
[ $# -ge 1 ] && shift
other_args="$*"


# 记录日志
log(){
    local level="INFO"
    if [[ -n $2 ]]; then
        level=$2
    fi
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')][${level}] $1"
    echo "${msg}" >> "$LOGFILE"

    if [[ "${VERBOSE}" == 'true' ]]; then
        echo "${msg}"
    fi
}

# 刷新数据
reflush_data(){
	cd "$MYSQLDATA_PATH"
	log "remove dirty data file"
	# 停止数据库，删除数据目录
	service mysqld stop
	rm -fr ./*
	# 清理系统缓存
	sync && echo 3 >/proc/sys/vm/drop_cache
	# 清理swap
	swapoff -a && swapon -a
	log "add new data file"
	# 拷贝数据文件，启动数据库
	alias cp='cp' && cp -r $NEWDATA/* ./
	rm -f *.lock *.sock auto.cnf
	chown -R mysql.mysql ../*
	service mysqld restart
	sleep 10
}

# 失败退出
_exit(){
	reflush_data
	trap - SIGINT SIGTERM
	kill -- -$$
	exit $1
}

main(){
	# 清理下环境
	for thread in ${threads[@]};do
		$MYSQL -h$MYSQL_HOST -u $MYSQL_USER -p"$MYSQL_PASSWORD" -S $MYSQL_SOCKET -e "drop database if exists sbtest;create database if not exists sbtest;"
		if [ "$?" != "0" ];then
			log "mysql status error ,exit . . . "
			_exit
		fi
		log "********************************Start testing MySQL with $thread threads . . . prepare********************************"
		$SYSBENCH $OLTP_LUA_PATH \
			--mysql-host=$MYSQL_HOST \
			--mysql-port=3306 \
			--mysql-user=$MYSQL_USER \
			--mysql-password=$MYSQL_PASSWORD \
			--mysql-socket=$MYSQL_SOCKET \
			--mysql-db=sbtest \
			--report-interval=30 \
			--time=$RUN_TIME \
			--threads=$thread \
			--oltp-tables-count=$INIT_TABLE_COUNT \
			--oltp-table-size=$INIT_TABLE_SIZE prepare >> $LOGFILE
		sleep 10
		log "********************************Start testing MySQL with $thread threads . . . run********************************"
		$SYSBENCH $OLTP_LUA_PATH \
			--mysql-host=$MYSQL_HOST \
			--mysql-port=3306 \
			--mysql-user=$MYSQL_USER \
			--mysql-password=$MYSQL_PASSWORD \
			--mysql-socket=$MYSQL_SOCKET \
			--mysql-db=sbtest \
			--report-interval=30 \
			--time=$RUN_TIME \
			--threads=$thread \
			--oltp-tables-count=$INIT_TABLE_COUNT \
			--oltp-table-size=$INIT_TABLE_SIZE run >> $LOGFILE
		sleep 10
		log "********************************Start using $thread threads to test MySQL at the end . . . ********************************"
		reflush_data
	done
}


case "$mode" in
  'start')
    # 执行压测
    for i in `echo $other_args`;do
        if [ "$i" != "" ];then
                cfg_item=${i%%=*}
                sed -i "s/$cfg_item/#$cfg_item/g" /etc/my.cnf
                sed -i "/#$cfg_item/a$i" /etc/my.cnf
        fi
     done
	main
    ;;

  'repair')
    # 执行修复数据库
    reflush_data
    ;;
	
    *)
      # usage
      echo "USAGE $0 start [innodb_buffer_pool_size=128M] | repair"
	  exit 1
    ;;
esac

exit 0
