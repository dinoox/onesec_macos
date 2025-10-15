#!/bin/bash

echo "🚀 启动 UDS Mock Server..."
echo ""

# 设置 socket 路径
export UDS_PATH=${UDS_PATH:-/tmp/onesec.sock}

echo "📁 Socket 路径: $UDS_PATH"
echo ""

# 启动服务器
pnpm dev

