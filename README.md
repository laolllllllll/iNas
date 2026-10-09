# iNas GitHub Action 打包配置

## 目录结构

```
inas-build/
├── .github/
│   └── workflows/
│       └── build-windows.yml    # GitHub Action 工作流
└── windows/
    ├── package.json              # Electron 项目配置（示例，替换为你的实际配置）
    ├── main.js                   # Electron 主进程（你的代码）
    ├── build/
    │   └── build-installer.sh    # 本地构建脚本（可选）
    └── stub/
        └── main.go               # 自解压安装器 Go stub
```

## 使用方法

### 1. 将文件放入你的 GitHub 仓库

把以下文件复制到你的 iNas 项目仓库根目录：

- `.github/workflows/build-windows.yml` → 仓库根目录的 `.github/workflows/`
- `windows/stub/main.go` → 仓库的 `windows/stub/` 目录
- `windows/package.json` → **用你自己的 package.json 覆盖**（这只是示例）

### 2. 确保项目结构

你的仓库应该有类似这样的结构：

```
your-repo/
├── .github/
│   └── workflows/
│       └── build-windows.yml
├── windows/
│   ├── package.json
│   ├── package-lock.json
│   ├── main.js
│   ├── stub/
│   │   ├── go.mod
│   │   └── main.go
│   └── ... (其他 Electron 源码)
└── mobile/                     # Flutter 移动端（暂时不用打包）
```

### 3. 初始化 Go stub 模块

在 `windows/stub/` 目录下执行：

```bash
cd windows/stub
go mod init inas-stub
go mod tidy
```

### 4. 触发构建

**方式一：推送 Tag（推荐，自动创建 Release）**

```bash
git tag v1.0.0
git push origin v1.0.0
```

推送 tag 后，GitHub Action 会自动：
1. 构建 Electron
2. 编译 Go stub
3. 拼接成自解压安装器 EXE
4. 上传到 Actions 产物
5. **自动创建 GitHub Release 并附加 EXE**

**方式二：手动触发**

在 GitHub 仓库页面：
1. 点击 **Actions** 标签
2. 选择 **Build iNas Windows Installer**
3. 点击 **Run workflow**
4. 输入版本号（如 `1.0.0`）
5. 点击 **Run workflow**

### 5. 下载产物

构建完成后：
- **Actions 产物**：在 Actions 页面的构建记录底部，下载 `iNas-Setup-x.x.x`
- **Release**（tag 触发）：在仓库的 Releases 页面下载

## 安装器行为

生成的 `iNas-Setup-x.x.x.exe` 是自解压安装器，运行后会：

1. 将所有文件解压到 `C:\iNas root\`
2. Electron 程序放在 `C:\iNas root\System\iNas.exe`
3. 自动创建默认文件夹：回收站、音乐、视频、图片、下载
4. 创建桌面快捷方式 `iNas.lnk`
5. 创建开始菜单快捷方式

## 技术细节

### 自解压原理

```
┌─────────────────┐
│   Go Stub EXE   │  ← 安装器引导程序（负责解压+创建快捷方式）
├─────────────────┤
│   ZIP 数据      │  ← Electron 打包后的所有文件
└─────────────────┘
```

Stub 程序运行时：
1. 读取自身 EXE 文件
2. 查找 ZIP 文件头签名 `PK\x03\x04`
3. 从该位置开始解压所有文件到安装目录
4. 创建快捷方式

### Electron 版本

使用 **Electron 22.3.27**，兼容 Windows 7 x64。

### Node.js 版本

GitHub Action 使用 **Node.js 16.x**，与 Electron 22 匹配。

## 常见问题

### Q: 构建失败，提示找不到 main.js？
A: 确保 `windows/package.json` 中的 `main` 字段指向正确的入口文件，并且 `build.files` 包含了所有需要的文件。

### Q: 安装后桌面没有快捷方式？
A: Stub 使用 VBScript 创建快捷方式，确保目标系统有 `cscript`（Windows 默认都有）。可以检查 `%TEMP%\create_shortcut.vbs` 是否执行成功。

### Q: 想修改安装目录？
A: 编辑 `windows/stub/main.go` 中的 `installDir` 变量，默认是 `C:\iNas root`。

### Q: 想同时打包 APK？
A: 暂时不需要。后续可以添加另一个 job 使用 `ubuntu-latest` + Flutter 环境构建 APK。

## 本地测试构建

如果你想在本地测试构建流程：

```bash
# 需要 Go 和 Node.js 环境
cd windows
bash build/build-installer.sh 1.0.0
```

产物会在 `windows/dist/iNas-Setup-1.0.0.exe`。
