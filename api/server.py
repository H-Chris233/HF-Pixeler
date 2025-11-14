#!/usr/bin/env python3
"""
Minecraft Server API for Hugging Face
提供状态监控、日志流和控制接口
"""

import os
import sys
import json
import time
import subprocess
from datetime import datetime
from flask import Flask, jsonify, request, send_from_directory, Response
from flask_cors import CORS

# 配置
app = Flask(__name__)
CORS(app)

# 状态存储
server_status = {
    "running": False,
    "type": os.getenv("TYPE", "VANILLA"),
    "version": os.getenv("VERSION", "LATEST"),
    "memory": os.getenv("MEMORY", "1G"),
    "players": "0/0"
}

tunnel_status = {
    "mode": os.getenv("TUNNEL_MODE", "token"),
    "running": False,
    "url": os.getenv("TUNNEL_URL", "tcp://localhost:25565")
}

# 日志缓冲区
log_buffer = []

def log(message, level="info"):
    """记录日志"""
    timestamp = datetime.now().strftime("%H:%M:%S")
    entry = {"timestamp": timestamp, "message": message, "level": level}
    log_buffer.append(entry)
    if len(log_buffer) > 1000:
        log_buffer.pop(0)
    print(f"[{timestamp}] [{level.upper()}] {message}", file=sys.stderr)

@app.route('/')
def index():
    """提供前端页面"""
    return send_from_directory('/tmp/hf', 'index.html')

@app.route('/<path:path>')
def serve_file(path):
    """提供静态文件"""
    return send_from_directory('/tmp/hf', path)

@app.route('/api/status')
def get_status():
    """获取服务器状态"""
    return jsonify(server_status)

@app.route('/api/tunnel')
def get_tunnel():
    """获取 Tunnel 状态"""
    return jsonify(tunnel_status)

@app.route('/api/start', methods=['POST'])
def start_server():
    """启动服务器"""
    global server_status
    if not server_status["running"]:
        server_status["running"] = True
        log("服务器启动命令已发送", "success")
        return jsonify({"message": "Server start command sent", "success": True})
    log("服务器已在运行中", "warning")
    return jsonify({"message": "Server already running", "success": False})

@app.route('/api/stop', methods=['POST'])
def stop_server():
    """停止服务器"""
    global server_status
    if server_status["running"]:
        server_status["running"] = False
        log("服务器停止命令已发送", "success")
        return jsonify({"message": "Server stop command sent", "success": True})
    log("服务器未运行", "warning")
    return jsonify({"message": "Server not running", "success": False})

@app.route('/api/logs')
def get_logs():
    """获取最近日志"""
    try:
        log_file = '/data/logs/latest.log'
        if os.path.exists(log_file):
            with open(log_file, 'r') as f:
                logs = f.readlines()[-100:]
            return jsonify({"logs": logs})
        return jsonify({"logs": []})
    except Exception as e:
        log(f"读取日志失败: {e}", "error")
        return jsonify({"logs": []})

@app.route('/api/logs/stream')
def stream_logs():
    """实时日志流（Server-Sent Events）"""
    def generate():
        log_file = '/data/logs/latest.log'
        
        if not os.path.exists(log_file):
            yield f"data: {json.dumps({'timestamp': datetime.now().strftime('%H:%M:%S'), 'message': 'No log file found', 'level': 'warning'})}\n\n"
            return
        
        with open(log_file, 'r') as f:
            f.seek(0, 2)  # 移动到文件末尾
            while True:
                line = f.readline()
                if line:
                    yield f"data: {json.dumps({'timestamp': datetime.now().strftime('%H:%M:%S'), 'message': line.strip(), 'level': 'info'})}\n\n"
                time.sleep(0.1)
    
    return Response(generate(), mimetype='text/event-stream', headers={
        'Cache-Control': 'no-cache',
        'X-Accel-Buffering': 'no'
    })

@app.route('/api/stats')
def get_stats():
    """获取性能统计"""
    try:
        # 获取内存使用
        with open('/proc/meminfo', 'r') as f:
            meminfo = f.read()
        
        # 获取 CPU 使用
        with open('/proc/stat', 'r') as f:
            stat = f.readline()
        
        return jsonify({
            "memory": meminfo,
            "cpu": stat,
            "timestamp": datetime.now().isoformat()
        })
    except Exception as e:
        log(f"获取统计失败: {e}", "error")
        return jsonify({"error": str(e)})

if __name__ == '__main__':
    log("API 服务器启动中...")
    
    # 确保前端文件存在
    if not os.path.exists('/tmp/hf/index.html'):
        log("前端文件不存在，创建默认页面", "warning")
        os.makedirs('/tmp/hf', exist_ok=True)
        with open('/tmp/hf/index.html', 'w') as f:
            f.write('<html><body><h1>Minecraft Server Dashboard</h1><p>Loading...</p></body></html>')
    
    # 启动 Flask 服务器
    try:
        app.run(host='0.0.0.0', port=7860, debug=False, threaded=True)
    except Exception as e:
        log(f"API 服务器启动失败: {e}", "error")
        sys.exit(1)
