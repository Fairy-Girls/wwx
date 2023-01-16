#!/bin/bash
#版本号
version=wwxznb
#上一个版本号
a_version=wwxzds
#前端更新域
#ui=(center drug emr fee inpdoctor inpnurse lab matl mr outpatient pacs patient payment paymentH5 treat up weboutp vms weixin)	#
#集群
website=(drug emr eqp fee inp lab mr matl pacs patient treat weboutp)
#其他服务
others=(zlchs.up zlchs.center zlsoft.up.logger zlsoft.message zlchs.up.signalr zlchs.ts zlchs.payment zlchs.weixin zlchs.aer zlchs.quartz)
#数据库更新域
#sql=(drug emr fee inp lab outpatient pacs patient treat updb mr matl mobile)	#
#服务器信息文件
file_path=/usr/adressIP.txt
#存储升级文件及备份文件路径
bk_url=/usr/upgrade
#日志文件
log=${bk_url}/${version}/upgrade.log
#数据库升级日志
dblog=${bk_url}/${version}/db.log
#升级包路径
pt_url=/usr/patch
#redis密码
Redis_pwd=123456
#判断服务器信息文件是否存在
if [ ! -f "${file_path}" ]; then
	echo "未找到服务器信息文件,请检查后重试（${file_path}:文件不存在）"
	exit
fi
#判断是否存在备份文件夹
if [ ! -d "${bk_url}" ];then
	mkdir ${bk_url}
fi

#获取所有服务器地址
get_ips(){
source ${file_path}
echo ${updb} >>/usr/ip.txt
echo ${drugdb} >>/usr/ip.txt
echo ${emrdb} >>/usr/ip.txt
echo ${inpdb} >>/usr/ip.txt
echo ${labdb} >>/usr/ip.txt
echo ${matldb} >>/usr/ip.txt
echo ${mrdb} >>/usr/ip.txt
echo ${pacsdb} >>/usr/ip.txt
echo ${patientdb} >>/usr/ip.txt
echo ${outpatientdb} >>/usr/ip.txt
echo ${treatdb} >>/usr/ip.txt
echo ${loggerdb} >>/usr/ip.txt
sort -k2n /usr/ip.txt|uniq >/usr/db_ips.txt
#数据库服务器IP
db_ips=(`cat /usr/db_ips.txt |xargs echo`)	
for value in ${IPs_website[@]};do echo ${value} >>/usr/ip.txt;done
echo ${IPs_other} >>/usr/ip.txt
echo ${IPs_middleware} >>/usr/ip.txt
echo ${IP_reportpush} >>/usr/ip.txt
echo ${IP_minio} >>/usr/ip.txt
echo ${IPs_ui} >>/usr/ip.txt
sort -k2n /usr/ip.txt|uniq >/usr/ips.txt
#所有服务器IP
ips=(`cat /usr/ips.txt |xargs echo`)	
rm -rf /usr/ip.txt /usr/db_ips.txt /usr/ips.txt
}
#获取配置信息
get_ips
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
	#
}
#版本号比较函数
function version_gt() { test "$(echo "$@" | tr " " "\n" | sort -V | head -n 1)" != "$1"; }	#小于
function version_le() { test "$(echo "$@" | tr " " "\n" | sort -V | head -n 1)" == "$1"; }	#小于等于
function version_lt() { test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" != "$1"; }	#大于
function version_ge() { test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" == "$1"; } #大于等于
#获取当前版本号
v_sql="SELECT version_number FROM sys_version;"
ssh -Tq -p ${ssh_port} root@$updb "/usr/local/pgsql/bin/psql -d updb -U updb -c 'SELECT version_number FROM sys_version;'" >version.txt 2>&1
clear version.txt
n_version=`sed 's/^[ \t]*//g' version.txt`
rm -f version.txt
#判断当前版本与升级版本
if [ "$n_version" != "$a_version" ];then
	echo "当前系统版本为【${n_version}】，本升级包基于版本【${a_version}】，请检查版本后升级，已退出"
	exit
fi
#判断当前升级包是否已执行
if [ ! -d "${bk_url}/${version}" ];then
	mkdir ${bk_url}/${version} ${bk_url}/${version}/backup
else
	echo "已存在【$version】升级记录，请勿重复执行（${bk_url}/${version}：文件夹已存在）"
	exit
fi
if [ "${PRODUCT}" = "yhis" ];then
	system="基层医疗卫生机构综合系统"
elif [ "${PRODUCT}" = "fy" ];then
	system="飞跃医院信息系统"
else
	system=""
	echo "未获取到系统参数{PRODUCT},请及时检查"
fi
echo "当前系统为【${system} ${n_version}】"
sleep 1
date=`date`
echo "当前系统时间为【${date}】"
sleep 1
echo "本次升级由【${n_version}】====>【${version}】，升级过程中请勿中断"
sleep 1
read -p "是否备份?(y/n):" answer
if [ $answer = "N" -o $answer = "n" ];then
	a=0
else
	a=1
fi
if [ $a -eq 1 ];then
echo "正在备份，请稍后...."
find /usr/upgrade/ -name 'backup' -mtime +30 -exec rm -rf "{}" \; -prune
#前端备份
echo 【前端备份 版本：${version} `date`】>>$log
mkdir ${bk_url}/${version}/backup/ui
for value in `ls ${pt_url}/ui/`;
do
	if [ -d "${pt_url}/ui/${value}" ];then
		echo "正在备份${value}...."
		scp -r -P $ssh_port root@$IP_ui:/usr/source/ui/${value} ${bk_url}/${version}/backup/ui/ >/dev/null 2>>$log
		echo `date`"   ${value}备份完成" >>$log
	fi
done
#后端备份
echo "" >>$log
echo 【后端备份 版本：${version} `date`】>>$log
mkdir ${bk_url}/${version}/backup/website
for value in `ls ${pt_url}/website/`;
do
if [ -d "${pt_url}/website/${value}" ];then
	echo "正在备份${value}...."
	#UP
	if [ ${value} = "zlchs.up" ];then		#平台
		mkdir -p ${bk_url}/${version}/backup/website/${value}/Orleans-Server
		scp -r -P $ssh_port root@${IPs_website[0]}:/usr/source/website/${value}/Orleans-Server/Services ${bk_url}/${version}/backup/website/${value}/Orleans-Server >/dev/null 2>>$log
		scp -r -P $ssh_port root@$IP_other:/usr/source/website/${value}/WebApi-Server ${bk_url}/${version}/backup/website/${value}/ >/dev/null 2>>$log
	#center-webapi
	elif [ ${value} = "zlchs.center" ];then
		mkdir -p ${bk_url}/${version}/backup/website/${value}/WebApi-Server
		scp -r -P $ssh_port root@$IP_other:/usr/source/website/${value}/WebApi-Server/*.* ${bk_url}/${version}/backup/website/${value}/WebApi-Server/ >/dev/null 2>>$log
	#（消费、日志、signalr、ts、payment、up-webapi、center-webapi、aer、quartz）
	elif [ ${value} = "zlsoft.message" ] || [ ${value} = "zlsoft.up.logger" ] || [ ${value} = "zlchs.up.signalr" ] || [ ${value} = "zlchs.ts" ] || [ ${value} = "zlchs.payment" ] || [ ${value} = "zlchs.center" ] || [ ${value} = "zlchs.payment" ] || [ ${value} = "zlchs.aer" ] || [ ${value} = "zlchs.quartz" ];then
		mkdir  ${bk_url}/${version}/backup/website/${value}
		scp -r -P $ssh_port root@$IP_other:/usr/source/website/${value}/*.* ${bk_url}/${version}/backup/website/${value}/ >/dev/null 2>>$log
	#网关
	elif [ ${value} = "zlchs.gateway" ];then	
		mkdir  ${bk_url}/${version}/backup/website/${value}
		scp -r -P $ssh_port root@$IP_ui:/usr/source/website/${value} ${bk_url}/${version}/backup/website/ >/dev/null 2>>$log
	#报表服务
	elif [ ${value} = "zlchs.reportpush" ];then 	
		mkdir  ${bk_url}/${version}/backup/website/${value}
		scp -r -P $ssh_port root@$IP_reportpush:/usr/source/website/${value} ${bk_url}/${version}/backup/website/ >/dev/null 2>>$log
	#WebApi集群
	else
		mkdir -p ${bk_url}/${version}/backup/website/${value}/WebApi-Server
		scp -r -P $ssh_port root@$IPs_website:/usr/source/website/${value}/WebApi-Server/*.* ${bk_url}/${version}/backup/website/${value}/WebApi-Server/ >/dev/null 2>>$log
	fi
	echo `date`"   ${value}备份完成" >>$log
fi
done
echo "备份完成！"
else 
	echo "本次升级不备份"
	echo "本次升级不备份" >>$log
fi
sleep 2
#数据库升级
echo "正在升级数据库，请稍后...."
echo "" >>$log
echo 【数据库升级 版本：${version} `date`】>>$log
#重启数据库
for value in ${db_ips[@]};
do
	ssh -Tq -p ${ssh_port} root@${value} "runuser -l postgres -c '/usr/local/pgsql/bin/pg_ctl restart' >/dev/null 2>&1" >/dev/null 2>>$log
done
ssh -Tq -p ${ssh_port} root@$loggerdb "if [ ! -d '/usr/local/src/sql/${version}' ];then mkdir /usr/local/src/sql/${version};fi;"
scp -r -P $ssh_port ${pt_url}/sql/* root@$loggerdb:/usr/local/src/sql/${version}/ >/dev/null 2>>$log
ssh -Tq -p ${ssh_port} root@${loggerdb} <<remotessh 1>>$dblog 2>>$log
	if [ -f "/usr/local/src/sql/${version}/drug.sql" ];then
		export PGPASSWORD=zlsoft;/usr/local/pgsql/bin/psql -h ${drugdb} -U zlchs -p 5432 -d drug -f /usr/local/src/sql/${version}/drug.sql
		echo "Drug数据库升级完成！" >&2
	fi
	if [ -f "/usr/local/src/sql/${version}/emr.sql" ];then
		export PGPASSWORD=zlsoft;/usr/local/pgsql/bin/psql -h ${emrdb} -U zlchs -p 5432 -d emr -f /usr/local/src/sql/${version}/emr.sql
		echo "Emr数据库升级完成！" >&2
	fi
	if [ -f "/usr/local/src/sql/${version}/fee.sql" ];then
		export PGPASSWORD=zlsoft;/usr/local/pgsql/bin/psql -h ${drugdb} -U zlchs -p 5432 -d fee -f /usr/local/src/sql/${version}/fee.sql
		echo "Fee数据库升级完成！" >&2
	fi
	if [ -f "/usr/local/src/sql/${version}/inp.sql" ];then
		export PGPASSWORD=zlsoft;/usr/local/pgsql/bin/psql -h ${inpdb} -U zlchs -p 5432 -d inp -f /usr/local/src/sql/${version}/inp.sql
		echo "Inp数据库升级完成！" >&2
	fi
	if [ -f "/usr/local/src/sql/${version}/lab.sql" ];then
		export PGPASSWORD=zlsoft;/usr/local/pgsql/bin/psql -h ${labdb} -U zlchs -p 5432 -d lab -f /usr/local/src/sql/${version}/lab.sql
		echo "Lab数据库升级完成！" >&2
	fi
	if [ -f "/usr/local/src/sql/${version}/logger.sql" ];then
		/usr/local/pgsql/bin/psql -U logger -p 5432 -d logger -f /usr/local/src/sql/${version}/logger.sql
		echo "Logger数据库升级完成！" >&2
	fi
	if [ -f "/usr/local/src/sql/${version}/matl.sql" ];then
		export PGPASSWORD=zlsoft;/usr/local/pgsql/bin/psql -h ${matldb} -U zlchs -p 5432 -d matl -f /usr/local/src/sql/${version}/matl.sql
		echo "Matl数据库升级完成！" >&2
	fi
	if [ -f "/usr/local/src/sql/${version}/mr.sql" ];then
		export PGPASSWORD=zlsoft;/usr/local/pgsql/bin/psql -h ${mrdb} -U zlchs -p 5432 -d mr -f /usr/local/src/sql/${version}/mr.sql
		echo "Mr数据库升级完成！" >&2
	fi
	if [ -f "/usr/local/src/sql/${version}/outpatient.sql" ];then
		export PGPASSWORD=zlsoft;/usr/local/pgsql/bin/psql -h ${outpatientdb} -U zlchs -p 5432 -d outpatient -f /usr/local/src/sql/${version}/outpatient.sql
		echo "Outpatient数据库升级完成！" >&2
	fi
	if [ -f "/usr/local/src/sql/${version}/pacs.sql" ];then
		export PGPASSWORD=zlsoft;/usr/local/pgsql/bin/psql -h ${pacsdb} -U zlchs -p 5432 -d pacs -f /usr/local/src/sql/${version}/pacs.sql
		echo "Pacs数据库升级完成！" >&2
	fi
	if [ -f "/usr/local/src/sql/${version}/patient.sql" ];then
		export PGPASSWORD=zlsoft;/usr/local/pgsql/bin/psql -h ${patientdb} -U zlchs -p 5432 -d patient -f /usr/local/src/sql/${version}/patient.sql
		echo "Patient数据库升级完成！" >&2
	fi
	if [ -f "/usr/local/src/sql/${version}/treat.sql" ];then
		export PGPASSWORD=zlsoft;/usr/local/pgsql/bin/psql -h ${treatdb} -U zlchs -p 5432 -d treat -f /usr/local/src/sql/${version}/treat.sql
		echo "Treat数据库升级完成！" >&2
	fi
	if [ -f "/usr/local/src/sql/${version}/updb.sql" ];then
		export PGPASSWORD=updb;/usr/local/pgsql/bin/psql -h ${updb} -U updb -p 5432 -d updb -f /usr/local/src/sql/${version}/updb.sql
		echo "UPDB数据库升级完成！" >&2
	fi
	if [ -f "/usr/local/src/sql/${version}/mobile.sql" ];then
		export PGPASSWORD=mobile;/usr/local/pgsql/bin/psql -h ${updb} -U mobile -p 5432 -d mobile -f /usr/local/src/sql/${version}/mobile.sql
		echo "Mobile数据库升级完成！" >&2
	fi
	if [ -f "/usr/local/src/sql/${version}/yhis.sql" ];then
		export PGPASSWORD=zlsoft;/usr/local/pgsql/bin/psql -h ${updb} -U zlchs -p 5432 -d yhis -f /usr/local/src/sql/${version}/yhis.sql
		echo "Yhis数据库升级完成！" >&2
	fi
	if [ -f "/usr/local/src/sql/${version}/eqp.sql" ];then
		export PGPASSWORD=zlsoft;/usr/local/pgsql/bin/psql -h ${matldb} -U zlchs -p 5432 -d eqp -f /usr/local/src/sql/${version}/eqp.sql
		echo "EQP数据库升级完成！" >&2
	fi
remotessh
#清理redis缓存
ssh -Tq -p ${ssh_port} root@${IP_middleware} "docker exec redis redis-cli -a '${Redis_pwd}' -n 3 flushdb;docker exec redis redis-cli -a '${Redis_pwd}' -n 1 flushdb;" >/dev/null 2>/dev/null
echo `date`"   数据库升级完成" >>$log
#后端升级
###########################################################

###########################################################
echo "正在升级后端服务，请稍后...."
sleep 5
echo "" >>$log
echo 【后端升级 版本：${version} `date`】>>$log
#集群
for value in ${IPs_website[@]};
do
	#Orleans集群
	echo "正在更新【${value}】集群...."
	echo `date`"   正在更新【${value}】集群...." >>$log
	if [ -d "${pt_url}/website/zlchs.up/Orleans-Server" ];then
		echo "正在更新Orleans...."
		echo `date`"   Orleans正在更新...." >>$log
		scp -r -P $ssh_port ${pt_url}/website/zlchs.up/Orleans-Server root@$value:/usr/source/website/zlchs.up/ >/dev/null 2>>$log
		ssh -Tq -p ${ssh_port} root@$value "docker exec website systemctl restart zlchs.up.orleans.service" >/dev/null 2>&1
		echo `date`"   Orleans更新完成" >>$log
	fi
	#WebApi集群
	for server in ${website[@]};
	do
		if [ -d "${pt_url}/website/zlchs.${server}" ];then
			echo "${server}服务正在更新...."
			echo `date`"   ${server}服务正在更新...." >>$log
			scp -r -P $ssh_port ${pt_url}/website/zlchs.${server} root@$value:/usr/source/website/ >/dev/null 2>>$log
			ssh -Tq -p ${ssh_port} root@$value "docker exec website systemctl restart zlchs.${server}.webapi.service" >/dev/null 2>&1
			echo `date`"   ${server}服务更新完成" >>$log
		fi
	done
	echo "【${value}】集群更新完成！"
done
#其他服务
#UP-WebAPi
if [ -d "${pt_url}/website/zlchs.up/WebApi-Server" ];then
	echo "正在更新UP-WebApi服务...."
	echo `date`"   UP-WebApi服务正在更新....">>$log
	scp -r -P $ssh_port ${pt_url}/website/zlchs.up/WebApi-Server root@$IP_other:/usr/source/website/zlchs.up/ >/dev/null 2>>$log
	ssh -Tq -p ${ssh_port} root@$IP_other "docker exec website systemctl restart zlchs.up.webapi.service"  >/dev/null 2>&1
	echo `date`"   UP-WebApi服务更新完成"  >>$log
fi
#日志
if [ -d "${pt_url}/website/zlsoft.up.logger" ];then
	echo "正在更新日志服务...."
	echo `date`"   Logger服务正在更新....">>$log
	scp -r -P $ssh_port ${pt_url}/website/zlsoft.up.logger root@$IP_other:/usr/source/website/ >/dev/null 2>>$log
	ssh -Tq -p ${ssh_port} root@$IP_other "docker exec website systemctl restart zlchs.logger.service" >/dev/null 2>&1
	echo `date`"   Logger服务更新完成"  >>$log
fi
#消费
if [ -d "${pt_url}/website/zlsoft.message" ];then
	echo "正在更新消息队列服务...."
	echo `date`"   Message服务正在更新....">>$log
	ssh -Tq -p ${ssh_port} root@$IP_other "docker exec website systemctl stop zlchs.message.service"  >/dev/null 2>&1
	scp -r -P $ssh_port ${pt_url}/website/zlsoft.message root@$IP_other:/usr/source/website/ >/dev/null 2>>$log
	ssh -Tq -p ${ssh_port} root@$IP_other "docker exec website systemctl restart zlchs.message.service"  >/dev/null 2>&1
	echo `date`"   Message服务更新完成"  >>$log
fi
#Signalr
if [ -d "${pt_url}/website/zlchs.up.signalr" ];then
	echo "正在更新Signalr服务...."
	echo `date`"   Signalr服务正在更新....">>$log
	scp -r -P $ssh_port ${pt_url}/website/zlchs.up.signalr root@$IP_other:/usr/source/website/ >/dev/null 2>>$log
	ssh -Tq -p ${ssh_port} root@$IP_other "docker exec website systemctl restart zlchs.up.signalr.service"  >/dev/null 2>&1
	echo `date`"   Signalr服务更新完成"  >>$log
fi
#三方
if [ -d "${pt_url}/website/zlchs.ts" ];then
	echo "正在更新三方服务...."
	echo `date`"   TS服务正在更新....">>$log
	scp -r -P $ssh_port ${pt_url}/website/zlchs.ts root@$IP_other:/usr/source/website/ >/dev/null 2>>$log
	ssh -Tq -p ${ssh_port} root@$IP_other "docker exec website systemctl restart zlchs.ts.service"  >/dev/null 2>&1
	echo `date`"   TS服务更新完成"  >>$log
fi
#移动支付
if [ -d "${pt_url}/website/zlchs.payment" ];then
	echo "正在更新移动支付服务...."
	echo `date`"   Payment服务正在更新....">>$log
	scp -r -P $ssh_port ${pt_url}/website/zlchs.payment root@$IP_other:/usr/source/website/ >/dev/null 2>>$log
	ssh -Tq -p ${ssh_port} root@$IP_other "docker exec website systemctl restart zlchs.payment.service"  >/dev/null 2>&1
	echo `date`"   Payment服务更新完成"  >>$log
fi
#Center
if [ -d "${pt_url}/website/zlchs.center" ];then
	echo "正在更新公共服务...."
	echo `date`"   Center服务正在更新....">>$log
	scp -r -P $ssh_port ${pt_url}/website/zlchs.center root@$IP_other:/usr/source/website/ >/dev/null 2>>$log
	ssh -Tq -p ${ssh_port} root@$IP_other "docker exec website systemctl restart zlchs.center.webapi.service"  >/dev/null 2>&1
	echo `date`"   Center服务更新完成"  >>$log
fi
#公众号
if [ -d "${pt_url}/website/zlchs.weixin" ];then
	echo "正在更新公众号服务...."
	echo `date`"   WeiXin服务正在更新....">>$log
	scp -r -P $ssh_port ${pt_url}/website/zlchs.weixin root@$IP_other:/usr/source/website/ >/dev/null 2>>$log
	ssh -Tq -p ${ssh_port} root@$IP_other "docker exec website systemctl restart zlchs.weixin.orleans.service;docker exec website systemctl restart zlchs.weixin.webapi.service;"  >/dev/null 2>&1
	echo `date`"   WeiXin服务更新完成"  >>$log
fi
#报表
if [ -d "${pt_url}/website/zlchs.reportpush" ];then
	echo "正在更新报表服务...."
	echo `date`"   ReportPush服务正在更新....">>$log
	scp -r -P $ssh_port ${pt_url}/website/zlchs.reportpush root@$IP_reportpush:/usr/source/website/ 1>/dev/null 2>>$log
	ssh -Tq -p ${ssh_port} root@$IP_reportpush "docker exec website systemctl restart zlchs.reportpush.service"  >/dev/null 2>&1
	echo `date`"   ReportPush服务更新完成"  >>$log
fi
#网关
if [ -d "${pt_url}/website/zlchs.gateway" ];then
	echo "正在更新网关服务...."
	echo `date`"   Gateway服务正在更新....">>$log
	scp -r -P $ssh_port ${pt_url}/website/zlchs.gateway root@$IP_ui:/usr/source/website/ >/dev/null 2>>$log
	ssh -Tq -p ${ssh_port} root@$IP_ui "docker exec website systemctl restart zlchs.gateway.service"  >/dev/null 2>&1
	echo `date`"   Gateway服务更新完成"  >>$log
fi
#不良事件上报
if [ -d "${pt_url}/website/zlchs.aer" ];then
	echo "正在更新不良事件上报服务...."
	echo `date`"   Aer服务正在更新....">>$log
	scp -r -P $ssh_port ${pt_url}/website/zlchs.aer root@$IP_other:/usr/source/website/ >/dev/null 2>>$log
	ssh -Tq -p ${ssh_port} root@$IP_other "docker exec website systemctl restart zlchs.aer.service"  >/dev/null 2>&1
	echo `date`"   Aer服务更新完成"  >>$log
fi
#定时任务
if [ -d "${pt_url}/website/zlchs.quartz" ];then
	echo "正在更新定时任务服务...."
	echo `date`"   Quartz服务正在更新....">>$log
	scp -r -P $ssh_port ${pt_url}/website/zlchs.quartz root@$IP_other:/usr/source/website/ >/dev/null 2>>$log
	ssh -Tq -p ${ssh_port} root@$IP_other "docker exec website systemctl restart zlchs.quartz.service"  >/dev/null 2>&1
	echo `date`"   Quartz服务更新完成"  >>$log
fi
#重启消息队列服务
ssh -Tq -p ${ssh_port} root@$IP_other "docker exec website systemctl restart zlchs.message.service" >/dev/null 2>&1
#前端升级
echo "正在更新前端服务...."
echo "" >>$log
echo 【前端升级 版本：${version} `date`】>>$log
echo `date`"   正在更新前端服务...." >>$log
if [ -d "${pt_url}/ui/zlchs.weixin.ui" ];then
	scp -r -P $ssh_port root@$IP_ui:/usr/source/ui/zlchs.weixin.ui/admin-ui/appSettings.js ${pt_url}/ui/zlchs.weixin.ui/admin-ui/ >/dev/null 2>>$log
	ssh -Tq -p ${ssh_port} root@$IP_ui "rm -rf /usr/source/ui/zlchs.weixin.ui/" >/dev/null 2>>$log
fi
if [ -d "${pt_url}/ui/zlchs.payment.ui" ];then
	scp -r -P $ssh_port root@$IP_ui:/usr/source/ui/zlchs.payment.ui/appSettings.js ${pt_url}/ui/zlchs.payment.ui/ >/dev/null 2>>$log
	ssh -Tq -p ${ssh_port} root@$IP_ui "rm -rf /usr/source/ui/zlchs.payment.ui/" >/dev/null 2>>$log
fi
if [ -d "${pt_url}/ui/zlchs.paymentH5.ui" ];then
	scp -r -P $ssh_port root@$IP_ui:/usr/source/ui/zlchs.paymentH5.ui/js/appSettings.js ${pt_url}/ui/zlchs.paymentH5.ui/js/ >/dev/null 2>>$log
	ssh -Tq -p ${ssh_port} root@$IP_ui "rm -rf /usr/source/ui/zlchs.paymentH5.ui/" >/dev/null 2>>$log
fi
if [ -d "${pt_url}/ui/zlchs.emrbrowser.ui" ];then
	ssh -Tq -p ${ssh_port} root@$IP_ui "rm -rf /usr/source/ui/zlchs.emrbrowser.ui/" >/dev/null 2>>$log
fi
scp -r -P $ssh_port ${pt_url}/ui root@$IP_ui:/usr/source/ >/dev/null 2>>$log
echo `date`"   前端服务更新完成" >>$log
#修改版本号
v_sql="UPDATE public.sys_version SET version_number = '$version' WHERE id = '16718c46fdc8b942';"
ssh -Tq -p ${ssh_port} root@$updb <<remotessh >/dev/null 2>&1
/usr/local/pgsql/bin/psql -d updb -U updb -c "$v_sql" >/dev/null
remotessh
###########################################################################
echo "正在整合资源...."
echo "正在整合资源...." >>$log
###########################################################################
echo "升级完成!当前版本为【${version}】" >>$log
sed -i '/Authorized users only/d' $log
sed -i '/Authorized users only/d' $dblog
sed -i '/^$/d' $log
sed -i '/^$/d' $dblog
echo "升级完成!当前版本为【${version}】"
echo "提示1：升级日志文件路径：/usr/upgrade/${version}/upgrade.log，请查看日志,如有问题请及时反馈。"
echo "提示2：根据项目需求，对问题清单中的问题按需测试，有问题请及时反馈。"
rm -rf /usr/patch
