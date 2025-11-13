#!/bin/bash

# HuggingFace Spaces 数据持久化脚本
# 解决容器重启导致数据丢失的问题

set -e

# 配置
BACKUP_INTERVAL=3600    # 1小时备份一次
WORLD_BACKUP_INTERVAL=7200  # 完整世界备份每2小时一次
MAX_BACKUPS=24          # 保留24小时备份
HF_DATASET_REPO="${HF_DATASET_REPO:-}"  # 可选：HF数据集仓库
S3_BUCKET="${S3_BUCKET:-}"              # 可选：S3存储桶

# 数据目录
WORLD_DIR="/data/world"
CONFIG_DIR="/data/config"
PLAYER_DATA_DIR="/data/world/playerdata"
STATS_DIR="/data/world/stats"
BACKUP_DIR="/tmp/backups"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [PERSISTENCE] $*" >&2
}

# 创建备份目录
init_backup() {
    mkdir -p "$BACKUP_DIR"/{world,config,playerdata,stats}
}

# 压缩完整世界数据（使用Git LFS）
backup_world() {
    if [ ! -d "$WORLD_DIR" ]; then
        log "世界目录不存在，跳过备份"
        return 0
    fi

    local backup_file="$BACKUP_DIR/world/world_$(date +%Y%m%d_%H%M%S).tar.gz"

    log "开始备份完整世界数据（包含所有区块）..."

    # 备份完整世界，包括区块文件
    tar -czf "$backup_file" \
        -C "$(dirname "$WORLD_DIR")" \
        --exclude='*.tmp' \      # 排除临时文件
        --exclude='session.lock' \  # 排除锁文件（避免冲突）
        world/ 2>/dev/null || {
        log "世界数据备份失败"
        return 1
    }

    local size=$(du -h "$backup_file" | cut -f1)
    log "世界数据备份完成: $size"

    # 保留更多备份（使用Git LFS，空间够用）
    find "$BACKUP_DIR/world" -name "world_*.tar.gz" -mtime +7 -delete 2>/dev/null || true

    return 0
}

# 备份玩家数据
backup_player_data() {
    if [ ! -d "$PLAYER_DATA_DIR" ]; then
        return 0
    fi

    local backup_file="$BACKUP_DIR/playerdata/playerdata_$(date +%Y%m%d_%H%M%S).tar.gz"

    tar -czf "$backup_file" -C "$(dirname "$PLAYER_DATA_DIR")" playerdata/ 2>/dev/null || {
        log "玩家数据备份失败"
        return 1
    }

    log "玩家数据备份完成: $(du -h "$backup_file" | cut -f1)"

    # 清理旧备份
    find "$BACKUP_DIR/playerdata" -name "playerdata_*.tar.gz" -mtime +7 -delete 2>/dev/null || true

    return 0
}

# 备份统计数据
backup_stats() {
    if [ ! -d "$STATS_DIR" ]; then
        return 0
    fi

    local backup_file="$BACKUP_DIR/stats/stats_$(date +%Y%m%d_%H%M%S).tar.gz"

    tar -czf "$backup_file" -C "$(dirname "$STATS_DIR")" stats/ 2>/dev/null || {
        log "统计数据备份失败"
        return 1
    }

    log "统计数据备份完成: $(du -h "$backup_file" | cut -f1)"

    # 清理旧备份
    find "$BACKUP_DIR/stats" -name "stats_*.tar.gz" -mtime +7 -delete 2>/dev/null || true

    return 0
}

# 备份配置文件
backup_config() {
    local backup_file="$BACKUP_DIR/config/config_$(date +%Y%m%d_%H%M%S).tar.gz"

    tar -czf "$backup_file" -C /data \
        server.properties \
        eula.txt \
        ops.json \
        whitelist.json \
        banned-players.json \
        banned-ips.json \
        bukkit.yml \
        spigot.yml \
        paper.yml 2>/dev/null || {
        log "配置备份失败"
        return 1
    }

    log "配置文件备份完成: $(du -h "$backup_file" | cut -f1)"

    # 清理旧备份
    find "$BACKUP_DIR/config" -name "config_*.tar.gz" -mtime +30 -delete 2>/dev/null || true

    return 0
}

# 初始化Git LFS
init_git_lfs() {
    if [ -z "$HF_DATASET_REPO" ] || [ ! -d ".git" ]; then
        return 0
    fi

    log "初始化Git LFS..."

    # 确保Git LFS已安装
    if ! command -v git-lfs >/dev/null 2>&1; then
        log "安装Git LFS..."
        # 对于Debian/Ubuntu
        if command -v apt-get >/dev/null 2>&1; then
            apt-get update && apt-get install -y git-lfs
        else
            # 对于其他系统，尝试使用包管理器
            curl -s https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | bash
            apt-get install -y git-lfs
        fi
    fi

    # 初始化Git LFS
    git lfs install

    # 配置LFS跟踪大文件
    git lfs track "*.tar.gz"
    git lfs track "*.jar"
    git lfs track "world/region/*.mca"
    git lfs track "world/entities/*.mca"
    git lfs track "world/poi/*.mca"

    # 提交LFS配置
    git add .gitattributes
    git commit -m "Configure Git LFS for large files" 2>/dev/null || true

    log "Git LFS初始化完成"
    return 0
}

# Git提交备份（使用LFS存储完整备份）
git_commit_backup() {
    if [ -z "$HF_DATASET_REPO" ] || [ ! -d ".git" ]; then
        return 0
    fi

    log "Git提交备份..."

    # 添加所有备份文件到Git LFS
    git add server.properties eula.txt ops.json whitelist.json 2>/dev/null || true
    git add world/ 2>/dev/null || true  # 完整世界目录
    git add "$BACKUP_DIR"/*.tar.gz 2>/dev/null || true  # 备份文件

    # 检查是否有更改
    if git diff --cached --quiet; then
        log "没有文件更改，跳过提交"
        return 0
    fi

    # 检查LFS文件大小
    local total_size=$(git ls-files -s | awk '$1 ~ /120000/ {s+=$4} END {print s+0}')
    if [ "$total_size" -gt 500000000 ]; then  # 500MB限制
        log "LFS文件过大: $(( total_size / 1024 / 1024 ))MB，跳过此次提交"
        return 0
    fi

    # 提交并推送
    git config user.email "backup@minecraft-server"
    git config user.name "Minecraft Backup Bot"

    git commit -m "Auto backup: $(date '+%Y-%m-%d %H:%M:%S') [Full World]" || {
        log "Git提交失败"
        return 1
    }

    # 推送到远程（包含LFS文件）
    git push origin main 2>/dev/null || git push origin master 2>/dev/null || {
        log "Git推送失败，可能是LFS配额超限"
        return 1
    }

    log "Git备份提交完成（包含完整世界）"
    return 0
}

# S3上传备份
s3_upload_backup() {
    if [ -z "$S3_BUCKET" ] || ! command -v aws >/dev/null 2>&1; then
        return 0
    fi

    log "S3上传备份..."

    local today=$(date +%Y-%m-%d)
    local s3_prefix="s3://$S3_BUCKET/minecraft-backups/$today"

    # 上传所有备份文件
    find "$BACKUP_DIR" -name "*.tar.gz" -type f | while read -r file; do
        local rel_path=${file#$BACKUP_DIR/}
        aws s3 cp "$file" "$s3_prefix/$rel_path" --only-show-errors || {
            log "S3上传失败: $file"
        }
    done

    log "S3备份上传完成"
    return 0
}

# 恢复数据
restore_data() {
    log "开始恢复数据..."

    # 查找最新备份
    local latest_world=$(find "$BACKUP_DIR/world" -name "world_*.tar.gz" -type f | sort -r | head -1)
    local latest_playerdata=$(find "$BACKUP_DIR/playerdata" -name "playerdata_*.tar.gz" -type f | sort -r | head -1)
    local latest_config=$(find "$BACKUP_DIR/config" -name "config_*.tar.gz" -type f | sort -r | head -1)

    # 恢复配置
    if [ -n "$latest_config" ]; then
        log "恢复配置文件..."
        tar -xzf "$latest_config" -C /data
    fi

    # 恢复玩家数据
    if [ -n "$latest_playerdata" ]; then
        log "恢复玩家数据..."
        mkdir -p "$PLAYER_DATA_DIR"
        tar -xzf "$latest_playerdata" -C /data
    fi

    # 恢复世界元数据
    if [ -n "$latest_world" ]; then
        log "恢复世界元数据..."
        mkdir -p "$WORLD_DIR"
        tar -xzf "$latest_world" -C "$WORLD_DIR"
    fi

    log "数据恢复完成"
    return 0
}

# 清理函数
cleanup() {
    log "清理临时备份..."
    # 清理超过30天的备份
    find "$BACKUP_DIR" -name "*.tar.gz" -mtime +30 -delete 2>/dev/null || true
}

# 主备份函数
backup_data() {
    log "开始完整数据备份..."

    # 初始化Git LFS（首次运行）
    init_git_lfs || true

    # 执行各种备份（包含完整世界）
    backup_config || true
    backup_player_data || true
    backup_stats || true
    backup_world || true  # 完整世界备份

    # 上传到Git LFS存储
    git_commit_backup || true

    # 可选：S3额外备份
    s3_upload_backup || true

    # 清理旧备份（保留更长时间，因为有LFS存储）
    cleanup

    log "完整数据备份完成"
    return 0
}

# 监控循环
monitor_and_backup() {
    log "启动数据持久化监控（间隔：${BACKUP_INTERVAL}秒）"

    while true; do
        sleep "$BACKUP_INTERVAL"
        backup_data
    done
}

# 信号处理
cleanup_and_exit() {
    log "收到退出信号，执行最终备份..."
    backup_data
    exit 0
}

trap cleanup_and_exit TERM INT

# 主程序
case "${1:-backup}" in
    init)
        init_backup
        ;;
    backup)
        backup_data
        ;;
    restore)
        restore_data
        ;;
    monitor)
        init_backup
        monitor_and_backup
        ;;
    *)
        echo "用法: $0 {init|backup|restore|monitor}"
        echo "  init    - 初始化备份目录"
        echo "  backup  - 执行一次备份"
        echo "  restore - 恢复最新备份"
        echo "  monitor - 启动监控循环"
        exit 1
        ;;
esac