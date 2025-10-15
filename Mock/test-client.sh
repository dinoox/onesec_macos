#!/bin/bash

# 测试 UDS 连接的简单脚本
SOCKET_PATH="/tmp/com.ripplestars.miaoyan.uds.test"

echo "🧪 测试 UDS Socket 连接"
echo "Socket 路径: $SOCKET_PATH"
echo ""

# 检查 socket 文件是否存在
if [ ! -S "$SOCKET_PATH" ]; then
    echo "❌ Socket 文件不存在，请先启动 Mock 服务器"
    echo "   运行: cd Mock && pnpm dev"
    exit 1
fi

echo "✅ Socket 文件存在"
echo ""
echo "尝试连接并发送测试消息..."
echo ""

# 使用 nc (netcat) 连接 UDS socket
# 发送一个测试消息
echo '{"type":"start_recording","timestamp":1697404800000,"data":{"recognition_mode":"normal"}}' | nc -U "$SOCKET_PATH"

echo ""
echo "✅ 消息已发送"
echo "查看 Mock 服务器终端是否收到消息"

