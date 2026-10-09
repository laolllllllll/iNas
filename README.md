# iNas - 跨平台文件管理器 + 远程 CMD 终端

iNas 是一套跨平台文件管理系统，包含 Windows 服务端和 iOS 移动端，支持同 WiFi 下的文件管理、远程 CMD 执行、文件传输等功能。

## 功能特性

### Windows 服务端
- HTTP 文件服务（Express），随机端口 + Token 认证
- 二维码绑定（含 IP + 端口 + Token）
- 完整文件管理 API：浏览、上传、下载、删除（回收站）、重命名、复制、移动、新建目录
- 文本文件读写 API
- **CMD 远程执行 API**（单次执行 + 交互式会话）
- 任务队列（复制/移动带进度）
- 自解压安装器，安装到 `C:\iNas root\`，自动创建桌面快捷方式

### iOS 移动端（四 Tab 结构）
1. **浏览**：双根目录切换（iNas Root / Windows C:），文件列表，长按菜单（下载/重命名/删除/复制/粘贴），图片/视频/HTML 预览，文本编辑器
2. **管理设备**：内嵌 Windows CMD 远程终端，同 WiFi 连接执行命令，实时输出显示，快捷命令面板
3. **队列**：上传/下载/跨设备复制任务，进度条，暂停/继续/取消
4. **此终端**：本地下载文件管理，iOS 原生分享面板（share_plus），用其他应用打开

## 技术栈
- **Windows**: Electron 22.3.27 + Express + multer + qrcode
- **移动端**: Flutter 3.24 + Dart（dio / share_plus / chewie / webview_flutter / mobile_scanner）
- **认证**: 所有 API 请求携带 Header `x-nas-token`
- **包名**: com.cor.iNas

## 仓库结构
```
iNas/
├── .github/workflows/
│   ├── build-windows.yml    # Windows EXE 安装器构建
│   └── build-ios.yml        # iOS IPA 构建（无签名，可侧载）
├── windows/
│   ├── main.js               # Electron 主进程 + Express 服务
│   ├── index.html            # 服务端 UI（状态 + 二维码）
│   ├── package.json
│   ├── build/build-installer.sh
│   └── stub/main.go          # 自解压安装器 Go stub
└── mobile/
    ├── pubspec.yaml
    ├── ios/                  # iOS 工程配置
    └── lib/
        ├── main.dart         # 四 Tab 主框架
        ├── models/
        ├── services/         # API 服务 + 下载管理
        ├── pages/            # 浏览/CMD/队列/终端/预览/编辑器
        └── widgets/
```

## API 列表
| 方法 | 路径 | 说明 |
|------|------|------|
| GET | /api/status | 服务状态 |
| GET | /api/files?path= | 文件列表 |
| GET | /api/download?path= | 下载文件 |
| POST | /api/upload | 上传文件 (multipart) |
| POST | /api/delete | 删除文件（移入回收站） |
| POST | /api/rename | 重命名 |
| POST | /api/copy | 复制（异步任务） |
| POST | /api/move | 移动 |
| POST | /api/mkdir | 新建目录 |
| GET | /api/read-text?path= | 读取文本文件 |
| POST | /api/write-text | 写入文本文件 |
| GET | /api/queue | 任务队列状态 |
| POST | /api/queue/:id/:action | 队列操作（pause/resume/cancel/remove） |
| POST | /api/cmd | CMD 单次执行 |
| POST | /api/cmd/session | 创建 CMD 交互式会话 |
| POST | /api/cmd/session/:id/write | 向会话写入命令 |
| GET | /api/cmd/session/:id/read | 读取会话输出 |
| POST | /api/cmd/session/:id/close | 关闭会话 |

## 构建

### Windows EXE 安装器
推送代码到 main 分支后自动触发 GitHub Action，产物为 `iNas-Setup-1.0.2.exe`。

安装器行为：
- 自解压到 `C:\iNas root\`
- Electron 程序位于 `C:\iNas root\System\iNas.exe`
- 自动创建默认文件夹：回收站、音乐、视频、图片、下载
- 创建桌面快捷方式和开始菜单快捷方式

### iOS IPA（可侧载）
推送代码到 main 分支后自动触发 GitHub Action（macOS runner），产物为 `iNas-1.0.2.ipa`。

- 无代码签名构建，可通过 TrollStore / AltStore 侧载
- 支持 iOS 12.0+
- 构建命令核心：`flutter build ios --release --no-codesign`

## 使用说明
1. 在 Windows 上运行 iNas-Setup.exe 安装并启动 iNas
2. 确保手机和电脑连接同一 WiFi
3. 在 iOS 端安装 iNas.ipa 并打开
4. 在浏览页点击"连接设备"，扫描 Windows 端二维码或手动输入 IP/端口/Token
5. 连接成功后即可浏览文件、远程执行 CMD、管理传输队列
