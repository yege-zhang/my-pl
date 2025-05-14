## 一、00-vless+vmes+hy2三协议
* 复制脚本回车根据提示安装：
```
bash <(curl -Ls https://raw.githubusercontent.com/yege-zhang/Serv00-CT8/refs/heads/main/003.sh)
```
## 二、00-vless+tuic+socks5三协议
* 复制脚本回车根据提示安装：
```
bash <(curl -Ls https://raw.githubusercontent.com/yege-zhang/Serv00-CT8/refs/heads/main/00-vless.sh)
```
* ①cf中cname账户用户名指向用户名.serv00.net,开小黄云
* ②脚本中输入：cname的主域名
* ③域名SSL/TLS加密方式改成灵活
## 三、ct8-hy2
* 复制脚本回车全自动安装节点：
```
bash <(curl -Ls https://raw.githubusercontent.com/yege-zhang/SC/refs/heads/main/ct8-hy2.sh)
```
## 四、其他
*  掉线重新安装即可
## 五、卸载及清理
*  ①结束所有进程：
```
pkill -u $(whoami)
```

*  ②卸载：
```
rm -rf /home/$USER/domains/$USER.serv00.net/public_html/*
```
