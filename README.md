
# mtproxy

这是一个可以在serv00便用的 MTProxy 代理的绿色脚本

添加通知功能：pushplus微信

首次安装推送&保活脚本重启推送


## 安装方式

执行如下代码进行安装

```bash
curl -sSL https://raw.githubusercontent.com/moneytree520/serv00-mtproto/main/mtg.sh -o mtg.sh && chmod +x mtg.sh

bash mtg.sh
```

## 卸载安装

因为是绿色版卸载极其简单，直接删除所在目录即可。

```bash
rm -rf /home/${USER}/mtg
rm -rf /home/${USER}/mtg.sh
```

# 可自行选择保活

设置定时任务每10分钟执行一次


## 引用项目

- <https://github.com/TelegramMessenger/MTProxy>
- <https://github.com/9seconds/mtg>
