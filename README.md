# One-Click SOCKS5 Proxy Setup (sing-box)

一键在 VPS 上搭建 SOCKS5 代理，基于 **sing-box**，支持主流 Linux 发行版。

## 支持系统

| 系统 | 状态 |
|------|------|
| Debian 9+ / Ubuntu 18.04+ | ✅ |
| Alpine 3.12+ | ✅ |
| CentOS 7/8/9 / Rocky / AlmaLinux | ✅ |
| RHEL / Fedora | ✅ |

## 支持架构

| 架构 | 状态 |
|------|------|
| x86_64 (amd64) | ✅ |
| ARM64 (aarch64) | ✅ |
| ARMv7 | ✅ |

## 功能特性

- 🚀 **sing-box 核心** — Go 语言高性能代理核心，SOCKS5 开箱即用
- 🔑 随机生成 **6 位用户名+密码**（纯英文+数字）
- 🌐 自动检测 **IPv4 / IPv6** 公网地址
- 🌍 通过 **ip-api.com** 查询 VPS 地理位置信息
- 📝 输出 **socks5://** 标准代理链接
- 🔗 输出 **v2rayN 可导入格式** 分享链接
- 💾 结果保存至 `{国家}_{ASN}_{组织}.txt` 文件
- 🔥 自动配置防火墙（UFW / firewalld / iptables）
- ⚡ 设置开机自启
- 🧹 每次运行自动清理旧配置，重新生成新凭证

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
  socks5://aB3xKc:yZ8mQp@203.0.113.1:28473

  v2rayN 导入格式:
  socks://aB3xKc:yZ8mQp@203.0.113.1:28473#China_AS4134_Chinanet_IPv4

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

## sing-box 配置文件

配置路径：`/etc/sing-box/config.json`

```json
{
  "log": { "level": "warn" },
  "inbounds": [
    {
      "type": "socks",
      "listen": "0.0.0.0",
      "listen_port": 28473,
      "users": [
        { "username": "xxx", "password": "xxx" }
      ]
    }
  ]
}
```

## 常用管理命令

```bash
# 查看服务状态
systemctl status sing-box

# 重启服务
systemctl restart sing-box

# 停止服务
systemctl stop sing-box

# 查看日志
journalctl -u sing-box -f

# 重新生成凭证（重新运行脚本）
sudo bash socks5.sh
```

## 卸载

```bash
systemctl stop sing-box
systemctl disable sing-box
rm -f /usr/local/bin/sing-box
rm -rf /etc/sing-box
rm -f /etc/systemd/system/sing-box.service
systemctl daemon-reload
```

## License

MIT