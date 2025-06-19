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
    
    local ip_array=()
    local domain_array=()
    local display_array=()
    
    # 动态解析 `devil vhost list` 的输出
    # 假设格式为: IP地址 域名 ...
    while read -r ip domain rest; do
        # 确保我们只处理看起来是IP地址的行
        if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            ip_array+=("$ip")
            domain_array+=("$domain")
            display_array+=("$ip ($domain)")
        fi
    done < <(devil vhost list)

    if [ ${#ip_array[@]} -eq 0 ]; then
        print_red "未能动态检测到任何IP地址和域名。"; exit 1;
    fi

    print_green "请选择要使用的IP地址和对应的域名:"
    for i in "${!display_array[@]}"; do
        echo "$((i+1)). ${display_array[$i]}" >&2
    done

    local default_choice=1; local choice
    reading "请输入您想使用的序号 (默认选择第一个): " choice; choice=${choice:-$default_choice}
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#display_array[@]} ]; then
        print_red "无效的选择。将使用默认选项 (列表中的第一个)。"; choice=$default_choice
    fi
    
    local selected_index=$((choice-1))
    # 将选择的IP和域名用冒号分隔后输出，方便主脚本捕获
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
            print_yellow "端口 $udp_port 不可用，正在尝试其他端口..."
            sleep 0.1
        fi
    done
}


# --- 主脚本逻辑 ---
export LC_ALL=C
HOSTNAME=$(hostname); NAME=$(echo "$HOSTNAME" | cut -d '.' -f 1)
PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 8)

# --- 步骤 1: 动态选择IP和域名 ---
print_green "--- 步骤 1: 动态选择IP和域名 ---"
# 使用IFS和read来同时接收函数返回的IP和域名
IFS=':' read -r SELECTED_IP SELECTED_DOMAIN < <(select_ip_and_domain_interactive)
if [ -z "$SELECTED_IP" ] || [ -z "$SELECTED_DOMAIN" ]; then print_red "IP和域名选择失败，正在退出。"; exit 1; fi
print_purple "您选择的IP是: $SELECTED_IP"
print_purple "对应的域名是: $SELECTED_DOMAIN"


# --- 步骤 2: 检查执行权限 ---
print_green "--- 步骤 2: 检查执行权限 ---"
mkdir -p "/home/$USER/web"; pkill -f "hysteria-freebsd-amd64 server"
cat << EOF > "/home/$USER/1.sh"
#!/bin/bash
echo "ok"
EOF
chmod +x "/home/$USER/1.sh"
if ! /home/$USER/1.sh; then
    devil binexec on
    print_yellow "首次运行，已为您开启binexec权限。请重新登录SSH后再次执行脚本。"; exit 0
fi

# --- 步骤 3: 自动配置端口 ---
print_green "--- 步骤 3: 自动清理并配置端口 ---"
print_purple "正在清理所有旧的UDP端口..."
devil port list | awk '/udp/ {print $1}' | while read -r port; do
    devil port del udp "$port" >/dev/null 2>&1
done
print_purple "正在自动寻找并添加一个可用的UDP端口..."
hy2_port=$(add_udp_port_robustly)
if [ -z "$hy2_port" ]; then
    print_red "无法自动添加UDP端口，脚本终止。"; exit 1
fi

# --- 步骤 4: 下载和配置Hysteria2 ---
print_green "--- 步骤 4: 下载和配置Hysteria2 ---"
cd "/home/$USER/web" || exit; rm -rf /home/$USER/web/*; sleep 1
wget https://github.com/apernet/hysteria/releases/download/v2.3.1/hysteria-freebsd-amd64
chmod +x hysteria-freebsd-amd64
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout web.key -out web.crt -subj "/CN=bing.com" -days 36500

cat << EOF > "/home/$USER/web/config.yaml"
listen: :$hy2_port
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

# --- 步骤 5: 设置守护进程和定时任务 ---
print_green "--- 步骤 5: 设置守护进程和定时任务 ---"
cat << EOF > "/home/$USER/web/updateweb.sh"
#!/bin/bash
if pgrep -f "hysteria-freebsd-amd64 server" > /dev/null; then exit 0; else
    cd "/home/$USER/web" || exit
    nohup ./hysteria-freebsd-amd64 server --config config.yaml > /dev/null 2>&1 &
fi
EOF
chmod +x updateweb.sh; ./updateweb.sh
cron_job="*/39 * * * * /home/$USER/web/updateweb.sh"
if ! crontab -l 2>/dev/null | grep -q "updateweb.sh"; then
    (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
    print_green "保活任务已成功添加到 crontab。"
fi

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
