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
NAME=$(echo $HOSTNAME | cut -d '.' -f 1)
IP=$(curl -fs ip.sb)
PASSWORD=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 8)
REMARK=$(openssl rand -hex 10 | tr -dc '0-9' | head -c 5)
UUID=$(uuidgen)
hostname_number=$(hostname | sed 's/^s\([0-9]*\)\..*/\1/')
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



cd /home/$USER/domains/$USER.serv00.net/public_html/
pkill tmd.py
pkill long.py
pkill zui.py
rm -rf /home/$USER/domains/$USER.serv00.net/public_html/*
sleep 1

read_vless_domain() {
    while true; do
        red "此脚本Serv00服务器专用"
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

# 等待端口生效（如果 devil 有延迟）
sleep 2

# 通过 devil port list 获取最新端口号
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
    vless=${tcp_ports[0]}
    socks=${tcp_ports[1]}
    tuic=${udp_ports[0]}
else
    echo "端口分配失败，请检查 devil port list 输出"
    exit 1
fi


echo "域名清理中---"
devil www del $vless_domain
sleep 2
echo "域名添加中---"
devil www add $vless_domain proxy localhost $vless
devil www add $USER.serv00.net


cd /home/$USER/domains/$USER.serv00.net/public_html

wget -O 'amd64.zip' 'https://blog.222609.xyz/soft/xrfreebsd.zip'
unzip amd64.zip 
chmod +x xray
mv xray tmd.py
rm amd64.zip
dd if=/dev/zero bs=1 count=$(( (RANDOM % 30) + 1 )) status=none >> tmd.py

wget https://blog.222609.xyz/soft/tufreebsd
mv tufreebsd long.py
chmod +x long.py
dd if=/dev/zero bs=1 count=$(( (RANDOM % 30) + 1 )) status=none >> long.py
openssl req -x509 -nodes -newkey ec:<(openssl ecparam -name prime256v1) -keyout web.key -out web.crt -subj "/CN=bing.com" -days 36500

cat << EOF > /home/$USER/domains/$USER.serv00.net/public_html/config.json
{
  "inbounds": [{
    "port": $vless,
    "listen": "0.0.0.0",
    "tag": "vless-inbound",
    "protocol": "vless",
    "settings": {
      "auth": "noauth",
      "udp": false,
      "ip": "0.0.0.0",
      "clients": [{
        "id": "$UUID"
      }],
      "decryption": "none"
    },
    "sniffing": {
      "enabled": true,
      "destOverride": ["http", "tls"]
    },
    "streamSettings": {
      "network": "ws",
      "wsSettings": {
        "path": "/$USER"
      }  
    }
  },
   {
    "port": $socks,
    "listen": "0.0.0.0",
    "protocol": "socks",
    "settings": {
      "auth": "password",
      "accounts": [
        {
          "user": "$USER",
          "pass": "$PASSWORD"
        }
      ],
      "udp": false,
      "ip": "0.0.0.0"
    }
  }],
  "outbounds": [{
    "protocol": "freedom",
    "settings": {},
    "tag": "direct"
  }, {
    "protocol": "blackhole",
    "settings": {},
    "tag": "blocked"
  }],
  "routing": {
    "domainStrategy": "IPOnDemand",
    "rules": [{
      "type": "field",
      "ip": ["geoip:private"],
      "outboundTag": "blocked"
    }, {
      "type": "field",
      "domain": ["geosite:category-ads"],
      "outboundTag": "blocked"
    }]
  },
  "dns": {
    "hosts": {
      "domain:v2fly.org": "www.vicemc.net",
      "domain:github.io": "pages.github.com",
      "domain:wikipedia.org": "www.wikimedia.org",
      "domain:shadowsocks.org": "electronicsrealm.com"
    },
    "servers": [
      "1.1.1.1",
      {
        "address": "114.114.114.114",
        "port": 53,
        "domains": ["geosite:cn"]
      },
      "8.8.8.8",
      "localhost"
    ]
  },
  "policy": {
    "levels": {
      "0": {
        "uplinkOnly": 0,
        "downlinkOnly": 0
      }
    },
    "system": {
      "statsInboundUplink": false,
      "statsInboundDownlink": false,
      "statsOutboundUplink": false,
      "statsOutboundDownlink": false
    }
  }
}
EOF
sleep 1

cat << EOF > /home/$USER/domains/$USER.serv00.net/public_html/web.json
{
    "server": "[::]:$tuic",
    "users": {
        "$UUID": "$PASSWORD"
    },
    "certificate": "/home/$USER/domains/$USER.serv00.net/public_html/web.crt",
    "private_key": "/home/$USER/domains/$USER.serv00.net/public_html/web.key",
    "congestion_control": "bbr",
    "alpn": ["h3", "spdy/3.1"],
    "udp_relay_ipv6": true,
    "zero_rtt_handshake": false,
    "auth_timeout": "3s",
    "max_idle_time": "10s",
    "max_external_packet_size": 1500,
    "gc_interval": "3s",
    "gc_lifetime": "15s",
    "log_level": "warn"
}
EOF

cat << EOF > /home/$USER/domains/$USER.serv00.net/public_html/start123.sh

#!/bin/bash
if ps -aux | grep -v grep | grep -q "tmd.py"; then
	cd /home/$USER/domains/$USER.serv00.net/public_html
                exit 0
else
                cd /home/$USER/domains/$USER.serv00.net/public_html
	nohup ./tmd.py > /dev/null 2>&1 &
	echo "$(date '+%Y-%m-%d %H:%M:%S') restarted" >> /home/$USER/domains/$USER.serv00.net/public_html/log.txt
                nohup ./long.py -c web.json > /dev/null 2>&1 &
	echo "$(date '+%Y-%m-%d %H:%M:%S') restarted" >> /home/$USER/domains/$USER.serv00.net/public_html/log.txt

fi
EOF
cd /home/$USER/domains/$USER.serv00.net/public_html
chmod +x start123.sh
./start123.sh

cron_job="9 */2 * * * /home/$USER/domains/$USER.serv00.net/public_html/start123.sh"
# 检查任务是否已存在
if crontab -l | grep -q "start123.sh"; then
    echo "保活任务已存在，跳过添加。"
else
    (crontab -l ; echo "$cron_job") | crontab -
    echo "保活任务已添加到 crontab。"
fi
if ps -aux | grep -v grep | grep -q "tmd.py"; then
	cd /home/$USER/domains/$USER.serv00.net/public_html
	echo "Vless节点已成功安装"
else
                cd /home/$USER/domains/$USER.serv00.net/public_html	
	nohup ./tmd.py > /dev/null 2>&1 &
	echo "$(date '+%Y-%m-%d %H:%M:%S') restarted" >> /home/$USER/domains/$USER.serv00.net/public_html/log.txt
fi

if ps -aux | grep -v grep | grep -q "long.py"; then
	cd /home/$USER/domains/$USER.serv00.net/public_html
	echo "Tuic节点已成功安装"
else
                cd /home/$USER/domains/$USER.serv00.net/public_html	
                nohup ./long.py -c web.json > /dev/null 2>&1 &
	echo "$(date '+%Y-%m-%d %H:%M:%S') restarted" >> /home/$USER/domains/$USER.serv00.net/public_html/log.txt
fi

sleep 3

if ps -aux | grep -v grep | grep -q "long.py"; then
	cd /home/$USER/domains/$USER.serv00.net/public_html
else
                cd /home/$USER/domains/$USER.serv00.net/public_html	
	echo "Tuic节点安装失败，已退出脚本，重新安装脚本尝试！"
	exit 0
fi

if ps -aux | grep -v grep | grep -q "tmd.py"; then
	cd /home/$USER/domains/$USER.serv00.net/public_html
else
                cd /home/$USER/domains/$USER.serv00.net/public_html	
	echo "Vless节点安装失败，已退出脚本，重新安装脚本尝试！"
	exit 0
fi

red ""
red "当前节点信息"
red ""
red "复制下面的网页地址，在浏览器打开，查看节点信息"
red ""
red "https://$USER.serv00.net/$USER.html"
cat << EOF > /home/$USER/domains/$USER.serv00.net/public_html/$USER.html
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
        <p style="color: red; font-size: 24px;">复制下面的 VLESS+tuic节点地址到客户端Hiddify ，v2rayN等客户端使用</p>
        <p>SOCKS5代理: 一般不必使用</p>
        <div class="link-box"><button class="copy-btn" onclick="copyText(this)">复制</button> socks5://$USER:$PASSWORD@s$hostname_number.serv00.com:$socks </div>
        <p>Vless节点通常比较稳定 </p>
        <div class="link-box"><button class="copy-btn" onclick="copyText(this)">复制</button> vless://$UUID@www.wto.org:443?allowInsecure=1&host=$vless_domain&path=%2F$USER&security=tls&sni=$vless_domain&type=ws#波兰-$NAME@$USER-vless-Serv00</div>
        <p>本服务器的三个域名</p>
        <p>s$hostname_number.serv00.com</p>
        <p>cache$hostname_number.serv00.com</p> 
        <p>web$hostname_number.serv00.com</p>
       <p>去网站查询当前哪个域名可以使用，就用下面那个TUIC节点   {  https://ss.fkj.pp.ua/  }</p>
       <p>tuic节点类似于hy2属于直连，通不通取决于域名IP是否被封，如果域名是通的，节点不通，可以重新安装脚本，会自动更换端口</p>
        <div class="link-box"><button class="copy-btn" onclick="copyText(this)">复制</button> tuic://$UUID:$PASSWORD@s$hostname_number.serv00.com:$tuic?sni=www.bing.com&congestion_control=bbr&udp_relay_mode=native&alpn=h3&allowinsecure=1#波兰-$NAME@$USER-tuic--s$hostname_number.serv00.com</div>
        <div class="link-box"><button class="copy-btn" onclick="copyText(this)">复制</button> tuic://$UUID:$PASSWORD@cache$hostname_number.serv00.com:$tuic?sni=www.bing.com&congestion_control=bbr&udp_relay_mode=native&alpn=h3&allowinsecure=1#波兰-$NAME@$USER-tuic--cache$hostname_number.serv00.com</div>
        <div class="link-box"><button class="copy-btn" onclick="copyText(this)">复制</button> tuic://$UUID:$PASSWORD@web$hostname_number.serv00.com:$tuic?sni=www.bing.com&congestion_control=bbr&udp_relay_mode=native&alpn=h3&allowinsecure=1#波兰-$NAME@$USER-tuic--web$hostname_number.serv00.com</div>
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
        function copyLink(elementId) {
            var text = document.getElementById(elementId).textContent;
            navigator.clipboard.writeText(text).then(() => {
                alert("下载链接复制成功!");
            }).catch(err => {
                console.error("复制失败", err);
            });
        }
    </script>
</body>
</html>
EOF
cat << EOF > /home/$USER/domains/$USER.serv00.net/public_html/index.html
<!DOCTYPE html>
<html>
    <head>
        <meta charset=utf-8 />
        <title>$USER.serv00.net - hosted on Serv00.com</title>
        <style type="text/css">
            * {
                margin: 0;
                padding: 0;
                border: 0;
            }

            body {
                background-image: linear-gradient(137deg, #2E457B 0%, #237431 100%) !important;
                background-attachment: fixed;
                color: #333;
                font-family: Arial, Verdana, Tahoma;
                font-size: 13px;
            }

            #main {
                background: #FFF;
                box-shadow: 0 0 40px #00275A;
                margin-top: 65px;
                padding-top: 20px;
                padding-bottom: 20px;
                width: 100%;
            }

            #mainwrapper {
                display: table;
                text-align: center;
                margin: 0 auto;
            }

            h1 {
                color: #EE6628;
                font-size: 44px;
                font-weight: normal;
                text-shadow: 1px 1px 2px #A7A7A7;
            }

            h2 {
                color: #385792;
                font-weight: normal;
                font-size: 25px;
                text-shadow: 1px 1px 2px #D4D4D4;
            }

            ul {
                text-align: left;
                margin-top: 20px;
            }

            p {
                margin-top: 20px;
                color: #888;
            }

            a {
                color: #4D73BB;
                text-decoration: none;
            }

            a:hover, a:focus {
                text-decoration: underline;
            }
        </style>
    </head>

    <body>

        <div id="main">
            <div id="mainwrapper">
                <h1>$USER.serv00.net</h1>
                <h2>Page successfully added</h2>

                <ul>
                    <li>The page is in the directory <b>/usr/home/$USER/domains/$USER.serv00.net/public_html</b></li>
                    <li>This file can be deleted (index.html),</li>
                    <li>Files can be put on the server using the <b>FTP</b>, <b>FTPS</b> or <b>SFTP</b> protocols.</li>
                </ul>

                <p>If you have any questions <a href="https://www.serv00.com/contact">contact us</a>.</p>
            </div>
        </div>
    </body>

</html>
EOF

red ""


