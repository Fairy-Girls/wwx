#!/bin/bash
#updb数据库服务器执行
#日志路径
date=`date +'%Y%m%d%H%M%S'`
log=/var/log/logic/${date}.txt
mkdir /var/log/logic 2>/dev/null
#声明数据库密码
export PGPASSWORD=admin..1121
#清理sql文件函数，$1为文件地址
 clear(){
	#删除第一行
	sed -i '1d' $1
	#再删第一行
	sed -i '1d' $1
	#删除空行
	sed -i '/^$/d' $1
	#删除最后一行
	sed -i '$d' $1
	#删除"|"符号
	sed -i "s/|//g" $1
}
#获取数据源信息
/usr/local/pgsql/bin/psql -U postgres -d updb -c "SELECT sr.source_db,(select serverip FROM sys_database sd WHERE sd.instance=sr.source_db )as source_ip,sr.target_db,(select serverip FROM sys_database sd WHERE sd.instance=sr.target_db )as target_ip,sr.tables_name,sr.slot_name,sr.pub_name,sr.sub_name FROM syn_rules sr" >db_info.txt
clear db_info.txt
while read line;do
	source_db=`echo $line|awk '{print $1}'`
	source_ip=`echo $line|awk '{print $2}'`
	target_db=`echo $line|awk '{print $3}'`
	target_ip=`echo $line|awk '{print $4}'`
	tables_name=`echo $line|awk '{print $5}'`
	slot_name=`echo $line|awk '{print $6}'`
	pub_name=`echo $line|awk '{print $7}'`
	sub_name=`echo $line|awk '{print $8}'`
	#创建复制槽
	echo "#############${source_db}====>${target_db}###########"
	echo `date`"#############${source_db}====>${target_db}###########" >>$log
	echo "正在创建${source_db}同步到${target_db}的复制槽...."
	echo `date`"正在创建${source_db}同步到${target_db}的复制槽...." >>$log
	/usr/local/pgsql/bin/psql -h ${source_ip} -U postgres -d ${source_db} -c "select pg_create_logical_replication_slot('${slot_name}','pgoutput');" >/dev/null
	echo "已创建${slot_name}复制槽...."
	echo `date`"已创建${slot_name}复制槽...." >>$log
	#创建发布
	echo "正在创建发布...."
	echo `date`"正在创建发布...." >>$log
	/usr/local/pgsql/bin/psql -h ${source_ip} -U postgres -d ${source_db} -c "create PUBLICATION ${pub_name} FOR table ${tables_name}" >/dev/null
	echo "本次发布如下表："${tables_name}
	echo "本次发布如下表："${tables_name} >>$log
	echo "正在删除${target_db}库表...."
	echo `date`"正在删除${target_db}库表...." >>$log
	for value in `echo ${tables_name}|sed "s/,/\\n/g"`;
	do
		continue
		#获取需同步表结构
		/usr/local/pgsql/bin/pg_dump -h ${source_ip} -U postgres -d ${source_db} -t "${value}" -s >> table_s.sql 
		#删除目标域表
		/usr/local/pgsql/bin/psql -U postgres -h ${target_ip} -d ${target_db} -c "drop table ${value} CASCADE;" >/dev/null 2>/dev/null
	done
	#创建目标域表
	echo "正在同步表结构...."
	echo `date`"正在同步表结构...." >>$log
	/usr/local/pgsql/bin/psql -U postgres -h ${target_ip} -d ${target_db} -f table_s.sql >/dev/null 2>/dev/null
	rm -rf table_s.sql
	#更改表权限
	echo "正在更改表权限...."
	echo `date`"正在更改表权限...." >>$log
	if [ "${target_db}" = "updb" ];then
		owner="updb"
	elif [ "${target_db}" = "mobile" ];then
		owner="mobile"
	else
		owner="zlchs"
	fi
	for value in `echo ${tables_name}|sed "s/,/\\n/g"`;
	do
		continue
		/usr/local/pgsql/bin/psql -U postgres -h ${target_ip} -d ${target_db} -c "alter table ${value} owner to ${owner};" >/dev/null
	done
	#目标域创建订阅
	sub_sql="CREATE SUBSCRIPTION ${sub_name} CONNECTION 'host=${source_ip} port=5432 dbname=${source_db} user=postgres password=admin..1121' PUBLICATION ${pub_name} with(create_slot=false,slot_name='${slot_name}');"
	echo "正在创建订阅...."
	echo `date`"正在创建订阅...." >>$log
	/usr/local/pgsql/bin/psql -U postgres -h ${target_ip} -d ${target_db} -c "${sub_sql}" >/dev/null
	echo "已创建${sub_name}订阅...."
	echo `date`"已创建${sub_name}订阅...." >>$log
	echo "##################################################"
	echo "##################################################" >>$log
	echo ""
	echo ""
	echo "" >>$log
	echo "" >>$log
done < db_info.txt
rm -rf db_info.txt