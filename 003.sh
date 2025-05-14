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

USERNAME=$(whoami | tr '[:upper:]' '[:lower:]')
HOSTNAME=$(hostname)
snb=$(hostname | cut -d. -f1)
nb=$(hostname | cut -d '.' -f 1 | tr -d 's')
PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 8)
UUID=$(uuidgen)
WORKDIR="${HOME}/domains/${USERNAME}.${address}/logs"
FILE_PATH="${HOME}/domains/${USERNAME}.${address}/public_html"
keep_path="${HOME}/domains/${snb}.${USERNAME}.serv00.net/public_nodejs"

# 创建必要目录
mkdir -p "$WORKDIR" "$FILE_PATH"
[ "$SERVER_TYPE" = "serv00" ] && mkdir -p "$keep_path"

# 检查程序权限
mkdir -p /home/$USER/domains/$USER.serv00.net/public_html
cat << EOF > /home/$USER/domains/$USER.serv00.net/public_html/1.sh
#!/bin/bash
echo "ok"
EOF
chmod +x /home/$USER/domains/$USER.serv00.net/public_html/1.sh

if /home/$USER/domains/$USER.serv00.net/public_html/1.sh; then
  echo "程序权限已开启"
else
  devil binexec on
  echo "首次运行，需要重新登录SSH，输入exit 退出ssh"
  echo "重新登陆SSH后，再执行一次脚本便可"
  exit 0
fi

# 清理旧进程和文件
cd /home/$USER/domains/$USER.serv00.net/public_html/
pkill tmd.py
pkill long.py
pkill zui.py
rm -rf /home/$USER/domains/$USER.serv00.net/public_html/*
sleep 1

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

read_vless_domain

# 删除所有已开放端口
devil port list | awk 'NR>1 && $1 ~ /^[0-9]+$/ { print $1, $2 }' | while read -r port type; do
    if [[ "$type" == "tcp" ]]; then
        echo "删除 TCP 端口: $port"
        devil port del tcp "$port"
    elif [[ "$type" == "udp" ]]; then
        echo "删除 UDP 端口: $port"
        devil port del udp "$port"
    fi
done

# 添加 2 个 TCP 端口 和 1 个 UDP 端口
devil port add tcp random
devil port add tcp random
devil port add udp random

# 等待端口生效
sleep 2

# 获取最新端口号
ports=($(devil port list | awk 'NR>1 && $1 ~ /^[0-9]+$/ { print $1 }'))
types=($(devil port list | awk 'NR>1 && $2 ~ /tcp|udp/ { print $2 }'))

# 变量赋值
tcp_ports=()
udp_ports=()
for i in "${!types[@]}"; do
    if [[ "${types[i]}" == "tcp" ]]; then
        tcp_ports+=("${ports[i]}")
    elif [[ "${types[i]}" == "udp" ]]; then
        udp_ports+=("${ports[i]}")
    fi
done

# 确保至少有 2 个 TCP 和 1 个 UDP 端口
if [[ ${#tcp_ports[@]} -ge 2 && ${#udp_ports[@]} -ge 1 ]]; then
    vless_port=${tcp_ports[0]}
    vmess_port=${tcp_ports[1]}
    hy2_port=${udp_ports[0]}
else
    echo "端口分配失败，请检查 devil port list 输出"
    exit 1
fi

# 设置域名
echo "域名清理中---"
devil www del $vless_domain
sleep 2
echo "域名添加中---"
devil www add $vless_domain proxy localhost $vless_port
devil www add $USER.$address

# 下载和配置sing-box
cd $FILE_PATH
wget -O sing-box.tar.gz "https://github.com/SagerNet/sing-box/releases/download/v1.3.0/sing-box-1.3.0-linux-amd64.tar.gz"
tar -xzf sing-box.tar.gz
mv sing-box-*/sing-box .
chmod +x sing-box
rm -rf sing-box-* sing-box.tar.gz

# 生成密钥对
output=$(./sing-box generate reality-keypair)
private_key=$(echo "${output}" | awk '/PrivateKey:/ {print $2}')
public_key=$(echo "${output}" | awk '/PublicKey:/ {print $2}')
echo "${private_key}" > private_key.txt
echo "${public_key}" > public_key.txt

# 生成TLS证书
openssl ecparam -genkey -name prime256v1 -out "private.key"
openssl req -new -x509 -days 3650 -key "private.key" -out "cert.pem" -subj "/CN=$USERNAME.${address}"

# 创建配置文件
cat > config.json << EOF
{
  "log": {
    "disabled": true,
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "tag": "vless-reality",
      "type": "vless",
      "listen": "::",
      "listen_port": $vless_port,
      "users": [
        {
          "uuid": "$UUID",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$vless_domain",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "$vless_domain",
            "server_port": 443
          },
          "private_key": "$private_key",
          "short_id": [""]
        }
      }
    },
    {
      "tag": "vmess-ws",
      "type": "vmess",
      "listen": "::",
      "listen_port": $vmess_port,
      "users": [
        {
          "uuid": "$UUID"
        }
      ],
      "transport": {
        "type": "ws",
        "path": "/$UUID-vm",
        "early_data_header_name": "Sec-WebSocket-Protocol"
      }
    },
    {
      "tag": "hysteria2",
      "type": "hysteria2",
      "listen": "::",
      "listen_port": $hy2_port,
      "users": [
        {
          "password": "$UUID"
        }
      ],
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "cert.pem",
        "key_path": "private.key"
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

# 启动服务
nohup ./sing-box run -c config.json >/dev/null 2>&1 &

# 创建保活脚本
cat > start123.sh <<EOF
#!/bin/bash
if ! pgrep -x "sing-box" > /dev/null; then
    cd $FILE_PATH
    nohup ./sing-box run -c config.json >/dev/null 2>&1 &
    echo "$(date '+%Y-%m-%d %H:%M:%S') restarted" >> log.txt
fi
EOF
chmod +x start123.sh

# 添加定时任务
cron_job="9 */2 * * * $FILE_PATH/start123.sh"
if ! crontab -l | grep -q "start123.sh"; then
    (crontab -l ; echo "$cron_job") | crontab -
    echo "保活任务已添加到 crontab。"
fi

# 生成节点信息
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
        <div class="link-box"><button class="copy-btn" onclick="copyText(this)">复制</button> vless://$UUID@$vless_domain:$vless_port?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$vless_domain&fp=chrome&pbk=$public_key&type=tcp&headerType=none#$snb-reality-$USER</div>
        
        <p>Vmess-ws节点:</p>
        <div class="link-box"><button class="copy-btn" onclick="copyText(this)">复制</button> vmess://$(echo "{ \"v\": \"2\", \"ps\": \"$snb-vmess-ws-$USER\", \"add\": \"$vless_domain\", \"port\": \"$vmess_port\", \"id\": \"$UUID\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"\", \"path\": \"/$UUID-vm\", \"tls\": \"\", \"sni\": \"\", \"alpn\": \"\", \"fp\": \"\"}" | base64 -w0)</div>
        
        <p>Hysteria2节点:</p>
        <div class="link-box"><button class="copy-btn" onclick="copyText(this)">复制</button> hysteria2://$UUID@$vless_domain:$hy2_port?insecure=1&sni=$vless_domain#$snb-hy2-$USER</div>
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
red "https://$USER.$address/$USER.html"
