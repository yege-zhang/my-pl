#!/bin/bash

# 字体颜色定义
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

# 环境设置
export LC_ALL=C
HOSTNAME=$(hostname)
USERNAME=$(whoami | tr '[:upper:]' '[:lower:]')

# 识别服务器类型
if [[ "$HOSTNAME" =~ ct8 ]]; then
    CURRENT_DOMAIN="ct8.pl"
elif [[ "$HOSTNAME" =~ hostuno ]]; then
    CURRENT_DOMAIN="useruno.com"
else
    CURRENT_DOMAIN="serv00.net"
fi

# 工作目录设置
WORKDIR="${HOME}/domains/${USERNAME}.${CURRENT_DOMAIN}/logs"
FILE_PATH="${HOME}/domains/${USERNAME}.${CURRENT_DOMAIN}/public_html"
mkdir -p "$WORKDIR" "$FILE_PATH"
chmod 777 "$WORKDIR" "$FILE_PATH" >/dev/null 2>&1

# 检查依赖
command -v curl &>/dev/null && COMMAND="curl -so" || command -v wget &>/dev/null && COMMAND="wget -qO" || { 
    red "Error: neither curl nor wget found, please install one of them." >&2; exit 1; 
}

# 检查权限
cat << EOF > "$HOME/1.sh"
#!/bin/bash
echo "ok"
EOF
chmod +x "$HOME/1.sh"

if ! "$HOME/1.sh" > /dev/null; then
  devil binexec on
  echo "首次运行，需退出并重新登录SSH，再运行一次脚本"
  exit 0
fi

# 清理旧文件
rm -rf "$WORKDIR"/*
sleep 1

# 端口管理函数
check_port() {
    port_list=$(devil port list)
    tcp_ports=$(echo "$port_list" | grep -c "tcp")
    udp_ports=$(echo "$port_list" | grep -c "udp")

    if [[ $tcp_ports -ne 2 || $udp_ports -ne 1 ]]; then
        red "端口规则不符合要求，正在调整..."

        # 删除多余端口
        if [[ $tcp_ports -gt 2 ]]; then
            tcp_to_delete=$((tcp_ports - 2))
            echo "$port_list" | awk '/tcp/ {print $1, $2}' | head -n $tcp_to_delete | while read port type; do
                devil port del $type $port >/dev/null 2>&1
                green "已删除TCP端口: $port"
            done
        fi

        if [[ $udp_ports -gt 1 ]]; then
            udp_to_delete=$((udp_ports - 1))
            echo "$port_list" | awk '/udp/ {print $1, $2}' | head -n $udp_to_delete | while read port type; do
                devil port del $type $port >/dev/null 2>&1
                green "已删除UDP端口: $port"
            done
        fi

        # 添加缺失端口
        if [[ $tcp_ports -lt 2 ]]; then
            tcp_ports_to_add=$((2 - tcp_ports))
            tcp_ports_added=0
            while [[ $tcp_ports_added -lt $tcp_ports_to_add ]]; do
                tcp_port=$(shuf -i 10000-65535 -n 1) 
                result=$(devil port add tcp $tcp_port 2>&1)
                if [[ $result == *"Ok"* ]]; then
                    green "已添加TCP端口: $tcp_port"
                    if [[ $tcp_ports_added -eq 0 ]]; then
                        tcp_port1=$tcp_port
                    else
                        tcp_port2=$tcp_port
                    fi
                    tcp_ports_added=$((tcp_ports_added + 1))
                else
                    yellow "端口 $tcp_port 不可用，尝试其他端口..."
                fi
            done
        fi

        if [[ $udp_ports -lt 1 ]]; then
            while true; do
                udp_port=$(shuf -i 10000-65535 -n 1) 
                result=$(devil port add udp $udp_port 2>&1)
                if [[ $result == *"Ok"* ]]; then
                    green "已添加UDP端口: $udp_port"
                    break
                else
                    yellow "端口 $udp_port 不可用，尝试其他端口..."
                fi
            done
        fi
    else
        tcp_ports=$(echo "$port_list" | awk '/tcp/ {print $1}')
        tcp_port1=$(echo "$tcp_ports" | sed -n '1p')
        tcp_port2=$(echo "$tcp_ports" | sed -n '2p')
        udp_port=$(echo "$port_list" | awk '/udp/ {print $1}')
    fi

    export VLESS_PORT=$tcp_port1
    export VMESS_PORT=$tcp_port2
    export HY2_PORT=$udp_port
}

# 读取域名
read_vless_domain() {
    while true; do
        red "此脚本Serv00/CT8服务器专用"
        reading "请输入cloudflare添加的主域名 (例如：123456.xyz): " input_domain
        # 验证域名格式
        if [[ "$input_domain" =~ ^[a-zA-Z0-9.-]+$ ]] && [[ "$input_domain" =~ \.[a-zA-Z]{2,}$ ]]; then
            # 检查域名是否已经包含$USER
            if [[ "$input_domain" == "$USER"* ]]; then
                vless_domain="$input_domain"
                green "你的vless域名为: $vless_domain"
            else
                vless_domain="$USER.$input_domain"
                green "你的vless域名为: $vless_domain"
            fi
            break
        else
            yellow "输入错误，请重新输入有效的域名"
        fi
    done
}

# 生成配置
generate_config() {
    # 生成密钥对
    output=$(./sing-box generate reality-keypair)
    private_key=$(echo "${output}" | awk '/PrivateKey:/ {print $2}')
    public_key=$(echo "${output}" | awk '/PublicKey:/ {print $2}')
    echo "${private_key}" > private_key.txt
    echo "${public_key}" > public_key.txt

    # 生成TLS证书
    openssl ecparam -genkey -name prime256v1 -out "private.key"
    openssl req -new -x509 -days 3650 -key "private.key" -out "cert.pem" -subj "/CN=$USERNAME.${CURRENT_DOMAIN}"

    # 获取可用IP
    yellow "获取可用IP中，请稍等..."
    available_ip=$(get_ip)
    purple "当前选择IP为：$available_ip 如安装完后节点不通可尝试重新安装"

    # 创建配置文件
    cat > config.json <<EOF
{
  "log": {
    "disabled": true,
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
  "tag": "vless-ws",
  "type": "vless",
  "listen": "::",
  "listen_port": $VLESS_PORT,
  "users": [
    {
      "uuid": "$UUID"
    }
  ],
  "transport": {
    "type": "ws",
    "path": "/$USER",
    "early_data_header_name": "Sec-WebSocket-Protocol"
  }
}
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    }
  ]
}
EOF
}

# 获取IP
get_ip() {
  IP_LIST=($(devil vhost list | awk '/^[0-9]+/ {print $1}'))
  API_URL="https://status.eooce.com/api"
  IP=""
  THIRD_IP=${IP_LIST[2]}
  RESPONSE=$(curl -s --max-time 2 "${API_URL}/${THIRD_IP}")
  if [[ $(echo "$RESPONSE" | jq -r '.status') == "Available" ]]; then
      IP=$THIRD_IP
  else
      FIRST_IP=${IP_LIST[0]}
      RESPONSE=$(curl -s --max-time 2 "${API_URL}/${FIRST_IP}")
      if [[ $(echo "$RESPONSE" | jq -r '.status') == "Available" ]]; then
          IP=$FIRST_IP
      else
          IP=${IP_LIST[1]}
      fi
  fi
  echo "$IP"
}

# 下载sing-box
download_singbox() {
  ARCH=$(uname -m)
  if [ "$ARCH" == "arm" ] || [ "$ARCH" == "arm64" ] || [ "$ARCH" == "aarch64" ]; then
      BASE_URL="https://github.com/SagerNet/sing-box/releases/download/v1.3.0/sing-box-1.3.0-linux-arm64"
  elif [ "$ARCH" == "amd64" ] || [ "$ARCH" == "x86_64" ] || [ "$ARCH" == "x86" ]; then
      BASE_URL="https://github.com/SagerNet/sing-box/releases/download/v1.3.0/sing-box-1.3.0-linux-amd64"
  else
      echo "Unsupported architecture: $ARCH"
      exit 1
  fi

  $COMMAND sing-box "$BASE_URL"
  chmod +x sing-box
}

# 启动服务
start_services() {
  nohup ./sing-box run -c config.json >/dev/null 2>&1 &
  sleep 2
  if pgrep -x "sing-box" > /dev/null; then
      green "sing-box 主进程已启动"
  else
      red "sing-box 主进程启动失败, 重启中..."
      pkill -x "sing-box"
      nohup ./sing-box run -c config.json >/dev/null 2>&1 &
      sleep 2
      purple "sing-box 主进程已重启"
  fi
}

# 创建保活脚本
create_keepalive() {
  cat > start123.sh <<EOF
#!/bin/bash
if ! pgrep -x "sing-box" > /dev/null; then
    cd $WORKDIR
    nohup ./sing-box run -c config.json >/dev/null 2>&1 &
    echo "$(date '+%Y-%m-%d %H:%M:%S') restarted" >> log.txt
fi
EOF
  chmod +x start123.sh

  # 添加定时任务
  cron_job="9 */2 * * * $WORKDIR/start123.sh"
  if ! crontab -l | grep -q "start123.sh"; then
      (crontab -l ; echo "$cron_job") | crontab -
      echo "保活任务已添加到 crontab。"
  fi
}

# 生成节点信息
generate_node_info() {
  cat << EOF > $FILE_PATH/$USER.html
<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>节点信息</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            background-color: #f4f4f4;
            color: #333;
            margin: 0;
            padding: 20px;
        }
        h1 {
            text-align: center;
            color: #007BFF;
            font-size: 28px;
        }
        .content {
            background-color: white;
            border-radius: 8px;
            box-shadow: 0 0 10px rgba(0, 0, 0, 0.1);
            padding: 20px;
            max-width: 800px;
            margin: 0 auto;
            font-size: 16px;
            line-height: 1.6;
        }
        .link-box {
            display: flex;
            align-items: center;
            background-color: #222;
            color: #fff;
            padding: 10px;
            border-radius: 5px;
            overflow-x: auto;
            white-space: nowrap;
            word-break: break-all;
            margin-bottom: 10px;
        }
        .copy-btn {
            margin-right: 10px;
            padding: 5px 10px;
            border: none;
            background-color: #007BFF;
            color: white;
            border-radius: 5px;
            cursor: pointer;
        }
        .copy-btn:hover {
            background-color: #0056b3;
        }
        .footer {
            text-align: center;
            margin-top: 30px;
            color: #777;
        }
    </style>
</head>
<body>
    <h1>用户$USER当前节点信息</h1>
    <div class="content">
        <p style="color: red; font-size: 24px;">复制下面的节点地址到客户端使用</p>
        
        <p>Vless-reality节点:</p>
        <div class="link-box"><button class="copy-btn" onclick="copyText(this)">复制</button> vless://$UUID@$vless_domain:$VLESS_PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$vless_domain&fp=chrome&pbk=$public_key&type=tcp&headerType=none#$HOSTNAME-reality-$USER</div>
        
        <p>Vmess-ws节点:</p>
        <div class="link-box"><button class="copy-btn" onclick="copyText(this)">复制</button> vmess://$(echo "{ \"v\": \"2\", \"ps\": \"$HOSTNAME-vmess-ws-$USER\", \"add\": \"$vless_domain\", \"port\": \"$VMESS_PORT\", \"id\": \"$UUID\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"\", \"path\": \"/$UUID-vm\", \"tls\": \"\", \"sni\": \"\", \"alpn\": \"\", \"fp\": \"\"}" | base64 -w0)</div>
        
        <p>Hysteria2节点:</p>
        <div class="link-box"><button class="copy-btn" onclick="copyText(this)">复制</button> hysteria2://$UUID@$vless_domain:$HY2_PORT?insecure=1&sni=$vless_domain#$HOSTNAME-hy2-$USER</div>
    </div>
    
    <script>
        function copyText(button) {
            var text = button.parentElement.textContent.replace("复制", "").trim();
            navigator.clipboard.writeText(text).then(() => {
                alert("复制成功!");
            }).catch(err => {
                console.error("复制失败", err);
            });
        }
    </script>
</body>
</html>
EOF

  # 显示节点信息
  red ""
  red "当前节点信息"
  red ""
  red "复制下面的网页地址，在浏览器打开，查看节点信息"
  red ""
  red "https://$USER.$CURRENT_DOMAIN/$USER.html"
}

# 主安装函数
install() {
  cd "$WORKDIR"
  
  # 读取域名
  read_vless_domain
  
  # 检查并设置端口
  check_port
  
  # 下载sing-box
  download_singbox
  
  # 生成配置
  generate_config
  
  # 启动服务
  start_services
  
  # 创建保活脚本
  create_keepalive
  
  # 生成节点信息
  generate_node_info
  
  # 创建快捷命令
  quick_command
}

# 创建快捷命令
quick_command() {
  COMMAND="00"
  SCRIPT_PATH="$HOME/bin/$COMMAND"
  mkdir -p "$HOME/bin"
  printf '#!/bin/bash\n' > "$SCRIPT_PATH"
  echo "bash <(curl -Ls https://raw.githubusercontent.com/your-repo/vless-serv00/main/vless.sh)" >> "$SCRIPT_PATH"
  chmod +x "$SCRIPT_PATH"
  
  if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
      echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
      source "$HOME/.bashrc"
  fi
  
  green "快捷指令00创建成功，下次运行输入00快速进入脚本"
}

# 卸载函数
uninstall() {
  reading "确定要卸载吗？【y/n】: " choice
  case "$choice" in
      [Yy])
          bash -c 'ps aux | grep $(whoami) | grep -v "sshd\|bash\|grep" | awk "{print \$2}" | xargs -r kill -9 >/dev/null 2>&1' >/dev/null 2>&1
          rm -rf "$WORKDIR" "$FILE_PATH/$USER.html"
          crontab -l | grep -v "start123.sh" | crontab -
          green "已卸载所有服务"
          ;;
      [Nn]) exit 0 ;;
      *) red "无效的选择，请输入y或n" ;;
  esac
}

# 主菜单
menu() {
  clear
  echo ""
  purple "=== Serv00/CT8三协议一键安装脚本 ==="
  echo ""
  green "1. 安装 vless-reality + vmess-ws + hysteria2"
  echo "================================="
  red "2. 卸载所有服务"
  echo "================================="
  green "3. 查看节点信息"
  echo "================================="
  red "0. 退出脚本"
  echo "================================="
  reading "请输入选择(0-3): " choice
  echo ""
  case "${choice}" in
      1) install ;;
      2) uninstall ;;
      3) 
         if [ -f "$FILE_PATH/$USER.html" ]; then
             red "节点信息: https://$USER.$CURRENT_DOMAIN/$USER.html"
         else
             red "尚未安装服务，请先选择1安装"
         fi
         ;;
      0) exit 0 ;;
      *) red "无效的选项，请输入 0 到 3" ;;
  esac
}

# 启动菜单
menu
