# Bridge Server 配置

## 快速开始

### 1. 安装依赖

```bash
# Python 3.7+ 必需
python3 --version

# 安装可选依赖（用于密码加密）
pip3 install cryptography
```

### 2. 首次配置

```bash
cd /Users/user/Documents/sucode/bridge

# 运行配置向导
python3 bridge_server.py --setup
```

配置向导会提示输入：
- SSH 主机地址
- SSH 端口（默认 22）
- SSH 用户名
- SSH 密码
- Claude Code 启用状态

### 3. 启动服务器

```bash
# 默认端口 8765
python3 bridge_server.py

# 指定端口
python3 bridge_server.py --port 8766
```

### 4. 查看配置

```bash
python3 bridge_server.py --show-config
```

---

## 环境变量

| 变量名 | 说明 | 默认值 |
|--------|------|--------|
| `BRIDGE_API_KEY` | API 认证密钥 | `sucode-dev-key` |
| `BRIDGE_ENCRYPTION_KEY` | 密码加密密钥 | 无（明文存储） |

### 生成加密密钥

```bash
pip3 install cryptography
python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
```

---

## API 端点

### GET /api/config/capabilities
获取设备能力（无需认证）

### GET /api/config
获取完整配置（需要 X-API-Key）

### GET /api/health
健康检查

---

## 开机自启

### macOS (launchd)

创建 `~/Library/LaunchAgents/com.sucode.bridge.plist`，然后：
```bash
launchctl load ~/Library/LaunchAgents/com.sucode.bridge.plist
```

### Linux (systemd)

创建 `/etc/systemd/system/sucode-bridge.service`，然后：
```bash
sudo systemctl enable sucode-bridge
sudo systemctl start sucode-bridge
```

---

## 安全建议

1. 修改默认 API Key
2. 启用密码加密（安装 cryptography）
3. 限制配置文件权限：`chmod 600 ~/.bridge/config.json`
4. 使用防火墙限制访问
