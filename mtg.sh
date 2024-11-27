#!/bin/bash

# 获取当前脚本的绝对路径，并设置 mtg 目录
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
MTG_DIR="${BASE_DIR}/mtg"

# 创建 mtg 目录
mkdir -p "${MTG_DIR}"
cd "${MTG_DIR}" || { echo "无法进入目录 ${MTG_DIR}"; exit 1; }

# 下载 mtg 可执行文件并赋予执行权限
echo "正在下载 mtg..."
curl -LO https://rain3.serv00.net/serv00-app/mtproto/mtg > /dev/null 2>&1
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
read -p "请输入 mtg 使用的端口号: " port

# 检查输入的端口是否有效
if [[ ! "$port" =~ ^[0-9]+$ || "$port" -lt 1024 || "$port" -gt 65535 ]]; then
    echo "无效的端口号。请输入一个有效的端口（1024-65535）。"
    exit 1
fi

mtpport="$port"
echo "使用的端口为：$mtpport"

# 创建 config.json 配置文件
cat > config.json <<EOF
{
  "host": "$host",
  "secret": "$secret",
  "port": "$mtpport"
}
EOF

# 启动 mtg 并在后台运行，完全隐藏输出
nohup ./mtg simple-run -n 1.1.1.1 -t 30s -a 1MB 0.0.0.0:${mtpport} ${secret} -c 8192 --prefer-ip="prefer-ipv6" > /dev/null 2>&1 &

# 检查 mtg 是否启动成功
sleep 3
if pgrep -x "./mtg" > /dev/null; then
    mtproto="https://t.me/proxy?server=${host}&port=${mtpport}&secret=${secret}"
    echo "生成的 mtproto 链接：$mtproto"
    echo "启动成功"
else
    echo "启动失败，请检查进程"
    exit 1
fi

# 创建 Keep-alive 脚本，并将其放到 mtg 目录
cat > "${MTG_DIR}/keep_alive.sh" <<EOL
#!/bin/bash

# 检查TCP端口是否有进程在监听
if ! sockstat -4 -l | grep -q "0.0.0.0:${mtpport}"; then
    echo "[\$(date)] 端口 ${mtpport} 未监听，尝试重启 mtg。" > /dev/null 2>&1
    cd "${MTG_DIR}"
    TMPDIR="${MTG_DIR}/" nohup ./mtg simple-run -n 1.1.1.1 -t 30s -a 1MB 0.0.0.0:${mtpport} ${secret} -c 8192 --prefer-ip="prefer-ipv6" > /dev/null 2>&1 &
else
    echo "[\$(date)] mtg 正在运行。" > /dev/null 2>&1
fi
EOL

chmod +x "${MTG_DIR}/keep_alive.sh"
echo "保活脚本已创建并放置在 ${MTG_DIR} 目录中。"

# 询问用户是否启用保活功能
read -p "是否启用保活功能？[y/N]: " enable_keep_alive

if [[ "$enable_keep_alive" =~ ^[Yy]$ ]]; then
    # 设置定时任务每13分钟执行一次
    (crontab -l ; echo "*/13 * * * * ${MTG_DIR}/keep_alive.sh") | crontab -
    echo "定时任务已设置，每13分钟检查一次 mtg 是否在运行。"
else
    echo "未启用保活功能。"
fi
























