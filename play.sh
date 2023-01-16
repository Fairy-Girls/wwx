#!/bin/bash
#提取更新文件并打包，2022/03/29，wwx
#/*1、过滤restartService.sh文件
#  2、打包时，修改数据库版本的状态
#  3、添加电子病历浏览器打包模块 202301041426*/
#if [ $# = 0 ];then
#	read -p "请输入版本号（如：V4.0.2）:" version
#elif [ $# = 1 ];then
#	version=$1
#else
#	echo "参数输入错误，已退出"
#	exit
#fi
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
#版本号
day=$(echo `date +%m%d`) 	#当前日期
#判断是否存在已打包的版本
export PGPASSWORD=updb;/usr/local/pgsql/bin/psql -h 192.168.31.156 -U updb -d Versions -c "select name from patches where id =(SELECT min(id) FROM patches where status='已打包' ) ;">pack_version.txt
clear pack_version.txt
p_version=`sed 's/^[ \t]*//g' pack_version.txt`	##删除空格
if [ -s pack_version.txt ];then
	echo "版本【${p_version}】状态为【已打包】，请将此发版后再打包！"
	rm -rf pack_version.txt
	exit
else
	rm -rf pack_version.txt
fi
#查询数据库未发版版本，获取未发版最小ID的版本号
export PGPASSWORD=updb;/usr/local/pgsql/bin/psql -h 192.168.31.156 -U updb -d Versions -c "select name from patches where id =(SELECT min(id) FROM patches where status='未打包' ) ;">version.txt
clear version.txt
export PGPASSWORD=updb;/usr/local/pgsql/bin/psql -h 192.168.31.156 -U updb -d Versions -c "select name from patches where id =(SELECT max(id) FROM patches where status='已发版' )">ageversion.txt
clear ageversion.txt
#上次版本号
a_version=`sed 's/^[ \t]*//g' ageversion.txt`	##删除空格
#当前版本号
version=`sed 's/^[ \t]*//g' version.txt`	##删除空格
rm -f version.txt
echo "本次打包版本为：【${version}】"
#version=V4.0.2.0323
#数据库版本号
versions=$(echo "'${version}'")		#如果数据库获取多个版本:$(echo "'V4.0.2.0322','V4.0.2.0321'")
#上次打包时间，获取已发版最大ID的版本发版时间
#BDATE=$(echo `ls --full-time /etc/time.txt |awk '{print $6 " " $7}' |cut -d '.' -f 1`)	#格式：2022-02-26 00:00:00
export PGPASSWORD=updb;/usr/local/pgsql/bin/psql -h 192.168.31.156 -U updb -d Versions -c "select pack_time from patches where id =(SELECT max(id) FROM patches where status='已发版' )">agetime.txt
clear agetime.txt
BDATE=`sed 's/^[ \t]*//g' agetime.txt`
rm -f agetime.txt
echo "上次打包时间为：【$BDATE】"
#当前时间
ADATE=$(echo `date +%Y-%m-%d` `date +%H:%M:%S`)	#格式：2022-02-26 00:00:00
echo "本次打包时间为：【$ADATE】"
echo "正在打包，请稍后...."
#打包路径
purl=/usr/update/$version
#查询数据库是否存在当前版本
export PGPASSWORD=updb;/usr/local/pgsql/bin/psql -h 192.168.31.156 -U updb -d Versions -c "select count(id) from patches where name in (${versions});">num.txt
clear num.txt
num=`cat num.txt`
if [ ${num} = 0 ];then
	echo "提示:数据库不存在版本【${version}】,请检查后再试"
	exit
fi
#判断是否存在当前版本文件夹
if [ ! -d "${purl}/" ];then
	mkdir ${purl}
else
	echo "【${purl}】已存在"
	exit
fi
#修改数据库版本的状态
export PGPASSWORD=updb;/usr/local/pgsql/bin/psql -h 192.168.31.156 -U updb -d Versions -c "UPDATE patches SET  status = '已打包',pack_time = '${ADATE}' WHERE name in (${versions});">/dev/null
#时间重置
>/etc/time.txt
#获取此次后端更新文件路径
find /usr/source/website ! -path '*log-data*' ! -path '*.pdf' ! -path '*cpapi*' ! -path '*restartService.sh' -newerct "${BDATE}" ! -newerct "${ADATE}" -type f -print >newfile.txt	#后端文件找到B-->A日期之间的文件，排除日志文件,排除插件文件，排除支付
#遍历文件，获取目录
while read line;do
	#获取文件目录
	dirname $line >mkdir.txt
	#获取文件名
	filename=`basename "$line"`
	if [ "$filename" = "appsettings.json" -o "$filename" = "app.json" -o "$filename" = "database.config" -o "$filename" = "licenses.txt" -o "$filename" = "OrleansServer.json" ];then
		a=`stat $line|grep 最近改动`
		echo $line"，"$a
	else
		sed -i "s@/usr/source@${purl}@" mkdir.txt
		url=(`cat mkdir.txt`)
		#是否存在打包文件路径，不存在则创建
		if [ ! -d "${url}/" ];then
			mkdir -p ${url}
		fi
		#复制文件
		cp -a "${line}" ${url}
	fi
done <newfile.txt
#获取此次前端更新文件路径
find /usr/source/ui ! -path '*.log' -newerct "${BDATE}" ! -newerct "${ADATE}" -type f -print >newfile.txt	#前端文件找到B-->A日期之间的文件
#遍历文件，获取目录
while read line;do
	#获取文件目录
	dirname "$line" >mkdir.txt
	#获取文件名
	filename=`basename "$line"`
	#生成包路径
	sed -i "s@/usr/source@${purl}@" mkdir.txt
	url=(`cat mkdir.txt`)
	#是否存在打包文件路径，不存在则创建
	if [ ! -d "${url}/" ];then
		mkdir -p ${url}
	fi
	#复制文件
	cp -a "${line}" ${url}

done <newfile.txt

#生成sql文件夹
mkdir $purl/sql
#获取当前版本所有SQL文件
export PGPASSWORD=updb;/usr/local/pgsql/bin/psql -h 192.168.31.156 -U updb -d Versions -c "select id,sys_code from scripts where patch_id in (select id from patches where name in(${versions})) order by id;">a.txt
clear a.txt
while read line ;do
	id=`echo $line|awk '{print $1}'`		#sql 的id
	dbname=`echo $line|awk '{print $3}'`	#sql所属库
	#获取当前sql内容
	export PGPASSWORD=updb;/usr/local/pgsql/bin/psql -h 192.168.31.156 -U updb -d Versions -c "select script from scripts where id =${id};">b.txt
	clear b.txt
	#删除每行末尾+号
	sed -i 's/\+$/\ /g' b.txt
	cat b.txt >> ${purl}/sql/$dbname.sql
done < a.txt
rm -f mkdir.txt newfile.txt a.txt b.txt num.txt ageversion.txt
#添加升级脚本
cp -r /usr/update/upgrade.sh /usr/update/$version/
sed -i "s/wwxznb/$version/g" `grep wwxznb -rl /usr/update/${version}/upgrade.sh`
sed -i "s/wwxzds/$a_version/g" `grep wwxzds -rl /usr/update/${version}/upgrade.sh`
#修改前端更新域版本信息
#遍历升级包前端域，获取本次升级域
for file in `ls ${purl}/ui` 
do
	if [ ! -d "${purl}/ui/${file}/js/" ];then
		mkdir ${purl}/ui/${file}/js/
	fi
	cat > ${purl}/ui/${file}/js/site.version.js <<EOF
	const sitePack = {
    version: "${version}"
	}
EOF
	#修改当前服务器前端版本号
	#cp ${purl}/ui/${file}/js/site.version.js /usr/source/ui/${file}/js/
	a='$'
	if [ "${file}" = "zlchs.up.ui" ];then
		cp /usr/update/zlsoft.up.resource.js ${purl}/ui/${file}/js/
		sed -i "s/zsbbh/${version}/g" ${purl}/ui/${file}/js/zlsoft.up.resource.js
	fi
	if [ "${file}" = "zlchs.weixin.ui" ] || [ "${file}" = "zlchs.payment.ui" ] || [ "${file}" = "zlchs.paymentH5.ui" ] || [ "${file}" = "zlchs.emrbrowser.ui" ];then
		rm -rf ${purl}/ui/${file}/*
		cp -r /usr/source/ui/${file}/* ${purl}/ui/${file}/
		rm -rf ${purl}/ui/zlchs.weixin.ui/admin-ui/appSettings.js
		rm -rf ${purl}/ui/zlchs.paymentH5.ui/js/appSettings.js
		rm -rf ${purl}/ui/zlchs.payment.ui/appSettings.js
	fi
done
#添加报表模块
mkdir ${purl}/patch ${purl}/报表
mv ${purl}/sql ${purl}/patch/
mv ${purl}/ui ${purl}/patch/
mv ${purl}/website ${purl}/patch/
mv ${purl}/upgrade.sh ${purl}/patch/
if [ -d "/usr/source/minio/data/report/${version}" ];then
	cp /usr/source/minio/data/report/${version}/* ${purl}/报表
fi
