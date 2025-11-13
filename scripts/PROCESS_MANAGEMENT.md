# 进程管理改进说明

## 旧版本问题

### 致命缺陷
1. **无进程监控** - 只有 `wait -n`，不知道哪个进程挂了
2. **无自动重启** - 任何一个进程挂了，整个服务就全停了
3. **无健康检查** - 不知道服务是否真的在工作
4. **固定延迟** - 等30秒可能不够，也可能太长

## 新版本改进

### 🎯 核心改进

**1. 进程状态监控**
- 每30秒检查所有进程状态
- 区分"进程存在"和"服务正常"
- 详细的错误日志和状态报告

**2. 健康检查机制**
```bash
# API健康检查：实际调用接口
check_api_health() {
    curl -s "http://localhost:${HF_PORT}/api/status" >/dev/null 2>&1
}

# Minecraft健康检查：进程+日志活动
check_minecraft_health() {
    # 检查进程是否存在
    # 检查最近5分钟是否有日志输出
}

# Tunnel健康检查：进程存在即可
check_tunnel_health() {
    is_process_running "${PIDS[tunnel]}"
}
```

**3. 自动重启机制**
- 检测到异常立即重启
- 启动失败自动重试（最多3次）
- 重启顺序：先停进程，等3秒再启动

**4. 优雅关闭**
- 按相反顺序停止：Tunnel → Minecraft → API
- 先发TERM信号等待10秒
- 超时强制KILL

### 🔧 技术细节

**进程跟踪**
```bash
declare -A PIDS              # 存储进程ID
declare -A PROCESS_NAMES     # 存储进程名称
declare -A LAST_HEALTH_CHECK # 存储最后检查时间
```

**启动流程**
1. API 服务器（带健康检查）
2. Minecraft 服务器（等待最多2分钟）
3. Cloudflare Tunnel（快速启动）
4. 进入监控循环

**监控循环**
```bash
monitor_processes() {
    while true; do
        sleep 30  # 每30秒检查一次

        # 检查API健康状态
        # 检查Minecraft健康状态
        # 检查Tunnel健康状态

        # 如果异常，自动重启
        # 记录状态日志
    done
}
```

## 使用方法

### 1. 替换启动脚本
```bash
# 在Dockerfile或docker-compose中修改启动命令
CMD ["/scripts/start-with-tunnel-v2.sh"]
```

### 2. 监控日志
```bash
# 查看启动日志
tail -f /tmp/api_server.log
tail -f /tmp/minecraft.log
tail -f /tmp/tunnel.log

# 查看系统日志
docker logs <container_id>
```

### 3. 手动测试
```bash
# 测试API健康检查
curl http://localhost:7860/api/status

# 检查进程状态
ps aux | grep -E "(python|minecraft|cloudflared)"

# 模拟进程崩溃
kill -9 <python_pid>  # 应该会自动重启
```

## 预期效果

### 稳定性提升
- **自动恢复** - 任何进程崩溃都会自动重启
- **早期发现** - 30秒内发现服务异常
- **详细日志** - 便于问题诊断

### 可靠性增强
- **启动重试** - 启动失败自动重试3次
- **健康检查** - 区分进程存在和服务正常
- **优雅关闭** - 正确处理容器停止信号

### 运维友好
- **状态透明** - 定期输出所有服务状态
- **问题定位** - 详细的错误信息和日志
- **手动干预** - 支持手动停止/启动服务

## 注意事项

1. **资源消耗** - 监控循环会消耗少量CPU（约0.1%）
2. **重启延迟** - 异常重启会有3-30秒服务中断
3. **日志增长** - 需要定期清理日志文件
4. **依赖检查** - 确保curl命令可用

## 故障排除

### API服务器频繁重启
- 检查端口7860是否被占用
- 检查Python依赖是否正确安装
- 查看`/tmp/api_server.log`错误信息

### Minecraft服务器无法启动
- 检查内存配置是否足够
- 查看Minecraft日志`/tmp/minecraft.log`
- 检查EULA设置

### Tunnel连接失败
- 验证TUNNEL_TOKEN是否正确
- 检查网络连接
- 查看Cloudflare日志`/tmp/tunnel.log`