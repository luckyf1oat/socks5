# One-Click SOCKS5 Proxy Setup (Dante)

一键在 VPS 上搭建 SOCKS5 代理，基于 **Dante**，支持主流 Linux 发行版。

## 支持系统

| 系统 | 状态 |
|------|------|
| Debian 9+ / Ubuntu 18.04+ | ✅ |
| Alpine 3.12+ | ✅ |
| CentOS 7/8/9 / Rocky / AlmaLinux | ✅ |
| RHEL / Fedora | ✅ |
| Amazon Linux | ✅ |

## 功能特性

- 🔑 随机生成 **6 位用户名+密码**（含大小写字母、数字、特殊符号）
- 🌐 自动检测 **IPv4 / IPv6** 公网地址
- 🌍 通过 **ip-api.com** 查询 VPS 地理位置信息
- 📝 输出 **socks5://** 标准代理链接
- 🔗 输出 **v2rayN 可导入格式** 分享链接
- 💾 结果保存至 `{国家}_{ASN}_{组织}.txt` 文件
- 🔥 自动配置防火墙（UFW / firewalld / iptables）
- ⚡ 设置开机自启

## 一键安装

```bash
# 使用 curl（推荐）
curl -sSL https://raw.githubusercontent.com/luckyf1oat/socks5/main/socks5.sh | sudo bash

# 或本地运行
chmod +x socks5.sh
sudo ./socks5.sh
```

## 输出示例

```
========================================
    SOCKS5 代理搭建完成！
========================================

━━━ IPv4 ━━━
  代理地址:
  socks5://aB3$xK:yZ8@mQ@203.0.113.1:28473

  v2rayN 导入格式:
  socks://aB3$xK:yZ8@mQ@203.0.113.1:28473#China_AS4134_Chinanet_IPv4

========================================
信息已保存到: China_AS4134_Chinanet.txt
```

## v2rayN 导入方式

1. 打开 v2rayN → **服务器** → **批量导入分享URL**
2. 粘贴脚本输出的 `socks://` 链接
3. 点击确定完成导入

## 结果文件

脚本运行后会在当前目录生成一个以 VPS 信息命名的 `.txt` 文件，包含完整代理信息：

```
China_AS4134_Chinanet.txt
```

## 配置文件位置

| 文件 | 路径 |
|------|------|
| Dante 配置 | `/etc/danted.conf` (Debian/Ubuntu) |
| Dante 配置 | `/etc/sockd.conf` (CentOS/RHEL) |
| Dante 配置 | `/etc/dante/sockd.conf` (Alpine) |
| 密码文件 | `/etc/danted.passwd` |

## 常用管理命令

```bash
# 查看服务状态
systemctl status danted     # Debian/Ubuntu
systemctl status sockd      # CentOS/RHEL/Alpine

# 重启服务
systemctl restart danted

# 停止服务
systemctl stop danted

# 查看日志
journalctl -u danted -f
```

## 卸载

```bash
# Debian/Ubuntu
apt-get remove --purge dante-server

# CentOS/RHEL
yum remove dante-server

# Alpine
apk del dante-server
```

## License

MIT