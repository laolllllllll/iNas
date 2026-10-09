const { app, BrowserWindow, ipcMain } = require('electron');
const path = require('path');
const fs = require('fs');
const os = require('os');
const net = require('net');
const crypto = require('crypto');
const express = require('express');
const multer = require('multer');
const QRCode = require('qrcode');
const AdmZip = require('adm-zip');
const { exec, spawn } = require('child_process');
const http = require('http');
const https = require('https');
// WebTorrent 运行时按需加载（不打包进 asar，首次使用时安装到运行时目录）
let WebTorrent = null;
let wtInstalling = null;

// ============ 配置 ============
const INSTALL_DIR = path.join('C:', 'iNas root');
const DATA_DIR = path.join(INSTALL_DIR, 'System', 'data');
const RECYCLE_BIN = path.join(INSTALL_DIR, '回收站');
const TRASH_META = path.join(RECYCLE_BIN, '.trash.json');
const TOKEN_FILE = path.join(DATA_DIR, 'token.json');
const APP_DIR = path.join(INSTALL_DIR, 'var', 'library', 'Application');
const VAR_DB = path.join(INSTALL_DIR, 'var', 'db');
const DEVICES_FILE = path.join(VAR_DB, 'devices.json');
const MESSAGES_FILE = path.join(VAR_DB, 'messages.json');
const SERVER_NAME_FILE = path.join(DATA_DIR, 'server-name.json');
const PHOTOS_DIR = path.join(INSTALL_DIR, 'Photos');

// 受保护目录定义
const PROTECTED_DIRS = {
  '音乐': 'music',
  'Photos': 'photos',
  '下载': 'download',
  '回收站': 'recycle',
  'System': 'system',
  'var': 'system'
};

// 确保目录存在
[INSTALL_DIR, DATA_DIR, RECYCLE_BIN, APP_DIR, VAR_DB, PHOTOS_DIR,
 path.join(INSTALL_DIR, '音乐'),
 path.join(INSTALL_DIR, '下载')
].forEach(d => { try { fs.mkdirSync(d, { recursive: true }); } catch(e){} });

// 迁移旧的 图片/视频 目录到 Photos
['图片', '视频'].forEach(oldDir => {
  const oldPath = path.join(INSTALL_DIR, oldDir);
  if (fs.existsSync(oldPath)) {
    try {
      const entries = fs.readdirSync(oldPath);
      entries.forEach(f => {
        try { fs.renameSync(path.join(oldPath, f), path.join(PHOTOS_DIR, f)); } catch(e){}
      });
      fs.rmSync(oldPath, { recursive: true, force: true });
    } catch(e){}
  }
});

// 最近删除目录
const RECENTLY_DELETED_DIR = path.join(PHOTOS_DIR, '最近删除');
const RECENTLY_DELETED_META = path.join(RECENTLY_DELETED_DIR, '.deleted.json');
fs.mkdirSync(RECENTLY_DELETED_DIR, { recursive: true });
if (!fs.existsSync(RECENTLY_DELETED_META)) {
  try { fs.writeFileSync(RECENTLY_DELETED_META, JSON.stringify({ items: {} }, null, 2)); } catch(e){}
}

// 确保数据文件存在
if (!fs.existsSync(TRASH_META)) {
  try { fs.writeFileSync(TRASH_META, JSON.stringify({ items: [] }, null, 2)); } catch(e){}
}
if (!fs.existsSync(DEVICES_FILE)) {
  try { fs.writeFileSync(DEVICES_FILE, JSON.stringify({ devices: [] }, null, 2)); } catch(e){}
}
if (!fs.existsSync(MESSAGES_FILE)) {
  try { fs.writeFileSync(MESSAGES_FILE, JSON.stringify({ messages: [] }, null, 2)); } catch(e){}
}

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
function createTask(type, name, total = 0, extra = {}) {
  const id = String(++taskIdCounter);
  taskQueue.set(id, {
    id, type, name,
    status: 'pending',
    progress: 0,
    total,
    transferred: 0,
    speed: 0,
    error: null,
    createdAt: Date.now(),
    _cancel: false,
    _pause: false,
    ...extra
  });
  return id;
}
function updateTask(id, updates) {
  const t = taskQueue.get(id);
  if (t) Object.assign(t, updates);
}

// ============ HTTP 静态服务管理 ============
const httpServers = new Map();

// ============ 临时下载链接管理 ============
const tempDownloads = new Map(); // token -> { filePath, expiresAt, oneTime }

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

// ============ 回收站元数据操作 ============
function readTrashMeta() {
  try {
    return JSON.parse(fs.readFileSync(TRASH_META, 'utf8'));
  } catch(e) {
    return { items: [] };
  }
}
function writeTrashMeta(meta) {
  try { fs.writeFileSync(TRASH_META, JSON.stringify(meta, null, 2)); } catch(e){}
}
function addTrashItem(trashedName, originalPath, originalName) {
  const meta = readTrashMeta();
  meta.items.push({
    filename: trashedName,
    originalPath,
    originalName: originalName || path.basename(originalPath),
    deletedAt: Date.now()
  });
  writeTrashMeta(meta);
}
function findTrashItem(trashedName) {
  const meta = readTrashMeta();
  return meta.items.find(i => i.filename === trashedName);
}
function removeTrashItem(trashedName) {
  const meta = readTrashMeta();
  meta.items = meta.items.filter(i => i.filename !== trashedName);
  writeTrashMeta(meta);
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

  // 路径安全解析（支持多盘符）
  function resolveSafePath(relativePath) {
    if (!relativePath) return INSTALL_DIR;
    // Windows 根目录模式：windows-root 或 windows-root/C/ 或 windows-root/D/sub
    if (relativePath === 'windows-root' || relativePath === '/') {
      return 'C:\\';
    }
    if (relativePath.startsWith('windows-root/')) {
      const sub = relativePath.substring('windows-root/'.length);
      if (!sub) return 'C:\\';
      // sub 格式: C 或 C/Users 或 D/folder
      const parts = sub.split('/');
      const drive = parts[0].toUpperCase(); // C, D, E...
      if (!/^[A-Z]$/.test(drive)) return null;
      const rest = parts.slice(1).join('\\');
      return rest ? path.join(`${drive}:\\`, rest) : `${drive}:\\`;
    }
    // 默认 iNas root
    const clean = relativePath.replace(/^\/+/, '');
    const resolved = path.join(INSTALL_DIR, clean);
    if (!resolved.startsWith(INSTALL_DIR) && resolved !== INSTALL_DIR) {
      return null;
    }
    return resolved;
  }

  // 构建文件项（含受保护标记）
  function buildFileItem(name, fullPath, relPath, st) {
    const isDir = st.isDirectory();
    const item = {
      name,
      path: relPath ? `${relPath}/${name}` : name,
      size: isDir ? 0 : Math.trunc(st.size),
      modified: Math.trunc(st.mtimeMs),
      isDirectory: isDir,
      protected: false,
      specialType: null
    };
    // 检查是否为受保护目录（仅 iNas Root 下）
    if (isDir && PROTECTED_DIRS[name]) {
      const specialType = PROTECTED_DIRS[name];
      // System 目录标记为 system，调用方会过滤
      item.protected = true;
      item.specialType = specialType;
      // 显示名称映射
      if (specialType === 'photos') item.displayName = '相册';
      if (specialType === 'music') item.displayName = '音乐';
      if (specialType === 'download') item.displayName = '下载';
      if (specialType === 'recycle') item.displayName = '废纸篓';
    }
    return item;
  }

  // ============ API: 状态 ============
  app_express.get('/api/status', (req, res) => {
    res.json({
      ok: true,
      version: '2.2026.1010',
      hostname: os.hostname(),
      platform: os.platform(),
      totalMem: Math.trunc(os.totalmem()),
      freeMem: Math.trunc(os.freemem()),
      uptime: os.uptime()
    });
  });

  // ============ API: 可用盘符列表 ============
  app_express.get('/api/drives', auth, (req, res) => {
    const drives = [];
    for (let i = 67; i <= 90; i++) { // C to Z
      const letter = String.fromCharCode(i);
      const drivePath = `${letter}:\\`;
      try {
        if (fs.existsSync(drivePath)) {
          const stat = fs.statSync(drivePath);
          drives.push({
            name: `${letter}:`,
            letter,
            type: 'fixed',
            ready: stat.isDirectory()
          });
        }
      } catch(e) {}
    }
    res.json({ drives });
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
          size: Math.trunc(stat.size),
          modified: Math.trunc(stat.mtimeMs),
          isDirectory: false
        });
      }
      const entries = fs.readdirSync(target);
      const files = [];
      const dirs = [];
      for (const name of entries) {
        // 跳过隐藏元数据文件
        if (name === '.trash.json') continue;
        const fullPath = path.join(target, name);
        try {
          const st = fs.statSync(fullPath);
          const item = buildFileItem(name, fullPath, relPath, st);
          // 过滤 system 类型目录（不返回给前端）
          if (item.specialType === 'system') continue;
          // 回收站项目：附加 originalName
          if (target === RECYCLE_BIN) {
            const ti = findTrashItem(name);
            if (ti && ti.originalName) item.originalName = ti.originalName;
          }
          if (st.isDirectory()) dirs.push(item);
          else files.push(item);
        } catch(e) {}
      }
      dirs.sort((a,b) => a.name.localeCompare(b.name, 'zh-CN'));
      files.sort((a,b) => a.name.localeCompare(b.name, 'zh-CN'));
      // 判断当前目录是否为回收站
      const isRecycle = target === RECYCLE_BIN;
      res.json({
        type: 'directory',
        path: relPath,
        name: path.basename(target) || (relPath.startsWith('windows-root') ? `Windows (${relPath.split('/')[1] || 'C'}:)` : 'iNas Root'),
        isRecycle,
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

  // ============ API: 临时下载（带 token，无需 x-nas-token） ============
  app_express.get('/api/temp-download/:token', (req, res) => {
    const { token } = req.params;
    const dl = tempDownloads.get(token);
    if (!dl) return res.status(404).json({ error: 'Link expired or invalid' });
    if (dl.expiresAt < Date.now()) {
      tempDownloads.delete(token);
      return res.status(410).json({ error: 'Link expired' });
    }
    const target = resolveSafePath(dl.filePath);
    if (!target || !fs.existsSync(target)) {
      return res.status(404).json({ error: 'File not found' });
    }
    if (dl.oneTime) tempDownloads.delete(token);
    const stat = fs.statSync(target);
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
    limits: { fileSize: 1024 * 1024 * 1024 * 10 }
  });
  app_express.post('/api/upload', auth, upload.single('file'), (req, res) => {
    if (!req.file) return res.status(400).json({ error: 'No file uploaded' });
    res.json({
      ok: true,
      filename: req.file.filename,
      size: Math.trunc(req.file.size),
      path: req.body.path || ''
    });
  });

  // ============ API: 从 URL 上传 ============
  app_express.post('/api/upload-url', auth, (req, res) => {
    const { url, path: targetPath } = req.body;
    if (!url) return res.status(400).json({ error: 'URL required' });
    const target = resolveSafePath(targetPath || '');
    if (!target || !fs.existsSync(target)) {
      return res.status(400).json({ error: 'Invalid target path' });
    }
    const fileName = url.split('/').pop().split('?')[0] || `download_${Date.now()}`;
    const destPath = path.join(target, fileName);
    const taskId = createTask('url-download', `下载: ${fileName}`, 0, { sourceUrl: url, destPath });
    updateTask(taskId, { status: 'pending' });
    res.json({ ok: true, taskId, filename: fileName });
    setTimeout(processDownloadQueue, 100);
  });

  // ============ API: 删除文件（移入回收站） ============
  app_express.post('/api/delete', auth, (req, res) => {
    const relPath = req.body.path || '';
    const target = resolveSafePath(relPath);
    if (!target || !fs.existsSync(target)) {
      return res.status(404).json({ error: 'File not found' });
    }
    // 不允许删除受保护目录
    const baseName = path.basename(target);
    if (PROTECTED_DIRS[baseName]) {
      return res.status(403).json({ error: 'Protected directory cannot be deleted' });
    }
    try {
      const fileName = path.basename(target);
      const trashedName = `${Date.now()}_${fileName}`;
      const dest = path.join(RECYCLE_BIN, trashedName);
      fs.renameSync(target, dest);
      addTrashItem(trashedName, target, fileName);
      res.json({ ok: true, movedTo: dest });
    } catch(e) {
      try {
        const fileName = path.basename(target);
        const trashedName = `${Date.now()}_${fileName}`;
        const dest = path.join(RECYCLE_BIN, trashedName);
        if (fs.statSync(target).isDirectory()) {
          fs.cpSync(target, dest, { recursive: true });
          fs.rmSync(target, { recursive: true, force: true });
        } else {
          fs.copyFileSync(target, dest);
          fs.unlinkSync(target);
        }
        addTrashItem(trashedName, target, fileName);
        res.json({ ok: true, movedTo: dest });
      } catch(e2) {
        res.status(500).json({ error: e2.message });
      }
    }
  });

  // ============ API: 回收站 - 恢复文件 ============
  app_express.post('/api/recycle/restore', auth, (req, res) => {
    const { path: relPath } = req.body;
    if (!relPath) return res.status(400).json({ error: 'Path required' });
    // relPath 格式如: 回收站/1234567890_filename
    const trashedName = path.basename(relPath);
    const trashItem = findTrashItem(trashedName);
    if (!trashItem) {
      return res.status(404).json({ error: 'Trash item metadata not found' });
    }
    const src = path.join(RECYCLE_BIN, trashedName);
    if (!fs.existsSync(src)) {
      removeTrashItem(trashedName);
      return res.status(404).json({ error: 'File not found in recycle bin' });
    }
    try {
      const dest = trashItem.originalPath;
      // 确保目标目录存在
      fs.mkdirSync(path.dirname(dest), { recursive: true });
      // 如果目标已存在，加后缀
      let finalDest = dest;
      let counter = 1;
      while (fs.existsSync(finalDest)) {
        const ext = path.extname(dest);
        const base = path.basename(dest, ext);
        finalDest = path.join(path.dirname(dest), `${base}_恢复${counter}${ext}`);
        counter++;
      }
      fs.renameSync(src, finalDest);
      removeTrashItem(trashedName);
      res.json({ ok: true, restoredTo: finalDest });
    } catch(e) {
      res.status(500).json({ error: e.message });
    }
  });

  // ============ API: 回收站 - 清空 ============
  app_express.post('/api/recycle/empty', auth, (req, res) => {
    try {
      const entries = fs.readdirSync(RECYCLE_BIN);
      for (const name of entries) {
        if (name === '.trash.json') continue;
        const fullPath = path.join(RECYCLE_BIN, name);
        try {
          if (fs.statSync(fullPath).isDirectory()) {
            fs.rmSync(fullPath, { recursive: true, force: true });
          } else {
            fs.unlinkSync(fullPath);
          }
        } catch(e){}
      }
      writeTrashMeta({ items: [] });
      res.json({ ok: true, cleared: entries.length - 1 });
    } catch(e) {
      res.status(500).json({ error: e.message });
    }
  });

  // ============ API: 重命名 ============
  app_express.post('/api/rename', auth, (req, res) => {
    const { path: relPath, newName } = req.body;
    const target = resolveSafePath(relPath);
    if (!target || !fs.existsSync(target)) {
      return res.status(404).json({ error: 'File not found' });
    }
    const baseName = path.basename(target);
    if (PROTECTED_DIRS[baseName]) {
      return res.status(403).json({ error: 'Protected directory cannot be renamed' });
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
    (async () => {
      try {
        const srcStat = fs.statSync(src);
        let totalSize = srcStat.size;
        if (srcStat.isDirectory()) totalSize = await calcDirSize(src);
        updateTask(taskId, { total: totalSize });
        const destPath = path.join(dst, path.basename(src));
        if (srcStat.isDirectory()) await copyDirWithProgress(src, destPath, taskId);
        else await copyFileWithProgress(src, destPath, taskId);
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
      if (entry.isDirectory()) await copyDirWithProgress(srcFull, dstFull, taskId);
      else await copyFileWithProgress(srcFull, dstFull, taskId);
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

  // ============ API: 创建空文件 ============
  app_express.post('/api/create-file', auth, (req, res) => {
    const { path: relPath, filename } = req.body;
    if (!filename) return res.status(400).json({ error: 'Filename required' });
    const target = resolveSafePath(relPath || '');
    if (!target) return res.status(400).json({ error: 'Invalid path' });
    try {
      const filePath = path.join(target, filename);
      if (fs.existsSync(filePath)) {
        return res.status(409).json({ error: 'File already exists' });
      }
      fs.writeFileSync(filePath, '');
      res.json({ ok: true, path: relPath ? `${relPath}/${filename}` : filename });
    } catch(e) {
      res.status(500).json({ error: e.message });
    }
  });

  // ============ API: 读取/写入文本 ============
  app_express.get('/api/read-text', auth, (req, res) => {
    const relPath = req.query.path || '';
    const target = resolveSafePath(relPath);
    if (!target || !fs.existsSync(target)) return res.status(404).json({ error: 'File not found' });
    try {
      const content = fs.readFileSync(target, 'utf8');
      res.json({ ok: true, content, path: relPath });
    } catch(e) { res.status(500).json({ error: e.message }); }
  });
  app_express.post('/api/write-text', auth, (req, res) => {
    const { path: relPath, content } = req.body;
    const target = resolveSafePath(relPath);
    if (!target) return res.status(400).json({ error: 'Invalid path' });
    try {
      fs.mkdirSync(path.dirname(target), { recursive: true });
      fs.writeFileSync(target, content, 'utf8');
      res.json({ ok: true });
    } catch(e) { res.status(500).json({ error: e.message }); }
  });

  // ============ API: 启用 HTTP 静态文件服务 ============
  app_express.post('/api/http-server/start', auth, async (req, res) => {
    const { path: relPath } = req.body;
    if (!relPath) return res.status(400).json({ error: 'Path required' });
    const target = resolveSafePath(relPath);
    if (!target || !fs.existsSync(target)) {
      return res.status(404).json({ error: 'Directory not found' });
    }
    try {
      const port = await findAvailablePort(18000 + Math.floor(Math.random() * 1000));
      const staticApp = express();
      staticApp.use(express.static(target, { dotfiles: 'allow' }));
      const httpServer = staticApp.listen(port, '0.0.0.0', () => {
        console.log(`HTTP static server on port ${port} for ${target}`);
      });
      const ip = getLocalIP();
      const url = `http://${ip}:${port}/`;
      const taskId = createTask('http-server', `HTTP服务: ${path.basename(target)}`, 0, {
        url, port, servePath: target
      });
      updateTask(taskId, { status: 'running', progress: 100 });
      httpServers.set(taskId, httpServer);
      res.json({ ok: true, taskId, url, port });
    } catch(e) {
      res.status(500).json({ error: e.message });
    }
  });

  // ============ API: 停止 HTTP 服务 ============
  app_express.post('/api/http-server/stop', auth, (req, res) => {
    const { taskId } = req.body;
    if (!taskId) return res.status(400).json({ error: 'taskId required' });
    const httpServer = httpServers.get(taskId);
    if (httpServer) {
      try { httpServer.close(); } catch(e){}
      httpServers.delete(taskId);
    }
    updateTask(taskId, { status: 'cancelled' });
    res.json({ ok: true });
  });

  // ============ API: 生成下载链接 ============
  app_express.post('/api/download-link', auth, (req, res) => {
    const { path: relPath } = req.body;
    if (!relPath) return res.status(400).json({ error: 'Path required' });
    const target = resolveSafePath(relPath);
    if (!target || !fs.existsSync(target)) {
      return res.status(404).json({ error: 'File not found' });
    }
    if (fs.statSync(target).isDirectory()) {
      return res.status(400).json({ error: 'Cannot create link for directory' });
    }
    const token = crypto.randomBytes(16).toString('hex');
    const expiresAt = Date.now() + 24 * 60 * 60 * 1000; // 24小时
    tempDownloads.set(token, { filePath: relPath, expiresAt, oneTime: false });
    const ip = getLocalIP();
    const url = `http://${ip}:${serverPort}/api/temp-download/${token}`;
    const taskId = createTask('download-link', `下载链接: ${path.basename(target)}`, 0, {
      url, token, expiresAt
    });
    updateTask(taskId, { status: 'running', progress: 100 });
    res.json({ ok: true, taskId, url, expiresAt });
  });

  // ============ API: 使下载链接失效 ============
  app_express.post('/api/download-link/revoke', auth, (req, res) => {
    const { taskId } = req.body;
    const task = taskQueue.get(taskId);
    if (task && task.token) {
      tempDownloads.delete(task.token);
    }
    updateTask(taskId, { status: 'cancelled' });
    res.json({ ok: true });
  });

  // ============ API: 队列状态/操作 ============
  app_express.get('/api/queue', auth, (req, res) => {
    const tasks = Array.from(taskQueue.values())
      .map(t => {
        const { _cancel, _pause, ...publicTask } = t;
        return publicTask;
      })
      .sort((a,b) => b.createdAt - a.createdAt);
    res.json({ tasks });
  });
  app_express.post('/api/queue/:id/:action', auth, (req, res) => {
    const { id, action } = req.params;
    const task = taskQueue.get(id);
    if (!task) return res.status(404).json({ error: 'Task not found' });
    switch(action) {
      case 'pause':
        task._pause = true; task.status = 'paused'; break;
      case 'resume':
        task._pause = false; task.status = 'running'; break;
      case 'cancel':
        task._cancel = true; task.status = 'cancelled';
        // 如果是 HTTP 服务，同时关闭
        if (task.type === 'http-server') {
          const srv = httpServers.get(id);
          if (srv) { try { srv.close(); } catch(e){} httpServers.delete(id); }
        }
        // 如果是下载链接，同时失效
        if (task.type === 'download-link' && task.token) {
          tempDownloads.delete(task.token);
        }
        break;
      case 'remove':
        taskQueue.delete(id); break;
      default:
        return res.status(400).json({ error: 'Unknown action' });
    }
    res.json({ ok: true, task: { id: task.id, status: task.status } });
  });

  // ============ API: 清空队列（仅已结束任务） ============
  app_express.post('/api/queue/clear', auth, (req, res) => {
    let cleared = 0;
    for (const [id, task] of taskQueue) {
      if (['completed', 'failed', 'cancelled'].includes(task.status)) {
        // 清理关联资源
        if (task.type === 'http-server') {
          const srv = httpServers.get(id);
          if (srv) { try { srv.close(); } catch(e){} httpServers.delete(id); }
        }
        if (task.type === 'download-link' && task.token) tempDownloads.delete(task.token);
        taskQueue.delete(id);
        cleared++;
      }
    }
    res.json({ ok: true, cleared });
  });

  // ============ 下载调度器（最多3并发） ============
  const MAX_CONCURRENT_DOWNLOADS = 3;
  const btClients = new Map(); // taskId -> WebTorrent client
  let wtClient = null;
  // 运行时按需安装 webtorrent 到可写目录，避免打包进 asar 导致构建超时
  async function ensureWebTorrent() {
    if (WebTorrent) return WebTorrent;
    if (wtInstalling) return wtInstalling;
    wtInstalling = (async () => {
      const btDir = path.join(INSTALL_DIR, 'var', 'bt-runtime');
      fs.mkdirSync(btDir, { recursive: true });
      const pkgPath = path.join(btDir, 'package.json');
      if (!fs.existsSync(pkgPath)) {
        fs.writeFileSync(pkgPath, JSON.stringify({ name: 'inas-bt-runtime', version: '1.0.0', private: true }, null, 2));
      }
      const modPath = path.join(btDir, 'node_modules', 'webtorrent');
      if (!fs.existsSync(modPath)) {
        console.log('Installing webtorrent to runtime dir...');
        await new Promise((resolve, reject) => {
          child_process.exec('npm install webtorrent@2.1.36 --no-save --omit=dev', { cwd: btDir, timeout: 120000 }, (err, stdout, stderr) => {
            if (err) { console.error('npm install webtorrent failed:', stderr || err.message); reject(err); }
            else { console.log('webtorrent installed'); resolve(); }
          });
        });
      }
      WebTorrent = require(modPath);
      return WebTorrent;
    })();
    try { return await wtInstalling; } finally { wtInstalling = null; }
  }
  function getWTClient() {
    if (!wtClient && WebTorrent) {
      try { wtClient = new WebTorrent(); } catch(e) { console.log('WebTorrent init failed:', e.message); }
    }
    return wtClient;
  }
  function processDownloadQueue() {
    const active = Array.from(taskQueue.values()).filter(t => t.status === 'downloading' && (t.type === 'url-download' || t.type === 'bt-download')).length;
    if (active >= MAX_CONCURRENT_DOWNLOADS) return;
    const pending = Array.from(taskQueue.values())
      .filter(t => t.status === 'pending' && (t.type === 'url-download' || t.type === 'bt-download'))
      .sort((a, b) => a.createdAt - b.createdAt);
    for (const task of pending) {
      if (active >= MAX_CONCURRENT_DOWNLOADS) break;
      if (task.type === 'url-download') startUrlDownload(task.id);
      else if (task.type === 'bt-download') startBTDownload(task.id);
    }
  }

  // ============ API: BT 下载 ============
  app_express.post('/api/bt/download', auth, (req, res) => {
    const { torrentPath, destPath } = req.body;
    if (!torrentPath) return res.status(400).json({ error: 'torrentPath required' });
    const torrentFull = resolveSafePath(torrentPath);
    if (!torrentFull || !fs.existsSync(torrentFull)) return res.status(404).json({ error: 'Torrent file not found' });
    const dest = destPath ? resolveSafePath(destPath) : path.join(INSTALL_DIR, '下载');
    if (!dest) return res.status(400).json({ error: 'Invalid dest path' });
    fs.mkdirSync(dest, { recursive: true });
    const taskId = createTask('bt-download', `BT: ${path.basename(torrentPath)}`, 0, {
      torrentPath: torrentFull, destPath: dest, status: 'pending'
    });
    updateTask(taskId, { status: 'pending' });
    res.json({ ok: true, taskId });
    setTimeout(processDownloadQueue, 100);
  });

  async function startBTDownload(taskId) {
    const task = taskQueue.get(taskId);
    if (!task) return;
    updateTask(taskId, { status: 'downloading' });
    try { await ensureWebTorrent(); } catch(e) {
      updateTask(taskId, { status: 'failed', error: 'WebTorrent install failed: ' + e.message });
      processDownloadQueue(); return;
    }
    const wt = getWTClient();
    if (!wt) { updateTask(taskId, { status: 'failed', error: 'WebTorrent init failed' }); processDownloadQueue(); return; }
    try {
      const torrentBuf = fs.readFileSync(task.torrentPath);
      wt.add(torrentBuf, { path: task.destPath }, (torrent) => {
        btClients.set(taskId, torrent);
        torrent.on('download', () => {
          const t = taskQueue.get(taskId);
          if (!t) return;
          const progress = torrent.length > 0 ? (torrent.downloaded / torrent.length * 100) : 0;
          updateTask(taskId, {
            progress: Math.min(100, Math.trunc(progress)),
            total: torrent.length,
            transferred: torrent.downloaded,
            speed: torrent.downloadSpeed,
            peers: torrent.numPeers
          });
        });
        torrent.on('done', () => {
          updateTask(taskId, { status: 'completed', progress: 100, transferred: torrent.length });
          btClients.delete(taskId);
          processDownloadQueue();
        });
        torrent.on('error', (err) => {
          updateTask(taskId, { status: 'failed', error: err.message });
          btClients.delete(taskId);
          processDownloadQueue();
        });
      });
    } catch(e) {
      updateTask(taskId, { status: 'failed', error: e.message });
      processDownloadQueue();
    }
  }

  app_express.get('/api/bt/status/:taskId', auth, (req, res) => {
    const task = taskQueue.get(req.params.taskId);
    if (!task) return res.status(404).json({ error: 'Task not found' });
    const { _cancel, _pause, ...pub } = task;
    res.json(pub);
  });

  app_express.post('/api/bt/cancel/:taskId', auth, (req, res) => {
    const taskId = req.params.taskId;
    const task = taskQueue.get(taskId);
    if (!task) return res.status(404).json({ error: 'Task not found' });
    const torrent = btClients.get(taskId);
    if (torrent) { try { torrent.destroy(); } catch(e){} btClients.delete(taskId); }
    updateTask(taskId, { status: 'cancelled' });
    res.json({ ok: true });
    processDownloadQueue();
  });

  // ============ URL 下载调度（从 upload-url 重构为队列式） ============
  function startUrlDownload(taskId) {
    const task = taskQueue.get(taskId);
    if (!task) return;
    updateTask(taskId, { status: 'downloading' });
    const { sourceUrl, destPath } = task;
    const client = sourceUrl.startsWith('https') ? https : http;
    (async () => {
      try {
        await new Promise((resolve, reject) => {
          const fileStream = fs.createWriteStream(destPath);
          client.get(sourceUrl, (response) => {
            if (response.statusCode >= 300 && response.statusCode < 400 && response.headers.location) {
              const rUrl = response.headers.location;
              const rClient = rUrl.startsWith('https') ? https : http;
              rClient.get(rUrl, (r2) => {
                const total = parseInt(r2.headers['content-length'] || '0', 10);
                updateTask(taskId, { total });
                let transferred = 0;
                r2.on('data', (chunk) => {
                  transferred += chunk.length;
                  updateTask(taskId, { transferred, progress: total > 0 ? Math.min(100, Math.trunc(transferred/total*100)) : 0, speed: r2.socket ? r2.socket.bytesRead*8/1024 : 0 });
                });
                r2.pipe(fileStream);
                fileStream.on('finish', resolve);
                r2.on('error', reject);
              }).on('error', reject);
              return;
            }
            const total = parseInt(response.headers['content-length'] || '0', 10);
            updateTask(taskId, { total });
            let transferred = 0;
            response.on('data', (chunk) => {
              transferred += chunk.length;
              updateTask(taskId, { transferred, progress: total > 0 ? Math.min(100, Math.trunc(transferred/total*100)) : 0 });
            });
            response.pipe(fileStream);
            fileStream.on('finish', resolve);
            response.on('error', reject);
          }).on('error', reject);
        });
        updateTask(taskId, { status: 'completed', progress: 100 });
      } catch(e) {
        updateTask(taskId, { status: 'failed', error: e.message });
        try { fs.unlinkSync(task.destPath); } catch(e2){}
      }
      processDownloadQueue();
    })();
  }

  // ============ API: CMD 远程执行（UTF-8） ============
  const cmdSessions = new Map();
  let cmdSessionId = 0;

  app_express.post('/api/cmd', auth, (req, res) => {
    const { command, sessionId } = req.body;
    if (!command) return res.status(400).json({ error: 'No command specified' });
    const sid = sessionId || String(++cmdSessionId);
    // 先 chcp 65001 切换 UTF-8，再执行命令
    const fullCommand = `chcp 65001 >nul && ${command}`;
    const child = spawn('cmd.exe', ['/c', fullCommand], {
      cwd: INSTALL_DIR,
      windowsHide: true,
      env: { ...process.env, PROMPT: '$P$G' }
    });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (data) => { stdout += data.toString('utf8'); });
    child.stderr.on('data', (data) => { stderr += data.toString('utf8'); });
    child.on('close', (code) => {
      res.json({ ok: true, sessionId: sid, command, stdout, stderr, exitCode: code, cwd: INSTALL_DIR });
    });
    child.on('error', (err) => {
      res.status(500).json({ error: err.message, sessionId: sid });
    });
    setTimeout(() => { try { child.kill(); } catch(e) {} }, 60000);
  });

  // CMD 交互式会话
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
    child.stdout.on('data', (d) => { outputBuffer += d.toString('utf8'); });
    child.stderr.on('data', (d) => { outputBuffer += d.toString('utf8'); });
    cmdSessions.set(sid, { child, outputBuffer, cwd: workDir || INSTALL_DIR, lastAccess: Date.now() });
    // 会话启动时切换 UTF-8 代码页
    try { child.stdin.write('chcp 65001 >nul\r\n'); } catch(e){}
    res.json({ ok: true, sessionId: sid, cwd: workDir || INSTALL_DIR });
  });
  app_express.post('/api/cmd/session/:id/write', auth, (req, res) => {
    const { id } = req.params;
    const { input } = req.body;
    const session = cmdSessions.get(id);
    if (!session) return res.status(404).json({ error: 'Session not found' });
    try {
      session.child.stdin.write(input + '\r\n');
      session.lastAccess = Date.now();
      res.json({ ok: true });
    } catch(e) { res.status(500).json({ error: e.message }); }
  });
  app_express.get('/api/cmd/session/:id/read', auth, (req, res) => {
    const { id } = req.params;
    const session = cmdSessions.get(id);
    if (!session) return res.status(404).json({ error: 'Session not found' });
    const output = session.outputBuffer;
    session.outputBuffer = '';
    session.lastAccess = Date.now();
    res.json({ ok: true, output, alive: !session.child.killed });
  });
  app_express.post('/api/cmd/session/:id/close', auth, (req, res) => {
    const { id } = req.params;
    const session = cmdSessions.get(id);
    if (session) { try { session.child.kill(); } catch(e){} cmdSessions.delete(id); }
    res.json({ ok: true });
  });
  setInterval(() => {
    const now = Date.now();
    for (const [id, session] of cmdSessions) {
      if (now - session.lastAccess > 600000) {
        try { session.child.kill(); } catch(e){}
        cmdSessions.delete(id);
      }
    }
  }, 60000);

  // 清理过期临时下载链接
  setInterval(() => {
    const now = Date.now();
    for (const [token, dl] of tempDownloads) {
      if (dl.expiresAt < now) tempDownloads.delete(token);
    }
  }, 300000);


  // ============ v2: 设备连接与命名 ============
  app_express.post('/api/connect', auth, (req, res) => {
    const { deviceName } = req.body;
    if (!deviceName || !deviceName.trim()) {
      return res.status(400).json({ error: 'Device name required' });
    }
    const name = deviceName.trim();
    try {
      const data = JSON.parse(fs.readFileSync(DEVICES_FILE, 'utf8'));
      // 检查重名
      const existing = data.devices.find(d => d.name === name);
      if (existing) {
        // 更新连接时间
        existing.lastConnected = Date.now();
        fs.writeFileSync(DEVICES_FILE, JSON.stringify(data, null, 2));
        return res.json({ ok: true, deviceId: existing.id, name });
      }
      // 限制最多10台
      if (data.devices.length >= 10) {
        return res.status(403).json({ error: 'Maximum 10 devices reached' });
      }
      const deviceId = crypto.randomBytes(8).toString('hex');
      data.devices.push({ id: deviceId, name, connectedAt: Date.now(), lastConnected: Date.now() });
      fs.writeFileSync(DEVICES_FILE, JSON.stringify(data, null, 2));
      res.json({ ok: true, deviceId, name });
    } catch(e) {
      res.status(500).json({ error: e.message });
    }
  });

  // ============ v2: 设备管理 ============
  app_express.get('/api/devices', auth, (req, res) => {
    try {
      const data = JSON.parse(fs.readFileSync(DEVICES_FILE, 'utf8'));
      res.json({ devices: data.devices });
    } catch(e) { res.status(500).json({ error: e.message }); }
  });
  app_express.delete('/api/devices/:id', auth, (req, res) => {
    try {
      const data = JSON.parse(fs.readFileSync(DEVICES_FILE, 'utf8'));
      data.devices = data.devices.filter(d => d.id !== req.params.id);
      fs.writeFileSync(DEVICES_FILE, JSON.stringify(data, null, 2));
      res.json({ ok: true });
    } catch(e) { res.status(500).json({ error: e.message }); }
  });

  // ============ v2: 电源控制 ============
  app_express.post('/api/power/shutdown', auth, (req, res) => {
    res.json({ ok: true, message: 'Shutting down...' });
    setTimeout(() => { exec('shutdown /s /t 0', (err) => { if (err) console.error(err); }); }, 1000);
  });
  app_express.post('/api/power/restart', auth, (req, res) => {
    res.json({ ok: true, message: 'Restarting...' });
    setTimeout(() => { exec('shutdown /r /t 0', (err) => { if (err) console.error(err); }); }, 1000);
  });

  // ============ v2: 设置 - 服务器名字 ============
  app_express.get('/api/settings/server-name', auth, (req, res) => {
    try {
      let name = os.hostname();
      if (fs.existsSync(SERVER_NAME_FILE)) {
        const d = JSON.parse(fs.readFileSync(SERVER_NAME_FILE, 'utf8'));
        name = d.name || os.hostname();
      }
      res.json({ name });
    } catch(e) { res.json({ name: os.hostname() }); }
  });
  app_express.post('/api/settings/server-name', auth, (req, res) => {
    const { name } = req.body;
    if (!name) return res.status(400).json({ error: 'Name required' });
    try {
      fs.writeFileSync(SERVER_NAME_FILE, JSON.stringify({ name, updatedAt: Date.now() }));
      res.json({ ok: true, name });
    } catch(e) { res.status(500).json({ error: e.message }); }
  });

  // ============ v2: 服务器信息 ============
  app_express.get('/api/server-info', auth, (req, res) => {
    try {
      let serverName = os.hostname();
      if (fs.existsSync(SERVER_NAME_FILE)) {
        serverName = JSON.parse(fs.readFileSync(SERVER_NAME_FILE, 'utf8')).name || os.hostname();
      }
      // 统计文件数量
      let musicCount = 0, appCount = 0, photoCount = 0;
      try { musicCount = fs.readdirSync(path.join(INSTALL_DIR, '音乐')).length; } catch(e){}
      try { appCount = fs.readdirSync(APP_DIR).filter(d => d.endsWith('.app')).length; } catch(e){}
      try { photoCount = fs.readdirSync(PHOTOS_DIR).length; } catch(e){}
      // 磁盘空间
      const drives = [];
      for (let i = 67; i <= 90; i++) {
        const letter = String.fromCharCode(i);
        const dp = `${letter}:\\`;
        try {
          if (fs.existsSync(dp)) {
            const { execSync } = require('child_process');
            try {
              const out = execSync(`wmic logicaldisk where "DeviceID='${letter}:'" get Size,FreeSpace /format:csv`, { encoding: 'utf8' });
              const lines = out.trim().split('\n').filter(l => l.includes(','));
              if (lines.length > 0) {
                const parts = lines[0].split(',');
                const freeSpace = parseInt(parts[1]) || 0;
                const size = parseInt(parts[2]) || 0;
                drives.push({ letter, name: `${letter}:`, size, freeSpace, used: size - freeSpace });
              }
            } catch(e2) { drives.push({ letter, name: `${letter}:`, size: 0, freeSpace: 0, used: 0 }); }
          }
        } catch(e){}
      }
      res.json({
        serverName,
        hostname: os.hostname(),
        windowsVersion: `${os.release()} (${os.version()})`,
        inasVersion: '2.2026.1010',
        stats: { musicCount, appCount, photoCount },
        drives,
        totalMem: Math.trunc(os.totalmem()),
        freeMem: Math.trunc(os.freemem())
      });
    } catch(e) { res.status(500).json({ error: e.message }); }
  });

  // ============ v2: 服务管理 ============
  app_express.post('/api/service/stop', auth, (req, res) => {
    res.json({ ok: true, message: 'Stopping iNas service...' });
    setTimeout(() => { app.quit(); }, 500);
  });
  app_express.post('/api/service/restart', auth, (req, res) => {
    res.json({ ok: true, message: 'Restarting iNas service...' });
    setTimeout(() => { app.relaunch(); app.quit(); }, 500);
  });

  // ============ v2: 消息系统 ============
  app_express.get('/api/messages', auth, (req, res) => {
    try {
      const data = JSON.parse(fs.readFileSync(MESSAGES_FILE, 'utf8'));
      res.json({ messages: data.messages.slice(-200) });
    } catch(e) { res.json({ messages: [] }); }
  });
  app_express.post('/api/messages', auth, (req, res) => {
    const { deviceName, content } = req.body;
    if (!deviceName || !content) return res.status(400).json({ error: 'deviceName and content required' });
    try {
      const data = JSON.parse(fs.readFileSync(MESSAGES_FILE, 'utf8'));
      const msg = { id: crypto.randomBytes(8).toString('hex'), deviceName: deviceName.trim(), content: content.trim(), timestamp: Date.now() };
      data.messages.push(msg);
      if (data.messages.length > 500) data.messages = data.messages.slice(-500);
      fs.writeFileSync(MESSAGES_FILE, JSON.stringify(data, null, 2));
      res.json({ ok: true, message: msg });
    } catch(e) { res.status(500).json({ error: e.message }); }
  });

  // ============ v2: NAP 应用管理 ============
  const napUpload = multer({ storage: multer.diskStorage({
    destination: (req, file, cb) => cb(null, require('os').tmpdir()),
    filename: (req, file, cb) => cb(null, `nap_${Date.now()}.nap`)
  })});

  function parseAppInfo(appPath) {
    try {
      const infoPlistPath = path.join(appPath, 'Info.plist');
      if (!fs.existsSync(infoPlistPath)) return null;
      const content = fs.readFileSync(infoPlistPath, 'utf8');
      // 简单解析 plist XML
      const bundleId = (content.match(/<key>CFBundleIdentifier<\/key>\s*<string>([^<]+)<\/string>/) || [])[1] || '';
      const name = (content.match(/<key>CFBundleName<\/key>\s*<string>([^<]+)<\/string>/) || [])[1] || path.basename(appPath, '.app');
      const version = (content.match(/<key>CFBundleShortVersionString<\/key>\s*<string>([^<]+)<\/string>/) || [])[1] || '1.0';
      const icon = (content.match(/<key>CFBundleIconFile<\/key>\s*<string>([^<]+)<\/string>/) || [])[1] || '';
      return { bundleId, name, version, icon, path: appPath };
    } catch(e) { return null; }
  }

  app_express.get('/api/apps', auth, (req, res) => {
    try {
      if (!fs.existsSync(APP_DIR)) return res.json({ apps: [] });
      const entries = fs.readdirSync(APP_DIR).filter(d => d.endsWith('.app'));
      const apps = [];
      for (const entry of entries) {
        const info = parseAppInfo(path.join(APP_DIR, entry));
        if (info) apps.push(info);
      }
      res.json({ apps });
    } catch(e) { res.status(500).json({ error: e.message }); }
  });

  app_express.post('/api/apps/install', auth, napUpload.single('file'), async (req, res) => {
    let napPath = null;
    let extractDir = null;
    try {
      // 确保应用目录存在
      fs.mkdirSync(APP_DIR, { recursive: true });

      if (req.file) {
        napPath = req.file.path;
      } else if (req.body && req.body.url) {
        const url = req.body.url;
        napPath = path.join(os.tmpdir(), `nap_dl_${Date.now()}.nap`);
        const client = url.startsWith('https') ? https : http;
        await new Promise((resolve, reject) => {
          const fileStream = fs.createWriteStream(napPath);
          client.get(url, (response) => {
            if (response.statusCode >= 300 && response.statusCode < 400 && response.headers.location) {
              const rUrl = response.headers.location;
              const rc = rUrl.startsWith('https') ? https : http;
              rc.get(rUrl, (r2) => { r2.pipe(fileStream); fileStream.on('finish', resolve); }).on('error', reject);
              return;
            }
            response.pipe(fileStream);
            fileStream.on('finish', resolve);
          }).on('error', reject);
        });
      } else {
        return res.status(400).json({ success: false, error: '未提供文件或URL' });
      }

      if (!napPath || !fs.existsSync(napPath)) {
        return res.status(400).json({ success: false, error: 'NAP文件上传失败' });
      }

      // 用 adm-zip 解压（纯JS，不依赖系统PowerShell）
      extractDir = path.join(os.tmpdir(), `nap_extract_${Date.now()}`);
      fs.mkdirSync(extractDir, { recursive: true });
      try {
        const zip = new AdmZip(napPath);
        zip.extractAllTo(extractDir, true);
      } catch(e) {
        return res.status(400).json({ success: false, error: 'NAP解压失败: ' + e.message + '（文件可能不是有效的ZIP/NAP格式）' });
      }

      // 找到 Payload 下的 .app 目录
      const payloadDir = path.join(extractDir, 'Payload');
      if (!fs.existsSync(payloadDir)) {
        return res.status(400).json({ success: false, error: '无效NAP: 缺少 Payload 目录' });
      }
      const appEntries = fs.readdirSync(payloadDir).filter(d => d.endsWith('.app'));
      if (appEntries.length === 0) {
        return res.status(400).json({ success: false, error: '无效NAP: Payload 中没有 .app 目录' });
      }
      const appName = appEntries[0];
      const srcApp = path.join(payloadDir, appName);
      const destApp = path.join(APP_DIR, appName);

      // 如果已存在，先删除再复制
      if (fs.existsSync(destApp)) {
        try { fs.rmSync(destApp, { recursive: true, force: true }); } catch(e){}
      }
      try {
        fs.cpSync(srcApp, destApp, { recursive: true });
      } catch(e) {
        return res.status(500).json({ success: false, error: '安装文件复制失败: ' + e.message });
      }

      // 解析应用信息（带兜底默认值）
      let info = parseAppInfo(destApp);
      if (!info) {
        info = {
          bundleId: 'com.cor.unknown.' + Date.now(),
          name: path.basename(appName, '.app'),
          version: '1.0.0',
          icon: '',
          path: destApp,
        };
      }

      res.json({ success: true, app: info });
    } catch(e) {
      console.error('NAP install error:', e);
      res.status(500).json({ success: false, error: '安装失败: ' + e.message });
    } finally {
      // 清理临时文件
      if (napPath) { try { fs.unlinkSync(napPath); } catch(e){} }
      if (extractDir) { try { fs.rmSync(extractDir, { recursive: true, force: true }); } catch(e){} }
    }
  });

  app_express.delete('/api/apps/:bundleId', auth, (req, res) => {
    try {
      const { bundleId } = req.params;
      if (!fs.existsSync(APP_DIR)) return res.status(404).json({ error: 'No apps installed' });
      const entries = fs.readdirSync(APP_DIR).filter(d => d.endsWith('.app'));
      for (const entry of entries) {
        const info = parseAppInfo(path.join(APP_DIR, entry));
        if (info && info.bundleId === bundleId) {
          fs.rmSync(path.join(APP_DIR, entry), { recursive: true, force: true });
          return res.json({ ok: true, bundleId });
        }
      }
      res.status(404).json({ error: 'App not found' });
    } catch(e) { res.status(500).json({ error: e.message }); }
  });

  // 静态 serve 应用资源
  app_express.get('/api/apps/:bundleId/*', auth, (req, res) => {
    try {
      const { bundleId } = req.params;
      const resourcePath = req.params[0] || 'index.html';
      if (!fs.existsSync(APP_DIR)) return res.status(404).json({ error: 'App not found' });
      const entries = fs.readdirSync(APP_DIR).filter(d => d.endsWith('.app'));
      for (const entry of entries) {
        const info = parseAppInfo(path.join(APP_DIR, entry));
        if (info && info.bundleId === bundleId) {
          const filePath = path.join(APP_DIR, entry, resourcePath);
          if (fs.existsSync(filePath) && fs.statSync(filePath).isFile()) {
            return res.sendFile(filePath);
          }
          // 回退到 index.html
          const indexPath = path.join(APP_DIR, entry, 'index.html');
          if (fs.existsSync(indexPath)) return res.sendFile(indexPath);
          return res.status(404).json({ error: 'Resource not found' });
        }
      }
      res.status(404).json({ error: 'App not found' });
    } catch(e) { res.status(500).json({ error: e.message }); }
  });

  // ============ 相册：最近删除 ============
  function readDeletedMeta() {
    try { return JSON.parse(fs.readFileSync(RECENTLY_DELETED_META, 'utf8')); } catch(e) { return { items: {} }; }
  }
  function writeDeletedMeta(meta) {
    try { fs.writeFileSync(RECENTLY_DELETED_META, JSON.stringify(meta, null, 2)); } catch(e){}
  }
  function cleanupExpiredDeleted() {
    const meta = readDeletedMeta();
    const now = Date.now();
    const THIRTY_DAYS = 30 * 24 * 60 * 60 * 1000;
    let changed = false;
    for (const [filename, ts] of Object.entries(meta.items)) {
      if (now - ts > THIRTY_DAYS) {
        const fp = path.join(RECENTLY_DELETED_DIR, filename);
        try { if (fs.existsSync(fp)) fs.rmSync(fp, { recursive: true, force: true }); } catch(e){}
        delete meta.items[filename];
        changed = true;
      }
    }
    if (changed) writeDeletedMeta(meta);
    return meta;
  }

  app_express.get('/api/photos/recently-deleted', auth, (req, res) => {
    try {
      const meta = cleanupExpiredDeleted();
      const entries = [];
      for (const [filename, deletedAt] of Object.entries(meta.items)) {
        const fp = path.join(RECENTLY_DELETED_DIR, filename);
        if (!fs.existsSync(fp)) continue;
        const stat = fs.statSync(fp);
        entries.push({ name: filename, deletedAt, size: stat.size, isDirectory: stat.isDirectory() });
      }
      entries.sort((a, b) => b.deletedAt - a.deletedAt);
      res.json({ entries });
    } catch(e) { res.status(500).json({ error: e.message }); }
  });

  app_express.post('/api/photos/soft-delete', auth, (req, res) => {
    try {
      const { files } = req.body;
      if (!Array.isArray(files) || files.length === 0) return res.status(400).json({ error: 'files required' });
      const meta = readDeletedMeta();
      const now = Date.now();
      let count = 0;
      for (const filename of files) {
        const src = path.join(PHOTOS_DIR, filename);
        if (!fs.existsSync(src)) continue;
        // 避免重名
        let destName = filename;
        let dest = path.join(RECENTLY_DELETED_DIR, destName);
        if (fs.existsSync(dest)) {
          const ext = path.extname(filename);
          const base = path.basename(filename, ext);
          let i = 1;
          while (fs.existsSync(path.join(RECENTLY_DELETED_DIR, `${base}_${i}${ext}`))) i++;
          destName = `${base}_${i}${ext}`;
          dest = path.join(RECENTLY_DELETED_DIR, destName);
        }
        fs.renameSync(src, dest);
        meta.items[destName] = now;
        count++;
      }
      writeDeletedMeta(meta);
      res.json({ ok: true, moved: count });
    } catch(e) { res.status(500).json({ error: e.message }); }
  });

  app_express.post('/api/photos/recover', auth, (req, res) => {
    try {
      const { files } = req.body;
      if (!Array.isArray(files)) return res.status(400).json({ error: 'files required' });
      const meta = readDeletedMeta();
      let count = 0;
      for (const filename of files) {
        const src = path.join(RECENTLY_DELETED_DIR, filename);
        if (!fs.existsSync(src)) continue;
        let dest = path.join(PHOTOS_DIR, filename);
        if (fs.existsSync(dest)) {
          const ext = path.extname(filename);
          const base = path.basename(filename, ext);
          let i = 1;
          while (fs.existsSync(path.join(PHOTOS_DIR, `${base}_${i}${ext}`))) i++;
          dest = path.join(PHOTOS_DIR, `${base}_${i}${ext}`);
        }
        fs.renameSync(src, dest);
        delete meta.items[filename];
        count++;
      }
      writeDeletedMeta(meta);
      res.json({ ok: true, recovered: count });
    } catch(e) { res.status(500).json({ error: e.message }); }
  });

  app_express.post('/api/photos/purge', auth, (req, res) => {
    try {
      const { files } = req.body;
      if (!Array.isArray(files)) return res.status(400).json({ error: 'files required' });
      const meta = readDeletedMeta();
      let count = 0;
      for (const filename of files) {
        const fp = path.join(RECENTLY_DELETED_DIR, filename);
        if (fs.existsSync(fp)) { try { fs.rmSync(fp, { recursive: true, force: true }); } catch(e){} }
        delete meta.items[filename];
        count++;
      }
      writeDeletedMeta(meta);
      res.json({ ok: true, purged: count });
    } catch(e) { res.status(500).json({ error: e.message }); }
  });

  // ============ 压缩包解压 ============
  app_express.post('/api/extract', auth, (req, res) => {
    try {
      const { path: archivePath, password } = req.body;
      if (!archivePath) return res.status(400).json({ error: 'path required' });
      const full = resolveSafePath(archivePath);
      if (!full || !fs.existsSync(full)) return res.status(404).json({ error: 'Archive not found' });
      const ext = path.extname(full).toLowerCase();
      if (ext !== '.zip') return res.status(400).json({ error: '仅支持 .zip 格式解压' });
      const baseName = path.basename(full, ext);
      const parentDir = path.dirname(full);
      let destFolder = path.join(parentDir, baseName);
      let i = 1;
      while (fs.existsSync(destFolder)) { destFolder = path.join(parentDir, `${baseName}_${i}`); i++; }
      fs.mkdirSync(destFolder, { recursive: true });
      const taskId = createTask('extract', `解压: ${path.basename(full)}`, 0, { destFolder });
      res.json({ ok: true, taskId, destFolder });
      // 异步执行解压
      setImmediate(() => {
        try {
          const zip = new AdmZip(full);
          const entries = zip.getEntries();
          const total = entries.length;
          let done = 0;
          updateTask(taskId, { status: 'downloading', total });
          for (const entry of entries) {
            const task = taskQueue.get(taskId);
            if (task && task.status === 'cancelled') { updateTask(taskId, { status: 'cancelled' }); return; }
            try {
              if (entry.isDirectory) {
                fs.mkdirSync(path.join(destFolder, entry.entryName), { recursive: true });
              } else {
                const data = entry.getData(password);
                const outPath = path.join(destFolder, entry.entryName);
                fs.mkdirSync(path.dirname(outPath), { recursive: true });
                fs.writeFileSync(outPath, data);
              }
            } catch(e) {
              // 密码错误或其他错误
              if (e.message && (e.message.includes('password') || e.message.includes('Wrong') || e.message.includes('invalid'))) {
                updateTask(taskId, { status: 'failed', error: '需要密码或密码错误' });
              } else {
                updateTask(taskId, { status: 'failed', error: e.message });
              }
              return;
            }
            done++;
            updateTask(taskId, { progress: Math.min(100, Math.trunc(done / total * 100)), transferred: done });
          }
          updateTask(taskId, { status: 'completed', progress: 100, transferred: total });
        } catch(e) {
          updateTask(taskId, { status: 'failed', error: e.message });
        }
      });
    } catch(e) { res.status(500).json({ error: e.message }); }
  });

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
    width: 900, height: 650, title: 'iNas', resizable: true,
    backgroundColor: '#1a1a2e',
    webPreferences: { nodeIntegration: true, contextIsolation: false }
  });
  try { serverInfo = await startServer(); } catch(e) { console.error('Failed to start server:', e); }
  mainWindow.loadFile('index.html');
  mainWindow.webContents.on('did-finish-load', () => {
    if (serverInfo) {
      const ip = getLocalIP();
      const connectUrl = `http://${ip}:${serverInfo.port}`;
      const qrData = JSON.stringify({ ip, port: serverInfo.port, token: serverInfo.token, hostname: os.hostname() });
      QRCode.toDataURL(qrData, { width: 280, margin: 2, color: { dark: '#1a1a2e', light: '#ffffff' } })
        .then(qrImg => {
          mainWindow.webContents.send('server-info', {
            ip, port: serverInfo.port, token: serverInfo.token,
            connectUrl, qrImg, hostname: os.hostname(), installDir: INSTALL_DIR
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
ipcMain.handle('get-server-info', () => {
  if (!serverInfo) return null;
  return { ip: getLocalIP(), port: serverInfo.port, token: serverInfo.token, hostname: os.hostname() };
});
ipcMain.handle('reset-token', () => {
  authToken = crypto.randomBytes(16).toString('hex');
  try { fs.writeFileSync(TOKEN_FILE, JSON.stringify({ token: authToken, created: Date.now() })); } catch(e){}
  return authToken;
});
app.whenReady().then(() => {
  createWindow();
  app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createWindow(); });
});
app.on('window-all-closed', () => {
  if (server) { try { server.close(); } catch(e){} }
  if (process.platform !== 'darwin') app.quit();
});
