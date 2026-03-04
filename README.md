# Sucode

🦞 **Sucode** - AI 集群管理与远程终端控制 iOS 应用

一句话介绍：用手机指挥多台电脑的 AI 团队，24小时为你干活。

---

## 📱 功能特性

### 🤖 AI 集群管理
- 同时管理 Windows、macOS、VPS 多端设备
- WebSocket 实时连接，状态即时同步
- 批量命令执行，一键操作多台设备

### 💻 远程终端
- 内置 WebSocket 终端 (xterm.js)
- 支持 Ctrl+C、Ctrl+D 等快捷键
- 命令历史、自动补全

### 🎯 AI 助手
- 集成 Kimi API (流式响应)
- 自然语言控制设备
- 任务自动拆解与执行

### 🎨 精美界面
- 全屏渐变背景 (SwiftUI)
- 自定义 TabBar
- 设备状态可视化
- 动画过渡效果

---

## 🏗️ 项目架构

```
sucode/
├── sucode/                    # iOS 应用源码 (SwiftUI)
│   ├── ContentView.swift      # 主界面 (自定义 TabBar)
│   ├── AIClusterView.swift    # AI 集群控制台
│   ├── DeviceListView.swift   # 设备列表
│   ├── TerminalView.swift     # 终端界面
│   ├── AIChatView.swift       # AI 对话
│   └── ...                    # 其他 27 个 Swift 文件
│
├── sucode.xcodeproj/          # Xcode 项目配置
├── bridge/                    # Python Bridge 服务
├── docs/                      # 项目文档
├── NMSSH/                     # SSH 库 (手动集成)
└── project_lobster_integration.md  # Project Lobster 整合方案
```

---

## 🛠️ 技术栈

| 层级 | 技术 |
|------|------|
| **前端** | SwiftUI、Combine、SwiftData |
| **网络** | WebSocket、URLSession |
| **终端** | WKWebView + xterm.js |
| **AI** | Kimi API (流式对话) |
| **SSH** | NMSSH (手动集成) |
| **后端** | Python Bridge (WebSocket) |

---

## 🚀 快速开始

### 要求
- iOS 16+
- Xcode 15+
- macOS 14+ (开发)

### 安装

```bash
# 克隆项目
git clone https://github.com/Haoshaopeng/sucode.git
cd sucode

# 打开 Xcode
open sucode.xcodeproj
```

### 配置

1. **设备配置**：在 `AIClusterManager.swift` 中修改设备 IP
   ```swift
   ClusterDevice(name: "Windows", host: "192.168.1.63", port: 8080)
   ClusterDevice(name: "macOS", host: "192.168.1.64", port: 8765)
   ClusterDevice(name: "VPS", host: "123.207.187.104", port: 8766)
   ```

2. **AI API**：在 `AIService.swift` 中配置 Kimi API Key

3. **Bridge 服务**：在各节点部署 Python Bridge
   ```bash
   cd bridge
   python bridge_server.py
   ```

---

## 🎯 使用场景

| 场景 | 操作 |
|------|------|
| **远程开发** | 手机下发命令，Windows/macOS/VPS 并行编码 |
| **服务器管理** | 一键查看三端状态，批量执行维护命令 |
| **AI 协作** | 自然语言描述任务，AI 自动拆解分配执行 |
| **实时监控** | 实时查看 CPU、内存、任务执行进度 |

---

## 📊 项目规模

- **代码文件**：32 个 Swift 文件
- **总代码量**：~20,000 行
- **项目大小**：53 MB
- **开发周期**：持续迭代中

---

## 🔮 未来规划

### Project Lobster 整合
正在整合 [Project Lobster](project_lobster_integration.md) 三级智能体架构：

```
用户 (iOS App)
    ↓
指挥官 (HierarchicalSwarm Director)
    ↓
调度官 (Windows/VPS/macOS Claude Code)
    ↓
执行层 (Agent Team)
```

实现目标：一句话同时操作三台设备，自动拆解、分配、执行、汇报。

---

## 🤝 贡献

这是一个个人项目，但欢迎提出建议和改进！

---

## 📄 许可证

MIT License

---

## 🔗 链接

- **GitHub**: https://github.com/Haoshaopeng/sucode
- **Gitee**: https://gitee.com/hao-shaopeng58/sucode

---

**Made with ❤️ by haoshaopeng**