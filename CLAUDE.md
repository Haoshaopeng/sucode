# sucode iOS 开发文档

## 必读：开发路径和文件位置

**项目路径**: `/Users/user/Documents/sucode/`
**代码文件**: `/Users/user/Documents/sucode/sucode/*.swift`

**重要**: 我通过 SSH 直接修改上述路径的文件，不需要手动同步！

---

## 常见错误总结

### 1. Exit code 2 (SSH/SCP 相关)

**原因**:
- 网络连接超时
- SSH 密钥问题
- 远程命令语法错误

**解决**:
```bash
# 测试 SSH 连接
ssh user@192.168.98.128 "echo test"
```

### 2. HEREDOC 语法错误

**原因**: Bash 中特殊字符转义问题

**解决**: 使用 SCP 文件传输代替直接 heredoc

### 3. 文件未同步 (最常见)

**原因**: 修改了共享文件夹，但 Xcode 打开的是本地 Documents

**解决**: 定死使用 `/Users/user/Documents/sucode/` 路径

### 4. 编译失败 - 找不到文件

**解决**:
1. 在 Xcode 中右键点击文件 → Delete → Remove References
2. 右键点击文件夹 → Add Files to sucode...
3. 重新选择文件

---

## 项目概述

sucode 是一个私人助手 iOS/iPadOS 应用，远程控制电脑和 VPS，支持 AI 对话。

---

**维护者**: Claude + 用户
**最后更新**: 2026-03-02
