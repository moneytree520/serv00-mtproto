#!/bin/bash

# 获取当前脚本的绝对路径，并设置 mtg 目录
BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
MTG_DIR="${BASE_DIR}/mtg"

# 创建 mtg 目录
mkdir -p "${MTG_DIR}"
cd "${MTG_DIR}" || { echo "无法进入目录 ${MTG_DIR}"; exit 1; }

# 下载 mtg 可执行文件并赋予执行权限
echo "正在下载 mtg..."
curl -LO https://raw.githubusercontent.com/boosoyz/mtproto/main/mtg > /dev/null 2>&1
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

# 让用户输入 PushPlus Token（首次安装时输入）
read -p "请输入您的 PushPlus Token (用于发送 mtproto 链接通知): " PUSHPLUS_TOKEN
if [ -z "$PUSHPLUS_TOKEN" ]; then
    echo "PushPlus Token 未输入，无法发送通知。"
fi

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
    mtproto="https://t.me/proxy?server=${host}&port=${port}&secret=${secret}"
    echo "生成的 mtproto 链接：$mtproto"
    echo "启动成功"

    # 如果 PushPlus Token 已提供，发送通知
    if [ -n "$PUSHPLUS_TOKEN" ]; then
        # 对 secret 进行 URL 编码，确保其特殊字符不影响发送
        encoded_secret=$(echo "$secret" | jq -sRr @uri)

        message="Mtg 已启动，mtproto 链接如下：https://t.me/proxy?server=${host}&port=${port}&secret=${encoded_secret}"
        curl -s -X POST https://www.pushplus.plus/send \
            -d "token=${PUSHPLUS_TOKEN}&title=Mtproto链接&content=${message}" > /dev/null
        echo "通知已发送至 PushPlus。"
    fi
else
    echo "启动失败，请检查进程"
    exit 1
fi

# 创建 Keep-alive 脚本，并将其放到 mtg 目录
cat > "${MTG_DIR}/keep_alive.sh" <<EOL
#!/bin/bash

# 获取 mtg 配置信息
MTG_DIR="$(cd "$(dirname "$0")" && pwd)"
PORT=$(jq -r '.port' "${MTG_DIR}/config.json")
SECRET=$(jq -r '.secret' "${MTG_DIR}/config.json")
HOST=$(jq -r '.host' "${MTG_DIR}/config.json")

# 用户的 PushPlus Token
PUSHPLUS_TOKEN="${PUSHPLUS_TOKEN}"

# 检查TCP端口是否有进程在监听
if ! sockstat -4 -l | grep -q "0.0.0.0:${PORT}"; then
    # 如果没有监听，重启 mtg
    echo "端口 ${PORT} 没有进程在监听，正在重启 mtg..."
    
    # 重新启动 mtg
    cd "${MTG_DIR}"
    TMPDIR="${MTG_DIR}/" nohup ./mtg simple-run -n 1.1.1.1 -t 30s -a 1MB 0.0.0.0:${PORT} ${SECRET} -c 8192 > /dev/null 2>&1 &

    # 等待 3 秒钟确保 mtg 启动
    sleep 3

    # 检查 mtg 是否成功启动
    if pgrep -x "mtg" > /dev/null; then
        # 生成 mtproto 链接
        mtproto="https://t.me/proxy?server=${HOST}&port=${PORT}&secret=${SECRET}"
        echo "生成的 mtproto 链接：$mtproto"

        # 对 secret 进行 URL 编码，确保其特殊字符不影响发送
        encoded_secret=$(echo "$SECRET" | jq -sRr @uri)

        # 如果 PushPlus Token 已提供，发送通知
        if [ -n "$PUSHPLUS_TOKEN" ]; then
            message="Mtg 重启，mtproto 链接如下：\nhttps://t.me/proxy?server=${HOST}&port=${PORT}&secret=${encoded_secret}"
            curl -s -X POST https://pushplus.hxtrip.com/send \
                -d "token=${PUSHPLUS_TOKEN}&title=Mtproto链接&content=${message}" > /dev/null
            echo "通知已发送至 PushPlus。"
        fi
    else
        echo "重启 mtg 失败，请检查进程"
    fi
else
    echo "端口 ${PORT} 已经有进程在监听，无需重启 mtg。"
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
