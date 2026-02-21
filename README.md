# MeetingTranscriber Flutter

跨平台会议转录应用，支持 Windows、macOS、Linux、iOS 和 Android。

## 功能特性

- ✅ 实时语音转录
- ✅ 多说话人识别与分段
- ✅ 对话轮次自动换行
- ✅ 待办事项管理
- ✅ 会议记录存储
- ✅ 多模型支持 (Tiny/Base/Small)
- ✅ 跨平台支持

## 技术栈

- **UI 框架**: Flutter
- **语音识别**: Whisper.cpp
- **数据存储**: SQLite
- **状态管理**: Provider

## 快速开始

### 1. 安装 Flutter

```bash
# Windows (使用 Chocolatey)
choco install flutter

# macOS (使用 Homebrew)
brew install flutter

# Linux
snap install flutter --classic
```

### 2. 克隆项目

```bash
cd /Users/vector
git clone <repo-url> MeetingTranscriberFlutter
cd MeetingTranscriberFlutter
```

### 3. 安装依赖

```bash
flutter pub get
```

### 4. 下载 Whisper 模型

从 Hugging Face 下载模型文件，放到 `assets/models/` 目录：

- [ggml-tiny.bin](https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin) (39MB)
- [ggml-base.bin](https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin) (74MB)
- [ggml-small.bin](https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin) (244MB)

### 5. 编译 Whisper.cpp

#### Windows
```bash
cd whisper.cpp
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
cmake --build . --config Release
copy bin\Release\whisper.dll ..\..\assets\
```

#### macOS
```bash
cd whisper.cpp
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j
cp libwhisper.dylib ../../assets/
```

#### Linux
```bash
cd whisper.cpp
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j
cp libwhisper.so ../../assets/
```

### 6. 运行应用

```bash
# Windows
flutter run -d windows

# macOS
flutter run -d macos

# Linux
flutter run -d linux
```

## 项目结构

```
MeetingTranscriberFlutter/
├── lib/
│   ├── main.dart                 # 应用入口
│   ├── models/
│   │   └── models.dart          # 数据模型
│   ├── providers/
│   │   └── app_state.dart       # 状态管理
│   ├── screens/
│   │   ├── home_screen.dart     # 主页
│   │   ├── recording_screen.dart # 录音页
│   │   ├── meeting_detail_screen.dart # 详情页
│   │   └── settings_screen.dart # 设置页
│   └── services/
│       ├── database_service.dart # 数据库服务
│       ├── whisper_service.dart  # Whisper 服务
│       ├── audio_recording_service.dart # 录音服务
│       └── transcription_post_processor.dart # 后处理
├── assets/
│   └── models/                   # Whisper 模型文件
├── windows/                      # Windows 平台配置
├── pubspec.yaml                  # 依赖配置
└── README.md
```

## 对话分段功能

应用支持两种对话分段方式：

### 1. 说话人变化换行
当检测到不同说话人时，自动换行并显示说话人标签：

```
【说话人1】大家好，今天我们来讨论项目进展。

【说话人2】好的，我来介绍一下上周的工作。
```

### 2. 对话轮次换行
当检测到时间间隔超过阈值（默认 1.5 秒）时，自动换行：

```
接下来我们讨论一下下周的计划。

（时间间隔超过阈值）

好的，我来总结一下今天的会议内容。
```

## 配置选项

### 后处理配置

```dart
final config = PostProcessorConfig(
  removeFillerWords: true,        // 移除填充词
  fixPunctuation: true,           // 修复标点
  breakOnSpeakerChange: true,     // 说话人变化换行
  breakOnConversationTurn: true,  // 对话轮次换行
  addSpeakerLabels: true,         // 添加说话人标签
  conversationTurnGap: Duration(seconds: 1, milliseconds: 500), // 时间间隔阈值
);
```

## 构建发布版本

```bash
# Windows
flutter build windows --release

# macOS
flutter build macos --release

# Linux
flutter build linux --release
```

## 许可证

MIT License
