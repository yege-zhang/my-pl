#!/bin/bash

# 字体颜色输出函数
function red()    { echo -e "\033[1;91m$1\033[0m"; }
function green()  { echo -e "\033[1;32m$1\033[0m"; }
function yellow() { echo -e "\033[1;33m$1\033[0m"; }
function purple() { echo -e "\033[1;35m$1\033[0m"; }

# 环境变量
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

# 创建基础运行验证脚本
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

# 清理旧文件
rm -rf "$WORKDIR"/*
sleep 1

# 清除所有 UDP 端口
devil port list | awk 'NR>1 && $2 == "udp" { print $1 }' | while read -r port; do
  devil port del udp "$port"
done

# 添加中段随机 UDP 端口
while true; do
  udp_port=$(shuf -i 30000-40000 -n 1)
  result=$(devil port add udp "$udp_port" 2>&1)
  [[ "$result" == *"Ok"* ]] && break
done
purple "已添加 UDP 端口：$udp_port"

# UUID 输入或自动生成
read -p "请输入 UUID（回车自动生成）: " input_uuid
UUID=${input_uuid:-$(uuidgen)}
PASSWORD="$UUID"

# 用户输入伪装域名
read -p "请输入伪装域名（回车默认 bing.com）: " input_domain
MASQUERADE_DOMAIN=${input_domain:-bing.com}
purple "使用伪装域名：$MASQUERADE_DOMAIN"

# 下载 hysteria2 程序
curl -Lo hysteria2 https://download.hysteria.network/app/latest/hysteria-freebsd-amd64
chmod +x hysteria2

# 生成 TLS 自签证书
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
  -keyout "$WORKDIR/web.key" \
  -out "$WORKDIR/web.crt" \
  -subj "/CN=${MASQUERADE_DOMAIN}" -days 36500

# 写入配置文件
cat << EOF > "$WORKDIR/web.yaml"
listen: :$udp_port

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

# 写入保活脚本
cat << EOF > "$WORKDIR/updateweb.sh"
#!/bin/bash
sleep \$((RANDOM % 30 + 10))
if ! pgrep -f hysteria2 > /dev/null; then
  cd "$WORKDIR"
  nohup ./hysteria2 server -c web.yaml > /dev/null 2>&1 &
fi
EOF
chmod +x "$WORKDIR/updateweb.sh"

# 启动服务
"$WORKDIR/updateweb.sh"

# 添加 crontab 保活任务（唯一标识）
cron_job="*/39 * * * * $WORKDIR/updateweb.sh # hysteria2_keepalive"
crontab -l 2>/dev/null | grep -q 'hysteria2_keepalive' || \
  (crontab -l 2>/dev/null; echo "$cron_job") | crontab -

# 构建订阅链接
SERVER_NAME=$(echo "$HOSTNAME" | cut -d '.' -f 1)
TAG="$SERVER_NAME@$USERNAME-hy2"
SUB_URL="hysteria2://$PASSWORD@$HOSTNAME:$udp_port/?sni=$MASQUERADE_DOMAIN&alpn=h3&insecure=1#$TAG"

# 用户输入 Telegram 推送参数
read -p "请输入你的 Telegram Bot Token: " TELEGRAM_BOT_TOKEN
read -p "请输入你的 Telegram Chat ID: " TELEGRAM_CHAT_ID

# Base64 编码订阅链接
ENCODED_LINK=$(echo -n "$SUB_URL" | base64)

# 拼接消息文本（带说明）
MSG="HY2 节点部署成功 ✅

$ENCODED_LINK"

# 静默发送到 Telegram（无任何返回输出）
curl -s -o /dev/null -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d chat_id="${TELEGRAM_CHAT_ID}" \
  -d text="$MSG"

green "=============================="
green "Hysteria2 已部署成功 "
green "已通过 Telegram 发送节点信息"
green "=============================="