package main

import (
	"archive/zip"
	"bytes"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"unsafe"
)

var (
	shell32               = syscall.NewLazyDLL("shell32.dll")
	procSHCreateShortcut   = shell32.NewProc("SHCreateShortcut")
	kernel32              = syscall.NewLazyDLL("kernel32.dll")
	procGetModuleFileName = kernel32.NewProc("GetModuleFileNameW")
)

func main() {
	// 获取自身 exe 路径
	exePath := getExePath()
	fmt.Println("=== iNas Installer v1.0 ===")
	fmt.Printf("Installer: %s\n", exePath)

	// 安装目录
	installDir := `C:\iNas root`
	fmt.Printf("Install dir: %s\n", installDir)

	// 创建安装目录
	if err := os.MkdirAll(installDir, 0755); err != nil {
		fmt.Printf("Failed to create install dir: %v\n", err)
		pauseExit(1)
	}

	// 读取自身 exe，找到 zip 数据起始位置（ZIP 文件头 PK\x03\x04）
	exeData, err := os.ReadFile(exePath)
	if err != nil {
		fmt.Printf("Failed to read installer: %v\n", err)
		pauseExit(1)
	}

	zipStart := findZipSignature(exeData)
	if zipStart < 0 {
		fmt.Println("Error: Embedded data not found")
		pauseExit(1)
	}
	fmt.Printf("Embedded data found at offset: %d\n", zipStart)

	// 解压 zip 到安装目录
	zipData := exeData[zipStart:]
	zipReader, err := zip.NewReader(bytes.NewReader(zipData), int64(len(zipData)))
	if err != nil {
		fmt.Printf("Failed to open zip: %v\n", err)
		pauseExit(1)
	}

	fmt.Println("Extracting files...")
	for _, f := range zipReader.File {
		targetPath := filepath.Join(installDir, f.Name)

		// 安全检查：防止路径穿越
		if !strings.HasPrefix(filepath.Clean(targetPath), filepath.Clean(installDir)+string(os.PathSeparator)) &&
			filepath.Clean(targetPath) != filepath.Clean(installDir) {
			continue
		}

		if f.FileInfo().IsDir() {
			os.MkdirAll(targetPath, 0755)
			continue
		}

		if err := os.MkdirAll(filepath.Dir(targetPath), 0755); err != nil {
			continue
		}

		outFile, err := os.OpenFile(targetPath, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, f.Mode())
		if err != nil {
			continue
		}

		rc, err := f.Open()
		if err != nil {
			outFile.Close()
			continue
		}

		io.Copy(outFile, rc)
		rc.Close()
		outFile.Close()
	}

	// 创建默认文件夹结构
	folders := []string{
		filepath.Join(installDir, "System"),
		filepath.Join(installDir, "回收站"),
		filepath.Join(installDir, "音乐"),
		filepath.Join(installDir, "视频"),
		filepath.Join(installDir, "图片"),
		filepath.Join(installDir, "下载"),
	}
	for _, folder := range folders {
		os.MkdirAll(folder, 0755)
	}

	// 创建桌面快捷方式
	desktopDir := getDesktopDir()
	shortcutPath := filepath.Join(desktopDir, "iNas.lnk")
	exeTarget := filepath.Join(installDir, "System", "iNas.exe")
	createShortcut(shortcutPath, exeTarget, installDir)

	// 创建开始菜单快捷方式
	startMenuDir := filepath.Join(os.Getenv("APPDATA"), `Microsoft\Windows\Start Menu\Programs`)
	os.MkdirAll(startMenuDir, 0755)
	startMenuShortcut := filepath.Join(startMenuDir, "iNas.lnk")
	createShortcut(startMenuShortcut, exeTarget, installDir)

	fmt.Println("\n=== Installation Complete ===")
	fmt.Printf("Installed to: %s\n", installDir)
	fmt.Println("Desktop shortcut created.")
	fmt.Println("Start Menu shortcut created.")
	fmt.Println("\nPress Enter to exit...")
	fmt.Scanln()
}

func getExePath() string {
	var path [260]uint16
	procGetModuleFileName.Call(0, uintptr(unsafe.Pointer(&path[0])), 260)
	return syscall.UTF16ToString(path[:])
}

func findZipSignature(data []byte) int {
	sig := []byte{'P', 'K', 0x03, 0x04}
	for i := 0; i <= len(data)-4; i++ {
		if data[i] == sig[0] && data[i+1] == sig[1] && data[i+2] == sig[2] && data[i+3] == sig[3] {
			return i
		}
	}
	return -1
}

func getDesktopDir() string {
	desktop := filepath.Join(os.Getenv("USERPROFILE"), "Desktop")
	if _, err := os.Stat(desktop); err == nil {
		return desktop
	}
	// 中文系统可能是"桌面"
	desktopCN := filepath.Join(os.Getenv("USERPROFILE"), "桌面")
	if _, err := os.Stat(desktopCN); err == nil {
		return desktopCN
	}
	return desktop
}

func createShortcut(shortcutPath, targetPath, workDir string) {
	// 使用 VBScript 创建快捷方式（兼容性最好）
	vbsContent := fmt.Sprintf(`Set WshShell = CreateObject("WScript.Shell")
Set oShellLink = WshShell.CreateShortcut("%s")
oShellLink.TargetPath = "%s"
oShellLink.WorkingDirectory = "%s"
oShellLink.WindowStyle = 1
oShellLink.Description = "iNas File Manager"
oShellLink.Save
`, shortcutPath, targetPath, workDir)

	vbsPath := filepath.Join(os.TempDir(), "create_shortcut.vbs")
	os.WriteFile(vbsPath, []byte(vbsContent), 0644)
	defer os.Remove(vbsPath)

	exec.Command("cscript", "//nologo", vbsPath).Run()
}

func pauseExit(code int) {
	fmt.Println("\nPress Enter to exit...")
	fmt.Scanln()
	os.Exit(code)
}
