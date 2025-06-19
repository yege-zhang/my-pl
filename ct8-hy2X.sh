#!/bin/bash

# --- 样式与颜色函数 ---
# 修正：将所有交互式输出重定向到 stderr (>&2)，这样就不会被命令替换 `$(...)` 捕获。
# 只有最终的数据（如此处的IP地址）才应输出到 stdout。

print_red() { echo -e "\e[1;91m$1\e[0m" >&2; }
print_green() { echo -e "\e[1;32m$1\e[0m" >&2; }
print_yellow() { echo -e "\e[1;33m$1\e[0m" >&2; }
print_purple() { echo -e "\e[1;35m$1\e[0m" >&2; }
# 'reading' 函数特殊处理，以正确显示 read 命令的提示符
reading() { read -p "$(echo -e "\e[1;91m$1\e[0m")" "$2"; }


# --- 函数：显示IP列表并让用户选择 ---
# 修正：将所有 echo 输出到 stderr (>&2)，除了最后返回值的 echo。
select_ip_interactive() {
    print_purple "正在获取服务器IP列表..."
    # 使用 local 确保 ip_list 是局部变量
    local ip_list
    # 使用更安全的方式读取命令输出到数组
    mapfile -t ip_list < <(devil vhost list | awk '/^[0-9]+/ {print $1}')
    
    if [ ${#ip_list[@]} -eq 0 ]; then
        print_red "未能从服务器获取任何IP地址。"
        exit 1
    fi

    # 向用户显示IP列表 (输出到 stderr)
    print_green "请选择要使用的IP地址:"
    for i in "${!ip_list[@]}"; do
        local ip=${ip_list[$i]}
        echo "$((i+1)). $ip" >&2
    done

    # 提示用户选择，默认值为1
    local default_choice=1
    local choice
    reading "请输入您想使用的IP序号 (默认选择第一个): " choice
    choice=${choice:-$default_choice}

    # 验证用户的选择
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#ip_list[@]} ]; then
        print_red "无效的选择。将使用默认IP (列表中的第一个)。"
        choice=$default_choice
    fi
    
    local selected_ip=${ip_list[$((choice-1))]}
    print_purple "您已选择: $selected_ip"
    
    # 关键：只将最终的纯净数据输出到 stdout，以便被 `SELECTED_IP=$(...)` 正确捕获。
    echo "$selected_ip"
}


# --- 主脚本逻辑 ---

export LC_ALL=C
HOSTNAME=$(hostname)
NAME=$(echo "$HOSTNAME" | cut -d '.' -f 1)
PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 8)
UUID=$(uuidgen)
# 注意：以下两个变量在原始脚本中已定义但未使用
REMARK=$(openssl rand -hex 10 | tr -dc '0-9' | head -c 5)
hostname_number=$(hostname | sed 's/^s\([0-9]*\)\..*/\1/')

# 调用函数来选择IP，这将正确地只捕获IP地址
print_green "--- 步骤 1: 选择服务器IP ---"
SELECTED_IP=$(select_ip_interactive)
if [ -z "$SELECTED_IP" ]; then
    print_red "IP选择失败，正在退出。"
    exit 1
fi

print_green "--- 步骤 2: 检查并设置执行权限 ---"
mkdir -p "/home/$USER/web"
# 预先终止可能存在的旧进程
pkill -f "pyy.py server -c web.yaml"

cat << EOF > "/home/$USER/1.sh"
#!/bin/bash
echo "ok"
EOF
chmod +x "/home/$USER/1.sh"

if /home/$USER/1.sh; then
    echo "程序权限正常。" >&2
else
    devil binexec on
    print_yellow "首次运行，已为您开启binexec权限。"
    print_yellow "请按提示操作：输入 exit 退出当前SSH会话，然后重新登录。"
    print_yellow "重新登陆SSH后，再次执行此脚本即可完成安装。"
    exit 0
fi

print_green "--- 步骤 3: 清理和配置端口 ---"
cd "/home/$USER/web" || exit

rm -rf /home/$USER/web/*
sleep 1

# 删除所有已开放UDP端口
print_purple "正在清理旧的UDP端口..."
devil port list | awk 'NR>1 && $1 ~ /^[0-9]+$/ && $2 == "udp" { print $1 }' | while read -r port; do
    echo "删除 UDP 端口: $port" >&2
    devil port del udp "$port"
done

# 添加1 个 UDP 端口
print_purple "正在添加新的UDP端口..."
devil port add udp random

# 等待端口生效
sleep 2

# 获取新分配的UDP端口
udp_ports=($(devil port list | awk 'NR>1 && $2 == "udp" { print $1 }'))

if [[ ${#udp_ports[@]} -ge 1 ]]; then
    hy2=${udp_ports[0]}
    echo "获取到HY2端口: $hy2" >&2
else
    print_red "未找到可用的UDP端口，无法继续。"
    exit 1
fi

print_green "--- 步骤 4: 下载和配置Hysteria2 ---"
cd "/home/$USER/web" || exit

wget https://download.hysteria.network/app/latest/hysteria-freebsd-amd64
mv hysteria-freebsd-amd64 pyy.py
chmod +x pyy.py
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

print_green "--- 步骤 5: 设置守护进程和定时任务 ---"
cat << EOF > "/home/$USER/web/updateweb.sh"
#!/bin/bash
# 使用更可靠的 pgrep 检查进程
if pgrep -f "pyy.py server -c web.yaml" > /dev/null; then
    # 进程已在运行，无需操作
    exit 0
else
    # 进程未运行，启动它
    cd "/home/$USER/web" || exit
    nohup ./pyy.py server -c web.yaml > /dev/null 2>&1 &
fi
EOF
chmod +x updateweb.sh
./updateweb.sh

cron_job="*/5 * * * * /home/$USER/web/updateweb.sh"
# 检查任务是否已存在
if crontab -l 2>/dev/null | grep -q "updateweb.sh"; then
    print_yellow "保活任务已存在，跳过添加。"
else
    (crontab -l 2>/dev/null; echo "$cron_job") | crontab -
    print_green "保活任务已成功添加到 crontab。"
fi

print_green "--- ✅ 安装完成 ---"
print_yellow "复制下面的Hysteria2链接进行连接:"
# 使用 print_red 在最后高亮显示结果，但由于链接本身不是错误，用普通 echo 或其他颜色也可
echo "" >&2 # 输出一个空行以增加间距
echo -e "\e[1;91mhysteria2://$PASSWORD@$SELECTED_IP:$hy2/?sni=www.bing.com&alpn=h3&insecure=1#$NAME@$USER-hy2\e[0m" >&2
echo "" >&2
