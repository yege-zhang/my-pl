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

# --- 函数：以可靠的方式添加UDP端口 ---
add_udp_port_robustly() {
    while true; do
        local udp_port; udp_port=$(shuf -i 10000-65535 -n 1)
        local result; result=$(devil port add udp "$udp_port" 2>&1)
        if [[ "$result" == *"Ok"* ]]; then
            print_green "成功添加UDP端口: $udp_port"
            echo "$udp_port"; break
        else
            sleep 0.1
        fi
    done
}

# --- 核心逻辑：两段式端口检查和配置 ---
check_and_configure_ports() {
    print_green "--- 步骤1: 检查端口配置 ---"
    local udp_port_count
    udp_port_count=$(devil port list | grep -c "udp")

    if [ "$udp_port_count" -ne 1 ]; then
        print_yellow "端口数量不符合要求(需要1个UDP端口)，正在自动调整..."
        print_purple "正在清理所有旧的UDP端口..."
        devil port list | awk '/udp/ {print $1}' | while read -r port; do
            devil port del udp "$port" >/dev/null 2>&1
        done
        
        print_purple "正在自动寻找并添加一个可用的UDP端口..."
        add_udp_port_robustly >/dev/null # 添加端口，并隐藏端口号
        
        print_green "=================================================================="
        print_green "端口已自动配置完成！"
        print_yellow "为了使新端口在所有IP上完全生效，请您立即重新执行一次此脚本。"
        print_green "=================================================================="
        exit 0
    else
        print_green "端口配置正确 (已存在1个UDP端口)，继续安装..."
        local hy2_port
        hy2_port=$(devil port list | awk '/udp/ {print $1}')
        echo "$hy2_port"
    fi
}

# --- 主脚本执行流程 ---
main() {
    local hy2_port
    hy2_port=$(check_and_configure_ports)
    if [ -z "$hy2_port" ]; then return; fi
    print_purple "检测到可用UDP端口为: $hy2_port"

    export LC_ALL=C
    HOSTNAME=$(hostname); NAME=$(echo "$HOSTNAME" | cut -d '.' -f 1)
    PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 8)

    print_green "--- 步骤2: 动态选择IP和域名 ---"
    IFS=':' read -r SELECTED_IP SELECTED_DOMAIN < <(select_ip_and_domain_interactive)
    if [ -z "$SELECTED_IP" ]; then print_red "IP和域名选择失败，正在退出。"; exit 1; fi
    print_purple "您选择的IP是: $SELECTED_IP (对应域名: $SELECTED_DOMAIN)"

    local WORKDIR="${HOME}/domains/${SELECTED_DOMAIN}/hysteria2"
    print_green "--- 步骤3: 准备环境 (目录: $WORKDIR) ---"
    mkdir -p "$WORKDIR"; pkill -f "hysteria-freebsd-amd64"; cd "$WORKDIR" || exit
    rm -rf ./*

    print_green "--- 步骤4: 下载并配置Hysteria2 ---"
    local LATEST_VERSION
    LATEST_VERSION=$(curl -s "https://api.github.com/repos/apernet/hysteria/releases/latest" | grep '"tag_name":' | cut -d'"' -f4)
    if [ -z "$LATEST_VERSION" ]; then print_red "自动获取最新版本号失败！"; exit 1; fi
    local DOWNLOAD_URL="https://github.com/apernet/hysteria/releases/download/${LATEST_VERSION}/hysteria-freebsd-amd64"
    print_purple "正在下载Hysteria2最新版: $LATEST_VERSION"
    wget -q "$DOWNLOAD_URL"
    if [ ! -s "hysteria-freebsd-amd64" ]; then print_red "错误: Hysteria2 程序下载失败！"; exit 1; fi
    chmod +x hysteria-freebsd-amd64
    openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout web.key -out web.crt -subj "/CN=bing.com" -days 36500

    cat << EOF > config.yaml
listen: ${SELECTED_IP}:${hy2_port}
tls: {cert: ${WORKDIR}/web.crt, key: ${WORKDIR}/web.key}
auth: {type: password, password: $PASSWORD}
masquerade: {type: proxy, proxy: {url: https://bing.com, rewriteHost: true}}
EOF
    print_green "配置文件已生成，服务将明确监听在 $SELECTED_IP"

    print_green "--- 步骤5: 启动服务并设置守护任务 ---"
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

    # --- 最终输出与TG推送 ---
    print_green "--- ✅ 安装完成 ---"
    
    # 构建节点链接
    local USER=$(whoami)
    local TAG_IP="$NAME@$USER-IP"
    local TAG_DOMAIN="$NAME@$USER-Domain"
    local LINK_IP="hysteria2://$PASSWORD@$SELECTED_IP:$hy2_port/?sni=www.bing.com&alpn=h3&insecure=1#$TAG_IP"
    local LINK_DOMAIN="hysteria2://$PASSWORD@$SELECTED_DOMAIN:$hy2_port/?sni=www.bing.com&alpn=h3&insecure=1#$TAG_DOMAIN"

    # TG推送功能
    local TELEGRAM_BOT_TOKEN
    local TELEGRAM_CHAT_ID
    local TELEGRAM_SUCCESS="no"
    read -p "请输入你的 Telegram Bot Token（可回车跳过）: " TELEGRAM_BOT_TOKEN
    read -p "请输入你的 Telegram Chat ID（可回车跳过）: " TELEGRAM_CHAT_ID

    if [[ -n "$TELEGRAM_BOT_TOKEN" && -n "$TELEGRAM_CHAT_ID" ]]; then
      print_purple "正在推送到 Telegram..."
      # 发送成功消息
      curl -s -o /dev/null -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" --data-urlencode "text=✅ HY2 部署成功"
      sleep 0.5
      # 发送节点信息
      local TG_MESSAGE="节点详情如下：

IP链接:
\`${LINK_IP}\`

域名链接:
\`${LINK_DOMAIN}\`"
      curl -s -o /dev/null -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" --data-urlencode "text=${TG_MESSAGE}" --data-urlencode "parse_mode=Markdown"
      TELEGRAM_SUCCESS="yes"
    fi
    
   # 最终屏幕显示
    echo "" >&2 # 增加一个空行
    print_green "=============================================="
    print_green " HY2 部署成功"
    if [[ "$TELEGRAM_SUCCESS" == "yes" ]]; then
        print_green " 已通过 Telegram 发送节点信息"
    fi
    print_green " 链接如下："
    print_yellow "$LINK_IP"
    print_yellow "$LINK_DOMAIN"
    print_green "=============================================="
}

# --- 运行主函数 ---
main
