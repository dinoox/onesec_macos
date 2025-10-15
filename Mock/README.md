# UDS Mock Server

精简的 Unix Domain Socket 服务器，用于测试 OnesecCore 的 UDSClient。

## 快速开始

### 1. 安装依赖

```bash
cd Mock
pnpm install
```

### 2. 启动服务器

```bash
# 使用默认路径 /tmp/onesec.sock
pnpm dev

# 或指定自定义路径
UDS_PATH=/tmp/custom.sock pnpm dev
```

### 3. 测试命令

服务器启动后，可以使用以下命令发送测试消息：

- **1** - 发送初始化配置 (init_config)
  - 包含 auth_token 和 hotkey_configs
  
- **2** - 发送快捷键设置 (hotkey_setting)
  - 模拟开始设置快捷键
  
- **3** - 发送快捷键设置结束 (hotkey_setting_end)
  - 包含新的快捷键组合
  
- **4** - 退出服务器

## 消息格式

所有消息均为 JSON 格式，以 `\n` 结尾：

```json
{
  "type": "init_config",
  "timestamp": 1697372400000,
  "data": {
    "auth_token": "test_token_123456",
    "hotkey_configs": [
      {
        "mode": "normal",
        "hotkey_combination": ["command", "shift", "a"]
      }
    ]
  }
}
```

## 接收的消息类型

服务器会记录从客户端接收的消息：

- `start_recording` - 开始录音
- `stop_recording` - 停止录音
- `mode_upgrade` - 模式升级
- `auth_token_failed` - 认证失败

## 注意事项

- 确保 Swift 客户端配置的 UDS_CHANNEL 路径与服务器一致
- 服务器启动时会自动清理旧的 socket 文件
- 使用 Ctrl+C 可以优雅退出服务器
