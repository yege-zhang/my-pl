#!/bin/bash

# 字体颜色输出函数
function red()    { echo -e "\033[1;91m$1\033[0m"; }
function green()  { echo -e "\033[1;32m$1\033[0m"; }
function yellow() { echo -e "\033[1;33m$1\033[0m"; }
function purple() { echo -e "\033[1;35m$1\033[0m"; }

export LC_ALL=C
HOSTNAME=$(hostname)
USERNAME=$(whoami | tr '[:upper:]' '[:lower:]')

# 自动识别站点域名
if [[ "$HOSTNAME" =~ ct8 ]]; then
  CURRENT_DOMAIN="ct8.pl"
elif [[ "$HOSTNAME" =~ hostuno ]]; then
  CURRENT_DOMAIN="useruno.com"
else
  CURRENT_DOMAIN="serv00.net"
fi

WORKDIR="$HOME/domains/${USERNAME}.${CURRENT_DOMAIN}/web"
mkdir -p "$WORKDIR"
cd "$WORKDIR" || exit 1

# 验证 devil 执行权限
cat << EOF > "$HOME/1.sh"
#!/bin/bash
echo "ok"
EOF
chmod +x "$HOME/1.sh"
if ! "$HOME/1.sh" > /dev/null; then
  devil binexec on
  echo "首次运行，请退出 SSH 后重新登录再执行此脚本"
  exit 0
fi

# 清理旧内容
rm -rf "$WORKDIR"/*
sleep 1

# 清除旧 UDP 端口
devil port list | awk 'NR>1 && $2 == "udp" { print $1 }' | while read -r port; do
  devil port del udp "$port"
done

# 添加新 UDP 端口
while true; do
  udp_port=$(shuf -i 30000-40000 -n 1)
  result=$(devil port add udp "$udp_port" 2>&1)
  [[ "$result" == *"Ok"* ]] && break
done
purple "已添加 UDP 端口：$udp_port"

# 多域名检测
SERVER_NAME=$(hostname | cut -d '.' -f 1)
SERVER_ID=$(echo "$SERVER_NAME" | sed 's/[^0-9]//g')
BASE_DOMAIN="serv00.com"

DOMAINS=(
  "${SERVER_NAME}.${BASE_DOMAIN}"
  "web${SERVER_ID}.${BASE_DOMAIN}"
  "cache${SERVER_ID}.${BASE_DOMAIN}"
)

> ip.txt
for domain in "${DOMAINS[@]}"; do
  response=$(curl -sL --connect-timeout 5 --max-time 7 "https://ss.fkj.pp.ua/api/getip?host=$domain")
  if [[ "$response" =~ "Accessible" ]]; then
    ip=$(echo "$response" | awk -F '|' '{print $1}')
    echo "$ip:$domain:可用" >> ip.txt
  else
    ip=$(dig +short "$domain" @8.8.8.8 | head -n 1)
    echo "$ip:$domain:被墙" >> ip.txt
  fi
done

SELECTED_LINE=$(grep "可用" ip.txt | head -n 1)
SELECTED_IP=$(echo "$SELECTED_LINE" | cut -d ':' -f 1)
SELECTED_DOMAIN=$(echo "$SELECTED_LINE" | cut -d ':' -f 2)

if [[ -z "$SELECTED_IP" || -z "$SELECTED_DOMAIN" ]]; then
  red "未找到可用 IP，请检查网络或域名状态。"
  exit 1
fi
green "已选择：$SELECTED_DOMAIN （$SELECTED_IP）"

# 自动生成 UUID 和默认伪装域名
UUID=$(uuidgen)
PASSWORD="$UUID"
MASQUERADE_DOMAIN="www.cloudflare.com"
purple "使用伪装域名：$MASQUERADE_DOMAIN"

# Base64 解码 hysteria 二进制（伪装文件名 index.cgi）
HYSTERIA_B64_URL="https://raw.githubusercontent.com/example/hy2-b64/main/hysteria-linux.b64"
curl -sLo hysteria.b64 "$HYSTERIA_B64_URL"
base64 -d hysteria.b64 > index.cgi
chmod +x index.cgi

# 生成 TLS 自签证书（CN 与伪装域名一致）
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
  -keyout "$WORKDIR/web.key" \
  -out "$WORKDIR/web.crt" \
  -subj "/CN=${MASQUERADE_DOMAIN}" -days 36500

# 写入 hy2 配置文件
cat << EOF > "$WORKDIR/web.yaml"
listen: $SELECTED_IP:$udp_port

tls:
  cert: $WORKDIR/web.crt
  key: $WORKDIR/web.key

auth:
  type: password
  password: $PASSWORD

masquerade:
  type: proxy
  proxy:
    url: https://${MASQUERADE_DOMAIN}
    rewriteHost: true

transport:
  udp:
    hopInterval: 30s
EOF

# 保活脚本
cat << EOF > "$WORKDIR/updateweb.sh"
#!/bin/bash
sleep \$((RANDOM % 30 + 10))
if ! pgrep -f index.cgi > /dev/null; then
  cd "$WORKDIR"
  nohup ./index.cgi server -c web.yaml > /dev/null 2>&1 &
fi
EOF
chmod +x "$WORKDIR/updateweb.sh"

# 启动 hy2 服务
"$WORKDIR/updateweb.sh"

# 添加定时任务保活
cron_job="*/39 * * * * $WORKDIR/updateweb.sh # hysteria2_keepalive"
crontab -l 2>/dev/null | grep -q 'hysteria2_keepalive' || \
  (crontab -l 2>/dev/null; echo "$cron_job") | crontab -

# 构建分享链接
SERVER_NAME=$(echo "$SELECTED_DOMAIN" | cut -d '.' -f 1)
TAG="$SERVER_NAME@$USERNAME-hy2"
SUB_URL="hysteria2://$PASSWORD@$SELECTED_DOMAIN:$udp_port/?sni=$MASQUERADE_DOMAIN&alpn=h2&insecure=1#$TAG"

# Telegram 推送（保留交互）
echo -n "请输入你的 Telegram Bot Token: "
read TELEGRAM_BOT_TOKEN
echo -n "请输入你的 Telegram Chat ID: "
read TELEGRAM_CHAT_ID

if [[ -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]]; then
  ENCODED_LINK=$(echo -n "$SUB_URL" | base64)
  curl -s -o /dev/null -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="${TELEGRAM_CHAT_ID}" \
    -d text="HY2 部署成功 ✅"
  sleep 0.5
  curl -s -o /dev/null -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="${TELEGRAM_CHAT_ID}" \
    -d text="$ENCODED_LINK"
fi

# 完成提示
green "=============================="
green "HY2 部署成功"
green "链接如下："
yellow "$SUB_URL"
green "=============================="
