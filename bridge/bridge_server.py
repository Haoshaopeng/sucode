#!/usr/bin/env python3
"""
Bridge Server - sucode iOS 远程管理桥接服务
支持 SSH/SFTP 配置管理、终端 WebSocket、Claude Code 集成
"""

import asyncio
import json
import os
import sys
from datetime import datetime
from functools import wraps
from typing import Optional

# 可选依赖：cryptography 用于密码加密
try:
    from cryptography.fernet import Fernet
    HAS_CRYPTO = True
except ImportError:
    HAS_CRYPTO = False
    print("Warning: cryptography not installed, passwords will be stored in plaintext")

# 配置
CONFIG_DIR = os.path.expanduser("~/.bridge")
CONFIG_FILE = os.path.join(CONFIG_DIR, "config.json")
DEFAULT_PORT = 8765

# 环境变量
API_KEY = os.environ.get("BRIDGE_API_KEY", "sucode-dev-key")
ENCRYPTION_KEY = os.environ.get("BRIDGE_ENCRYPTION_KEY")


def ensure_config_dir():
    """确保配置目录存在"""
    if not os.path.exists(CONFIG_DIR):
        os.makedirs(CONFIG_DIR, mode=0o700)


def get_default_config():
    """获取默认配置"""
    import platform

    system = platform.system().lower()
    hostname = platform.node()

    # 获取当前用户名
    username = os.environ.get("USER") or os.environ.get("USERNAME") or "root"

    return {
        "version": "1.0",
        "device": {
            "name": hostname,
            "platform": "macos" if system == "darwin" else ("windows" if system == "windows" else "linux"),
            "hostname": hostname
        },
        "ssh": {
            "enabled": True,
            "host": "127.0.0.1",
            "port": 22,
            "username": username,
            "auth_method": "password",
            "password": None,
            "private_key": None
        },
        "claude_code": {
            "enabled": True,
            "path": "/usr/local/bin/claude",
            "version": "2.2.5",
            "workspace": os.path.expanduser("~")
        },
        "capabilities": ["terminal", "claude_code", "sftp", "file_transfer"],
        "limits": {
            "max_upload_size": 100 * 1024 * 1024,  # 100MB
            "max_download_size": 100 * 1024 * 1024,
            "allowed_paths": ["/home", "/tmp", os.path.expanduser("~")]
        }
    }


def load_config():
    """加载配置文件"""
    ensure_config_dir()

    if os.path.exists(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, 'r') as f:
                config = json.load(f)
            # 合并默认配置（处理新增字段）
            default = get_default_config()
            default.update(config)
            return default
        except Exception as e:
            print(f"Error loading config: {e}")
            return get_default_config()
    else:
        # 创建默认配置文件
        config = get_default_config()
        save_config(config)
        return config


def save_config(config):
    """保存配置文件"""
    ensure_config_dir()
    try:
        with open(CONFIG_FILE, 'w') as f:
            json.dump(config, f, indent=2)
        os.chmod(CONFIG_FILE, 0o600)  # 限制文件权限
    except Exception as e:
        print(f"Error saving config: {e}")


def encrypt_value(value: str) -> str:
    """加密敏感值"""
    if not HAS_CRYPTO or not ENCRYPTION_KEY:
        return f"plaintext:{value}"

    try:
        f = Fernet(ENCRYPTION_KEY.encode())
        encrypted = f.encrypt(value.encode())
        return f"encrypted:{encrypted.decode()}"
    except Exception as e:
        print(f"Encryption error: {e}")
        return f"plaintext:{value}"


def decrypt_value(value: str) -> str:
    """解密敏感值"""
    if not value:
        return value

    if value.startswith("plaintext:"):
        return value[10:]

    if value.startswith("encrypted:"):
        if not HAS_CRYPTO or not ENCRYPTION_KEY:
            raise ValueError("Cannot decrypt: cryptography not available")

        try:
            encrypted_data = value[10:].encode()
            f = Fernet(ENCRYPTION_KEY.encode())
            return f.decrypt(encrypted_data).decode()
        except Exception as e:
            print(f"Decryption error: {e}")
            raise

    return value


# HTTP 服务器处理
class BridgeHTTPHandler:
    """Bridge HTTP API 处理器"""

    def __init__(self, config):
        self.config = config

    def check_auth(self, headers):
        """检查认证"""
        auth_header = headers.get('X-API-Key', '')
        return auth_header == API_KEY

    def handle_request(self, method, path, headers, body=None):
        """处理 HTTP 请求"""

        # CORS 头
        cors_headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, X-API-Key, X-API-Version',
            'Content-Type': 'application/json'
        }

        # OPTIONS 请求处理
        if method == 'OPTIONS':
            return (200, cors_headers, b'')

        # 公开端点（无需认证）
        if path == '/api/config/capabilities':
            return self.handle_capabilities(cors_headers)

        if path == '/api/health':
            return self.handle_health(cors_headers)

        # 需要认证的端点
        if not self.check_auth(headers):
            response = json.dumps({"error": "unauthorized", "message": "Invalid or missing API key"})
            return (401, cors_headers, response.encode())

        if path == '/api/config':
            if method == 'GET':
                return self.handle_get_config(cors_headers)
            elif method == 'POST':
                return self.handle_update_config(cors_headers, body)

        if path == '/api/config/refresh':
            return self.handle_refresh_config(cors_headers)

        # 404
        response = json.dumps({"error": "not_found", "message": "Endpoint not found"})
        return (404, cors_headers, response.encode())

    def handle_capabilities(self, cors_headers):
        """处理能力查询（公开）"""
        response = {
            "capabilities": self.config.get("capabilities", []),
            "version": self.config.get("version", "1.0"),
            "device": self.config.get("device", {}).get("name", "unknown")
        }
        return (200, cors_headers, json.dumps(response).encode())

    def handle_health(self, cors_headers):
        """处理健康检查"""
        response = {
            "status": "healthy",
            "timestamp": datetime.utcnow().isoformat() + 'Z',
            "version": self.config.get("version", "1.0")
        }
        return (200, cors_headers, json.dumps(response).encode())

    def handle_get_config(self, cors_headers):
        """处理获取配置"""
        # 重新加载配置以获取最新
        self.config = load_config()

        # 创建响应副本
        response_config = json.loads(json.dumps(self.config))

        # 添加时间戳
        response_config['timestamp'] = datetime.utcnow().isoformat() + 'Z'

        # 加密敏感字段
        ssh_config = response_config.get('ssh', {})
        if ssh_config.get('password'):
            ssh_config['password'] = encrypt_value(ssh_config['password'])
        if ssh_config.get('private_key'):
            ssh_config['private_key'] = encrypt_value(ssh_config['private_key'])

        return (200, cors_headers, json.dumps(response_config).encode())

    def handle_update_config(self, cors_headers, body):
        """处理更新配置"""
        if not body:
            response = json.dumps({"error": "bad_request", "message": "Missing request body"})
            return (400, cors_headers, response.encode())

        try:
            updates = json.loads(body)
            self.config.update(updates)
            save_config(self.config)

            response = json.dumps({"status": "ok", "message": "Configuration updated"})
            return (200, cors_headers, response.encode())
        except json.JSONDecodeError as e:
            response = json.dumps({"error": "bad_request", "message": f"Invalid JSON: {e}"})
            return (400, cors_headers, response.encode())

    def handle_refresh_config(self, cors_headers):
        """处理刷新配置"""
        self.config = load_config()
        response = json.dumps({"status": "ok", "message": "Configuration refreshed"})
        return (200, cors_headers, response.encode())


async def handle_http_request(reader, writer, handler):
    """处理 HTTP 请求"""
    try:
        # 读取请求行
        request_line = await reader.readline()
        request_line = request_line.decode().strip()

        if not request_line:
            return

        parts = request_line.split()
        if len(parts) < 3:
            return

        method, path, _ = parts

        # 读取请求头
        headers = {}
        while True:
            line = await reader.readline()
            if line == b'\r\n' or line == b'\n':
                break
            line = line.decode().strip()
            if ':' in line:
                key, value = line.split(':', 1)
                headers[key.strip()] = value.strip()

        # 读取请求体
        body = None
        content_length = int(headers.get('Content-Length', 0))
        if content_length > 0:
            body = await reader.read(content_length)
            body = body.decode()

        # 处理请求
        status, response_headers, response_body = handler.handle_request(method, path, headers, body)

        # 发送响应
        writer.write(f"HTTP/1.1 {status}\r\n".encode())
        for key, value in response_headers.items():
            writer.write(f"{key}: {value}\r\n".encode())
        writer.write(b"\r\n")
        writer.write(response_body if isinstance(response_body, bytes) else response_body.encode())
        await writer.drain()

    except Exception as e:
        print(f"HTTP request error: {e}")
    finally:
        writer.close()
        await writer.wait_closed()


async def start_server(port=DEFAULT_PORT):
    """启动 Bridge 服务器"""
    config = load_config()
    handler = BridgeHTTPHandler(config)

    server = await asyncio.start_server(
        lambda r, w: handle_http_request(r, w, handler),
        '0.0.0.0', port
    )

    print(f"🚀 Bridge Server running on http://0.0.0.0:{port}")
    print(f"   API Key: {API_KEY[:4]}...{API_KEY[-4:]}")
    print(f"   Config file: {CONFIG_FILE}")
    print(f"   Capabilities: {', '.join(config.get('capabilities', []))}")

    async with server:
        await server.serve_forever()


def setup_config():
    """交互式配置设置"""
    print("Bridge Server Configuration Setup")
    print("=" * 40)

    config = load_config()

    # SSH 配置
    print("\nSSH Configuration:")
    ssh = config['ssh']

    host = input(f"Host [{ssh['host']}]: ").strip()
    if host:
        ssh['host'] = host

    port = input(f"Port [{ssh['port']}]: ").strip()
    if port:
        ssh['port'] = int(port)

    username = input(f"Username [{ssh['username']}]: ").strip()
    if username:
        ssh['username'] = username

    password = input("Password (leave empty to keep current): ").strip()
    if password:
        ssh['password'] = password

    # Claude Code 配置
    print("\nClaude Code Configuration:")
    cc = config['claude_code']

    enabled = input(f"Enabled [{cc['enabled']}]: ").strip().lower()
    if enabled:
        cc['enabled'] = enabled in ('true', 'yes', '1', 'y')

    path = input(f"Path [{cc['path']}]: ").strip()
    if path:
        cc['path'] = path

    save_config(config)
    print(f"\n✅ Configuration saved to {CONFIG_FILE}")


def main():
    """主函数"""
    import argparse

    parser = argparse.ArgumentParser(description='Bridge Server for sucode')
    parser.add_argument('--port', '-p', type=int, default=DEFAULT_PORT, help='Server port')
    parser.add_argument('--setup', '-s', action='store_true', help='Run configuration setup')
    parser.add_argument('--show-config', action='store_true', help='Show current configuration')

    args = parser.parse_args()

    if args.setup:
        setup_config()
        return

    if args.show_config:
        config = load_config()
        # 隐藏密码
        if config['ssh'].get('password'):
            config['ssh']['password'] = '***'
        print(json.dumps(config, indent=2))
        return

    try:
        asyncio.run(start_server(args.port))
    except KeyboardInterrupt:
        print("\n👋 Bridge Server stopped")


if __name__ == '__main__':
    main()
