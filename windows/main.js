const { app, BrowserWindow, ipcMain } = require('electron');
const path = require('path');
const fs = require('fs');
const os = require('os');
const net = require('net');
const crypto = require('crypto');
const express = require('express');
const multer = require('multer');
const QRCode = require('qrcode');
const { exec, spawn } = require('child_process');

// ============ 配置 ============
const INSTALL_DIR = path.join('C:', 'iNas root');
const DATA_DIR = path.join(INSTALL_DIR, 'System', 'data');
const RECYCLE_BIN = path.join(INSTALL_DIR, '回收站');
const TOKEN_FILE = path.join(DATA_DIR, 'token.json');

// 确保目录存在
[INSTALL_DIR, DATA_DIR, RECYCLE_BIN,
 path.join(INSTALL_DIR, '音乐'),
 path.join(INSTALL_DIR, '视频'),
 path.join(INSTALL_DIR, '图片'),
 path.join(INSTALL_DIR, '下载')
].forEach(d => { try { fs.mkdirSync(d, { recursive: true }); } catch(e){} });

// ============ Token 管理 ============
let authToken = '';
function loadToken() {
  try {
    if (fs.existsSync(TOKEN_FILE)) {
      const data = JSON.parse(fs.readFileSync(TOKEN_FILE, 'utf8'));
      authToken = data.token || '';
    }
  } catch(e) {}
  if (!authToken) {
    authToken = crypto.randomBytes(16).toString('hex');
    try { fs.writeFileSync(TOKEN_FILE, JSON.stringify({ token: authToken, created: Date.now() })); } catch(e){}
  }
}
loadToken();

// ============ 队列管理 ============
const taskQueue = new Map();
let taskIdCounter = 0;

function createTask(type, name, total = 0) {
  const id = String(++taskIdCounter);
  taskQueue.set(id, {
    id, type, name,
    status: 'pending', // pending, running, paused, completed, failed, cancelled
    progress: 0,
    total,
    transferred: 0,
    speed: 0,
    error: null,
    createdAt: Date.now(),
    _cancel: false,
    _pause: false
  });
  return id;
}

function updateTask(id, updates) {
  const t = taskQueue.get(id);
  if (t) Object.assign(t, updates);
}

// ============ 获取本机 IP ============
function getLocalIP() {
  const interfaces = os.networkInterfaces();
  for (const name of Object.keys(interfaces)) {
    for (const iface of interfaces[name]) {
      if (iface.family === 'IPv4' && !iface.internal) {
        return iface.address;
      }
    }
  }
  return '127.0.0.1';
}

// ============ 查找可用端口 ============
function findAvailablePort(startPort = 18080) {
  return new Promise((resolve) => {
    const tryPort = (port) => {
      const server = net.createServer();
      server.unref();
      server.on('error', () => tryPort(port + 1));
      server.listen(port, '0.0.0.0', () => {
        server.close(() => resolve(port));
      });
    };
    tryPort(startPort);
  });
}

// ============ Express 服务 ============
let server = null;
let serverPort = 0;

async function startServer() {
  const app_express = express();
  app_express.use(express.json({ limit: '50mb' }));
  app_express.use(express.urlencoded({ extended: true, limit: '50mb' }));

  // CORS
  app_express.use((req, res, next) => {
    res.header('Access-Control-Allow-Origin', '*');
    res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
    res.header('Access-Control-Allow-Headers', 'Content-Type, x-nas-token');
    if (req.method === 'OPTIONS') return res.sendStatus(200);
    next();
  });

  // 认证中间件
  function auth(req, res, next) {
    const token = req.headers['x-nas-token'];
    if (!token || token !== authToken) {
      return res.status(401).json({ error: 'Unauthorized', message: 'Invalid or missing x-nas-token' });
    }
    next();
  }

  // 路径安全：将相对路径解析到安装目录
  function resolveSafePath(relativePath) {
    if (!relativePath) return INSTALL_DIR;
    // 支持 Windows root 和 iNas root 两种模式
    if (relativePath === 'windows-root' || relativePath === '/') {
      return 'C:\\';
    }
    if (relativePath.startsWith('windows-root/')) {
      const sub = relativePath.substring('windows-root/'.length);
      return path.join('C:\\', sub);
    }
    // 默认 iNas root
    const clean = relativePath.replace(/^\/+/, '');
    const resolved = path.join(INSTALL_DIR, clean);
    // 安全检查
    if (!resolved.startsWith(INSTALL_DIR) && resolved !== INSTALL_DIR) {
      return null;
    }
    return resolved;
  }

  // ============ API: 状态/连接信息 ============
  app_express.get('/api/status', (req, res) => {
    res.json({
      ok: true,
      version: '1.0.0',
      hostname: os.hostname(),
      platform: os.platform(),
      totalMem: os.totalmem(),
      freeMem: os.freemem(),
      uptime: os.uptime()
    });
  });

  // ============ API: 文件列表 ============
  app_express.get('/api/files', auth, (req, res) => {
    const relPath = req.query.path || '';
    const target = resolveSafePath(relPath);
    if (!target) return res.status(400).json({ error: 'Invalid path' });

    try {
      if (!fs.existsSync(target)) {
        return res.status(404).json({ error: 'Path not found', path: target });
      }
      const stat = fs.statSync(target);
      if (stat.isFile()) {
        return res.json({
          type: 'file',
          name: path.basename(target),
          path: relPath,
          size: stat.size,
          modified: stat.mtimeMs,
          isDirectory: false
        });
      }
      const entries = fs.readdirSync(target);
      const files = [];
      const dirs = [];
      for (const name of entries) {
        const fullPath = path.join(target, name);
        try {
          const st = fs.statSync(fullPath);
          const item = {
            name,
            path: relPath ? `${relPath}/${name}` : name,
            size: st.isDirectory() ? 0 : st.size,
            modified: st.mtimeMs,
            isDirectory: st.isDirectory()
          };
          if (st.isDirectory()) dirs.push(item);
          else files.push(item);
        } catch(e) {}
      }
      dirs.sort((a,b) => a.name.localeCompare(b.name));
      files.sort((a,b) => a.name.localeCompare(b.name));
      res.json({
        type: 'directory',
        path: relPath,
        name: path.basename(target) || (relPath === 'windows-root' ? 'Windows (C:)' : 'iNas Root'),
        entries: [...dirs, ...files]
      });
    } catch(e) {
      res.status(500).json({ error: e.message });
    }
  });

  // ============ API: 下载文件 ============
  app_express.get('/api/download', auth, (req, res) => {
    const relPath = req.query.path || '';
    const target = resolveSafePath(relPath);
    if (!target || !fs.existsSync(target)) {
      return res.status(404).json({ error: 'File not found' });
    }
    const stat = fs.statSync(target);
    if (stat.isDirectory()) {
      return res.status(400).json({ error: 'Cannot download directory' });
    }
    res.setHeader('Content-Disposition', `attachment; filename="${encodeURIComponent(path.basename(target))}"`);
    res.setHeader('Content-Length', stat.size);
    res.setHeader('Content-Type', 'application/octet-stream');
    fs.createReadStream(target).pipe(res);
  });

  // ============ API: 上传文件 ============
  const upload = multer({
    storage: multer.diskStorage({
      destination: (req, file, cb) => {
        const relPath = req.body.path || '';
        const target = resolveSafePath(relPath);
        if (target && fs.existsSync(target)) {
          cb(null, target);
        } else {
          cb(null, INSTALL_DIR);
        }
      },
      filename: (req, file, cb) => {
        cb(null, file.originalname);
      }
    }),
    limits: { fileSize: 1024 * 1024 * 1024 * 10 } // 10GB
  });

  app_express.post('/api/upload', auth, upload.single('file'), (req, res) => {
    if (!req.file) return res.status(400).json({ error: 'No file uploaded' });
    res.json({
      ok: true,
      filename: req.file.filename,
      size: req.file.size,
      path: req.body.path || ''
    });
  });

  // ============ API: 删除文件（移入回收站） ============
  app_express.post('/api/delete', auth, (req, res) => {
    const relPath = req.body.path || '';
    const target = resolveSafePath(relPath);
    if (!target || !fs.existsSync(target)) {
      return res.status(404).json({ error: 'File not found' });
    }
    try {
      const fileName = path.basename(target);
      const dest = path.join(RECYCLE_BIN, `${Date.now()}_${fileName}`);
      fs.renameSync(target, dest);
      res.json({ ok: true, movedTo: dest });
    } catch(e) {
      // 如果跨盘移动失败，尝试复制+删除
      try {
        const fileName = path.basename(target);
        const dest = path.join(RECYCLE_BIN, `${Date.now()}_${fileName}`);
        if (fs.statSync(target).isDirectory()) {
          fs.cpSync(target, dest, { recursive: true });
          fs.rmSync(target, { recursive: true, force: true });
        } else {
          fs.copyFileSync(target, dest);
          fs.unlinkSync(target);
        }
        res.json({ ok: true, movedTo: dest });
      } catch(e2) {
        res.status(500).json({ error: e2.message });
      }
    }
  });

  // ============ API: 重命名 ============
  app_express.post('/api/rename', auth, (req, res) => {
    const { path: relPath, newName } = req.body;
    const target = resolveSafePath(relPath);
    if (!target || !fs.existsSync(target)) {
      return res.status(404).json({ error: 'File not found' });
    }
    try {
      const newPath = path.join(path.dirname(target), newName);
      fs.renameSync(target, newPath);
      res.json({ ok: true, newPath });
    } catch(e) {
      res.status(500).json({ error: e.message });
    }
  });

  // ============ API: 复制 ============
  app_express.post('/api/copy', auth, (req, res) => {
    const { source, destination } = req.body;
    const src = resolveSafePath(source);
    const dst = resolveSafePath(destination);
    if (!src || !dst) return res.status(400).json({ error: 'Invalid path' });
    if (!fs.existsSync(src)) return res.status(404).json({ error: 'Source not found' });

    const taskId = createTask('copy', `${path.basename(src)} → ${destination}`, 0);
    updateTask(taskId, { status: 'running' });

    // 异步执行复制
    (async () => {
      try {
        const srcStat = fs.statSync(src);
        let totalSize = srcStat.size;
        if (srcStat.isDirectory()) {
          // 计算目录总大小
          totalSize = await calcDirSize(src);
        }
        updateTask(taskId, { total: totalSize });

        const destPath = path.join(dst, path.basename(src));
        if (srcStat.isDirectory()) {
          await copyDirWithProgress(src, destPath, taskId);
        } else {
          await copyFileWithProgress(src, destPath, taskId);
        }
        updateTask(taskId, { status: 'completed', progress: 100 });
      } catch(e) {
        updateTask(taskId, { status: 'failed', error: e.message });
      }
    })();

    res.json({ ok: true, taskId });
  });

  async function calcDirSize(dir) {
    let total = 0;
    const entries = fs.readdirSync(dir, { withFileTypes: true });
    for (const entry of entries) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) total += await calcDirSize(full);
      else { try { total += fs.statSync(full).size; } catch(e){} }
    }
    return total;
  }

  async function copyFileWithProgress(src, dst, taskId) {
    const task = taskQueue.get(taskId);
    return new Promise((resolve, reject) => {
      fs.mkdirSync(path.dirname(dst), { recursive: true });
      const readStream = fs.createReadStream(src);
      const writeStream = fs.createWriteStream(dst);
      readStream.on('data', (chunk) => {
        if (task._cancel) { readStream.destroy(); writeStream.destroy(); return reject(new Error('Cancelled')); }
        task.transferred += chunk.length;
        if (task.total > 0) task.progress = Math.min(100, (task.transferred / task.total) * 100);
      });
      readStream.on('error', reject);
      writeStream.on('error', reject);
      writeStream.on('finish', resolve);
      readStream.pipe(writeStream);
    });
  }

  async function copyDirWithProgress(src, dst, taskId) {
    fs.mkdirSync(dst, { recursive: true });
    const entries = fs.readdirSync(src, { withFileTypes: true });
    for (const entry of entries) {
      const task = taskQueue.get(taskId);
      if (task._cancel) throw new Error('Cancelled');
      const srcFull = path.join(src, entry.name);
      const dstFull = path.join(dst, entry.name);
      if (entry.isDirectory()) {
        await copyDirWithProgress(srcFull, dstFull, taskId);
      } else {
        await copyFileWithProgress(srcFull, dstFull, taskId);
      }
    }
  }

  // ============ API: 移动 ============
  app_express.post('/api/move', auth, (req, res) => {
    const { source, destination } = req.body;
    const src = resolveSafePath(source);
    const dst = resolveSafePath(destination);
    if (!src || !dst) return res.status(400).json({ error: 'Invalid path' });
    if (!fs.existsSync(src)) return res.status(404).json({ error: 'Source not found' });
    try {
      const destPath = path.join(dst, path.basename(src));
      fs.renameSync(src, destPath);
      res.json({ ok: true });
    } catch(e) {
      // 跨盘移动
      try {
        const destPath = path.join(dst, path.basename(src));
        if (fs.statSync(src).isDirectory()) {
          fs.cpSync(src, destPath, { recursive: true });
          fs.rmSync(src, { recursive: true, force: true });
        } else {
          fs.copyFileSync(src, destPath);
          fs.unlinkSync(src);
        }
        res.json({ ok: true });
      } catch(e2) {
        res.status(500).json({ error: e2.message });
      }
    }
  });

  // ============ API: 创建目录 ============
  app_express.post('/api/mkdir', auth, (req, res) => {
    const { path: relPath, name } = req.body;
    const target = resolveSafePath(relPath);
    if (!target) return res.status(400).json({ error: 'Invalid path' });
    try {
      const newDir = path.join(target, name);
      fs.mkdirSync(newDir, { recursive: true });
      res.json({ ok: true, path: newDir });
    } catch(e) {
      res.status(500).json({ error: e.message });
    }
  });

  // ============ API: 读取文本文件 ============
  app_express.get('/api/read-text', auth, (req, res) => {
    const relPath = req.query.path || '';
    const target = resolveSafePath(relPath);
    if (!target || !fs.existsSync(target)) {
      return res.status(404).json({ error: 'File not found' });
    }
    try {
      const content = fs.readFileSync(target, 'utf8');
      res.json({ ok: true, content, path: relPath });
    } catch(e) {
      res.status(500).json({ error: e.message });
    }
  });

  // ============ API: 写入文本文件 ============
  app_express.post('/api/write-text', auth, (req, res) => {
    const { path: relPath, content } = req.body;
    const target = resolveSafePath(relPath);
    if (!target) return res.status(400).json({ error: 'Invalid path' });
    try {
      fs.mkdirSync(path.dirname(target), { recursive: true });
      fs.writeFileSync(target, content, 'utf8');
      res.json({ ok: true });
    } catch(e) {
      res.status(500).json({ error: e.message });
    }
  });

  // ============ API: 队列状态 ============
  app_express.get('/api/queue', auth, (req, res) => {
    const tasks = Array.from(taskQueue.values()).sort((a,b) => b.createdAt - a.createdAt);
    res.json({ tasks });
  });

  // ============ API: 队列操作 ============
  app_express.post('/api/queue/:id/:action', auth, (req, res) => {
    const { id, action } = req.params;
    const task = taskQueue.get(id);
    if (!task) return res.status(404).json({ error: 'Task not found' });

    switch(action) {
      case 'pause':
        task._pause = true;
        task.status = 'paused';
        break;
      case 'resume':
        task._pause = false;
        task.status = 'running';
        break;
      case 'cancel':
        task._cancel = true;
        task.status = 'cancelled';
        break;
      case 'remove':
        taskQueue.delete(id);
        break;
      default:
        return res.status(400).json({ error: 'Unknown action' });
    }
    res.json({ ok: true, task: { id: task.id, status: task.status } });
  });

  // ============ API: CMD 远程执行 ============
  const cmdSessions = new Map();
  let cmdSessionId = 0;

  // 执行命令并返回完整输出（简单模式）
  app_express.post('/api/cmd', auth, (req, res) => {
    const { command, sessionId } = req.body;
    if (!command) return res.status(400).json({ error: 'No command specified' });

    const sid = sessionId || String(++cmdSessionId);

    // 使用 cmd.exe 执行
    const child = spawn('cmd.exe', ['/c', command], {
      cwd: INSTALL_DIR,
      windowsHide: true,
      env: { ...process.env, PROMPT: '$P$G' }
    });

    let stdout = '';
    let stderr = '';

    child.stdout.on('data', (data) => { stdout += data.toString(); });
    child.stderr.on('data', (data) => { stderr += data.toString(); });

    child.on('close', (code) => {
      res.json({
        ok: true,
        sessionId: sid,
        command,
        stdout,
        stderr,
        exitCode: code,
        cwd: INSTALL_DIR
      });
    });

    child.on('error', (err) => {
      res.status(500).json({ error: err.message, sessionId: sid });
    });

    // 超时保护 60 秒
    setTimeout(() => {
      try { child.kill(); } catch(e) {}
    }, 60000);
  });

  // CMD 交互式会话（WebSocket 风格的轮询）
  app_express.post('/api/cmd/session', auth, (req, res) => {
    const { cwd } = req.body;
    const sid = String(++cmdSessionId);
    const workDir = cwd ? resolveSafePath(cwd) : INSTALL_DIR;

    const child = spawn('cmd.exe', [], {
      cwd: workDir || INSTALL_DIR,
      windowsHide: true,
      stdio: ['pipe', 'pipe', 'pipe']
    });

    let outputBuffer = '';
    child.stdout.on('data', (d) => { outputBuffer += d.toString(); });
    child.stderr.on('data', (d) => { outputBuffer += d.toString(); });

    cmdSessions.set(sid, { child, outputBuffer, cwd: workDir || INSTALL_DIR, lastAccess: Date.now() });

    res.json({ ok: true, sessionId: sid, cwd: workDir || INSTALL_DIR });
  });

  // 向会话发送命令
  app_express.post('/api/cmd/session/:id/write', auth, (req, res) => {
    const { id } = req.params;
    const { input } = req.body;
    const session = cmdSessions.get(id);
    if (!session) return res.status(404).json({ error: 'Session not found' });
    try {
      session.child.stdin.write(input + '\r\n');
      session.lastAccess = Date.now();
      res.json({ ok: true });
    } catch(e) {
      res.status(500).json({ error: e.message });
    }
  });

  // 读取会话输出
  app_express.get('/api/cmd/session/:id/read', auth, (req, res) => {
    const { id } = req.params;
    const session = cmdSessions.get(id);
    if (!session) return res.status(404).json({ error: 'Session not found' });
    const output = session.outputBuffer;
    session.outputBuffer = '';
    session.lastAccess = Date.now();
    res.json({ ok: true, output, alive: !session.child.killed });
  });

  // 关闭会话
  app_express.post('/api/cmd/session/:id/close', auth, (req, res) => {
    const { id } = req.params;
    const session = cmdSessions.get(id);
    if (session) {
      try { session.child.kill(); } catch(e) {}
      cmdSessions.delete(id);
    }
    res.json({ ok: true });
  });

  // 清理超时会话（10分钟无访问）
  setInterval(() => {
    const now = Date.now();
    for (const [id, session] of cmdSessions) {
      if (now - session.lastAccess > 600000) {
        try { session.child.kill(); } catch(e) {}
        cmdSessions.delete(id);
      }
    }
  }, 60000);

  // ============ 启动服务 ============
  serverPort = await findAvailablePort(18080);
  server = app_express.listen(serverPort, '0.0.0.0', () => {
    console.log(`iNas server running on http://0.0.0.0:${serverPort}`);
    console.log(`Token: ${authToken}`);
  });

  return { port: serverPort, token: authToken };
}

// ============ Electron 窗口 ============
let mainWindow = null;
let serverInfo = null;

async function createWindow() {
  mainWindow = new BrowserWindow({
    width: 900,
    height: 650,
    title: 'iNas',
    resizable: true,
    backgroundColor: '#1a1a2e',
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false
    }
  });

  // 启动服务器
  try {
    serverInfo = await startServer();
  } catch(e) {
    console.error('Failed to start server:', e);
  }

  mainWindow.loadFile('index.html');

  // 窗口加载完成后推送服务器信息
  mainWindow.webContents.on('did-finish-load', () => {
    if (serverInfo) {
      const ip = getLocalIP();
      const connectUrl = `http://${ip}:${serverInfo.port}`;
      const qrData = JSON.stringify({ ip, port: serverInfo.port, token: serverInfo.token, hostname: os.hostname() });

      QRCode.toDataURL(qrData, { width: 280, margin: 2, color: { dark: '#1a1a2e', light: '#ffffff' } })
        .then(qrImg => {
          mainWindow.webContents.send('server-info', {
            ip,
            port: serverInfo.port,
            token: serverInfo.token,
            connectUrl,
            qrImg,
            hostname: os.hostname(),
            installDir: INSTALL_DIR
          });
        })
        .catch(err => {
          mainWindow.webContents.send('server-info', {
            ip, port: serverInfo.port, token: serverInfo.token,
            connectUrl, qrImg: null, hostname: os.hostname(), installDir: INSTALL_DIR
          });
        });
    }
  });
}

// IPC: 获取服务器信息（轮询备用）
ipcMain.handle('get-server-info', () => {
  if (!serverInfo) return null;
  return {
    ip: getLocalIP(),
    port: serverInfo.port,
    token: serverInfo.token,
    hostname: os.hostname()
  };
});

// IPC: 重置 token
ipcMain.handle('reset-token', () => {
  authToken = crypto.randomBytes(16).toString('hex');
  try { fs.writeFileSync(TOKEN_FILE, JSON.stringify({ token: authToken, created: Date.now() })); } catch(e) {}
  return authToken;
});

app.whenReady().then(() => {
  createWindow();
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (server) { try { server.close(); } catch(e){} }
  if (process.platform !== 'darwin') app.quit();
});
