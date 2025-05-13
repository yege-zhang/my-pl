## 一、00-vless协议
* 复制脚本回车根据提示安装：
```
bash <(curl -Ls https://raw.githubusercontent.com/yege-zhang/Serv00-CT8/refs/heads/main/00-ct8.sh)
```
* ①cf中cname账户用户名指向用户名.serv00.net,开小黄云
* ②脚本中输入：cname的主域名
* ③域名SSL/TLS加密方式改成灵活
## 二、00|CT8-hy2交互
* 复制脚本回车根据提示安装：
```
bash <(curl -Ls https://raw.githubusercontent.com/yege-zhang/SC/refs/heads/main/00-hy2.sh)
```
## 三、00|CT-hy2无交互
* 复制脚本回车全自动安装节点：
```
bash <(curl -Ls https://raw.githubusercontent.com/yege-zhang/SC/refs/heads/main/00-hy2U.sh)
```
## 四、ct8-hy2无交互
* 复制脚本回车全自动安装节点：
```
bash <(curl -Ls https://raw.githubusercontent.com/yege-zhang/SC/refs/heads/main/ct8-hy2.sh)
```
## 五、其他
*  掉线重新安装即可
## 六、卸载及清理
*  ①结束所有进程：
```
pkill -u $(whoami)
```

*  ②卸载：
```
rm -rf /home/$USER/domains/$USER.serv00.net/public_html/*
```
