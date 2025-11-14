#!/bin/bash
set -e

# 配置（使用环境变量）
: "${TUNNEL_MODE:=token}"
: "${TUNNEL_URL:=tcp://localhost:25565}"
: "${HF_PORT:=7860}"
: "${HF_HOST:=0.0.0.0}"

# 日志函数（立即刷新）
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

# ✅ 启动 Hugging Face 健康检查服务（必须最先启动）
start_hf_healthcheck() {
    log "[HF] 启动健康检查服务..."
    
    # 创建健康检查目录和文件
    mkdir -p /tmp/hf
    
    # 创建简单的 HTML 文件
    cat > /tmp/hf/index.html <<EOF
<!DOCTYPE html>
<html><head><title>Minecraft Server</title></head><body>
<h1>Minecraft Server with Cloudflare Tunnel</h1>
<p>Status: Running</p>
<p>Time: $(date)</p>
</body></html>
EOF
    
    # ✅ 使用 nohup 确保进程在后台持续运行
    cd /tmp/hf && nohup python3 -m http.server "$HF_PORT" --bind "$HF_HOST" > /tmp/hf_server.log 2>&1 &
    HF_PID=$!
    
    log "[HF] HTTP 服务器 PID: $HF_PID"
    
    # 等待服务启动（最多 10 秒）
    for i in {1..10}; do
        if ss -tuln 2>/dev/null | grep -q ":${HF_PORT}" || netstat -tuln 2>/dev/null | grep -q ":${HF_PORT}"; then
            log "[HF] ✅ 健康检查服务已启动在 $HF_HOST:$HF_PORT"
            return 0
        fi
        sleep 1
    done
    
    log "[HF] ❌ 健康检查服务启动失败！查看日志："
    cat /tmp/hf_server.log
    return 1
}

# 启动 API 服务器（可选，用于前端）
start_api_server() {
    log "[API] 启动 API 服务器..."
    
    # 创建前端目录
    mkdir -p /tmp/hf
    
    # 复制前端文件
    if [ -d "/tmp/hf/frontend" ]; then
        log "[API] 复制前端文件..."
        cp -r /tmp/hf/frontend/* /tmp/hf/
    fi
    
    # 安装依赖（如果未安装）
    if ! python3 -c "import flask, flask_cors" 2>/dev/null; then
        log "[API] 安装 Python 依赖..."
        pip3 install --user --no-cache-dir flask flask-cors > /tmp/pip_install.log 2>&1
    fi
    
    # 启动 API 服务器
    python3 /tmp/hf/api/server.py > /tmp/api_server.log 2>&1 &
    API_PID=$!
    
    log "[API] API 服务器 PID: $API_PID"
    
    # 等待服务启动（最多 10 秒）
    for i in {1..10}; do
        if curl -s "http://localhost:${HF_PORT}/api/status" >/dev/null 2>&1; then
            log "[API] ✅ API 服务器已启动"
            return 0
        fi
        
        if ! kill -0 "$API_PID" 2>/dev/null; then
            log "[API] ❌ API 服务器已退出"
            cat /tmp/api_server.log
            return 1
        fi
        
        sleep 1
    done
    
    log "[API] ❌ API 服务器启动超时"
    cat /tmp/api_server.log
    return 1
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
    log "[Shutdown] 收到关闭信号，优雅退出..."
    kill -TERM $HF_PID $MINECRAFT_PID $TUNNEL_PID 2>/dev/null || true
    wait $HF_PID $MINECRAFT_PID $TUNNEL_PID 2>/dev/null || true
    log "[Shutdown] 所有服务已停止"
    exit 0
}
trap cleanup TERM INT

# ✅ 启动顺序：健康检查 → Minecraft → Tunnel
start_hf_healthcheck
start_minecraft

# 等待 Minecraft 初始化（30 秒）
log "[Tunnel] 等待 Minecraft 服务器就绪..."
sleep 30

start_tunnel

# 保持运行并监控所有进程
log "[System] 所有服务已启动，保持运行..."
wait -n

# 如果到这里说明有进程异常退出
log "[ERROR] 一个服务已意外退出，正在关闭其他服务..."
kill $HF_PID $MINECRAFT_PID $TUNNEL_PID 2>/dev/null || true
wait 2>/dev/null || true
exit 1