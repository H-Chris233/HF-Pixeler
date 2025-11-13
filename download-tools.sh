#!/bin/bash
set -e

# 创建 tools 目录
mkdir -p tools

echo "📥 开始下载 Minecraft 服务器工具..."
echo "====================================="

# 下载函数（带错误检查）
download_file() {
    local url="$1"
    local output="$2"
    local retries=3
    
    for i in $(seq 1 $retries); do
        echo "[$i/$retries] 下载: $output"
        
        # 下载并检查 HTTP 状态码
        http_code=$(curl -L -w "%{http_code}" -o "$output" "$url")
        
        if [ "$http_code" -ne 200 ]; then
            echo "❌ 下载失败！HTTP 状态码: $http_code"
            rm -f "$output"
            
            if [ $i -eq $retries ]; then
                echo "已达到最大重试次数，退出"
                exit 1
            fi
            
            echo "等待 5 秒后重试..."
            sleep 5
            continue
        fi
        
        # 检查文件大小（必须 > 1KB）
        file_size=$(stat -c%s "$output" 2>/dev/null || echo "0")
        
        if [ "$file_size" -lt 1024 ]; then
            echo "❌ 文件太小（$file_size 字节），可能下载失败"
            rm -f "$output"
            
            if [ $i -eq $retries ]; then
                echo "已达到最大重试次数，退出"
                exit 1
            fi
            
            echo "等待 5 秒后重试..."
            sleep 5
            continue
        fi
        
        echo "✅ 下载成功！文件大小: $(numfmt --to=iec-i --suffix=B $file_size)"
        return 0
    done
    
    return 1
}

# easy-add
download_file "https://github.com/itzg/easy-add/releases/download/0.8.11/easy-add_linux_amd64" "tools/easy-add"
chmod +x tools/easy-add

# restify
download_file "https://github.com/itzg/restify/releases/download/1.7.10/restify_1.7.10_linux_amd64.tar.gz" "tools/restify.tar.gz"
tar -xzf tools/restify.tar.gz -C tools/
chmod +x tools/restify
rm tools/restify.tar.gz

# rcon-cli
download_file "https://github.com/itzg/rcon-cli/releases/download/1.7.1/rcon-cli_1.7.1_linux_amd64.tar.gz" "tools/rcon-cli.tar.gz"
tar -xzf tools/rcon-cli.tar.gz -C tools/
chmod +x tools/rcon-cli
rm tools/rcon-cli.tar.gz

# mc-monitor
download_file "https://github.com/itzg/mc-monitor/releases/download/0.15.6/mc-monitor_0.15.6_linux_amd64.tar.gz" "tools/mc-monitor.tar.gz"
tar -xzf tools/mc-monitor.tar.gz -C tools/
chmod +x tools/mc-monitor
rm tools/mc-monitor.tar.gz

# mc-server-runner
download_file "https://github.com/itzg/mc-server-runner/releases/download/1.13.4/mc-server-runner_1.13.4_linux_amd64.tar.gz" "tools/mc-server-runner.tar.gz"
tar -xzf tools/mc-server-runner.tar.gz -C tools/
chmod +x tools/mc-server-runner
rm tools/mc-server-runner.tar.gz

# mc-image-helper
# ✅ 注意：mc-image-helper 的 URL 格式不同
download_file "https://github.com/itzg/mc-image-helper/releases/download/1.50.4/mc-image-helper-1.50.4.tgz" "tools/mc-image-helper-1.50.4.tgz"

# cloudflared
download_file "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb" "tools/cloudflared.deb"

# Log4jPatcher
download_file "https://github.com/CreeperHost/Log4jPatcher/releases/download/v1.0.1/Log4jPatcher-1.0.1.jar" "tools/Log4jPatcher.jar"

echo "====================================="
echo "✅ 所有工具下载完成！"
echo "📦 文件已保存到 tools/ 目录"
ls -lh tools/