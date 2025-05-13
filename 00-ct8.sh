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


if [[ "$HOSTNAME" =~ ct8 ]]; then
    CURRENT_DOMAIN="ct8.pl"
elif [[ "$HOSTNAME" =~ useruno ]]; then
    CURRENT_DOMAIN="useruno.com"
else
    CURRENT_DOMAIN="serv00.net"
fi
WORKDIR="${HOME}/domains/${USERNAME}.${CURRENT_DOMAIN}/logs"
FILE_PATH="${HOME}/domains/${USERNAME}.${CURRENT_DOMAIN}/public_html"
rm -rf "$WORKDIR" && mkdir -p "$WORKDIR" "$FILE_PATH" && chmod 777 "$WORKDIR" "$FILE_PATH" >/dev/null 2>&1
command -v curl &>/dev/null && COMMAND="curl -so" || command -v wget &>/dev/null && COMMAND="wget -qO" || { red "Error: neither curl nor wget found, please install one of them." >&2; exit 1; }


# 检查是否为 root
[[ $EUID -ne 0 ]] && echo "请使用 root 用户运行本脚本" && exit 1

# 预安装依赖
install_base() {
  apt update && apt install -y curl wget unzip socat
}

# xray 安装
install_xray() {
  bash <(curl -Ls https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh)
}


# VLESS 安装逻辑
install_vless() {
  uuid=$(cat /proc/sys/kernel/random/uuid)
  read -p "请输入端口 (默认 443): " port
  [[ -z "$port" ]] && port=443

  cat > /usr/local/etc/xray/config.json <<EOF
{
  "inbounds": [{
    "port": $port,
    "protocol": "vless",
    "settings": {
      "clients": [{ "id": "$uuid" }],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "tcp"
    }
  }],
  "outbounds": [{ "protocol": "freedom" }]
}
EOF

  systemctl restart xray
  echo -e "\nVLESS 安装完成"
  echo -e "端口: $port"
  echo -e "UUID: $uuid"
}

# VMESS 安装逻辑
install_vmess() {
  uuid=$(cat /proc/sys/kernel/random/uuid)
  read -p "请输入端口 (默认 10086): " port
  [[ -z "$port" ]] && port=10086

  cat > /usr/local/etc/xray/config.json <<EOF
{
  "inbounds": [{
    "port": $port,
    "protocol": "vmess",
    "settings": {
      "clients": [{ "id": "$uuid", "alterId": 0 }]
    },
    "streamSettings": {
      "network": "tcp"
    }
  }],
  "outbounds": [{ "protocol": "freedom" }]
}
EOF

  systemctl restart xray
  echo -e "\nVMESS 安装完成"
  echo -e "端口: $port"
  echo -e "UUID: $uuid"
}

# Hysteria2 安装逻辑
install_hysteria2() {
  curl -Lo /usr/local/bin/hysteria https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-amd64
  chmod +x /usr/local/bin/hysteria

  read -p "请输入端口 (默认 5678): " port
  [[ -z "$port" ]] && port=5678
  read -p "请输入密码 (默认 password123): " password
  [[ -z "$password" ]] && password="password123"

  mkdir -p /etc/hysteria
  cat > /etc/hysteria/config.yaml <<EOF
listen: :$port
auth:
  type: password
  password: $password
tls:
  cert: /etc/hysteria/cert.pem
  key: /etc/hysteria/key.pem
EOF

  cat > /etc/systemd/system/hysteria.service <<EOF
[Unit]
Description=Hysteria Service
After=network.target

[Service]
ExecStart=/usr/local/bin/hysteria server -c /etc/hysteria/config.yaml
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reexec
  systemctl enable hysteria
  systemctl start hysteria

  echo -e "\nHysteria2 安装完成"
  echo -e "端口: $port"
  echo -e "密码: $password"
}

menu() {
  clear
  echo "=== 00-vless 多协议安装脚本 ==="
  echo "系统类型: $SYSTEM_TYPE"
  echo "请选择要安装的协议："
  echo "1. 安装 VLESS"
  echo "2. 安装 VMESS"
  echo "3. 安装 Hysteria2"
  
  echo "4. 初始化系统配置"
  echo "5. 一键卸载所有协议"

  echo "0. 退出"
  read -p "请输入选项 [0-3]: " num

  case "$num" in
    1) install_base; install_xray; install_vless ;;
    2) install_base; install_xray; install_vmess ;;
    3) install_base; install_hysteria2 ;;
    0) exit 0 ;;
    5) uninstall_all ;;
    4) init_system ;;
    *) echo "无效输入" ;;
  esac
}


# 一键卸载所有协议
uninstall_all() {
  echo "正在卸载所有协议与配置..."

  systemctl stop xray 2>/dev/null
  systemctl disable xray 2>/dev/null
  rm -f /usr/local/bin/xray /usr/local/etc/xray/config.json
  rm -f /etc/systemd/system/xray.service

  systemctl stop hysteria 2>/dev/null
  systemctl disable hysteria 2>/dev/null
  rm -f /usr/local/bin/hysteria
  rm -rf /etc/hysteria
  rm -f /etc/systemd/system/hysteria.service

  systemctl daemon-reload

  echo "已完成卸载。"
}

# 初始化系统配置
init_system() {
  echo "正在执行初始化..."
  rm -rf /usr/local/etc/xray
  rm -rf /etc/hysteria
  mkdir -p /usr/local/etc/xray
  mkdir -p /etc/hysteria
  echo "初始化完成。"
}

main() {
  menu
}

main
