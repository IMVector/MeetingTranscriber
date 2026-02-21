# Windows 编译指南

## 环境准备

### 1. 安装 Visual Studio 2022
下载地址: https://visualstudio.microsoft.com/downloads/

安装时选择以下工作负载:
- 使用 C++ 的桌面开发
- Windows 10/11 SDK

### 2. 安装 Flutter SDK

```powershell
# 方法1: 使用 Chocolatey (推荐)
choco install flutter

# 方法2: 手动安装
# 下载: https://docs.flutter.dev/get-started/install/windows
# 解压到 C:\flutter
# 添加 C:\flutter\bin 到系统 PATH
```

### 3. 验证环境

```powershell
flutter doctor
```

确保显示:
- [✓] Flutter SDK
- [✓] Visual Studio
- [✓] Windows SDK

## 编译步骤

### 1. 克隆/复制项目

```powershell
# 复制项目到 Windows
# 或使用 git clone
```

### 2. 安装依赖

```powershell
cd MeetingTranscriberFlutter
flutter pub get
```

### 3. 编译 Whisper.cpp (语音识别引擎)

```powershell
# 克隆 whisper.cpp
git clone https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp

# 使用 CMake 编译
mkdir build
cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
cmake --build . --config Release

# 复制 DLL 到项目
copy bin\Release\whisper.dll ..\..\assets\
```

### 4. 下载模型文件

从 Hugging Face 下载模型:

```powershell
# 在项目根目录创建 assets/models 文件夹
mkdir assets\models

# 下载模型 (选择一个)
# Tiny (39MB)
curl -L -o assets\models\ggml-tiny.bin https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin

# Base (74MB) - 推荐
curl -L -o assets\models\ggml-base.bin https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin

# Small (244MB) - 最高精度
curl -L -o assets\models\ggml-small.bin https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin
```

### 5. 编译 Flutter 应用

```powershell
# 回到项目目录
cd MeetingTranscriberFlutter

# 编译 Windows 版本
flutter build windows --release
```

### 6. 运行应用

编译完成后，可执行文件位于:
```
build\windows\x64\runner\Release\meeting_transcriber.exe
```

## 完整编译脚本

创建 `build_windows.ps1`:

```powershell
# build_windows.ps1 - Windows 编译脚本

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "MeetingTranscriber Windows 编译脚本" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# 检查 Flutter
Write-Host "`n[1/5] 检查 Flutter 环境..." -ForegroundColor Yellow
flutter doctor

# 安装依赖
Write-Host "`n[2/5] 安装 Flutter 依赖..." -ForegroundColor Yellow
flutter pub get

# 检查 whisper.dll
Write-Host "`n[3/5] 检查 Whisper.dll..." -ForegroundColor Yellow
if (-not (Test-Path "assets\whisper.dll")) {
    Write-Host "警告: assets\whisper.dll 不存在!" -ForegroundColor Red
    Write-Host "请先编译 whisper.cpp 并复制 DLL 到 assets 目录" -ForegroundColor Red
    exit 1
}

# 检查模型
Write-Host "`n[4/5] 检查模型文件..." -ForegroundColor Yellow
$models = @("ggml-tiny.bin", "ggml-base.bin", "ggml-small.bin")
$foundModel = $false
foreach ($model in $models) {
    if (Test-Path "assets\models\$model") {
        Write-Host "找到模型: $model" -ForegroundColor Green
        $foundModel = $true
    }
}
if (-not $foundModel) {
    Write-Host "警告: 没有找到任何模型文件!" -ForegroundColor Red
    Write-Host "请下载模型到 assets\models 目录" -ForegroundColor Red
    exit 1
}

# 编译
Write-Host "`n[5/5] 编译 Windows 版本..." -ForegroundColor Yellow
flutter build windows --release

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "编译完成!" -ForegroundColor Green
Write-Host "可执行文件: build\windows\x64\runner\Release\meeting_transcriber.exe" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
```

## 分发应用

### 方法1: 直接分发
将 `build\windows\x64\runner\Release\` 文件夹打包分发

### 方法2: 创建安装程序
使用 Inno Setup 或 NSIS 创建安装程序:

```iss
; setup.iss - Inno Setup 脚本
[Setup]
AppName=MeetingTranscriber
AppVersion=1.0.0
DefaultDirName={pf}\MeetingTranscriber
DefaultGroupName=MeetingTranscriber
OutputBaseFilename=MeetingTranscriber-Setup
Compression=lzma
SolidCompression=yes

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs

[Icons]
Name: "{group}\MeetingTranscriber"; Filename: "{app}\meeting_transcriber.exe"
Name: "{commondesktop}\MeetingTranscriber"; Filename: "{app}\meeting_transcriber.exe"
```

## 常见问题

### 1. 找不到 Visual Studio
确保安装了 Visual Studio 2022 并选择了 "使用 C++ 的桌面开发"

### 2. 编译失败: 找不到 Windows SDK
在 Visual Studio Installer 中安装 Windows 10/11 SDK

### 3. 麦克风权限
首次运行需要在 Windows 设置中授予麦克风权限:
设置 > 隐私 > 麦克风 > 允许应用访问麦克风

### 4. whisper.dll 缺失
确保 `assets\whisper.dll` 存在，并且与编译的架构匹配 (x64)

## 开发调试

```powershell
# 运行调试版本
flutter run -d windows

# 热重载
# 按 r 键

# 热重启
# 按 R 键

# 退出
# 按 q 键
```
