import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/models.dart';

// ============ Isolate 转录函数 ============
// 必须是顶层函数，在独立 isolate 中运行

/// 在 isolate 中执行转录
Map<String, dynamic>? _transcribeInIsolate(Map<String, dynamic> params) {
  // 注意: isolate 中不能使用 debugPrint，只能用 print
  print('🔍 [ISOLATE] 1. isolate 开始执行');

  final modelPath = params['modelPath'] as String;
  final samples = params['samples'] as Float32List;
  final libPath = params['libPath'] as String;

  print('🔍 [ISOLATE] 2. 参数解析完成');
  print('🔍 [ISOLATE]    模型路径: $modelPath');
  print('🔍 [ISOLATE]    样本数: ${samples.length}');
  print('🔍 [ISOLATE]    库路径: $libPath');

  try {
    // 在 isolate 中加载库和模型
    print('🔍 [ISOLATE] 3. 加载动态库');
    final lib = DynamicLibrary.open(libPath);
    print('🔍 [ISOLATE] 4. 动态库加载成功');

    // 绑定函数
    print('🔍 [ISOLATE] 5. 绑定 FFI 函数');
    final initFromFile = lib.lookupFunction<
        Pointer<Void> Function(Pointer<Utf8>),
        Pointer<Void> Function(Pointer<Utf8>)>(
      'whisper_init_from_file_with_params',
    );

    final free = lib.lookupFunction<
        Void Function(Pointer<Void>),
        void Function(Pointer<Void>)>('whisper_free');

    final fullDefaultParams = lib.lookupFunction<
        Pointer<Void> Function(Int32),
        Pointer<Void> Function(int)>(
      'whisper_full_default_params_by_ref',
    );

    final full = lib.lookupFunction<
        Int32 Function(Pointer<Void>, Pointer<Void>, Pointer<Float>, Int32),
        int Function(Pointer<Void>, Pointer<Void>, Pointer<Float>, int)>(
      'whisper_full',
    );

    final nSegments = lib.lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)>(
      'whisper_full_n_segments',
    );

    final getSegmentText = lib.lookupFunction<
        Pointer<Utf8> Function(Pointer<Void>, Int32),
        Pointer<Utf8> Function(Pointer<Void>, int)>(
      'whisper_full_get_segment_text',
    );

    final getSegmentT0 = lib.lookupFunction<
        Int64 Function(Pointer<Void>, Int32),
        int Function(Pointer<Void>, int)>(
      'whisper_full_get_segment_t0',
    );

    final getSegmentT1 = lib.lookupFunction<
        Int64 Function(Pointer<Void>, Int32),
        int Function(Pointer<Void>, int)>(
      'whisper_full_get_segment_t1',
    );
    print('🔍 [ISOLATE] 6. FFI 函数绑定完成');

    // 加载模型
    print('🔍 [ISOLATE] 7. 加载 whisper 模型');
    final modelPathPtr = modelPath.toNativeUtf8();
    final context = initFromFile(modelPathPtr);
    calloc.free(modelPathPtr);
    print('🔍 [ISOLATE] 8. 模型加载完成, context: ${context.address}');

    if (context.address == 0) {
      print('❌ [ISOLATE] 模型加载失败');
      return null;
    }

    // 准备音频数据
    print('🔍 [ISOLATE] 9. 准备音频数据');
    final samplesPtr = calloc<Float>(samples.length);
    for (int i = 0; i < samples.length; i++) {
      samplesPtr[i] = samples[i];
    }
    print('🔍 [ISOLATE] 10. 音频数据准备完成');

    // 执行转录
    print('🔍 [ISOLATE] 11. 开始执行 whisper 转录');
    final params = fullDefaultParams(0);
    final result = full(context, params, samplesPtr, samples.length);
    print('🔍 [ISOLATE] 12. whisper 转录完成, 结果: $result');

    // 释放音频数据内存
    calloc.free(samplesPtr);

    if (result != 0) {
      print('❌ [ISOLATE] 转录失败，错误码: $result');
      free(context);
      return null;
    }

    // 获取结果
    print('🔍 [ISOLATE] 13. 获取转录片段');
    final numSegments = nSegments(context);
    print('🔍 [ISOLATE] 14. 片段数量: $numSegments');

    final segments = <Map<String, dynamic>>[];

    for (int i = 0; i < numSegments; i++) {
      final textPtr = getSegmentText(context, i);
      final text = textPtr.toDartString();
      final t0 = getSegmentT0(context, i);
      final t1 = getSegmentT1(context, i);

      segments.add({
        'startTime': t0 / 100.0,
        'endTime': t1 / 100.0,
        'text': text.trim(),
      });
    }

    // 释放模型
    print('🔍 [ISOLATE] 15. 释放模型');
    free(context);

    print('🔍 [ISOLATE] 16. isolate 完成, 返回 ${segments.length} 个片段');
    return {'segments': segments};
  } catch (e, stack) {
    print('❌ [ISOLATE] 转录错误: $e');
    print('❌ [ISOLATE] 堆栈: $stack');
    return null;
  }
}

// FFI 类型定义
typedef WhisperContext = Pointer<Void>;

// whisper_init_from_file
typedef WhisperInitFromFileC = Pointer<Void> Function(Pointer<Utf8> path);
typedef WhisperInitFromFileDart = Pointer<Void> Function(Pointer<Utf8> path);

// whisper_free
typedef WhisperFreeC = Void Function(Pointer<Void> ctx);
typedef WhisperFreeDart = void Function(Pointer<Void> ctx);

// whisper_full_params
typedef WhisperFullDefaultParamsC = Pointer<Void> Function(Int32 strategy);
typedef WhisperFullDefaultParamsDart = Pointer<Void> Function(int strategy);

// whisper_full
typedef WhisperFullC = Int32 Function(Pointer<Void> ctx, Pointer<Void> params, Pointer<Float> samples, Int32 nSamples);
typedef WhisperFullDart = int Function(Pointer<Void> ctx, Pointer<Void> params, Pointer<Float> samples, int nSamples);

// whisper_full_n_segments
typedef WhisperFullNSegmentsC = Int32 Function(Pointer<Void> ctx);
typedef WhisperFullNSegmentsDart = int Function(Pointer<Void> ctx);

// whisper_full_get_segment_text
typedef WhisperFullGetSegmentTextC = Pointer<Utf8> Function(Pointer<Void> ctx, Int32 i);
typedef WhisperFullGetSegmentTextDart = Pointer<Utf8> Function(Pointer<Void> ctx, int i);

// whisper_full_get_segment_t0
typedef WhisperFullGetSegmentT0C = Int64 Function(Pointer<Void> ctx, Int32 i);
typedef WhisperFullGetSegmentT0Dart = int Function(Pointer<Void> ctx, int i);

// whisper_full_get_segment_t1
typedef WhisperFullGetSegmentT1C = Int64 Function(Pointer<Void> ctx, Int32 i);
typedef WhisperFullGetSegmentT1Dart = int Function(Pointer<Void> ctx, int i);

// whisper_print_system_info
typedef WhisperPrintSystemInfoC = Pointer<Utf8> Function();
typedef WhisperPrintSystemInfoDart = Pointer<Utf8> Function();

/// Whisper 转录结果
class WhisperTranscriptionResult {
  final String text;
  final List<TranscriptSegment> segments;
  final String? language;
  final Duration processingTime;

  WhisperTranscriptionResult({
    required this.text,
    required this.segments,
    this.language,
    required this.processingTime,
  });
}

/// 转录片段
class TranscriptSegment {
  final double startTime;
  final double endTime;
  final String text;
  final int? speakerId;

  TranscriptSegment({
    required this.startTime,
    required this.endTime,
    required this.text,
    this.speakerId,
  });

  TranscriptSegment copyWith({
    double? startTime,
    double? endTime,
    String? text,
    int? speakerId,
  }) {
    return TranscriptSegment(
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      text: text ?? this.text,
      speakerId: speakerId ?? this.speakerId,
    );
  }
}

/// Whisper FFI 绑定
class WhisperBindings {
  final DynamicLibrary _lib;

  WhisperBindings(this._lib);

  late final _initFromFile = _lib.lookupFunction<WhisperInitFromFileC, WhisperInitFromFileDart>(
    'whisper_init_from_file_with_params',
  );

  late final _free = _lib.lookupFunction<WhisperFreeC, WhisperFreeDart>('whisper_free');

  late final _fullDefaultParams = _lib.lookupFunction<WhisperFullDefaultParamsC, WhisperFullDefaultParamsDart>(
    'whisper_full_default_params_by_ref',
  );

  late final _full = _lib.lookupFunction<WhisperFullC, WhisperFullDart>('whisper_full');

  late final _nSegments = _lib.lookupFunction<WhisperFullNSegmentsC, WhisperFullNSegmentsDart>(
    'whisper_full_n_segments',
  );

  late final _getSegmentText = _lib.lookupFunction<WhisperFullGetSegmentTextC, WhisperFullGetSegmentTextDart>(
    'whisper_full_get_segment_text',
  );

  late final _getSegmentT0 = _lib.lookupFunction<WhisperFullGetSegmentT0C, WhisperFullGetSegmentT0Dart>(
    'whisper_full_get_segment_t0',
  );

  late final _getSegmentT1 = _lib.lookupFunction<WhisperFullGetSegmentT1C, WhisperFullGetSegmentT1Dart>(
    'whisper_full_get_segment_t1',
  );

  late final _systemInfo = _lib.lookupFunction<WhisperPrintSystemInfoC, WhisperPrintSystemInfoDart>(
    'whisper_print_system_info',
  );

  Pointer<Void> initFromFile(String path) {
    final pathPtr = path.toNativeUtf8();
    final result = _initFromFile(pathPtr);
    calloc.free(pathPtr);
    return result;
  }

  void free(Pointer<Void> ctx) => _free(ctx);

  String systemInfo() {
    final result = _systemInfo();
    return result.toDartString();
  }

  int transcribe(Pointer<Void> ctx, Float32List samples) {
    // 分配内存
    final samplesPtr = calloc<Float>(samples.length);
    for (int i = 0; i < samples.length; i++) {
      samplesPtr[i] = samples[i];
    }

    // 使用默认参数 (WHISPER_SAMPLING_GREEDY = 0)
    // whisper.cpp 会自动检测语言，对于中文音频效果很好
    final params = _fullDefaultParams(0);

    // 执行转录
    final result = _full(ctx, params, samplesPtr, samples.length);

    // 释放内存
    calloc.free(samplesPtr);

    return result;
  }

  List<TranscriptSegment> getSegments(Pointer<Void> ctx) {
    final segments = <TranscriptSegment>[];
    final nSegments = _nSegments(ctx);

    for (int i = 0; i < nSegments; i++) {
      final textPtr = _getSegmentText(ctx, i);
      final text = textPtr.toDartString();

      final t0 = _getSegmentT0(ctx, i);
      final t1 = _getSegmentT1(ctx, i);

      // 时间单位是 centiseconds (1/100 秒)
      segments.add(TranscriptSegment(
        startTime: t0 / 100.0,
        endTime: t1 / 100.0,
        text: text.trim(),
      ));
    }

    return segments;
  }
}

/// Whisper 服务 - 管理 Whisper.cpp 的语音识别
class WhisperService extends ChangeNotifier {
  static final WhisperService _instance = WhisperService._internal();
  factory WhisperService() => _instance;
  WhisperService._internal();

  WhisperBindings? _bindings;
  Pointer<Void>? _context;
  DynamicLibrary? _lib;

  bool _isModelLoaded = false;
  bool _isProcessing = false;
  WhisperModelSize _currentModel = WhisperModelSize.base;
  String _loadingStatus = '';
  String _modelPath = '';

  // Getters
  bool get isModelLoaded => _isModelLoaded;
  bool get isProcessing => _isProcessing;
  WhisperModelSize get currentModel => _currentModel;
  String get loadingStatus => _loadingStatus;

  /// 初始化 Whisper 库
  Future<bool> initialize() async {
    try {
      // 加载依赖库
      await _loadDependencies();

      // 加载主库
      final libPath = await _getLibraryPath('libwhisper');
      final libFile = File(libPath);

      if (!await libFile.exists()) {
        print('⚠️ Whisper 库文件不存在: $libPath');
        return false;
      }

      _lib = DynamicLibrary.open(libPath);
      _bindings = WhisperBindings(_lib!);

      final sysInfo = _bindings!.systemInfo();
      print('✓ Whisper 初始化成功: $sysInfo');
      return true;
    } catch (e) {
      print('❌ Whisper 服务初始化失败: $e');
      return false;
    }
  }

  /// 加载依赖库
  Future<void> _loadDependencies() async {
    if (!Platform.isMacOS) return;

    final dependencies = [
      'libggml-base',
      'libggml-cpu',
      'libggml-metal',
      'libggml-blas',
      'libggml',
    ];

    for (final dep in dependencies) {
      try {
        final path = await _getLibraryPath(dep);
        final file = File(path);
        if (await file.exists()) {
          DynamicLibrary.open(path);
          print('✓ 加载依赖库: $dep');
        }
      } catch (e) {
        print('⚠️ 加载依赖库 $dep 失败 (可能不是必需的): $e');
      }
    }
  }

  /// 获取 assets 目录
  Future<String> _getAssetsDirectory() async {
    // 开发模式：使用项目目录下的 assets
    // 生产模式：使用应用程序 bundle 内的 assets

    final possiblePaths = <String>[];

    // 1. 项目目录（开发模式）
    possiblePaths.add(p.join(Directory.current.path, 'assets'));

    // 2. 应用程序 bundle（生产模式）
    final exeDir = p.dirname(Platform.resolvedExecutable);
    possiblePaths.add(p.join(exeDir, '..', 'Resources', 'assets'));
    possiblePaths.add(p.join(exeDir, 'assets'));
    possiblePaths.add(p.join(exeDir, '..', 'assets'));

    for (final path in possiblePaths) {
      final dir = Directory(path);
      if (await dir.exists()) {
        final testFile = File(p.join(path, 'models', 'ggml-base.bin'));
        if (await testFile.exists()) {
          print('✓ 找到 assets 目录: $path');
          return path;
        }
      }
    }

    // 如果都没找到，返回默认路径
    print('⚠️ 未找到 assets 目录，使用默认路径');
    return p.join(Directory.current.path, 'assets');
  }

  /// 获取库目录
  Future<String> _getLibraryDirectory() async {
    final exeDir = p.dirname(Platform.resolvedExecutable);

    final possiblePaths = <String>[];

    // 1. Frameworks 目录（macOS app bundle）
    possiblePaths.add(p.join(exeDir, '..', 'Frameworks'));

    // 2. 项目 assets 目录（开发模式）
    possiblePaths.add(p.join(Directory.current.path, 'assets'));

    // 3. 应用程序目录
    possiblePaths.add(exeDir);

    for (final path in possiblePaths) {
      final dir = Directory(path);
      if (await dir.exists()) {
        final testFile = File(p.join(path, 'libwhisper.dylib'));
        if (await testFile.exists()) {
          print('✓ 找到库目录: $path');
          return path;
        }
      }
    }

    // 如果都没找到，返回默认路径
    print('⚠️ 未找到库目录，使用默认路径');
    return p.join(Directory.current.path, 'assets');
  }

  /// 获取平台特定的库路径
  Future<String> _getLibraryPath(String name) async {
    final libDir = await _getLibraryDirectory();

    if (Platform.isMacOS) {
      return p.join(libDir, '$name.dylib');
    } else if (Platform.isWindows) {
      return p.join(libDir, '$name.dll');
    } else if (Platform.isLinux) {
      return p.join(libDir, '$name.so');
    }
    throw UnsupportedError('Unsupported platform');
  }

  /// 加载模型
  Future<bool> loadModel(WhisperModelSize size) async {
    if (_isModelLoaded && _currentModel == size) {
      return true;
    }

    _loadingStatus = '正在加载模型...';
    notifyListeners();

    try {
      // 查找模型文件
      final assetsDir = await _getAssetsDirectory();
      _modelPath = p.join(assetsDir, 'models', 'ggml-${size.code}.bin');

      final modelFile = File(_modelPath);
      if (!await modelFile.exists()) {
        // 尝试其他路径
        final appDir = await getApplicationSupportDirectory();
        _modelPath = p.join(appDir.path, 'models', 'ggml-${size.code}.bin');

        final altModelFile = File(_modelPath);
        if (!await altModelFile.exists()) {
          _loadingStatus = '模型文件不存在: ggml-${size.code}.bin';
          notifyListeners();
          return false;
        }
      }

      // 释放旧模型
      if (_context != null) {
        _bindings!.free(_context!);
        _context = null;
      }

      // 加载新模型
      _context = _bindings!.initFromFile(_modelPath);

      if (_context == null || _context!.address == 0) {
        _loadingStatus = '模型加载失败';
        notifyListeners();
        return false;
      }

      _currentModel = size;
      _isModelLoaded = true;
      _loadingStatus = '模型加载完成';

      print('✓ 模型加载成功: ${size.displayName}');
      notifyListeners();
      return true;
    } catch (e) {
      _loadingStatus = '模型加载失败: $e';
      print('❌ 模型加载失败: $e');
      notifyListeners();
      return false;
    }
  }

  /// 转录音频文件
  Future<WhisperTranscriptionResult?> transcribeFile(String audioPath, {String language = 'auto'}) async {
    debugPrint('🔍 [WHISPER] transcribeFile 开始: $audioPath');
    if (!_isModelLoaded || _context == null) {
      print('❌ 模型未加载');
      return null;
    }

    _isProcessing = true;
    notifyListeners();

    final startTime = DateTime.now();

    try {
      // 读取音频文件并转换为 PCM
      debugPrint('🔍 [WHISPER] 加载音频文件');
      final samples = await _loadAudioFile(audioPath);
      if (samples == null) {
        _isProcessing = false;
        notifyListeners();
        return null;
      }
      debugPrint('🔍 [WHISPER] 音频加载完成, 样本数: ${samples.length}');

      print('📝 开始转录 (自动检测语言)');

      debugPrint('🔍 [WHISPER] 准备在 isolate 中执行转录');
      // 在 isolate 中执行转录以避免阻塞主线程
      final result = await compute(_transcribeInIsolate, {
        'modelPath': _modelPath,
        'samples': samples,
        'libPath': await _getLibraryPath('libwhisper'),
      });
      debugPrint('🔍 [WHISPER] isolate 转录完成');

      if (result == null) {
        print('❌ 转录失败');
        _isProcessing = false;
        notifyListeners();
        return null;
      }

      // 将 Map 转换为 TranscriptSegment
      final segmentMaps = result['segments'] as List<dynamic>;
      final segments = segmentMaps.map((m) {
        final map = m as Map<String, dynamic>;
        return TranscriptSegment(
          startTime: map['startTime'] as double,
          endTime: map['endTime'] as double,
          text: map['text'] as String,
        );
      }).toList();

      // 检测发言人变化（基于静音间隔）
      _assignSpeakerIds(segments, samples);

      final fullText = segments.map((s) => s.text).join(' ');

      final processingTime = DateTime.now().difference(startTime);

      _isProcessing = false;
      notifyListeners();

      print('✓ 转录完成，片段数: ${segments.length}，耗时: ${processingTime.inMilliseconds}ms');

      return WhisperTranscriptionResult(
        text: fullText,
        segments: segments,
        processingTime: processingTime,
        language: language,
      );
    } catch (e, stack) {
      print('❌ 转录失败: $e');
      debugPrint('❌ [WHISPER] 堆栈: $stack');
      _isProcessing = false;
      notifyListeners();
      return null;
    }
  }

  /// 根据静音间隔分配发言人ID
  void _assignSpeakerIds(List<TranscriptSegment> segments, Float32List samples) {
    if (segments.isEmpty) return;

    const silenceThreshold = 1.5; // 静音间隔阈值（秒）
    int currentSpeakerId = 1;

    // 为每个片段分配发言人ID
    segments[0] = TranscriptSegment(
      startTime: segments[0].startTime,
      endTime: segments[0].endTime,
      text: segments[0].text,
      speakerId: currentSpeakerId,
    );

    for (int i = 1; i < segments.length; i++) {
      final gap = segments[i].startTime - segments[i - 1].endTime;

      // 如果静音间隔超过阈值，切换发言人
      if (gap >= silenceThreshold) {
        currentSpeakerId++;
      }

      segments[i] = TranscriptSegment(
        startTime: segments[i].startTime,
        endTime: segments[i].endTime,
        text: segments[i].text,
        speakerId: currentSpeakerId,
      );
    }

    print('✓ 检测到 $currentSpeakerId 位发言人');
  }

  /// 转录音频数据
  Future<WhisperTranscriptionResult?> transcribeSamples(
    Float32List samples, {
    String language = 'auto',
  }) async {
    debugPrint('🔍 [WHISPER] transcribeSamples 开始, 样本数: ${samples.length}');
    if (!_isModelLoaded || _context == null) {
      debugPrint('🔍 [WHISPER] 模型未加载');
      return null;
    }

    final startTime = DateTime.now();

    try {
      debugPrint('🔍 [WHISPER] 准备在 isolate 中执行转录');
      // 在 isolate 中执行转录以避免阻塞主线程
      final result = await compute(_transcribeInIsolate, {
        'modelPath': _modelPath,
        'samples': samples,
        'libPath': await _getLibraryPath('libwhisper'),
      });
      debugPrint('🔍 [WHISPER] isolate 转录完成');

      if (result == null) {
        debugPrint('🔍 [WHISPER] 转录结果为空');
        return null;
      }

      // 将 Map 转换为 TranscriptSegment
      final segmentMaps = result['segments'] as List<dynamic>;
      final segments = segmentMaps.map((m) {
        final map = m as Map<String, dynamic>;
        return TranscriptSegment(
          startTime: map['startTime'] as double,
          endTime: map['endTime'] as double,
          text: map['text'] as String,
        );
      }).toList();

      final fullText = segments.map((s) => s.text).join(' ');

      final processingTime = DateTime.now().difference(startTime);
      debugPrint('🔍 [WHISPER] transcribeSamples 完成, 耗时: ${processingTime.inMilliseconds}ms');

      return WhisperTranscriptionResult(
        text: fullText,
        segments: segments,
        processingTime: processingTime,
        language: language,
      );
    } catch (e, stack) {
      debugPrint('❌ [WHISPER] 转录失败: $e');
      debugPrint('❌ [WHISPER] 堆栈: $stack');
      return null;
    }
  }

  /// 加载音频文件
  Future<Float32List?> _loadAudioFile(String path) async {
    try {
      final file = File(path);
      final bytes = await file.readAsBytes();

      // 检测文件格式
      if (_isWavFile(bytes)) {
        return _parseWavFile(bytes);
      }

      // 默认按 16-bit PCM 处理
      return convertToFloat32(bytes);
    } catch (e) {
      print('❌ 加载音频文件失败: $e');
      return null;
    }
  }

  /// 检测 WAV 文件
  bool _isWavFile(Uint8List bytes) {
    if (bytes.length < 12) return false;
    final header = String.fromCharCodes(bytes.sublist(0, 4));
    final wave = String.fromCharCodes(bytes.sublist(8, 12));
    return header == 'RIFF' && wave == 'WAVE';
  }

  /// 解析 WAV 文件
  Float32List _parseWavFile(Uint8List bytes) {
    // 跳过 WAV 头部，找到 data chunk
    int offset = 12;
    int dataSize = 0;
    int dataOffset = 0;

    while (offset < bytes.length - 8) {
      final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize = bytes[offset + 4] |
          (bytes[offset + 5] << 8) |
          (bytes[offset + 6] << 16) |
          (bytes[offset + 7] << 24);

      if (chunkId == 'data') {
        dataSize = chunkSize;
        dataOffset = offset + 8;
        break;
      }

      offset += 8 + chunkSize;
    }

    if (dataSize == 0) {
      // 没找到 data chunk，直接处理整个文件
      return convertToFloat32(bytes);
    }

    // 提取 PCM 数据
    final pcmData = bytes.sublist(dataOffset, dataOffset + dataSize);
    return convertToFloat32(pcmData);
  }

  /// 将字节数据转换为 Float32
  Float32List convertToFloat32(Uint8List bytes) {
    // 假设 16-bit PCM
    final sampleCount = bytes.length ~/ 2;
    final samples = Float32List(sampleCount);

    for (int i = 0; i < sampleCount; i++) {
      final int16 = bytes[i * 2] | (bytes[i * 2 + 1] << 8);
      // 处理有符号整数
      final signed = int16 > 32767 ? int16 - 65536 : int16;
      samples[i] = signed / 32768.0;
    }

    return samples;
  }

  /// 释放资源
  @override
  void dispose() {
    if (_context != null && _bindings != null) {
      _bindings!.free(_context!);
      _context = null;
    }
    super.dispose();
  }
}
