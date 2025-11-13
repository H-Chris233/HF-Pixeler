#!/bin/bash
set -e

# 配置
: "${TUNNEL_MODE:=legacy}"
: "${TUNNEL_URL:=tcp://localhost:25565}"
: "${HF_PORT:=7860}"
: "${HF_HOST:=0.0.0.0}"

# 进程状态跟踪
declare -A PIDS
declare -A PROCESS_NAMES
declare -A LAST_HEALTH_CHECK

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

# 错误日志
error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

# 进程状态检查
is_process_running() {
    local pid=$1
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

# 健康检查函数
check_api_health() {
    curl -s "http://localhost:${HF_PORT}/api/status" >/dev/null 2>&1
}

check_minecraft_health() {
    # 检查进程是否存在
    if ! is_process_running "${PIDS[minecraft]}"; then
        return 1
    fi

    # 检查日志文件是否有活动
    local log_file="/data/logs/latest.log"
    if [ -f "$log_file" ]; then
        # 检查最近5分钟是否有日志输出
        local recent_logs
        recent_logs=$(find "$log_file" -mmin -5 2>/dev/null || echo "")
        [ -n "$recent_logs" ]
    else
        return 1
    fi
}

check_tunnel_health() {
    is_process_running "${PIDS[tunnel]}"
}

# 启动进程（带重试）
start_process() {
    local name=$1
    local start_func=$2
    local max_retries=${3:-3}
    local retry_delay=${4:-5}

    local attempt=1
    while [ $attempt -le $max_retries ]; do
        log "[$name] 启动尝试 $attempt/$max_retries..."

        if $start_func; then
            log "[$name] ✅ 启动成功"
            return 0
        fi

        if [ $attempt -eq $max_retries ]; then
            error "[$name] ❌ 启动失败，已达最大重试次数"
            return 1
        fi

        log "[$name] 等待 $retry_delay 秒后重试..."
        sleep $retry_delay
        ((attempt++))
    done
}

# 启动 API 服务器
start_api_server() {
    # 创建前端目录
    mkdir -p /tmp/hf

    # 复制前端文件
    if [ -d "/tmp/hf/frontend" ]; then
        cp -r /tmp/hf/frontend/* /tmp/hf/
    fi

    # 安装依赖
    if ! python3 -c "import flask, flask_cors" 2>/dev/null; then
        log "[API] 安装 Python 依赖..."
        pip3 install --user --no-cache-dir flask flask-cors > /tmp/pip_install.log 2>&1
    fi

    # 启动 API 服务器
    python3 /tmp/hf/api/server.py > /tmp/api_server.log 2>&1 &
    PIDS[api]=$!
    PROCESS_NAMES[api]="API服务器"

    # 等待启动
    local wait_count=0
    while [ $wait_count -lt 10 ]; do
        if check_api_health; then
            log "[API] ✅ 健康检查通过"
            return 0
        fi

        if ! is_process_running "${PIDS[api]}"; then
            error "[API] ❌ 进程已退出"
            cat /tmp/api_server.log
            return 1
        fi

        sleep 2
        ((wait_count++))
    done

    error "[API] ❌ 健康检查超时"
    return 1
}

# 启动 Minecraft 服务器
start_minecraft() {
    # 先恢复数据
    log "[Minecraft] 检查数据恢复..."
    /scripts/data-persistence.sh restore

    # 启动服务器
    log "[Minecraft] 启动服务器..."
    /image/scripts/start > /tmp/minecraft.log 2>&1 &
    PIDS[minecraft]=$!
    PROCESS_NAMES[minecraft]="Minecraft服务器"

    # 等待启动
    local wait_count=0
    while [ $wait_count -lt 60 ]; do  # 等待最多2分钟
        if check_minecraft_health; then
            log "[Minecraft] ✅ 健康检查通过"
            return 0
        fi

        if ! is_process_running "${PIDS[minecraft]}"; then
            error "[Minecraft] ❌ 进程已退出"
            cat /tmp/minecraft.log
            return 1
        fi

        sleep 2
        ((wait_count++))
    done

    # 即使健康检查失败，也给个机会（可能服务器还在加载）
    if is_process_running "${PIDS[minecraft]}"; then
        log "[Minecraft] ⚠️ 健康检查未通过但进程运行中，继续监控"
        return 0
    fi

    error "[Minecraft] ❌ 启动超时"
    return 1
}

# 启动 Cloudflare Tunnel
start_tunnel() {
    case "$TUNNEL_MODE" in
        token)
            if [ -z "$TUNNEL_TOKEN" ]; then
                error "[Tunnel] ❌ TUNNEL_TOKEN 环境变量未设置"
                return 1
            fi
            cloudflared tunnel run --token "$TUNNEL_TOKEN" > /tmp/tunnel.log 2>&1 &
            ;;
        legacy)
            cloudflared tunnel --url "$TUNNEL_URL" > /tmp/tunnel.log 2>&1 &
            ;;
        *)
            error "[Tunnel] ❌ 未知的 TUNNEL_MODE: $TUNNEL_MODE"
            return 1
            ;;
    esac

    PIDS[tunnel]=$!
    PROCESS_NAMES[tunnel]="Cloudflare Tunnel"

    # 等待启动
    sleep 5  # tunnel启动很快

    if check_tunnel_health; then
        log "[Tunnel] ✅ 启动成功"
        return 0
    else
        error "[Tunnel] ❌ 启动失败"
        cat /tmp/tunnel.log
        return 1
    fi
}

# 重启进程
restart_process() {
    local name=$1
    local start_func=$2

    log "[$name] 🔄 正在重启..."

    # 先停止进程
    if [ -n "${PIDS[$name]}" ]; then
        kill -TERM "${PIDS[$name]}" 2>/dev/null || true
        wait "${PIDS[$name]}" 2>/dev/null || true
        unset PIDS[$name]
    fi

    # 等待一下再启动
    sleep 3

    # 重新启动
    if $start_func; then
        log "[$name] ✅ 重启成功"
        return 0
    else
        error "[$name] ❌ 重启失败"
        return 1
    fi
}

# 进程监控循环
monitor_processes() {
    local check_interval=30  # 30秒检查一次

    while true; do
        sleep $check_interval

        # 检查 API 服务器
        if ! check_api_health; then
            error "[监控] API 服务器异常，尝试重启..."
            restart_process "api" "start_api_server"
        fi

        # 检查 Minecraft 服务器
        if ! check_minecraft_health; then
            error "[监控] Minecraft 服务器异常，尝试重启..."
            restart_process "minecraft" "start_minecraft"
            # Minecraft重启后需要等更久再启动tunnel
            sleep 30
        fi

        # 检查 Tunnel
        if ! check_tunnel_health; then
            error "[监控] Tunnel 异常，尝试重启..."
            restart_process "tunnel" "start_tunnel"
        fi

        # 定期日志
        local api_status minecraft_status tunnel_status
        api_status=$(check_api_health && echo "✅" || echo "❌")
        minecraft_status=$(check_minecraft_health && echo "✅" || echo "❌")
        tunnel_status=$(check_tunnel_health && echo "✅" || echo "❌")

        log "[监控] 状态检查 - API:$api_status Minecraft:$minecraft_status Tunnel:$tunnel_status"
    done
}

# 优雅关闭
cleanup() {
    log "[关闭] 收到关闭信号，正在优雅停止所有服务..."

    # 按相反顺序停止服务
    for name in persistence tunnel minecraft api; do
        if [ -n "${PIDS[$name]}" ] && is_process_running "${PIDS[$name]}"; then
            log "[关闭] 停止 ${PROCESS_NAMES[$name]} (PID: ${PIDS[$name]})"
            kill -TERM "${PIDS[$name]}" 2>/dev/null || true

            # 等待进程优雅退出
            local wait_count=0
            while [ $wait_count -lt 10 ] && is_process_running "${PIDS[$name]}"; do
                sleep 1
                ((wait_count++))
            done

            # 如果还没退出，强制杀死
            if is_process_running "${PIDS[$name]}"; then
                log "[关闭] 强制停止 ${PROCESS_NAMES[$name]}"
                kill -KILL "${PIDS[$name]}" 2>/dev/null || true
            fi
        fi
    done

    log "[关闭] 所有服务已停止"
    exit 0
}

trap cleanup TERM INT

# 主启动流程
log "=== Docker Minecraft Server 启动开始 ==="

# 按顺序启动所有服务
if start_process "API" "start_api_server" &&
   start_process "Minecraft" "start_minecraft" &&
   start_process "Tunnel" "start_tunnel"; then

    log "=== 所有服务启动成功，开始监控 ==="

    # 显示进程信息
    for name in api minecraft tunnel; do
        log "[进程] ${PROCESS_NAMES[$name]} PID: ${PIDS[$name]}"
    done

    # 启动数据持久化监控（后台运行）
    log "[持久化] 启动数据备份监控..."
    /scripts/data-persistence.sh init
    /scripts/data-persistence.sh monitor &
    PIDS[persistence]=$!
    PROCESS_NAMES[persistence]="数据持久化"

    # 进入监控循环
    monitor_processes
else
    error "=== 服务启动失败，退出 ==="
    cleanup
fi