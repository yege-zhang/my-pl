#!/bin/bash

# --- 样式与颜色函数 ---
print_red() { echo -e "\e[1;91m$1\e[0m" >&2; }
print_green() { echo -e "\e[1;32m$1\e[0m" >&2; }
print_yellow() { echo -e "\e[1;33m$1\e[0m" >&2; }
print_purple() { echo -e "\e[1;35m$1\e[0m" >&2; }
reading() { read -p "$(echo -e "\e[1;91m$1\e[0m")" "$2"; }

# --- 函数：动态检测并交互式选择IP和域名 ---
select_ip_and_domain_interactive() {
    print_purple "正在动态检测您账户下的IP和域名..."
    local ip_array=() domain_array=() display_array=()
    while read -r ip domain rest; do
        if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            ip_array+=("$ip"); domain_array+=("$domain"); display_array+=("$ip ($domain)")
        fi
    done < <(devil vhost list)
    if [ ${#ip_array[@]} -eq 0 ]; then print_red "未能动态检测到任何IP和域名。"; exit 1; fi
    print_green "请选择要使用的IP地址 (这将决定最终链接中的地址):"
    for i in "${!display_array[@]}"; do echo "$((i+1)). ${display_array[$i]}" >&2; done
    local default_choice=1; local choice
    reading "请输入您想使用的序号 (默认选择第一个): " choice; choice=${choice:-$default_choice}
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#display_array[@]} ]; then
        print_red "无效的选择。将使用默认选项。"; choice=$default_choice
    fi
    local selected_index=$((choice-1))
    echo "${ip_array[$selected_index]}:${domain_array[$selected_index]}"
}

# --- 主脚本逻辑 ---
export LC_ALL=C
HOSTNAME=$(hostname); NAME=$(echo "$HOSTNAME" | cut -d '.' -f 1)
PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 8)

# --- 步骤 1: 用户输入和动态选择 ---
print_yellow "=================================================================="
print_yellow "重要：在继续之前，请确保您已经登录服务商的网页控制面板，"
print_yellow "手动开启了一个UDP端口供Hysteria2使用。"
print_yellow "=================================================================="
echo "" >&2
reading "请输入您在网页面板上已开启的UDP端口: " hy2_port
if ! [[ "$hy2_port" =~ ^[0-9]+$ ]] || [ "$hy2_port" -lt 1 ] || [ "$hy2_port" -gt 65535 ]; then
    print_red "端口输入错误，脚本退出。"; exit 1
fi
print_purple "您指定的Hysteria2端口为: $hy2_port"

IFS=':' read -r SELECTED_IP SELECTED_DOMAIN < <(select_ip_and_domain_interactive)
if [ -z "$SELECTED_IP" ]; then print_red "IP和域名选择失败，正在退出。"; exit 1; fi
print_purple "您选择的IP是: $SELECTED_IP (对应域名: $SELECTED_DOMAIN)"

# --- 步骤 2: 准备环境和文件 ---
WORKDIR="${HOME}/domains/${SELECTED_DOMAIN}/hysteria2"
print_green "--- 步骤2: 准备环境 (目录: $WORKDIR) ---"
mkdir -p "$WORKDIR"; pkill -f "hysteria-freebsd-amd64"; cd "$WORKDIR" || exit
rm -rf ./*

# --- 步骤 3: 下载和配置Hysteria2 ---
print_green "--- 步骤3: 下载并配置Hysteria2 ---"
# --- 升级：自动获取最新版本并下载 ---
print_purple "正在自动查询Hysteria2最新版本号..."
LATEST_VERSION=$(curl -s "https://api.github.com/repos/apernet/hysteria/releases/latest" | grep '"tag_name":' | cut -d'"' -f4)
if [ -z "$LATEST_VERSION" ]; then
    print_red "自动获取最新版本号失败！请检查网络或稍后再试。"; exit 1
fi
print_purple "检测到最新版本为: $LATEST_VERSION"
DOWNLOAD_URL="https://github.com/apernet/hysteria/releases/download/${LATEST_VERSION}/hysteria-freebsd-amd64"
print_purple "正在从以下地址下载: $DOWNLOAD_URL"

wget "$DOWNLOAD_URL"

if [ ! -s "hysteria-freebsd-amd64" ]; then
    print_red "错误: Hysteria2 程序下载失败！请检查网络。"; exit 1
fi
chmod +x hysteria-freebsd-amd64
print_green "Hysteria2 下载并授权成功。"

# --- 继续配置流程 ---
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout web.key -out web.crt -subj "/CN=bing.com" -days 36500

cat << EOF > config.yaml
listen: :$hy2_port
tls:
  cert: ${WORKDIR}/web.crt
  key: ${WORKDIR}/web.key
auth:
  type: password
  password: $PASSWORD
masquerade:
  type: proxy
  proxy:
    url: https://bing.com
    rewriteHost: true
EOF

# --- 步骤 4: 设置守护进程 ---
print_green "--- 步骤4: 启动服务并设置守护任务 ---"
cat << EOF > updateweb.sh
#!/bin/bash
if pgrep -f "hysteria-freebsd-amd64 server" > /dev/null; then exit 0; else
    cd "$WORKDIR" || exit
    nohup ./hysteria-freebsd-amd64 server --config config.yaml > /dev/null 2>&1 &
fi
EOF
chmod +x updateweb.sh; ./updateweb.sh
(crontab -l 2>/dev/null | grep -v "updateweb.sh"; echo "*/10 * * * * ${WORKDIR}/updateweb.sh") | crontab -
print_green "服务已启动，守护任务已设置。"

# --- 最终输出 ---
print_green "--- ✅ 安装完成 ---"
print_yellow "Hysteria2链接已生成。您可以使用IP或对应的域名作为地址进行连接："
echo "" >&2
print_purple "使用IP地址的链接:"
echo -e "\e[1;91mhysteria2://$PASSWORD@$SELECTED_IP:$hy2_port/?sni=www.bing.com&alpn=h3&insecure=1#$NAME-IP\e[0m" >&2
echo "" >&2
print_purple "使用域名的链接:"
echo -e "\e[1;91mhysteria2://$PASSWORD@$SELECTED_DOMAIN:$hy2_port/?sni=www.bing.com&alpn=h3&insecure=1#$NAME-Domain\e[0m" >&2
echo "" >&2
