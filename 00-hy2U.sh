#!/bin/bash

# 字体颜色函数
red="\033[1;91m"
green="\033[1;32m"
yellow="\033[1;33m"
purple="\033[1;35m"
reset="\033[0m"
function red() { echo -e "\033[1;91m$1${reset}"; }

# 环境变量
export LC_ALL=C
HOSTNAME=$(hostname)
USERNAME=$(whoami | tr '[:upper:]' '[:lower:]')

# 识别站点域名
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

# 首次执行提示 devil binexec
if ! "$HOME/1.sh" > /dev/null; then
  devil binexec on
  echo "首次运行，需退出并重新登录SSH，再运行一次脚本"
  exit 0
fi

# 清理旧文件
rm -rf "$WORKDIR"/*
sleep 1

# 清除所有 UDP 端口
devil port list | awk 'NR>1 && $2 == "udp" { print $1 }' | while read -r port; do
  devil port del udp "$port"
done

# 添加随机UDP端口直到成功
while true; do
  udp_port=$(shuf -i 10000-65535 -n 1)
  result=$(devil port add udp "$udp_port" 2>&1)
  [[ "$result" == *"Ok"* ]] && break
done

echo -e "${purple}已添加UDP端口：$udp_port${reset}"

# === UUID & 密码设置（交互模式）===
read -p "请输入 UUID（回车自动生成）: " input_uuid
UUID=${input_uuid:-$(uuidgen)}

# 使用 UUID 作为密码
PASSWORD="$UUID"

# 下载 hysteria2 执行文件
curl -Lo hysteria2 https://download.hysteria.network/app/latest/hysteria-freebsd-amd64
chmod +x hysteria2

# 生成证书
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) \
  -keyout "$WORKDIR/web.key" \
  -out "$WORKDIR/web.crt" \
  -subj "/CN=bing.com" -days 36500

# 创建配置文件
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
    url: https://bing.com
    rewriteHost: true

transport:
  udp:
    hopInterval: 30s
EOF

# 创建保活脚本
cat << EOF > "$WORKDIR/updateweb.sh"
#!/bin/bash
if ! pgrep -f hysteria2 > /dev/null; then
  cd "$WORKDIR"
  nohup ./hysteria2 server -c web.yaml > /dev/null 2>&1 &
fi
EOF
chmod +x "$WORKDIR/updateweb.sh"

# 启动服务
"$WORKDIR/updateweb.sh"

# 添加crontab保活任务
cron_job="*/39 * * * * $WORKDIR/updateweb.sh"
(crontab -l 2>/dev/null | grep -v 'updateweb.sh'; echo "$cron_job") | crontab -

# 输出订阅信息
SERVER_NAME=$(echo "$HOSTNAME" | cut -d '.' -f 1)
TAG="$SERVER_NAME@$USERNAME-hy2"
SUB_URL="hysteria2://$PASSWORD@$HOSTNAME:$udp_port/?sni=www.bing.com&alpn=h3&insecure=1#$TAG"

red "========================"
red "HY2 节点已部署完成"
red "订阅链接如下："
red "$SUB_URL"
red "========================"
