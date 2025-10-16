import * as net from 'net';
import * as fs from 'fs';
import * as readline from 'readline';

// UDS Socket 路径
const SOCKET_PATH = process.env.UDS_PATH || '/tmp/com.ripplestars.miaoyan.uds.test';

// 消息类型
type MessageType =
  | 'start_recording'
  | 'stop_recording'
  | 'mode_upgrade'
  | 'auth_token_failed'
  | 'hotkey_setting'
  | 'hotkey_setting_end'
  | 'init_config';

interface Message {
  type: MessageType;
  timestamp: number;
  data?: any;
}

// 创建消息
function createMessage(type: MessageType, data?: any): Message {
  return {
    type,
    timestamp: Date.now(),
    data
  };
}

// 发送消息
function sendMessage(socket: net.Socket, message: Message) {
  const json = JSON.stringify(message) + '\n';
  socket.write(json);
  console.log('📤 发送:', message.type, message.data || '');
}

// 清理旧的 socket 文件
if (fs.existsSync(SOCKET_PATH)) {
  fs.unlinkSync(SOCKET_PATH);
}

// 创建 UDS Server
const server = net.createServer((socket) => {
  console.log('✅ 客户端已连接');

  let buffer = '';

  // 接收客户端消息
  socket.on('data', (data) => {
    buffer += data.toString();
    const lines = buffer.split('\n');

    // 处理完整的消息行
    for (let i = 0; i < lines.length - 1; i++) {
      const line = lines[i].trim();
      if (line) {
        try {
          const message = JSON.parse(line) as Message;
          console.log('📥 接收:', message.type, message.data || '');
        } catch (e) {
          console.error('❌ 解析失败:', line);
        }
      }
    }

    // 保留最后一行（可能不完整）
    buffer = lines[lines.length - 1];
  });

  socket.on('end', () => {
    console.log('❌ 客户端断开连接');
  });

  socket.on('error', (err) => {
    console.error('❌ Socket 错误:', err);
  });

  setTimeout(() => {
    sendMessage(socket, createMessage('init_config', {
      auth_token: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI5IiwicGhvbmUiOiIxNzg2NjcwMzYyMiIsIm5pY2tuYW1lIjoiXHU3NTI4XHU2MjM3MzYyMjMzODMiLCJ0aW1lc3RhbXAiOjE3NjA2MDU0NzZ9.GeqhK0AlKjyzl1WotB6zmTosdWiUtpBnjlxz3ljtLVI',
      hotkey_configs: [
        {
          mode: 'normal',
          hotkey_combination: ['fn']
        },
        {
          mode: 'command',
          hotkey_combination: ['command', 'shift', 'c']
        }
      ]
    }));
  },4000)

  return

  // 命令行交互
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
    prompt: '\n命令 (1:init 2:hotkey 3:hotkey_end 4:quit)> '
  });

  rl.prompt();

  rl.on('line', (input) => {
    const cmd = input.trim();

    switch (cmd) {
      case '1':
        // 发送初始化配置
        console.log(1)
        return
        sendMessage(socket, createMessage('init_config', {
          auth_token: 'test_token_123456',
          hotkey_configs: [
            {
              mode: 'normal',
              hotkey_combination: ['command', 'shift', 'a']
            },
            {
              mode: 'command',
              hotkey_combination: ['command', 'shift', 'c']
            }
          ]
        }));
        break;

      case '2':
        // 发送快捷键设置
        sendMessage(socket, createMessage('hotkey_setting', {
          mode: 'normal'
        }));
        break;

      case '3':
        // 发送快捷键设置结束
        sendMessage(socket, createMessage('hotkey_setting_end', {
          mode: 'normal',
          hotkey_combination: ['command', 'option', 'n']
        }));
        break;

      case '4':
      case 'quit':
      case 'exit':
        console.log('👋 退出服务器');
        socket.end();
        server.close();
        rl.close();
        return;

      default:
        console.log('❓ 未知命令');
    }

    rl.prompt();
  });

  rl.on('close', () => {
    socket.end();
    server.close();
  });
});

server.listen(SOCKET_PATH, () => {
  console.log('🚀 UDS Server 启动成功');
  console.log('📁 Socket 路径:', SOCKET_PATH);
  console.log('⌨️  等待客户端连接...\n');
});

// 优雅退出
process.on('SIGINT', () => {
  console.log('\n\n👋 正在关闭服务器...');
  server.close();
  if (fs.existsSync(SOCKET_PATH)) {
    fs.unlinkSync(SOCKET_PATH);
  }
  process.exit(0);
});

process.on('exit', () => {
  if (fs.existsSync(SOCKET_PATH)) {
    fs.unlinkSync(SOCKET_PATH);
  }
});
