#!/bin/bash
# @kunming 20200212 
# 作用：
# auto_analyze_table.sh 根据输入的表名自动进行分析，更新索引基数统计，优化索引查询
# 对于频繁增删改查的表，建议定期在业务低峰期执行analyze table操作，刷新表的统计信息，提高查询效率
# # 0 1 * * * /bin/bash /path/auto_analyze_table.sh
# 读取文件内容：
# auto_analyze_table 保存需要analyze的 库名.表名 的形式，每表一行，使用时读取此文件
# cat auto_analyze_table
# monitor.monitor_host
# monitor.monitor_data
# monitor.monitor_host_group
# 权限：
# create user anaylze_user@'127.0.0.1' identified by 'password';grant select,insert on *.* to anaylze_user@'127.0.0.1' ;

# ----------------------
TB_FILE='/root/auto_analyze_table'
LOG_FILE='/root/analyze.log'
LOCK_FILE='/mysqldata/analyze.lock'
MYSQL="`which mysql` -h127.0.0.1 -uanaylze_user -ppassword -NBe "
concurrent=2 #并行度

# -----------------------

add_lock(){
	if [ -f "$LOCK_FILE" ];then
		# 存在锁，退出
		write_log "当前有analyze在运行或者上次analyze不完全，退出 - - -"
		exit 0
	else
		touch $LOCK_FILE
		write_log "创建锁文件成功 - - -"
	fi
}

release_lock(){
	if [ -f "$LOCK_FILE" ];then
		# 存在锁文件，清理释放锁
		rm -f $LOCK_FILE
		write_log "analyze结束，释放锁成功 - - "
	fi
}

write_log(){
	echo "`date +"%Y-%m-%d %H:%M:%S"` -analyze- $1"
	echo "`date +"%Y-%m-%d %H:%M:%S"` -analyze- $1" >> $LOG_FILE
}

analyze_table(){
	# 执行命令时会对表加读锁，同时从表定义缓存中删除表，这需要刷新锁，所以业务高峰期禁用
	info="`$MYSQL "analyze local table $i"`"
	write_log "$info"
}

main(){
	# 判断是否有需要analyze的表
	if [ -f "$TB_FILE" ];then
		TB_LIST="`cat $TB_FILE`"
	else
		write_log "没有设置$TB_FILE文件，退出"
		release_lock
		exit 0
	fi	
	tmp_fifo=$$.fifo
	# 用户取消执行，就关闭管道，并且删除临时文件
	trap "exec 1234>&-;exec 1234<&-;rm -f $tmp_fifo;exit 0" SIGINT	
	mkfifo $tmp_fifo							# mkfifo 创建命名管道
	exec 1234<>$tmp_fifo
	rm -rf $tmp_fifo							
	# 创建一个队列，以便后面使用
	for ((i=1;i<=${concurrent};i++))
	do
		echo "0">&1234
	done
	# 这里执行的是具体的并发任务
	for i in $TB_LIST;do
		read -u 1234								# 读取管道里面的内容
		{
		echo "开始并行analyze_table $i 执行命令 - - - "
		analyze_table "$i"
		echo "0">&1234
		} &
	done
	wait
	echo "done"
	# 关闭管道
	exec 1234>&-;
	exec 1234<&-;
	# exit $?
}

add_lock
main
release_lock
