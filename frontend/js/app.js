// API 基础 URL
const API_BASE = '/api';

// 配置
const config = {
    autoScroll: true,
    logBufferSize: 1000,
    updateInterval: 5000 // 5秒更新一次
};

// 状态存储
const state = {
    server: {
        running: false,
        type: '',
        version: '',
        memory: '',
        players: '0/0'
    },
    tunnel: {
        mode: '',
        running: false,
        url: ''
    },
    logs: []
};

// DOM 元素
const elements = {
    serverStatus: document.getElementById('server-status'),
    tunnelStatus: document.getElementById('tunnel-status'),
    startBtn: document.getElementById('start-btn'),
    stopBtn: document.getElementById('stop-btn'),
    serverType: document.getElementById('server-type'),
    serverVersion: document.getElementById('server-version'),
    serverMemory: document.getElementById('server-memory'),
    playerCount: document.getElementById('player-count'),
    tunnelMode: document.getElementById('tunnel-mode'),
    tunnelStatusDetail: document.getElementById('tunnel-status-detail'),
    tunnelUrl: document.getElementById('tunnel-url'),
    logsContainer: document.getElementById('logs-container'),
    lastUpdate: document.getElementById('last-update'),
    autoScrollStatus: document.getElementById('autoscroll-status')
};

// 初始化
document.addEventListener('DOMContentLoaded', () => {
    initializeApp();
});

function initializeApp() {
    log('初始化应用...', 'info');
    
    // 加载初始状态
    refreshStatus();
    
    // 启动实时日志
    startLogStream();
    
    // 定时刷新状态
    setInterval(refreshStatus, config.updateInterval);
    
    // 绑定日志容器滚动事件
    elements.logsContainer.addEventListener('scroll', handleLogScroll);
    
    log('应用初始化完成', 'success');
}

// API 请求封装
async function apiRequest(endpoint, options = {}) {
    try {
        const response = await fetch(`${API_BASE}${endpoint}`, {
            method: 'GET',
            headers: {
                'Content-Type': 'application/json',
                ...options.headers
            },
            ...options
        });
        
        if (!response.ok) {
            throw new Error(`HTTP ${response.status}: ${response.statusText}`);
        }
        
        return await response.json();
    } catch (error) {
        log(`API 请求失败: ${error.message}`, 'error');
        throw error;
    }
}

// 刷新状态
async function refreshStatus() {
    try {
        const [serverStatus, tunnelStatus] = await Promise.all([
            apiRequest('/status'),
            apiRequest('/tunnel')
        ]);
        
        updateServerStatus(serverStatus);
        updateTunnelStatus(tunnelStatus);
        
        elements.lastUpdate.textContent = new Date().toLocaleString('zh-CN');
    } catch (error) {
        log(`状态刷新失败: ${error.message}`, 'error');
    }
}

// 更新服务器状态
function updateServerStatus(status) {
    state.server = { ...state.server, ...status };
    
    // 更新状态显示
    const isRunning = status.running;
    elements.serverStatus.textContent = isRunning ? '运行中' : '已停止';
    elements.serverStatus.className = `status ${isRunning ? 'running' : 'stopped'}`;
    
    // 更新按钮状态
    elements.startBtn.disabled = isRunning;
    elements.stopBtn.disabled = !isRunning;
    
    // 更新信息
    elements.serverType.textContent = status.type || '-';
    elements.serverVersion.textContent = status.version || '-';
    elements.serverMemory.textContent = status.memory || '-';
    elements.playerCount.textContent = status.players || '0/0';
}

// 更新 Tunnel 状态
function updateTunnelStatus(status) {
    state.tunnel = { ...state.tunnel, ...status };
    
    // 更新状态显示
    const isRunning = status.running;
    elements.tunnelStatus.textContent = isRunning ? 'Tunnel 在线' : 'Tunnel 离线';
    elements.tunnelStatus.className = `status ${isRunning ? 'running' : 'stopped'}`;
    
    // 更新信息
    elements.tunnelMode.textContent = status.mode || '-';
    elements.tunnelStatusDetail.textContent = isRunning ? '已连接' : '未连接';
    elements.tunnelUrl.textContent = status.url || '-';
}

// 启动服务器
async function startServer() {
    if (state.server.running) {
        log('服务器已在运行中', 'warning');
        return;
    }
    
    log('正在启动服务器...', 'info');
    elements.startBtn.disabled = true;
    
    try {
        const result = await apiRequest('/start', { method: 'POST' });
        log(result.message || '服务器启动命令已发送', 'success');
        refreshStatus();
    } catch (error) {
        log(`启动失败: ${error.message}`, 'error');
        elements.startBtn.disabled = false;
    }
}

// 停止服务器
async function stopServer() {
    if (!state.server.running) {
        log('服务器未运行', 'warning');
        return;
    }
    
    log('正在停止服务器...', 'info');
    elements.stopBtn.disabled = true;
    
    try {
        const result = await apiRequest('/stop', { method: 'POST' });
        log(result.message || '服务器停止命令已发送', 'success');
        refreshStatus();
    } catch (error) {
        log(`停止失败: ${error.message}`, 'error');
        elements.stopBtn.disabled = false;
    }
}

// 启动实时日志流
function startLogStream() {
    log('启动实时日志流...', 'info');
    
    const eventSource = new EventSource(`${API_BASE}/logs/stream`);
    
    eventSource.onmessage = (event) => {
        const logEntry = JSON.parse(event.data);
        addLogEntry(logEntry);
    };
    
    eventSource.onerror = (error) => {
        log('日志流连接错误，尝试重连...', 'error');
        eventSource.close();
        
        // 5秒后重连
        setTimeout(() => {
            log('重新连接日志流...', 'info');
            startLogStream();
        }, 5000);
    };
    
    eventSource.onopen = () => {
        log('实时日志流已连接', 'success');
    };
}

// 添加日志条目
function addLogEntry(entry) {
    const logElement = document.createElement('div');
    logElement.className = `log-entry ${entry.level || 'info'}`;
    logElement.textContent = `[${entry.timestamp}] ${entry.message}`;
    
    elements.logsContainer.appendChild(logElement);
    state.logs.push(entry);
    
    // 限制日志缓冲区大小
    if (state.logs.length > config.logBufferSize) {
        state.logs.shift();
        elements.logsContainer.removeChild(elements.logsContainer.firstChild);
    }
    
    // 自动滚动
    if (config.autoScroll) {
        scrollToBottom();
    }
}

// 日志函数
function log(message, level = 'info') {
    const timestamp = new Date().toLocaleTimeString('zh-CN');
    addLogEntry({ timestamp, message, level });
}

// 清空日志
function clearLogs() {
    elements.logsContainer.innerHTML = '';
    state.logs = [];
    log('日志已清空', 'info');
}

// 切换自动滚动
function toggleAutoScroll() {
    config.autoScroll = !config.autoScroll;
    elements.autoScrollStatus.textContent = config.autoScroll ? '开启' : '关闭';
    log(`自动滚动: ${config.autoScroll ? '开启' : '关闭'}`, 'info');
}

// 滚动到日志底部
function scrollToBottom() {
    elements.logsContainer.scrollTop = elements.logsContainer.scrollHeight;
}

// 处理日志滚动
function handleLogScroll() {
    const { scrollTop, scrollHeight, clientHeight } = elements.logsContainer;
    const isAtBottom = scrollTop + clientHeight >= scrollHeight - 10;
    
    if (isAtBottom !== config.autoScroll) {
        config.autoScroll = isAtBottom;
        elements.autoScrollStatus.textContent = config.autoScroll ? '开启' : '关闭';
    }
}

// 格式化内存大小
function formatMemory(bytes) {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}
