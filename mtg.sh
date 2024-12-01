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
    # 生成完整的 mtproto 链接
    mtproto="https://t.me/proxy?server=${host}&port=${port}&secret=${secret}"

    # URL 编码 mtproto 链接
    encoded_mtproto=$(echo "$mtproto" | jq -sRr @uri)
    
    # 调试：输出生成的 mtproto 链接，确保它没有被截断
    echo "生成的 mtproto 链接：$mtproto"
    echo "生成的编码链接：$encoded_mtproto" > /dev/null 2>&1 &

    echo "启动成功"

    # 如果 PushPlus Token 已提供，发送通知
    if [ -n "$PUSHPLUS_TOKEN" ]; then
        message="已启动，链接如下：$encoded_mtproto"
        curl -s -X POST https://www.pushplus.plus/send \
            -d "token=${PUSHPLUS_TOKEN}&title=MTProxy 代理&content=${message}" > /dev/null
        echo "通知已发送至 PushPlus。"
    fi
else
    echo "启动失败，请检查进程"
    exit 1
fi

# 询问用户是否启用保活功能
read -p "是否启用保活功能？(y/n): " enable_keepalive
if [[ "$enable_keepalive" =~ ^[Yy]$ ]]; then
    echo "启用保活功能..."

    # 创建保活脚本
    cat > "${MTG_DIR}/keepalive.sh" <<'EOF'
#!/bin/bash

# 获取主机名、端口和密钥
PORT=$(jq -r '.port' config.json)   # 从 config.json 中获取端口
HOST=$(jq -r '.host' config.json)   # 从 config.json 中获取主机名
SECRET=$(jq -r '.secret' config.json)   # 从 config.json 中获取密钥

# 检查 mtg 进程是否存在
if ! pgrep -x "mtg" > /dev/null; then
    # 如果没有找到 mtg 进程，重启 mtg
    echo "未检测到 mtg 进程，正在重启 mtg..."
    pkill -f mtg   # 终止任何 mtg 相关进程（防止残留）
    
    # 启动 mtg
    nohup ./mtg simple-run -n 1.1.1.1 -t 30s -a 1MB 0.0.0.0:${PORT} ${SECRET} -c 8192 --prefer-ip="prefer-ipv6" > /dev/null 2>&1 &
    
    # 生成完整的 mtproto 链接
    mtproto="https://t.me/proxy?server=${host}&port=${port}&secret=${secret}"

    # URL 编码 mtproto 链接
    encoded_mtproto=$(echo "$mtproto" | jq -sRr @uri)
    
    # 调试：输出生成的 mtproto 链接，确保它没有被截断
    echo "生成的 mtproto 链接：$mtproto"
    echo "生成的编码链接：$encoded_mtproto" > /dev/null 2>&1 &

    echo "启动成功"

    # 如果 PushPlus Token 已提供，发送通知
    if [ -n "$PUSHPLUS_TOKEN" ]; then
        message="已重启，链接如下：$encoded_mtproto"
        curl -s -X POST https://www.pushplus.plus/send \
            -d "token=${PUSHPLUS_TOKEN}&title=MTProxy 代理&content=${message}" > /dev/null
        echo "通知已发送至 PushPlus。"
    fi
else
    echo "mtg 进程正在运行，无需重启。"
fi
EOF

    chmod +x "${MTG_DIR}/keepalive.sh"

    # 设置定时任务（每10分钟执行一次保活脚本）
    (crontab -l 2>/dev/null; echo "*/10 * * * * ${MTG_DIR}/keepalive.sh") | crontab -

    echo "保活功能已启用，定时任务已设置每10分钟执行一次。"
fi
