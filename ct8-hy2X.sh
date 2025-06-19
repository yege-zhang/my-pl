#!/bin/bash

# --- 样式与颜色函数 ---
print_red() { echo -e "\e[1;91m$1\e[0m" >&2; }
print_green() { echo -e "\e[1;32m$1\e[0m" >&2; }
print_yellow() { echo -e "\e[1;33m$1\e[0m" >&2; }
print_purple() { echo -e "\e[1;35m$1\e[0m" >&2; }
reading() { read -p "$(echo -e "\e[1;91m$1\e[0m")" "$2"; }

# --- 函数：显示IP列表并让用户选择 ---
select_ip_interactive() {
    print_purple "正在从 'devil' 获取您账户下的可用IP列表..."
    local ip_list; mapfile -t ip_list < <(devil vhost list | awk '/^[0-9]+/ {print $1}')
    if [ ${#ip_list[@]} -eq 0 ]; then print_red "未能从服务器获取任何IP地址。"; exit 1; fi
    print_green "请选择要使用的IP地址 (这将决定使用的域名):"
    for i in "${!ip_list[@]}"; do echo "$((i+1)). ${ip_list[$i]}" >&2; done
    local default_choice=1; local choice
    reading "请输入您想使用的IP序号 (默认选择第一个): " choice; choice=${choice:-$default_choice}
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#ip_list[@]} ]; then
        print_red "无效的选择。将使用默认IP (列表中的第一个)。"; choice=$default_choice
    fi
    local selected_ip=${ip_list[$((choice-1))]}
    print_purple "您已选择IP: $selected_ip"
    echo "$selected_ip"
}

# --- 主脚本逻辑 ---
export LC_ALL=C
declare -A IP_DOMAIN_MAP
IP_DOMAIN_MAP["136.243.156.104"]="s1.ct8.pl"
IP_DOMAIN_MAP["136.243.156.121"]="cache1.ct8.pl"
IP_DOMAIN_MAP["136.243.156.120"]="web1.ct8.pl"
HOSTNAME=$(hostname); NAME=$(echo "$HOSTNAME" | cut -d '.' -f 1)
PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 8)

# --- 步骤 1: 选择IP并匹配域名 ---
print_green "--- 步骤 1: 选择IP并匹配域名 ---"
SELECTED_IP=$(select_ip_interactive)
if [ -z "$SELECTED_IP" ]; then print_red "IP选择失败，正在退出。"; exit 1; fi
SELECTED_DOMAIN=${IP_DOMAIN_MAP[$SELECTED_IP]}
if [ -z "$SELECTED_DOMAIN" ]; then
    print_red "错误：选择的IP '$SELECTED_IP' 没有找到对应的域名，请检查脚本中的IP_DOMAIN_MAP设置。"
    exit 1
fi
print_purple "IP $SELECTED_IP 对应的域名是: $SELECTED_DOMAIN"

# --- 步骤 2: 检查执行权限 ---
print_green "--- 步骤 2: 检查执行权限 ---"
mkdir -p "/home/$USER/web"; pkill -f "pyy.py server -c web.yaml"
cat << EOF > "/home/$USER/1.sh"
#!/bin/bash
echo "ok"
EOF
chmod +x "/home/$USER/1.sh"
if ! /home/$USER/1.sh; then
    devil binexec on
    print_yellow "首次运行，已为您开启binexec权限。请重新登录SSH后再次执行脚本。"; exit 0
fi

# --- 步骤 3: 端口配置 (核心修改) ---
print_green "--- 步骤 3: 端口配置 ---"
# 关键修改：不再使用 "devil port add/del"。直接使用一个很可能默认开放的端口。
hy2=443
print_purple "已指定使用默认开放端口: $hy2"
# 如果443端口被占用，您可以尝试 2053, 2083, 2087, 2096, 8443 等

# --- 步骤 4: 下载和配置Hysteria2 ---
print_green "--- 步骤 4: 下载和配置Hysteria2 ---"
cd "/home/$USER/web" || exit; rm -rf /home/$USER/web/*; sleep 1
wget https://download.hysteria.network/app/latest/hysteria-freebsd-amd64
mv hysteria-freebsd-amd64 pyy.py; chmod +x pyy.py
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout web.key -out web.crt -subj "/CN=bing.com" -days 36500
cat << EOF > "/home/$USER/web/web.yaml"
listen: :$hy2
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
if pgrep -f "pyy.py server -c web.yaml" > /dev/null; then exit 0; else
    cd "/home/$USER/web" || exit; nohup ./pyy.py server -c web.yaml > /dev/null 2>&1 &
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
print_yellow "复制下面的Hysteria2链接进行连接 (端口已固定为 $hy2):"
echo "" >&2
echo -e "\e[1;91mhysteria2://$PASSWORD@$SELECTED_DOMAIN:$hy2/?sni=www.bing.com&alpn=h3&insecure=1#$NAME@$USER-hy2-北极之光\e[0m" >&2
echo "" >&2
