#!/bin/bash

re="\033[0m"
red="\033[1;91m"
green="\e[1;32m"
yellow="\e[1;33m"
purple="\e[1;35m"
red() { echo -e "\e[1;91m$1\033[0m"; }
green() { echo -e "\e[1;32m$1\033[0m"; }
yellow() { echo -e "\e[1;33m$1\033[0m"; }
purple() { echo -e "\e[1;35m$1\033[0m"; }
reading() { read -p "$(red "$1")" "$2"; }
export LC_ALL=C
HOSTNAME=$(hostname)
NAME=$(echo $HOSTNAME | cut -d '.' -f 1)
IP=$(curl -fs ip.sb)
PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 8)
REMARK=$(openssl rand -hex 10 | tr -dc '0-9' | head -c 5)
UUID=$(uuidgen)
hostname_number=$(hostname | sed 's/^s\([0-9]*\)\..*/\1/')
mkdir -p /home/$USER/web
pkill pyy.py
cat << EOF > /home/$USER/1.sh
#!/bin/bash
echo "ok"
EOF
chmod +x /home/$USER/1.sh

if /home/$USER/1.sh; then
  echo "程序权限已开启"
else
  devil binexec on
  echo "首次运行，需要重新登录SSH，输入exit 退出ssh"
  echo "重新登陆SSH后，再执行一次脚本便可"
  exit 0
fi

cd /home/$USER/web

rm -rf /home/$USER/web/*
sleep 1

# 删除所有已开放UDP端口
devil port list | awk 'NR>1 && $1 ~ /^[0-9]+$/ { print $1, $2 }' | while read -r port type; do
    if [[ "$type" == "udp" ]]; then
        echo "删除 UDP 端口: $port"
        devil port del udp "$port"
    fi
done

# 添加1 个 UDP 端口

devil port add udp random

# 等待端口生效（如果 devil 有延迟）
sleep 2

udp_ports=($(devil port list | awk 'NR>1 && $2 == "udp" { print $1 }'))

if [[ ${#udp_ports[@]} -ge 1 ]]; then
    hy2=${udp_ports[0]}
    echo "hy2=$hy2"
else
    echo "未找到 UDP 端口，无法赋值 hy2"
    exit 1
fi



cd /home/$USER/web

wget https://download.hysteria.network/app/latest/hysteria-freebsd-amd64
mv hysteria-freebsd-amd64 pyy.py
chmod +x pyy.py
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout web.key -out web.crt -subj "/CN=bing.com" -days 36500

cat << EOF > /home/$USER/web/web.yaml
listen: :$hy2

tls:
  cert: /home/$USER/web/web.crt
  key: /home/$USER/web/web.key

auth:
  type: password
  password: $PASSWORD
  
masquerade:
  type: proxy
  proxy:
    url: https://bing.com
    rewriteHost: true
EOF




cat << EOF > /home/$USER/web/updateweb.sh

#!/bin/bash
if ps -aux | grep -v grep | grep -q "pyy.py"; then
	cd /home/$USER/web

    exit 0
else
                cd /home/$USER/web
                nohup ./pyy.py server -c web.yaml > /dev/null 2>&1 &


fi
EOF
chmod +x updateweb.sh
./updateweb.sh
cron_job="*/39 * * * * /home/$USER/web/updateweb.sh"
# 检查任务是否已存在
if crontab -l | grep -q "updateweb.sh"; then
    echo "保活任务已存在，跳过添加。"
else
    (crontab -l ; echo "$cron_job") | crontab -
    echo "保活任务已添加到 crontab。"
fi
red "复制当前HY2节点信息"
red "hysteria2://$PASSWORD@s$hostname_number.ct8.pl:$hy2/?sni=www.bing.com&alpn=h3&insecure=1#$NAME@$USER-hy2-北极之光"
red ""

