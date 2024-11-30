#!/bin/bash

# 获取当前脚本的绝对路径，并设置 mtg 目录
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
MTG_DIR="${BASE_DIR}/mtg"

# 创建 mtg 目录
mkdir -p "${MTG_DIR}"
cd "${MTG_DIR}" || { echo "无法进入目录 ${MTG_DIR}"; exit 1; }

# 下载 mtg 可执行文件并赋予执行权限
echo "正在下载 mtg..."
curl -LO https://raw.githubusercontent.com/vipmc838/serv00-mtproto/main/mtg > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "下载失败，请检查网络连接。"
    exit 1
fi

# 赋予执行权限
chmod +x mtg
if [ $? -ne 0 ]; then
    echo "无法赋予执行权限。"
    exit 1
fi

# 获取主机名并生成密钥
host=$(hostname)
secret=$(./mtg generate-secret --hex "$host" 2>/dev/null)
if [ -z "$secret" ]; then
    echo "生成密钥失败。"
    exit 1
fi

# 让用户手动输入端口
while true; do
    read -p "请输入 mtg 使用的端口号 (1024-65535): " port
    # 清理输入并检查是否是有效数字，并且在指定范围内
    port=$(echo "$port" | tr -d '[:space:]')  # 清除多余空格
    if [[ "$port" =~ ^[0-9]+$ && "$port" -ge 1024 && "$port" -le 65535 ]]; then
        break  # 如果输入有效，则跳出循环
    else
        echo "无效的端口号。请输入一个有效的端口（1024-65535）。"
    fi
done

echo "使用的端口为：$port"

# 获取 PushPlus Token
if [ ! -f "${MTG_DIR}/pushplus_token.txt" ]; then
    read -p "请输入 PushPlus Token（首次安装时需要输入）： " pushplus_token
    echo "$pushplus_token" > "${MTG_DIR}/pushplus_token.txt"
else
    pushplus_token=$(cat "${MTG_DIR}/pushplus_token.txt")
fi

# 发送 PushPlus 通知
send_pushplus_notification() {
    mtproto="https://t.me/proxy?server=${host}&port=${port}&secret="${secret}"
    curl -s -X POST "https://www.pushplus.plus/send" \
        -d "token=${pushplus_token}" \
        -d "title=MTProto 链接" \
        -d "content=${mtproto}"
}

# 创建 config.json 配置文件
cat > config.json <<EOF
{
  "host": "$host",
  "secret": "$secret",
  "port": "$port"
}
EOF

# 启动 mtg 并在后台运行，完全隐藏输出
nohup ./mtg simple-run -n 1.1.1.1 -t 30s -a 1MB 0.0.0.0:${port} ${secret} -c 8192 --prefer-ip="prefer-ipv6" > /dev/null 2>&1 &

# 检查 mtg 是否启动成功
sleep 3
if pgrep -x "mtg" > /dev/null; then
    send_pushplus_notification
    echo "启动成功，mtproto 链接已发送。"
else
    echo "启动失败，请检查进程"
    exit 1
fi

# 创建 Keep-alive 脚本，并将其放到 mtg 目录
cat > "${MTG_DIR}/keep_alive.sh" <<EOL
#!/bin/bash

# 检查TCP端口是否有进程在监听
if ! sockstat -4 -l | grep -q "0.0.0.0:${port}"; then
    cd "${MTG_DIR}"
    TMPDIR="${MTG_DIR}/" nohup ./mtg simple-run -n 1.1.1.1 -t 30s -a 1MB 0.0.0.0:${port} ${secret} -c 8192 > /dev/null 2>&1 &
    # 发送通知
    curl -s -X POST "https://www.pushplus.plus/send" \
        -d "token=${pushplus_token}" \
        -d "title=MTProto 进程重启通知" \
        -d "content=MTProto 进程已重启，新的 mtproto 链接：${mtproto}"
fi
EOL

chmod +x "${MTG_DIR}/keep_alive.sh"
echo "保活脚本已创建并放置在 ${MTG_DIR} 目录中。"

# 询问用户是否启用保活功能
read -p "是否启用保活功能？[y/N]: " enable_keep_alive

if [[ "$enable_keep_alive" =~ ^[Yy]$ ]]; then
    # 设置定时任务每13分钟执行一次
    (crontab -l 2>/dev/null; echo "*/13 * * * * ${MTG_DIR}/keep_alive.sh") | crontab -
    echo "定时任务已设置，每13分钟检查一次 mtg 是否在运行。"
else
    echo "未启用保活功能。"
fi
