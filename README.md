```markdown
---
title: Minecraft Server on Hugging Face
emoji: 🎮
colorFrom: green
colorTo: gray
sdk: docker
sdk_version: "latest"
app_file: start-with-tunnel.sh
pinned: false
---

# 🎮 Minecraft Server on Hugging Face Spaces

在 Hugging Face Spaces 上部署你的 Minecraft 服务器！利用 Cloudflare Tunnel 实现安全访问，无需暴露公网 IP。

## ✨ 特性

- 🚀 **零配置部署**：一键启动 Minecraft 服务器
- 🔒 **安全访问**：通过 Cloudflare Tunnel 安全连接
- 🌐 **全球可达**：无论你在哪里，都能连接到你的服务器
- 💾 **持久化存储**：使用 Hugging Face 的持久化存储保存你的世界
- 📊 **实时监控**：通过 Web 界面查看服务器状态和日志

## 🚀 快速开始

1. **Fork 这个 Space**
2. **配置环境变量**：
   - `EULA=TRUE` (必需)
   - `TYPE=PAPER` (服务器类型: VANILLA, PAPER, FORGE 等)
   - `VERSION=1.21` (游戏版本)
   - `MEMORY=4G` (分配内存)
   - `TUNNEL_TOKEN=your-token` (Cloudflare Tunnel Token)

3. **获取 Cloudflare Tunnel Token**：
   ```bash
   # 本地安装 cloudflared
   curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
   sudo dpkg -i cloudflared.deb
   
   # 登录并创建 Tunnel
   cloudflared tunnel login
   cloudflared tunnel create minecraft-server
   cloudflared tunnel route dns minecraft-server your-domain.com
   
   # 获取 Token
   cloudflared tunnel token minecraft-server
   ```

4. **启动 Space**：点击 "Restart this Space"

5. **连接服务器**：
   - 通过 Tunnel 提供的域名连接
   - 或使用 Legacy 模式的临时地址

## ⚙️ 配置选项

### Minecraft 服务器配置

| 环境变量 | 说明 | 默认值 |
|----------|------|--------|
| `EULA` | 接受 Minecraft EULA | `FALSE` (必需设置为 `TRUE`) |
| `TYPE` | 服务器类型 | `VANILLA` |
| `VERSION` | 游戏版本 | `LATEST` |
| `MEMORY` | 分配内存 | `1G` |
| `LEVEL` | 世界名称 | `world` |
| `DIFFICULTY` | 游戏难度 | `normal` |
| `MAX_PLAYERS` | 最大玩家数 | `20` |

### Cloudflare Tunnel 配置

| 环境变量 | 说明 | 默认值 |
|----------|------|--------|
| `TUNNEL_MODE` | Tunnel 模式 | `token` |
| `TUNNEL_TOKEN` | Cloudflare Tunnel Token | `""` (必需) |
| `TUNNEL_URL` | Legacy 模式 URL | `tcp://localhost:25565` |

### Hugging Face 配置

| 环境变量 | 说明 | 默认值 |
|----------|------|--------|
| `HF_PORT` | 健康检查端口 | `7860` |
| `HF_HOST` | 健康检查主机 | `0.0.0.0` |

## 🔧 技术架构

```
[Minecraft 客户端] ←TCP→ [Cloudflare Tunnel] ←WebSocket→ [Hugging Face Space]
                                                              ↓
                                                      [Docker Container]
                                                              ↓
                                                    [Minecraft Server]
                                                              ↓
                                                    [Cloudflare Tunnel]
                                                              ↓
                                                    [Hugging Face Storage]
```

## 📊 监控面板

访问你的 Space URL (例如 `https://huggingface.co/spaces/H-Chris233/HF-Pixeler`) 查看：
- 实时服务器状态
- 在线玩家列表
- 服务器日志
- 性能指标

## 🛠️ 故障排查

### 构建失败
- 确保所有大文件已添加到 Git LFS
- 检查 `.gitattributes` 配置

### 启动失败
- 检查 Runtime Logs
- 验证 `TUNNEL_TOKEN` 是否正确
- 确保 `EULA=TRUE`

### 连接失败
- 检查 Cloudflare Tunnel 状态
- 验证域名解析
- 查看服务器日志

## 📚 相关链接

- [Hugging Face Spaces](https://huggingface.co/spaces)
- [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [itzg/minecraft-server](https://github.com/itzg/docker-minecraft-server)
- [Minecraft Server Documentation](https://minecraft.fandom.com/wiki/Tutorials/Setting_up_a_server)

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

MIT License - 详见 LICENSE 文件

---

