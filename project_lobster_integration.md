# Project Lobster + Sucode + Swarms 整合方案

## 一、架构对比分析

### 1.1 三种架构对比

| 维度 | Project Lobster (设计) | Sucode (已实现) | Swarms HierarchicalSwarm |
|------|------------------------|-----------------|--------------------------|
| **层级** | L0用户→L1指挥官→L2调度官→L3执行 | App→设备列表→终端 | Director→Workers |
| **通信** | WebSocket长连接 | WebSocket终端 | 函数调用 |
| **执行实体** | Claude Code实例 | Bridge服务 | Python Agent对象 |
| **位置** | 服务端+客户端 | iOS客户端 | Python库 |
| **监控** | 实时监控面板 | 设备状态显示 | 日志输出 |
| **横向通信** | Agent之间直接通信 | 无 | Director中转 |

### 1.2 核心问题识别

**问题1：层级不匹配**
- Lobster想要4层，Swarms只提供2层
- 需要映射：L2调度官 = Swarms Workers，L1指挥官 = Swarms Director

**问题2：执行实体差异**
- Lobster想用 Claude Code CLI（外部进程）
- Swarms Agent是Python对象（内部实例）
- 需要桥接：Python Agent → SSH/CLI调用 Claude Code

**问题3：通信协议**
- Lobster/Web/Swarms都没有原生WebSocket实时推送
- 需要添加 WebSocket 层包装 Swarms

**问题4：客户端集成**
- Sucode 是 iOS SwiftUI App
- 需要让它成为 Lobster 的 L0 入口

---

## 二、整合方案：三层架构建模

### 2.1 整体架构图

```
┌─────────────────────────────────────────────────────────────────┐
│                     L0: 用户层 (Sucode iOS App)                   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │  Dashboard   │  │ AI Cluster   │  │ Terminal/WebSocket   │  │
│  │   (首页)      │  │  (设备管理)   │  │    (终端控制)         │  │
│  └──────────────┘  └──────────────┘  └──────────────────────┘  │
│                         ↑ WebSocket ↓                           │
└─────────────────────────┬───────────────────────────────────────┘
                          │
┌─────────────────────────▼───────────────────────────────────────┐
│               L1: 指挥官层 (HierarchicalSwarm Director)          │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Swarms HierarchicalSwarm (Python Server on VPS:8765)    │   │
│  │  - 任务拆解 planning_enabled=True                        │   │
│  │  - 动态调整 max_loops=5                                  │   │
│  │  - 状态聚合 streaming_callback → WebSocket → iOS         │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────┬───────────────────────────────────────┘
                          │ 分配任务 (通过SSH/API调用)
          ┌───────────────┼───────────────┐
          ↓               ↓               ↓
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│   L2: Windows   │ │   L2: VPS       │ │   L2: macOS     │
│   调度官节点      │ │   调度官节点      │ │   调度官节点      │
│                 │ │                 │ │                 │
│  ┌───────────┐  │ │  ┌───────────┐  │ │  ┌───────────┐  │
│  │ ClaudeCode│  │ │  │ ClaudeCode│  │ │  │ ClaudeCode│  │
│  │  Bridge   │  │ │  │  Bridge   │  │ │  │  Bridge   │  │
│  │  (8765)   │  │ │  │  (8766)   │  │ │  │  (8767)   │  │
│  └───────────┘  │ │  └───────────┘  │ │  └───────────┘  │
│                 │ │                 │ │                 │
│  ┌───────────┐  │ │  ┌───────────┐  │ │  ┌───────────┐  │
│  │ Agent Team│  │ │  │ Agent Team│  │ │  │ Agent Team│  │
│  │ (内部进程) │  │ │  │ (内部进程) │  │ │  │ (内部进程) │  │
│  │ - UI任务  │  │ │  │ - API任务 │  │ │  │ - 测试任务│  │
│  │ - 本地文件│  │ │  │ - 模型推理│  │ │  │ - 文档任务│  │
│  └───────────┘  │ │  └───────────┘  │ │  └───────────┘  │
└─────────────────┘ └─────────────────┘ └─────────────────┘
          │               │               │
          └───────────────┴───────────────┘
                          │
                    横向通信 (通过主Director中转)
```

### 2.2 关键映射关系

| Lobster 概念 | Swarms 对应 | Sucode 对应 | 实现方式 |
|-------------|-------------|-------------|----------|
| L1 指挥官 | HierarchicalSwarm Director | AIClusterManager | Python服务端 |
| L2 调度官 | Swarm Worker Agents | ClusterDevice | SSH调用Claude Code |
| L3 执行层 | Agent Tools/Functions | TerminalView | Claude Code内部Agent |
| 实时监控 | streaming_callback | WebSocketClient | 自定义WebSocket中间件 |
| 横向通信 | Agent间消息传递 | 无（需新增） | 通过Director中转 |

---

## 三、具体实施方案

### 3.1 服务端部署 (VPS: 123.207.187.104)

#### 步骤1：部署 WebSocket 通信中枢

```python
# /root/lobster/hub.py - WebSocket通信中枢
import asyncio
import websockets
import json
from typing import Dict, Set
from datetime import datetime

class LobsterCommunicationHub:
    """
    Lobster 通信中枢
    - 管理所有 Agent 长连接
    - 转发 Swarms Director 的 streaming_callback
    - 接收 iOS App 的指令下发
    """

    def __init__(self):
        self.agents: Dict[str, websockets.WebSocketServerProtocol] = {}
        self.ios_clients: Set[websockets.WebSocketServerProtocol] = set()
        self.agent_states: Dict[str, dict] = {}
        self.message_history = []

    async def register(self, websocket, path):
        """注册新连接"""
        try:
            # 接收注册信息
            msg = await websocket.recv()
            data = json.loads(msg)
            client_type = data.get('type')  # 'agent', 'ios', 'director'

            if client_type == 'ios':
                self.ios_clients.add(websocket)
                print(f"📱 iOS App 已连接")
                await self.send_to_ios({'type': 'connected', 'agents': list(self.agents.keys())})

            elif client_type == 'agent':
                agent_name = data['name']
                self.agents[agent_name] = websocket
                self.agent_states[agent_name] = {
                    'status': 'online',
                    'connected_at': datetime.now().isoformat(),
                    'type': data.get('agent_type', 'worker'),
                    'node': data.get('node', 'unknown')
                }
                print(f"🤖 Agent {agent_name} 已连接")
                await self.broadcast_to_ios({'type': 'agent_online', 'agent': agent_name})

            elif client_type == 'director':
                print(f"👑 Director 已连接")

            # 保持连接并处理消息
            async for message in websocket:
                await self.route_message(websocket, message)

        except websockets.exceptions.ConnectionClosed:
            await self.unregister(websocket)

    async def route_message(self, websocket, message):
        """路由消息"""
        data = json.loads(message)
        msg_type = data.get('type')

        if msg_type == 'swarm_streaming':
            # Swarms Director 的 streaming_callback
            # 转发给所有 iOS 客户端
            await self.broadcast_to_ios({
                'type': 'streaming',
                'agent': data.get('agent_name'),
                'chunk': data.get('chunk'),
                'is_final': data.get('is_final')
            })

        elif msg_type == 'task_request':
            # iOS App 下发的任务
            # 转发给 Director
            await self.send_to_director(data)

        elif msg_type == 'peer_message':
            # Agent 间横向通信
            to_agent = data['to']
            if to_agent in self.agents:
                await self.agents[to_agent].send(json.dumps({
                    'type': 'peer',
                    'from': data['from'],
                    'message': data['message']
                }))

        elif msg_type == 'status_update':
            # Agent 状态更新
            agent_name = data['agent']
            self.agent_states[agent_name].update(data['state'])
            await self.broadcast_to_ios({
                'type': 'status',
                'agent': agent_name,
                'state': data['state']
            })

    async def broadcast_to_ios(self, message):
        """广播给所有 iOS 客户端"""
        dead_clients = set()
        for client in self.ios_clients:
            try:
                await client.send(json.dumps(message))
            except:
                dead_clients.add(client)
        self.ios_clients -= dead_clients

    async def send_to_director(self, message):
        """发送给 Director"""
        # 实现Director连接逻辑
        pass

    async def unregister(self, websocket):
        """注销连接"""
        if websocket in self.ios_clients:
            self.ios_clients.remove(websocket)
        for name, conn in list(self.agents.items()):
            if conn == websocket:
                del self.agents[name]
                self.agent_states[name]['status'] = 'offline'
                await self.broadcast_to_ios({'type': 'agent_offline', 'agent': name})

    async def start(self, host="0.0.0.0", port=8765):
        async with websockets.serve(self.register, host, port):
            print(f"🚀 Lobster Hub 启动: ws://{host}:{port}")
            await asyncio.Future()

if __name__ == "__main__":
    hub = LobsterCommunicationHub()
    asyncio.run(hub.start())
```

#### 步骤2：部署 HierarchicalSwarm Director

```python
# /root/lobster/director.py - Swarms 指挥官
import asyncio
import websockets
import json
from swarms import Agent
from swarms.structs.hiearchical_swarm import HierarchicalSwarm

class LobsterDirector:
    """
    Lobster L1 指挥官
    - 包装 HierarchicalSwarm
    - 通过 WebSocket 与 Hub 通信
    - 通过 SSH 调用远端 Claude Code
    """

    def __init__(self, hub_ws_url="ws://localhost:8765"):
        self.hub_url = hub_ws_url
        self.swarm = None
        self.agents = {}

    def create_node_agent(self, node_name, host, port, role):
        """创建节点 Agent（映射到远端 Claude Code）"""

        def execute_on_node(task: str) -> str:
            """通过 SSH 在远端节点执行 Claude Code"""
            import paramiko

            ssh = paramiko.SSHClient()
            ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())

            try:
                # 使用密钥连接
                ssh.connect(host, port=22, username='user', key_filename='~/.ssh/lobster_key')

                # 调用 Claude Code
                stdin, stdout, stderr = ssh.exec_command(
                    f'cd ~/claude_workspace && echo "{task}" | claude code --stdin'
                )
                result = stdout.read().decode()
                error = stderr.read().decode()

                ssh.close()

                return result if result else error

            except Exception as e:
                return f"Error: {str(e)}"

        return Agent(
            agent_name=f"{node_name}-Dispatcher",
            agent_description=f"{node_name} 节点调度官，负责 {role}",
            system_prompt=f"""你是 Lobster 系统的 {node_name} 节点调度官。
            你的职责：
            1. 接收指挥官分配的任务
            2. 使用本地 Claude Code 执行具体工作
            3. 实时上报执行进度和结果
            4. 与其他节点的调度官协作

            节点定位：{role}
            工作目录：~/claude_workspace
            """,
            model_name="gpt-4o",  # Director用GPT-4o做决策
            function=execute_on_node
        )

    def initialize_swarm(self):
        """初始化三级 Swarm"""

        # 创建三个 L2 调度官（对应三个节点）
        windows_agent = self.create_node_agent(
            "Windows", "192.168.1.63", 8080, "UI开发、本地文件操作"
        )

        vps_agent = self.create_node_agent(
            "VPS", "123.207.187.104", 8766, "后端API、数据库、模型推理"
        )

        macos_agent = self.create_node_agent(
            "macOS", "192.168.1.64", 8765, "测试、文档、iOS相关"
        )

        self.agents = {
            'Windows': windows_agent,
            'VPS': vps_agent,
            'macOS': macos_agent
        }

        # 创建 HierarchicalSwarm
        self.swarm = HierarchicalSwarm(
            name="Lobster-Three-Node-Swarm",
            description="Windows/VPS/macOS 三级协同系统",
            agents=[windows_agent, vps_agent, macos_agent],
            max_loops=5,           # 最多5轮反馈
            planning_enabled=True,  # 启用任务规划
            output_type="dict",
            verbose=True
        )

    async def connect_to_hub(self):
        """连接到通信中枢"""
        async with websockets.connect(self.hub_url) as ws:
            # 注册为 Director
            await ws.send(json.dumps({'type': 'director', 'name': 'Lobster-Director'}))

            # 包装 streaming_callback 到 WebSocket
            self.swarm.streaming_callback = lambda agent, chunk, final: asyncio.create_task(
                self.send_streaming(ws, agent, chunk, final)
            )

            # 监听来自 iOS 的任务
            async for message in ws:
                data = json.loads(message)
                if data.get('type') == 'task_request':
                    await self.handle_task(data['task'])

    async def send_streaming(self, ws, agent_name, chunk, is_final):
        """发送流式更新到 Hub"""
        await ws.send(json.dumps({
            'type': 'swarm_streaming',
            'agent_name': agent_name,
            'chunk': chunk,
            'is_final': is_final
        }))

    async def handle_task(self, task: str):
        """处理任务"""
        print(f"🎯 收到任务: {task}")
        result = self.swarm.run(task=task)
        print(f"✅ 任务完成")
        return result

    def run(self):
        self.initialize_swarm()
        asyncio.run(self.connect_to_hub())

if __name__ == "__main__":
    director = LobsterDirector()
    director.run()
```

#### 步骤3：部署节点 Agent

```python
# /root/lobster/node_agent.py - 节点端 Agent
import asyncio
import websockets
import json
import subprocess
import platform
import psutil
from datetime import datetime

class LobsterNodeAgent:
    """
    Lobster L2 调度官
    - 运行在每个节点上（Windows/VPS/macOS）
    - 本地执行 Claude Code
    - 上报状态到 Hub
    """

    def __init__(self, node_name, hub_url="ws://123.207.187.104:8765"):
        self.node_name = node_name
        self.hub_url = hub_url
        self.current_task = None
        self.task_history = []

    async def connect(self):
        """连接到 Hub"""
        async with websockets.connect(self.hub_url) as ws:
            # 注册
            await ws.send(json.dumps({
                'type': 'agent',
                'name': self.node_name,
                'agent_type': 'dispatcher',
                'node': platform.node(),
                'system': platform.system()
            }))

            # 启动状态上报循环
            asyncio.create_task(self.status_reporter(ws))

            # 处理消息
            async for message in ws:
                await self.handle_message(ws, message)

    async def status_reporter(self, ws):
        """定期上报状态"""
        while True:
            await asyncio.sleep(5)
            status = {
                'type': 'status_update',
                'agent': self.node_name,
                'state': {
                    'cpu': psutil.cpu_percent(),
                    'memory': psutil.virtual_memory().percent,
                    'current_task': self.current_task,
                    'timestamp': datetime.now().isoformat()
                }
            }
            try:
                await ws.send(json.dumps(status))
            except:
                break

    async def handle_message(self, ws, message):
        """处理消息"""
        data = json.loads(message)
        msg_type = data.get('type')

        if msg_type == 'task':
            # 执行本地任务
            result = await self.execute_task(data['task'])
            await ws.send(json.dumps({
                'type': 'task_result',
                'agent': self.node_name,
                'result': result
            }))

        elif msg_type == 'peer':
            # 处理来自其他 Agent 的消息
            print(f"📨 收到来自 {data['from']}: {data['message']}")
            # 可以回复或转发

    async def execute_task(self, task: str) -> dict:
        """本地执行 Claude Code"""
        self.current_task = task[:50]

        try:
            # 调用 Claude Code CLI
            process = subprocess.Popen(
                ['claude', 'code', task],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                cwd=f'~/claude_workspace'
            )

            stdout, stderr = process.communicate(timeout=600)  # 10分钟超时

            self.task_history.append({
                'task': task,
                'timestamp': datetime.now().isoformat(),
                'success': process.returncode == 0
            })

            self.current_task = None

            return {
                'success': process.returncode == 0,
                'output': stdout,
                'error': stderr,
                'node': self.node_name
            }

        except subprocess.TimeoutExpired:
            process.kill()
            self.current_task = None
            return {'success': False, 'error': 'Timeout'}
        except Exception as e:
            self.current_task = None
            return {'success': False, 'error': str(e)}

if __name__ == "__main__":
    import sys
    node = sys.argv[1] if len(sys.argv) > 1 else "Unknown"
    agent = LobsterNodeAgent(node)
    asyncio.run(agent.connect())
```

### 3.2 Sucode iOS 端改造

#### 修改1：AIClusterManager 添加 Lobster 支持

```swift
// AIClusterManager.swift - 添加 Lobster 集成

import Foundation
import Combine

class LobsterClient: ObservableObject {
    @Published var isConnected = false
    @Published var streamingText = ""
    @Published var agentStates: [String: AgentState] = [:]

    private var webSocketTask: URLSessionWebSocketTask?
    private let hubURL = "ws://123.207.187.104:8765"

    // MARK: - Connection

    func connect() {
        guard let url = URL(string: hubURL) else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        webSocketTask = URLSession.shared.webSocketTask(with: request)
        webSocketTask?.resume()

        // 发送注册信息
        send(message: [
            "type": "ios",
            "device": "iPhone",
            "timestamp": Date().timeIntervalSince1970
        ])

        receiveMessage()
    }

    // MARK: - Send Task

    func sendTask(_ task: String) {
        send(message: [
            "type": "task_request",
            "task": task,
            "timestamp": Date().timeIntervalSince1970
        ])
        streamingText = ""
    }

    // MARK: - Send Message

    private func send(message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let json = String(data: data, encoding: .utf8) else { return }

        webSocketTask?.send(.string(json)) { error in
            if let error = error {
                print("Send error: \(error)")
            }
        }
    }

    // MARK: - Receive

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                self?.handleMessage(message)
                self?.receiveMessage() // Continue receiving

            case .failure(let error):
                print("WebSocket error: \(error)")
                self?.isConnected = false
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        guard case .string(let text) = message,
              let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        DispatchQueue.main.async {
            let msgType = json["type"] as? String

            switch msgType {
            case "streaming":
                // Swarms streaming callback
                if let chunk = json["chunk"] as? String {
                    self.streamingText += chunk
                }

            case "status":
                // Agent 状态更新
                if let agent = json["agent"] as? String,
                   let state = json["state"] as? [String: Any] {
                    self.agentStates[agent] = AgentState(
                        name: agent,
                        cpu: state["cpu"] as? Double ?? 0,
                        memory: state["memory"] as? Double ?? 0,
                        currentTask: state["current_task"] as? String
                    )
                }

            case "agent_online", "agent_offline":
                // Agent 上下线
                let agent = json["agent"] as? String ?? ""
                let online = (msgType == "agent_online")
                // 更新 UI

            default:
                break
            }
        }
    }
}

// MARK: - Agent State

struct AgentState: Identifiable {
    let id = UUID()
    let name: String
    let cpu: Double
    let memory: Double
    let currentTask: String?

    var statusColor: Color {
        if cpu > 80 || memory > 80 { return .red }
        if currentTask != nil { return .green }
        return .gray
    }
}
```

#### 修改2：AIClusterView 添加 Lobster 控制台

```swift
// AIClusterView.swift - 添加 Lobster 任务控制台

struct LobsterControlPanel: View {
    @StateObject private var lobster = LobsterClient()
    @State private var taskInput = ""
    @State private var taskHistory: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            // 状态栏
            statusBar

            // Agent 状态矩阵
            agentMatrix

            Divider().background(Color.white.opacity(0.1))

            // 任务输入
            taskInputArea

            // 流式输出显示
            streamingOutput
        }
        .background(Color.black)
        .onAppear {
            lobster.connect()
        }
    }

    private var statusBar: some View {
        HStack {
            Circle()
                .fill(lobster.isConnected ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            Text(lobster.isConnected ? "Lobster 在线" : "连接中...")
                .font(.caption)
                .foregroundColor(.white)

            Spacer()

            Text("\(lobster.agentStates.count) 个 Agent")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding()
        .background(Color(hex: "1a1a2e"))
    }

    private var agentMatrix: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(lobster.agentStates.values)) { state in
                    AgentStatusCard(state: state)
                }
            }
            .padding(.horizontal)
        }
        .frame(height: 100)
        .background(Color(hex: "16213e"))
    }

    private var taskInputArea: some View {
        VStack(spacing: 8) {
            TextField("输入任务指令...", text: $taskInput, axis: .vertical)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .lineLimit(3...6)
                .padding(.horizontal)

            Button(action: sendTask) {
                HStack {
                    Image(systemName: "paperplane.fill")
                    Text("下发任务")
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .cornerRadius(8)
            }
            .disabled(taskInput.isEmpty || !lobster.isConnected)
            .padding(.horizontal)
        }
        .padding(.vertical)
    }

    private var streamingOutput: some View {
        ScrollView {
            Text(lobster.streamingText)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.green)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .background(Color.black)
    }

    private func sendTask() {
        guard !taskInput.isEmpty else { return }
        lobster.sendTask(taskInput)
        taskHistory.append(taskInput)
        taskInput = ""
    }
}

// MARK: - Agent Status Card

struct AgentStatusCard: View {
    let state: AgentState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(state.statusColor)
                    .frame(width: 8, height: 8)

                Text(state.name)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }

            HStack {
                Label("\(Int(state.cpu))%", systemImage: "cpu")
                Label("\(Int(state.memory))%", systemImage: "memorychip")
            }
            .font(.caption2)
            .foregroundColor(.gray)

            if let task = state.currentTask {
                Text(task)
                    .font(.caption2)
                    .foregroundColor(.green)
                    .lineLimit(1)
            }
        }
        .padding()
        .frame(width: 140)
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(state.statusColor.opacity(0.3), lineWidth: 1)
        )
    }
}
```

---

## 四、部署脚本

### 4.1 一键部署脚本

```bash
#!/bin/bash
# deploy_lobster.sh - 在 VPS 上运行

set -e

echo "🦞 Project Lobster 部署脚本"

# 1. 安装依赖
echo "📦 安装 Python 依赖..."
pip install swarms websockets paramiko psutil

# 2. 创建工作目录
mkdir -p ~/lobster/{logs,workspace}
cd ~/lobster

# 3. 下载代码文件（假设已上传）
# hub.py, director.py, node_agent.py

# 4. 启动 Hub（后台运行）
echo "🚀 启动通信中枢..."
nohup python hub.py > logs/hub.log 2>&1 &
echo $! > hub.pid

# 5. 启动 Director
echo "👑 启动指挥官..."
nohup python director.py > logs/director.log 2>&1 &
echo $! > director.pid

# 6. 检查状态
sleep 2
echo "📊 检查服务状态..."
ps aux | grep -E "hub.py|director.py" | grep -v grep

echo "✅ 部署完成！"
echo ""
echo "Hub 日志: tail -f ~/lobster/logs/hub.log"
echo "Director 日志: tail -f ~/lobster/logs/director.log"
```

### 4.2 节点启动脚本

```bash
#!/bin/bash
# start_node.sh - 在各节点运行

NODE_NAME=$1
HUB_URL=${2:-"ws://123.207.187.104:8765"}

if [ -z "$NODE_NAME" ]; then
    echo "Usage: ./start_node.sh <node_name> [hub_url]"
    echo "Example: ./start_node.sh Windows"
    exit 1
fi

echo "🤖 启动 Lobster 节点: $NODE_NAME"
nohup python node_agent.py "$NODE_NAME" > "logs/$NODE_NAME.log" 2>&1 &
echo $! > "logs/$NODE_NAME.pid"
echo "✅ 节点 $NODE_NAME 已启动"
```

---

## 五、验证测试

### 测试1：基础连通性
```bash
# 在 iOS App 中查看 Agent 列表
# 应该显示: Windows, VPS, macOS 三个节点在线
```

### 测试2：单节点任务
```
任务: "Windows节点，创建一个叫hello.txt的文件，内容是Hello from Lobster"
预期: Windows节点执行，返回文件创建成功
```

### 测试3：多节点协同
```
任务: "开发一个简单Web应用：Windows负责前端HTML，VPS负责后端Python API，macOS负责测试"
预期:
- Swarms Director 拆解为3个子任务
- 并行分发给三个节点
- 流式输出显示在各节点执行进度
- 最终返回完整项目代码
```

### 测试4：实时监控
```
任务: "长时间运行的训练任务，监控各节点CPU/内存"
预期: iOS App 实时显示资源占用曲线
```

---

## 六、与现有 Sucode 的整合点

| Sucode 现有功能 | Lobster 整合方案 |
|----------------|------------------|
| AIClusterView | 添加 LobsterControlPanel Tab |
| DeviceListView | 保持现有 WebSocket 终端 |
| TerminalView | 用于调试，Lobster 用于批量任务 |
| AIChatView | 聊天消息可直接作为 Lobster 任务下发 |
| DataPersistenceManager | 保存 Lobster 任务历史 |

---

## 七、关键设计决策

1. **为什么选择 Swarms HierarchicalSwarm？**
   - 成熟的企业级框架
   - 内置 planning_enabled 和 max_loops
   - streaming_callback 支持实时流式输出

2. **为什么需要 WebSocket Hub？**
   - Swarms 原生不支持 WebSocket
   - 需要桥接 Python 服务端和 iOS 客户端
   - 实现实时监控和横向通信

3. **为什么用 SSH 调用 Claude Code？**
   - Claude Code 是 CLI 工具，非 Python 库
   - SSH 是最简单的跨节点调用方式
   - 可以利用现有的 SSH 密钥配置

4. **如何处理横向通信？**
   - Lobster 设计：Agent 直接通信
   - 实际实现：通过 Director 中转（更安全、可监控）
   - 如需直接通信，可扩展 Hub 支持 P2P 路由

---

## 八、下一步行动

1. **立即执行**：在 VPS 部署 hub.py 和 director.py
2. **并行执行**：在三个节点部署 node_agent.py
3. **iOS 开发**：将 LobsterClient 集成到 Sucode
4. **测试验证**：运行上述4个测试用例
5. **优化迭代**：根据实际使用调整 max_loops、超时等参数

需要我为某个具体部分提供更详细的代码吗？
