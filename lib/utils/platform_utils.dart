import 'dart:io';

/// 平台工具类
class PlatformUtils {
  /// 是否为 Windows
  static bool get isWindows => Platform.isWindows;

  /// 是否为 macOS
  static bool get isMacOS => Platform.isMacOS;

  /// 是否为 Linux
  static bool get isLinux => Platform.isLinux;

  /// 是否为 iOS
  static bool get isIOS => Platform.isIOS;

  /// 是否为 Android
  static bool get isAndroid => Platform.isAndroid;

  /// 是否为桌面平台
  static bool get isDesktop => isWindows || isMacOS || isLinux;

  /// 是否为移动平台
  static bool get isMobile => isIOS || isAndroid;

  /// 获取平台名称
  static String get platformName {
    if (isWindows) return 'Windows';
    if (isMacOS) return 'macOS';
    if (isLinux) return 'Linux';
    if (isIOS) return 'iOS';
    if (isAndroid) return 'Android';
    return 'Unknown';
  }

  /// 获取动态库扩展名
  static String get libraryExtension {
    if (isWindows) return '.dll';
    if (isMacOS) return '.dylib';
    if (isLinux) return '.so';
    return '';
  }

  /// 获取可执行文件扩展名
  static String get executableExtension {
    if (isWindows) return '.exe';
    return '';
  }
}

/// 音频格式工具
class AudioFormatUtils {
  /// 支持的音频格式
  static const supportedFormats = [
    'wav',
    'mp3',
    'm4a',
    'aac',
    'flac',
    'ogg',
  ];

  /// 检查文件是否为支持的音频格式
  static bool isSupportedAudioFile(String path) {
    final extension = path.split('.').last.toLowerCase();
    return supportedFormats.contains(extension);
  }

  /// 获取音频格式
  static String? getAudioFormat(String path) {
    final extension = path.split('.').last.toLowerCase();
    return supportedFormats.contains(extension) ? extension : null;
  }
}

/// 时间格式化工具
class DurationUtils {
  /// 格式化时长为 mm:ss
  static String formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  /// 格式化时长为 hh:mm:ss
  static String formatDurationLong(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  /// 从秒数创建 Duration
  static Duration fromSeconds(int seconds) {
    return Duration(seconds: seconds);
  }

  /// 从毫秒数创建 Duration
  static Duration fromMilliseconds(int milliseconds) {
    return Duration(milliseconds: milliseconds);
  }
}

/// 文本处理工具
class TextUtils {
  /// 移除多余的空白
  static String removeExtraWhitespace(String text) {
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// 移除多余的换行
  static String removeExtraNewlines(String text) {
    return text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  /// 统计中文字符数
  static int countChineseCharacters(String text) {
    final chineseRegex = RegExp(r'[\u4e00-\u9fff]');
    return chineseRegex.allMatches(text).length;
  }

  /// 统计英文单词数
  static int countEnglishWords(String text) {
    final englishRegex = RegExp(r'[a-zA-Z]+');
    return englishRegex.allMatches(text).length;
  }

  /// 估计阅读时间（分钟）
  static int estimateReadingTime(String text, {int wordsPerMinute = 200}) {
    final chineseCount = countChineseCharacters(text);
    final englishCount = countEnglishWords(text);
    final totalWords = chineseCount + englishCount;
    return (totalWords / wordsPerMinute).ceil();
  }
}

/// 文件大小格式化工具
class FileSizeUtils {
  /// 格式化文件大小
  static String formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }

  /// 解析文件大小字符串
  static int? parseFileSize(String sizeStr) {
    final regex = RegExp(r'([\d.]+)\s*(B|KB|MB|GB)');
    final match = regex.firstMatch(sizeStr.toUpperCase());
    if (match == null) return null;

    final value = double.tryParse(match.group(1) ?? '');
    if (value == null) return null;

    final unit = match.group(2);
    switch (unit) {
      case 'B':
        return value.round();
      case 'KB':
        return (value * 1024).round();
      case 'MB':
        return (value * 1024 * 1024).round();
      case 'GB':
        return (value * 1024 * 1024 * 1024).round();
      default:
        return null;
    }
  }
}
