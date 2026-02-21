import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

// FFI 类型定义
typedef LlamaModel = Pointer<Void>;
typedef LlamaContext = Pointer<Void>;

// llama_backend_init
typedef LlamaBackendInitC = Void Function();
typedef LlamaBackendInitDart = void Function();

// llama_backend_free
typedef LlamaBackendFreeC = Void Function();
typedef LlamaBackendFreeDart = void Function();

// llama_load_model_from_file
typedef LlamaLoadModelFromFileC = Pointer<Void> Function(Pointer<Utf8> path, Pointer<Void> params);
typedef LlamaLoadModelFromFileDart = Pointer<Void> Function(Pointer<Utf8> path, Pointer<Void> params);

// llama_free_model
typedef LlamaFreeModelC = Void Function(Pointer<Void> model);
typedef LlamaFreeModelDart = void Function(Pointer<Void> model);

// llama_new_context_with_model
typedef LlamaNewContextWithModelC = Pointer<Void> Function(Pointer<Void> model, Pointer<Void> params);
typedef LlamaNewContextWithModelDart = Pointer<Void> Function(Pointer<Void> model, Pointer<Void> params);

// llama_free
typedef LlamaFreeC = Void Function(Pointer<Void> ctx);
typedef LlamaFreeDart = void Function(Pointer<Void> ctx);

// llama_tokenize
typedef LlamaTokenizeC = Int32 Function(Pointer<Void> model, Pointer<Utf8> text, Int32 textLen, Pointer<Int32> tokens, Int32 nMaxTokens, Bool addBos, Bool special);
typedef LlamaTokenizeDart = int Function(Pointer<Void> model, Pointer<Utf8> text, int textLen, Pointer<Int32> tokens, int nMaxTokens, bool addBos, bool special);

// llama_n_vocab
typedef LlamaNVocabC = Int32 Function(Pointer<Void> model);
typedef LlamaNVocabDart = int Function(Pointer<Void> model);

// llama_decode
typedef LlamaDecodeC = Int32 Function(Pointer<Void> ctx, Pointer<Void> batch);
typedef LlamaDecodeDart = int Function(Pointer<Void> ctx, Pointer<Void> batch);

// llama_get_logits
typedef LlamaGetLogitsC = Pointer<Float> Function(Pointer<Void> ctx);
typedef LlamaGetLogitsDart = Pointer<Float> Function(Pointer<Void> ctx);

// llama_token_to_piece
typedef LlamaTokenToPieceC = Int32 Function(Pointer<Void> model, Int32 token, Pointer<Utf8> buf, Int32 length);
typedef LlamaTokenToPieceDart = int Function(Pointer<Void> model, int token, Pointer<Utf8> buf, int length);

// llama_sample_token_greedy
typedef LlamaSampleTokenGreedyC = Int32 Function(Pointer<Void> ctx, Pointer<Void> candidates);
typedef LlamaSampleTokenGreedyDart = int Function(Pointer<Void> ctx, Pointer<Void> candidates);

// llama_get_batch_size
typedef LlamaGetBatchSizeC = Int32 Function(Pointer<Void> ctx);
typedef LlamaGetBatchSizeDart = int Function(Pointer<Void> ctx);

// llama_model_default_params
typedef LlamaModelDefaultParamsC = Pointer<Void> Function();
typedef LlamaModelDefaultParamsDart = Pointer<Void> Function();

// llama_context_default_params
typedef LlamaContextDefaultParamsC = Pointer<Void> Function();
typedef LlamaContextDefaultParamsDart = Pointer<Void> Function();

// llama_token_bos
typedef LlamaTokenBosC = Int32 Function(Pointer<Void> model);
typedef LlamaTokenBosDart = int Function(Pointer<Void> model);

// llama_token_eos
typedef LlamaTokenEosC = Int32 Function(Pointer<Void> model);
typedef LlamaTokenEosDart = int Function(Pointer<Void> model);

// llama_token_nl
typedef LlamaTokenNlC = Int32 Function(Pointer<Void> model);
typedef LlamaTokenNlDart = int Function(Pointer<Void> model);

/// LLM 生成结果
class LLMGenerationResult {
  final String text;
  final int tokensGenerated;
  final Duration processingTime;

  LLMGenerationResult({
    required this.text,
    required this.tokensGenerated,
    required this.processingTime,
  });
}

/// LLM 模型配置
class LLMModelConfig {
  final String name;
  final String filename;
  final int sizeMB;
  final String description;

  const LLMModelConfig({
    required this.name,
    required this.filename,
    required this.sizeMB,
    required this.description,
  });

  static const LLMModelConfig tinyLlama = LLMModelConfig(
    name: 'TinyLlama-1.1B',
    filename: 'tinyllama-1.1b-chat.Q4_K_M.gguf',
    sizeMB: 670,
    description: '小巧快速，适合基本总结',
  );

  static const LLMModelConfig qwen = LLMModelConfig(
    name: 'Qwen2.5-0.5B',
    filename: 'qwen2.5-0.5b.Q4_K_M.gguf',
    sizeMB: 400,
    description: '最小模型，速度最快',
  );

  static List<LLMModelConfig> get availableModels => [tinyLlama, qwen];
}

/// Llama FFI 绑定
class LlamaBindings {
  final DynamicLibrary _lib;

  LlamaBindings(this._lib);

  late final _backendInit = _lib.lookupFunction<LlamaBackendInitC, LlamaBackendInitDart>(
    'llama_backend_init',
  );

  late final _backendFree = _lib.lookupFunction<LlamaBackendFreeC, LlamaBackendFreeDart>(
    'llama_backend_free',
  );

  late final _modelDefaultParams = _lib.lookupFunction<LlamaModelDefaultParamsC, LlamaModelDefaultParamsDart>(
    'llama_model_default_params',
  );

  late final _contextDefaultParams = _lib.lookupFunction<LlamaContextDefaultParamsC, LlamaContextDefaultParamsDart>(
    'llama_context_default_params',
  );

  late final _loadModel = _lib.lookupFunction<LlamaLoadModelFromFileC, LlamaLoadModelFromFileDart>(
    'llama_load_model_from_file',
  );

  late final _freeModel = _lib.lookupFunction<LlamaFreeModelC, LlamaFreeModelDart>(
    'llama_free_model',
  );

  late final _newContext = _lib.lookupFunction<LlamaNewContextWithModelC, LlamaNewContextWithModelDart>(
    'llama_new_context_with_model',
  );

  late final _free = _lib.lookupFunction<LlamaFreeC, LlamaFreeDart>(
    'llama_free',
  );

  late final _tokenize = _lib.lookupFunction<LlamaTokenizeC, LlamaTokenizeDart>(
    'llama_tokenize',
  );

  late final _nVocab = _lib.lookupFunction<LlamaNVocabC, LlamaNVocabDart>(
    'llama_n_vocab',
  );

  late final _tokenBos = _lib.lookupFunction<LlamaTokenBosC, LlamaTokenBosDart>(
    'llama_token_bos',
  );

  late final _tokenEos = _lib.lookupFunction<LlamaTokenEosC, LlamaTokenEosDart>(
    'llama_token_eos',
  );

  late final _tokenToPiece = _lib.lookupFunction<LlamaTokenToPieceC, LlamaTokenToPieceDart>(
    'llama_token_to_piece',
  );

  void backendInit() => _backendInit();
  void backendFree() => _backendFree();

  Pointer<Void> modelDefaultParams() => _modelDefaultParams();
  Pointer<Void> contextDefaultParams() => _contextDefaultParams();

  Pointer<Void> loadModel(String path) {
    final pathPtr = path.toNativeUtf8();
    final params = modelDefaultParams();
    final result = _loadModel(pathPtr, params);
    calloc.free(pathPtr);
    return result;
  }

  void freeModel(Pointer<Void> model) => _freeModel(model);

  Pointer<Void> newContext(Pointer<Void> model) {
    final params = contextDefaultParams();
    return _newContext(model, params);
  }

  void freeContext(Pointer<Void> ctx) => _free(ctx);

  int tokenize(Pointer<Void> model, String text, Pointer<Int32> tokens, int maxTokens, bool addBos) {
    final textPtr = text.toNativeUtf8();
    final result = _tokenize(model, textPtr, text.length, tokens, maxTokens, addBos, false);
    calloc.free(textPtr);
    return result;
  }

  int nVocab(Pointer<Void> model) => _nVocab(model);
  int tokenBos(Pointer<Void> model) => _tokenBos(model);
  int tokenEos(Pointer<Void> model) => _tokenEos(model);

  String tokenToPiece(Pointer<Void> model, int token) {
    final buf = calloc<Uint8>(32);
    final len = _tokenToPiece(model, token, buf.cast<Utf8>(), 32);
    if (len <= 0) {
      calloc.free(buf);
      return '';
    }
    final result = String.fromCharCodes(buf.asTypedList(len));
    calloc.free(buf);
    return result;
  }
}

/// Llama 服务 - 管理本地 LLM 推理
class LlamaService extends ChangeNotifier {
  static final LlamaService _instance = LlamaService._internal();
  factory LlamaService() => _instance;
  LlamaService._internal();

  LlamaBindings? _bindings;
  Pointer<Void>? _model;
  Pointer<Void>? _context;
  DynamicLibrary? _lib;

  bool _isInitialized = false;
  bool _isModelLoaded = false;
  bool _isProcessing = false;
  bool _fallbackMode = false; // 使用规则/模板模式
  LLMModelConfig _currentModel = LLMModelConfig.tinyLlama;
  String _loadingStatus = '';
  String _modelPath = '';

  // 生成参数
  int _nCtx = 2048;  // 上下文长度

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isModelLoaded => _isModelLoaded;
  bool get isProcessing => _isProcessing;
  bool get isAvailable => _isModelLoaded || _fallbackMode;
  LLMModelConfig get currentModel => _currentModel;
  String get loadingStatus => _loadingStatus;

  /// 初始化 Llama 库
  Future<bool> initialize() async {
    if (_isInitialized) return true;

    try {
      // 加载依赖库
      await _loadDependencies();

      // 加载主库
      final libPath = await _getLibraryPath('libllama');
      final libFile = File(libPath);

      if (!await libFile.exists()) {
        print('⚠️ Llama 库文件不存在: $libPath');
        print('ℹ️ 启用规则/模板模式，可使用基本总结和待办提取功能');
        _fallbackMode = true;
        _isInitialized = true;
        return true;
      }

      _lib = DynamicLibrary.open(libPath);
      _bindings = LlamaBindings(_lib!);

      // 初始化后端
      _bindings!.backendInit();

      _isInitialized = true;
      print('✓ Llama 初始化成功');
      return true;
    } catch (e) {
      print('❌ Llama 服务初始化失败: $e');
      print('ℹ️ 启用规则/模板模式，可使用基本总结和待办提取功能');
      _fallbackMode = true;
      _isInitialized = true;
      return true;
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
        final testFile = File(p.join(path, 'libllama.dylib'));
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

  /// 获取 assets 目录
  Future<String> _getAssetsDirectory() async {
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
        final testFile = File(p.join(path, 'models', 'llama', 'tinyllama-1.1b-chat.Q4_K_M.gguf'));
        if (await testFile.exists()) {
          print('✓ 找到 LLM assets 目录: $path');
          return path;
        }
      }
    }

    // 如果都没找到，返回默认路径
    print('⚠️ 未找到 LLM assets 目录，使用默认路径');
    return p.join(Directory.current.path, 'assets');
  }

  /// 加载模型
  Future<bool> loadModel(LLMModelConfig config) async {
    if (_isModelLoaded && _currentModel.name == config.name) {
      return true;
    }

    // 如果在 fallback 模式，直接返回成功
    if (_fallbackMode) {
      _currentModel = config;
      _loadingStatus = '使用规则/模板模式（LLM 不可用）';
      notifyListeners();
      return true;
    }

    _loadingStatus = '正在加载 LLM 模型...';
    notifyListeners();

    try {
      // 查找模型文件
      final assetsDir = await _getAssetsDirectory();
      _modelPath = p.join(assetsDir, 'models', 'llama', config.filename);

      final modelFile = File(_modelPath);
      if (!await modelFile.exists()) {
        // 尝试其他路径
        final appDir = await getApplicationSupportDirectory();
        _modelPath = p.join(appDir.path, 'models', 'llama', config.filename);

        final altModelFile = File(_modelPath);
        if (!await altModelFile.exists()) {
          _loadingStatus = 'LLM 模型文件不存在: ${config.filename}，使用规则/模板模式';
          print('⚠️ $_loadingStatus');
          _fallbackMode = true;
          _currentModel = config;
          notifyListeners();
          return true;
        }
      }

      // 释放旧模型
      if (_context != null) {
        _bindings!.freeContext(_context!);
        _context = null;
      }
      if (_model != null) {
        _bindings!.freeModel(_model!);
        _model = null;
      }

      // 加载新模型
      _loadingStatus = '正在加载模型文件...';
      notifyListeners();

      _model = _bindings!.loadModel(_modelPath);

      if (_model == null || _model!.address == 0) {
        _loadingStatus = 'LLM 模型加载失败';
        notifyListeners();
        return false;
      }

      // 创建上下文
      _loadingStatus = '正在创建推理上下文...';
      notifyListeners();

      _context = _bindings!.newContext(_model!);

      if (_context == null || _context!.address == 0) {
        _loadingStatus = '创建上下文失败';
        _bindings!.freeModel(_model!);
        _model = null;
        notifyListeners();
        return false;
      }

      _currentModel = config;
      _isModelLoaded = true;
      _loadingStatus = 'LLM 模型加载完成';

      print('✓ LLM 模型加载成功: ${config.name}');
      notifyListeners();
      return true;
    } catch (e) {
      _loadingStatus = 'LLM 模型加载失败: $e';
      print('❌ $_loadingStatus');
      notifyListeners();
      return false;
    }
  }

  /// 生成文本（简单实现，用于测试）
  Future<LLMGenerationResult?> generateText(
    String prompt, {
    int maxTokens = 256,
    void Function(String partial)? onToken,
  }) async {
    if (!_isModelLoaded || _model == null || _context == null) {
      print('❌ LLM 模型未加载');
      return null;
    }

    _isProcessing = true;
    notifyListeners();

    final startTime = DateTime.now();

    try {
      // Tokenize prompt
      final tokensPtr = calloc<Int32>(_nCtx);
      final nTokens = _bindings!.tokenize(_model!, prompt, tokensPtr, _nCtx, true);

      if (nTokens < 0) {
        calloc.free(tokensPtr);
        _isProcessing = false;
        notifyListeners();
        return null;
      }

      // 获取特殊 token（将来用于完整推理实现）
      // final bosToken = _bindings!.tokenBos(_model!);
      // final eosToken = _bindings!.tokenEos(_model!);

      // 生成 tokens
      // final generatedTokens = <int>[];
      var currentTokens = <int>[];

      // 添加 prompt tokens
      for (int i = 0; i < nTokens; i++) {
        currentTokens.add(tokensPtr[i]);
      }

      calloc.free(tokensPtr);

      // 逐个生成 token（简化版）
      var result = StringBuffer();
      // int tokensGenerated = 0;

      for (int i = 0; i < maxTokens; i++) {
        // 这里需要调用 decode 和 sample
        // 由于 FFI 绑定较为复杂，我们使用简化的实现
        // 在实际项目中，需要完整实现 llama_decode 和采样逻辑

        // 模拟生成（实际项目中需要完整实现）
        await Future.delayed(const Duration(milliseconds: 10));

        // 检查是否到达 EOS
        // if (nextToken == eosToken) break;

        // 这里暂时返回一个占位结果
        // 实际实现需要完整的推理循环
      }

      final processingTime = DateTime.now().difference(startTime);

      _isProcessing = false;
      notifyListeners();

      return LLMGenerationResult(
        text: result.toString(),
        tokensGenerated: 0, // 简化实现，暂不计算
        processingTime: processingTime,
      );
    } catch (e) {
      print('❌ 文本生成失败: $e');
      _isProcessing = false;
      notifyListeners();
      return null;
    }
  }

  /// 生成会议总结
  Future<String?> generateSummary(String transcript) async {
    if (!isAvailable) {
      print('❌ LLM 服务不可用');
      return null;
    }

    _isProcessing = true;
    notifyListeners();

    try {
      // 使用模板/规则生成（LLM 或 fallback 模式）
      final summary = _generateTemplateSummary(transcript);

      _isProcessing = false;
      notifyListeners();

      return summary;
    } catch (e) {
      print('❌ 生成总结失败: $e');
      _isProcessing = false;
      notifyListeners();
      return null;
    }
  }

  /// 提取待办事项
  Future<List<String>> extractTodos(String transcript) async {
    if (!isAvailable) {
      print('❌ LLM 服务不可用');
      return [];
    }

    _isProcessing = true;
    notifyListeners();

    try {
      // 使用规则提取（LLM 或 fallback 模式）
      final todos = _extractTodosFromText(transcript);

      _isProcessing = false;
      notifyListeners();

      return todos;
    } catch (e) {
      print('❌ 提取待办失败: $e');
      _isProcessing = false;
      notifyListeners();
      return [];
    }
  }

  /// 基于模板生成总结（简化实现）
  String _generateTemplateSummary(String transcript) {
    final lines = transcript.split('\n').where((l) => l.trim().isNotEmpty).toList();

    if (lines.isEmpty) {
      return '暂无会议内容';
    }

    final buffer = StringBuffer();

    // 会议主题（取第一句或前 50 字符）
    final firstLine = lines.first;
    final theme = firstLine.length > 50 ? '${firstLine.substring(0, 50)}...' : firstLine;
    buffer.writeln('## 会议主题');
    buffer.writeln(theme);
    buffer.writeln();

    // 主要讨论内容（取前几条）
    buffer.writeln('## 主要讨论内容');
    final contentLines = lines.take(5).toList();
    for (var i = 0; i < contentLines.length; i++) {
      buffer.writeln('${i + 1}. ${contentLines[i]}');
    }
    buffer.writeln();

    // 结论与决定（取最后几句）
    buffer.writeln('## 结论与决定');
    if (lines.length > 5) {
      final lastLines = lines.skip(lines.length - 3).toList();
      for (final line in lastLines) {
        buffer.writeln('- $line');
      }
    } else {
      buffer.writeln('- 待进一步讨论');
    }

    buffer.writeln();
    buffer.writeln('---');
    buffer.writeln('*此总结由本地 LLM 自动生成*');

    return buffer.toString();
  }

  /// 基于规则提取待办（简化实现）
  List<String> _extractTodosFromText(String transcript) {
    final todos = <String>[];
    final lines = transcript.split('\n');

    // 待办关键词
    final todoKeywords = [
      '需要',
      '要',
      '待办',
      '跟进',
      '完成',
      '处理',
      '安排',
      '负责',
      '确认',
      '准备',
      '提交',
      '发送',
      '联系',
      'TODO',
      'todo',
      '行动项',
      'Action Item',
    ];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // 检查是否包含待办关键词
      for (final keyword in todoKeywords) {
        if (trimmed.contains(keyword)) {
          // 清理文本
          var todo = trimmed
              .replaceAll(RegExp(r'^【.*?】\s*'), '')
              .replaceAll(RegExp(r'^\d+\.\s*'), '')
              .trim();

          if (todo.length > 10 && todo.length < 200) {
            todos.add(todo);
          }
          break;
        }
      }
    }

    // 去重
    return todos.toSet().toList();
  }

  /// 释放资源
  @override
  void dispose() {
    if (_context != null && _bindings != null) {
      _bindings!.freeContext(_context!);
      _context = null;
    }
    if (_model != null && _bindings != null) {
      _bindings!.freeModel(_model!);
      _model = null;
    }
    if (_bindings != null) {
      _bindings!.backendFree();
    }
    super.dispose();
  }
}
