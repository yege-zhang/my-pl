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

# 生成随机文件名函数
generate_random_name() {
    local length=$((RANDOM % 4 + 1))  # 1到4个字母
    local name=""
    for ((i=0; i<length; i++)); do
        name+=$(printf "\\$(printf '%03o' $((RANDOM % 26 + 97)))")
    done
    echo "$name"
}

# 生成随机文件名
EXEC_NAME=$(generate_random_name)
CONFIG_NAME=$(generate_random_name)
SCRIPT_NAME=$(generate_random_name)
CERT_NAME=$(generate_random_name)
KEY_NAME=$(generate_random_name)
DIR_NAME=$(generate_random_name)
TEST_NAME=$(generate_random_name)

HOSTNAME=$(hostname)
NAME=$(echo $HOSTNAME | cut -d '.' -f 1)
IP=$(curl -fs ip.sb)
PASSWORD=$(uuidgen)
REMARK=$(openssl rand -hex 10 | tr -dc '0-9' | head -c 5)
UUID=$(uuidgen)
hostname_number=$(hostname | sed 's/^s\([0-9]*\)\..*/\1/')
mkdir -p /home/$USER/$DIR_NAME
pkill ${EXEC_NAME}.py
cat << EOF > /home/$USER/${TEST_NAME}.sh
#!/bin/bash
echo "ok"
EOF
chmod +x /home/$USER/${TEST_NAME}.sh
if /home/$USER/${TEST_NAME}.sh; then
  echo "程序权限已开启"
else
  devil binexec on
  echo "首次运行，需要重新登录SSH，输入exit 退出ssh"
  echo "重新登陆SSH后，再执行一次脚本便可"
  exit 0
fi
cd /home/$USER/$DIR_NAME
rm -rf /home/$USER/$DIR_NAME/*
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
sleep 2
udp_ports=($(devil port list | awk 'NR>1 && $2 == "udp" { print $1 }'))
if [[ ${#udp_ports[@]} -ge 1 ]]; then
    hy2=${udp_ports[0]}
    echo "hy2=$hy2"
else
    echo "未找到 UDP 端口，无法赋值 hy2"
    exit 1
fi
cd /home/$USER/$DIR_NAME
wget https://download.hysteria.network/app/latest/hysteria-freebsd-amd64
RANDOM_DATA=$(openssl rand -hex $((RANDOM % 1024 + 512)))
echo "# $RANDOM_DATA" >> hysteria-freebsd-amd64
mv hysteria-freebsd-amd64 ${EXEC_NAME}.py
chmod +x ${EXEC_NAME}.py
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout ${KEY_NAME}.key -out ${CERT_NAME}.crt -subj "/CN=bing.com" -days 36500
cat << EOF > /home/$USER/$DIR_NAME/${CONFIG_NAME}.yaml
listen: :$hy2
tls:
  cert: /home/$USER/$DIR_NAME/${CERT_NAME}.crt
  key: /home/$USER/$DIR_NAME/${KEY_NAME}.key
auth:
  type: password
  password: $PASSWORD
  
masquerade:
  type: proxy
  proxy:
    url: https://bing.com
    rewriteHost: true
EOF
cat << EOF > /home/$USER/$DIR_NAME/${SCRIPT_NAME}.sh
#!/bin/bash
if ps -aux | grep -v grep | grep -q "${EXEC_NAME}.py"; then
	cd /home/$USER/$DIR_NAME
    exit 0
else
                cd /home/$USER/$DIR_NAME
                nohup ./${EXEC_NAME}.py server -c ${CONFIG_NAME}.yaml > /dev/null 2>&1 &
fi
EOF
chmod +x ${SCRIPT_NAME}.sh
./${SCRIPT_NAME}.sh
CRON_INTERVAL=$((RANDOM % 30 + 30))
cron_job="*/$CRON_INTERVAL * * * * /home/$USER/$DIR_NAME/${SCRIPT_NAME}.sh"
if crontab -l | grep -q "${SCRIPT_NAME}.sh"; then
    echo "保活任务已存在，跳过添加。"
else
    (crontab -l ; echo "$cron_job") | crontab -
    echo "保活任务已添加到 crontab。"
fi
echo "Cron间隔: 每${CRON_INTERVAL}分钟检查一次"
rm -f /home/$USER/${TEST_NAME}.sh

red ""
red "请选择CT8或者Serv00的节点,复制粘贴到v2rayN中测试"
red ""
red "Ct8节点"
red "hysteria2://$PASSWORD@s$hostname_number.ct8.pl:$hy2/?sni=www.bing.com&alpn=h3&insecure=1#$NAME@$USER-hy2"
red ""
red "Serv00节点"
red "hysteria2://$PASSWORD@s$hostname_number.serv00.com:$hy2/?sni=www.bing.com&alpn=h3&insecure=1#$NAME@$USER-hy2--s$hostname_number.serv00.com"
red ""

# ================== Telegram 推送功能开始 ==================
read -p "请输入你的 Telegram Bot Token（可留空跳过）: " TELEGRAM_BOT_TOKEN
read -p "请输入你的 Telegram Chat ID（可留空跳过）: " TELEGRAM_CHAT_ID

if [[ -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]]; then
  NAME="${NAME:-defaultName}"
  TAG="$NAME@$USER-hy2"
  SUB_CT8="hysteria2://$PASSWORD@s$hostname_number.ct8.pl:$hy2/?sni=www.bing.com&alpn=h3&insecure=1#$TAG"
  SUB_SERV00="hysteria2://$PASSWORD@s$hostname_number.serv00.com:$hy2/?sni=www.bing.com&alpn=h3&insecure=1#$TAG--s$hostname_number.serv00.com"

  ENCODED_CT8=$(echo -n "$SUB_CT8" | base64 | tr -d '\n')
  ENCODED_SERV00=$(echo -n "$SUB_SERV00" | base64 | tr -d '\n')

  curl -s -o /dev/null -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=HY2 部署成功 ✅"

  sleep 0.5

  curl -s -o /dev/null -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=CT8 节点：$ENCODED_CT8"

  sleep 0.5

  curl -s -o /dev/null -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=Serv00 节点：$ENCODED_SERV00"

  green "=============================="
  green "HY2 部署成功"
  green "已通过 Telegram 发送两条节点信息"
  green "=============================="
else
  green "HY2 部署成功（未启用 Telegram 推送）"
fi
# ================== Telegram 推送功能结束 ==================
