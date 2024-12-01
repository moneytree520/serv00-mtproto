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

# 让用户选择通知方式
echo "请选择通知方式:"
echo "1. Telegram"
echo "2. PushPlus"
read -p "请输入选择的通知方式（1 或 2）: " notification_choice

# 根据选择处理通知
case "$notification_choice" in
    1)
        # Telegram通知
        read -p "请输入您的 Telegram Bot Token: " TELEGRAM_TOKEN
        read -p "请输入您的 Telegram Chat ID: " TELEGRAM_CHAT_ID
        if [ -z "$TELEGRAM_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
            echo "Telegram Token 或 Chat ID 未输入，无法发送 Telegram 通知。"
        fi
        ;;
    2)
        # PushPlus通知
        read -p "请输入您的 PushPlus Token (用于发送 mtproto 链接通知): " PUSHPLUS_TOKEN
        if [ -z "$PUSHPLUS_TOKEN" ]; then
            echo "PushPlus Token 未输入，无法发送通知。"
        fi
        ;;
    *)
        echo "无效的选择，默认不发送通知。"
        notification_choice=""
        ;;
esac

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
    # 生成完整的 mtproto 链接
    mtproto="https://t.me/proxy?server=${host}&port=${port}&secret=${secret}"

    # URL 编码 mtproto 链接
    encoded_mtproto=$(echo "$mtproto" | jq -sRr @uri)

    # 启动成功
    echo "启动成功"

    # 根据用户选择发送通知
    if [ "$notification_choice" == "1" ] && [ -n "$TELEGRAM_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        # 发送 Telegram 通知
        message="Mtg 已启动，mtproto 链接如下：$encoded_mtproto"
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
            -d "chat_id=${TELEGRAM_CHAT_ID}&text=${message}" > /dev/null
        echo "通知已发送至 Telegram。"
    elif [ "$notification_choice" == "2" ] && [ -n "$PUSHPLUS_TOKEN" ]; then
        # 发送 PushPlus 通知
        message="Mtg 已启动，mtproto 链接如下：\n$encoded_mtproto"
        curl -s -X POST https://www.pushplus.plus/send \
            -d "token=${PUSHPLUS_TOKEN}&title=Mtproto链接&content=${message}" > /dev/null
        echo "通知已发送至 PushPlus。"
    fi
else
    echo "启动失败，请检查进程"
    exit 1
fi
