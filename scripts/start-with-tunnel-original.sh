#!/bin/bash
set -e

# 配置
: "${TUNNEL_MODE:=token}"
: "${TUNNEL_URL:=tcp://localhost:25565}"
: "${HF_PORT:=7860}"
: "${HF_HOST:=0.0.0.0}"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

# ✅ 启动 API 服务器
start_api_server() {
    log "[API] 启动 API 服务器..."
    
    # 创建前端目录
    mkdir -p /tmp/hf
    
    # 复制前端文件
    if [ -d "/tmp/hf/frontend" ]; then
        log "[API] 复制前端文件..."
        cp -r /tmp/hf/frontend/* /tmp/hf/
    fi
    
    # ✅ 安装 Python 依赖（带重试）
    log "[API] 安装 Python 依赖..."
    for i in {1..3}; do
        if pip3 install --user --no-cache-dir flask flask-cors > /tmp/pip_install.log 2>&1; then
            log "[API] ✅ Python 依赖安装成功"
            break
        else
            log "[API] ❌ Python 依赖安装失败（尝试 $i/3）"
            cat /tmp/pip_install.log
            if [ $i -eq 3 ]; then
                log "[API] 安装失败，退出"
                exit 1
            fi
            sleep 5
        fi
    done
    
    # 启动 API 服务器
    log "[API] 启动 Python API 服务器..."
    nohup python3 /tmp/hf/api/server.py > /tmp/api_server.log 2>&1 &
    API_PID=$!
    
    log "[API] API 服务器 PID: $API_PID"
    
    # 等待服务启动
    sleep 5
    
    # 验证端口
    if ss -tuln 2>/dev/null | grep -q ":${HF_PORT}" || netstat -tuln 2>/dev/null | grep -q ":${HF_PORT}"; then
        log "[API] ✅ API 服务器已启动在 $HF_HOST:$HF_PORT"
        return 0
    else
        log "[API] ❌ API 服务器启动失败！查看日志："
        cat /tmp/api_server.log
        return 1
    fi
}

# ✅ 启动 Hugging Face 健康检查服务（通过 API 服务器提供）
start_hf_healthcheck() {
    log "[HF] 健康检查由 API 服务器提供..."
    # API 服务器已经运行在 7860 端口，无需额外启动
    return 0
}

# 启动 Minecraft 服务器
start_minecraft() {
    log "[Minecraft] 启动服务器..."
    /image/scripts/start &
    MINECRAFT_PID=$!
    log "[Minecraft] Minecraft PID: $MINECRAFT_PID"
    
    # 等待 Minecraft 初始化（最长 60 秒）
    log "[Minecraft] 等待服务器就绪..."
    for i in {1..60}; do
        if [ -f /data/logs/latest.log ]; then
            log "[Minecraft] ✅ 日志文件已创建..."
            break
        fi
        sleep 1
    done
    
    # 显示初始日志
    sleep 5
    if [ -f /data/logs/latest.log ]; then
        log "[Minecraft] 最新日志："
        tail -n 5 /data/logs/latest.log
    fi
}

# 启动 Cloudflare Tunnel
start_tunnel() {
    case "$TUNNEL_MODE" in
        token)
            if [ -z "$TUNNEL_TOKEN" ]; then
                log "[Tunnel] ❌ TUNNEL_TOKEN 环境变量未设置！"
                log "[Tunnel] 请在 Cloudflare Dashboard 创建 Tunnel 并获取 Token"
                exit 1
            fi
            log "[Tunnel] ✅ Token 模式启动..."
            nohup cloudflared tunnel run --token "$TUNNEL_TOKEN" > /tmp/tunnel.log 2>&1 &
            ;;
        legacy)
            log "[Tunnel] ✅ Legacy 模式启动..."
            nohup cloudflared tunnel --url "$TUNNEL_URL" > /tmp/tunnel.log 2>&1 &
            ;;
        *)
            log "[Tunnel] ❌ 未知的 TUNNEL_MODE: $TUNNEL_MODE"
            exit 1
            ;;
    esac
    TUNNEL_PID=$!
    log "[Tunnel] Tunnel PID: $TUNNEL_PID"
}

# 信号处理：优雅关闭
cleanup() {
    log "[Shutdown] 收到信号，优雅退出..."
    kill -TERM $API_PID $MINECRAFT_PID $TUNNEL_PID 2>/dev/null || true
    wait $API_PID $MINECRAFT_PID $TUNNEL_PID 2>/dev/null || true
    log "[Shutdown] 所有服务已停止"
    exit 0
}
trap cleanup TERM INT

# ✅ 启动顺序：API → Minecraft → Tunnel
start_api_server
start_minecraft

# 等待 Minecraft 初始化完成（30 秒）
log "[Tunnel] 等待 Minecraft 服务器就绪..."
sleep 30

start_tunnel

# 保持运行并监控所有进程
log "[System] 所有服务已启动，保持运行..."
wait -n

# 如果到这里说明有进程异常退出
log "[ERROR] 一个服务已意外退出，正在关闭其他服务..."
kill $API_PID $MINECRAFT_PID $TUNNEL_PID 2>/dev/null || true
wait 2>/dev/null || true
exit 1