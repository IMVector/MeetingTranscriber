import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/whisper_service.dart';
import '../services/audio_recording_service.dart';
import '../services/transcription_post_processor.dart';
import '../services/llama_service.dart';

/// 应用状态管理
class AppState extends ChangeNotifier {
  final DatabaseService _db = DatabaseService();
  final WhisperService _whisperService = WhisperService();
  final AudioRecordingService _recordingService = AudioRecordingService();
  final TranscriptionPostProcessor _postProcessor = TranscriptionPostProcessor();
  final LlamaService _llamaService = LlamaService();

  // 会议列表
  List<Meeting> _meetings = [];
  List<Meeting> get meetings => _meetings;

  // 当前会议
  Meeting? _currentMeeting;
  Meeting? get currentMeeting => _currentMeeting;

  // 服务 Getters
  WhisperService get whisperService => _whisperService;
  AudioRecordingService get recordingService => _recordingService;
  LlamaService get llamaService => _llamaService;

  // 初始化状态
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  // 实时转录状态
  bool _isLiveTranscribing = false;
  String _liveText = '';
  String _confirmedText = '';
  String get liveText => _liveText;
  String get confirmedText => _confirmedText;
  bool get isLiveTranscribing => _isLiveTranscribing;

  // 选中的模型
  WhisperModelSize _selectedModel = WhisperModelSize.base;
  WhisperModelSize get selectedModel => _selectedModel;

  /// 设置选中的模型
  void setSelectedModel(WhisperModelSize model) {
    _selectedModel = model;
    notifyListeners();
  }

  /// 初始化应用
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // 初始化数据库
      await _db.database;

      // 加载会议列表
      await loadMeetings();

      // 初始化 Whisper 服务
      await _whisperService.initialize();

      // 初始化 LLM 服务（异步，不阻塞启动）
      _llamaService.initialize().then((success) {
        if (success) {
          print('✓ LLM 服务初始化成功');
        } else {
          print('⚠️ LLM 服务初始化失败，总结和待办提取功能不可用');
        }
      });

      _isInitialized = true;
      print('✓ 应用初始化完成');
      notifyListeners();
    } catch (e) {
      print('❌ 应用初始化失败: $e');
    }
  }

  /// 加载会议列表
  Future<void> loadMeetings() async {
    _meetings = await _db.getAllMeetings();
    notifyListeners();
  }

  /// 创建新会议
  Future<Meeting> createMeeting(String title) async {
    final meeting = Meeting(title: title);
    await _db.insertMeeting(meeting);
    _meetings.insert(0, meeting);
    notifyListeners();
    return meeting;
  }

  /// 更新会议
  Future<void> updateMeeting(Meeting meeting) async {
    await _db.updateMeeting(meeting);
    final index = _meetings.indexWhere((m) => m.id == meeting.id);
    if (index != -1) {
      _meetings[index] = meeting;
      notifyListeners();
    }
  }

  /// 删除会议
  Future<void> deleteMeeting(String id) async {
    await _db.deleteMeeting(id);
    _meetings.removeWhere((m) => m.id == id);
    notifyListeners();
  }

  /// 选择当前会议
  void selectMeeting(Meeting? meeting) {
    _currentMeeting = meeting;
    notifyListeners();
  }

  /// 开始录音并转录
  Future<void> startRecordingWithTranscription(String title) async {
    // 创建会议
    final meeting = await createMeeting(title);
    _currentMeeting = meeting;

    // 开始录音
    final success = await _recordingService.startRecording();
    if (success) {
      _isLiveTranscribing = true;
      _liveText = '';
      _confirmedText = '';
      notifyListeners();
    }
  }

  /// 停止录音并转录
  Future<void> stopRecordingAndTranscribe() async {
    if (!_recordingService.isRecording) return;

    // 停止录音
    final audioPath = await _recordingService.stopRecording();
    if (audioPath == null || _currentMeeting == null) return;

    _isLiveTranscribing = false;
    notifyListeners();

    // 加载模型（如果未加载或需要切换模型）
    if (!_whisperService.isModelLoaded || _whisperService.currentModel != _selectedModel) {
      await _whisperService.loadModel(_selectedModel);
    }

    // 转录
    final result = await _whisperService.transcribeFile(audioPath, language: 'zh');
    if (result == null) return;

    // 后处理
    final processed = _postProcessor.process(
      result.text,
      segments: result.segments,
      config: PostProcessorConfig.meetingConfig,
    );

    // 保存转录
    final transcripts = processed.text.split('\n').where((t) => t.trim().isNotEmpty).map((text) {
      return Transcript(text: text.trim(), duration: Duration.zero);
    }).toList();

    await _db.insertTranscripts(transcripts, _currentMeeting!.id);

    // 更新会议
    final updatedMeeting = _currentMeeting!.copyWith(
      duration: _recordingService.recordingDuration,
      audioFilePath: audioPath,
      usedModelSize: _whisperService.currentModel.code,
      transcripts: transcripts,
    );
    await updateMeeting(updatedMeeting);
  }

  /// 重新转录会议
  Future<bool> retranscribeMeeting(String meetingId, WhisperModelSize model) async {
    final meeting = _meetings.firstWhere((m) => m.id == meetingId);
    if (meeting.audioFilePath == null) return false;

    // 加载模型
    if (!_whisperService.isModelLoaded || _whisperService.currentModel != model) {
      final loaded = await _whisperService.loadModel(model);
      if (!loaded) return false;
    }

    // 转录
    final result = await _whisperService.transcribeFile(meeting.audioFilePath!, language: 'zh');
    if (result == null) return false;

    // 后处理
    final processed = _postProcessor.process(
      result.text,
      segments: result.segments,
      config: PostProcessorConfig.meetingConfig,
    );

    // 保存转录
    final transcripts = processed.text.split('\n').where((t) => t.trim().isNotEmpty).map((text) {
      return Transcript(text: text.trim(), duration: Duration.zero);
    }).toList();

    await _db.deleteTranscripts(meetingId);
    await _db.insertTranscripts(transcripts, meetingId);

    // 更新会议
    final updatedMeeting = meeting.copyWith(
      usedModelSize: _whisperService.currentModel.code,
      transcripts: transcripts,
    );
    await updateMeeting(updatedMeeting);

    // 更新当前会议
    if (_currentMeeting?.id == meetingId) {
      _currentMeeting = updatedMeeting;
      notifyListeners();
    }

    return true;
  }

  /// 开始实时转录
  Future<void> startLiveTranscription(String title) async {
    debugPrint('🔍 [LIVE] 1. startLiveTranscription 开始');
    // 创建会议
    final meeting = await createMeeting(title);
    _currentMeeting = meeting;
    debugPrint('🔍 [LIVE] 2. 会议已创建: ${meeting.id}');

    // 加载模型（如果未加载）
    if (!_whisperService.isModelLoaded) {
      debugPrint('🔍 [LIVE] 3. 模型未加载，准备加载');
      await _whisperService.loadModel(_selectedModel);
      debugPrint('🔍 [LIVE] 4. 模型加载完成');
    } else {
      debugPrint('🔍 [LIVE] 3. 模型已加载');
    }

    // 清空转录状态
    _liveText = '';
    _confirmedText = '';
    _isLiveTranscribing = true;
    notifyListeners();
    debugPrint('🔍 [LIVE] 5. 状态已清空');

    // 设置音频块回调
    _recordingService.onAudioChunkReady = _processAudioChunk;
    debugPrint('🔍 [LIVE] 6. 回调已设置');

    // 开始录音
    debugPrint('🔍 [LIVE] 7. 准备开始录音');
    final success = await _recordingService.startRecording();
    debugPrint('🔍 [LIVE] 8. 录音开始: $success');
    if (!success) {
      _isLiveTranscribing = false;
      _recordingService.onAudioChunkReady = null;
      notifyListeners();
    }
  }

  /// 处理音频块（实时转录）
  Future<void> _processAudioChunk(Float32List samples) async {
    if (!_isLiveTranscribing || _recordingService.isPaused) return;

    debugPrint('🔍 [LIVE-CHUNK] 处理音频块, 样本数: ${samples.length}');
    final startTime = DateTime.now();

    try {
      // 执行转录
      final result = await _whisperService.transcribeSamples(samples, language: 'zh');
      final elapsed = DateTime.now().difference(startTime);
      debugPrint('🔍 [LIVE-CHUNK] 转录完成, 耗时: ${elapsed.inMilliseconds}ms');

      if (result != null && result.text.isNotEmpty) {
        // 简单后处理
        final processed = _postProcessor.process(
          result.text,
          segments: result.segments,
          config: PostProcessorConfig.defaultConfig,
        );

        // 更新实时文本
        updateLiveText(processed.text);
        debugPrint('🔍 [LIVE-CHUNK] 文本已更新: ${processed.text.length} 字符');
      }
    } catch (e, stack) {
      debugPrint('❌ [LIVE-CHUNK] 实时转录错误: $e');
      debugPrint('❌ [LIVE-CHUNK] 堆栈: $stack');
    }
  }

  /// 停止实时转录并保存
  Future<void> stopLiveTranscriptionAndSave() async {
    debugPrint('🔍 [SAVE] 1. stopLiveTranscriptionAndSave 开始');
    if (!_recordingService.isRecording) {
      debugPrint('🔍 [SAVE] 未在录音，直接返回');
      return;
    }

    // 移除回调
    _recordingService.onAudioChunkReady = null;
    debugPrint('🔍 [SAVE] 2. 回调已移除');

    // 确认最后的实时文本
    confirmLiveText();
    debugPrint('🔍 [SAVE] 3. 实时文本已确认');

    // 让 UI 有机会更新
    await Future.delayed(Duration.zero);
    debugPrint('🔍 [SAVE] 4. 准备停止录音');

    // 停止录音
    final audioPath = await _recordingService.stopRecording();
    debugPrint('🔍 [SAVE] 5. 录音已停止, audioPath: $audioPath');

    if (audioPath == null || _currentMeeting == null) {
      _isLiveTranscribing = false;
      notifyListeners();
      return;
    }

    _isLiveTranscribing = false;
    notifyListeners();
    debugPrint('🔍 [SAVE] 6. 状态已更新');

    // 让 UI 有机会更新
    await Future.delayed(Duration.zero);

    // 如果有实时转录结果，直接使用
    final liveTranscription = getFullLiveTranscription();
    debugPrint('🔍 [SAVE] 7. 实时转录长度: ${liveTranscription.length}');
    if (liveTranscription.isNotEmpty) {
      debugPrint('🔍 [SAVE] 8. 开始后处理');
      // 后处理完整的转录
      final processed = _postProcessor.process(
        liveTranscription,
        config: PostProcessorConfig.meetingConfig,
      );
      debugPrint('🔍 [SAVE] 9. 后处理完成');

      // 让 UI 有机会更新
      await Future.delayed(Duration.zero);

      // 保存转录
      final transcripts = processed.text.split('\n').where((t) => t.trim().isNotEmpty).map((text) {
        return Transcript(text: text.trim(), duration: Duration.zero);
      }).toList();
      debugPrint('🔍 [SAVE] 10. 准备保存到数据库, transcripts: ${transcripts.length}');

      await _db.insertTranscripts(transcripts, _currentMeeting!.id);
      debugPrint('🔍 [SAVE] 11. 数据库保存完成');

      // 更新会议
      final updatedMeeting = _currentMeeting!.copyWith(
        duration: _recordingService.recordingDuration,
        audioFilePath: audioPath,
        usedModelSize: _whisperService.currentModel.code,
        transcripts: transcripts,
      );
      await updateMeeting(updatedMeeting);
      debugPrint('🔍 [SAVE] 12. 会议更新完成');
    } else {
      debugPrint('🔍 [SAVE] 8. 无实时转录结果，准备重新转录');
      // 没有实时转录结果，重新转录整个文件
      await stopRecordingAndTranscribe();
      debugPrint('🔍 [SAVE] 9. 重新转录完成');
    }

    // 清空缓冲区
    _recordingService.clearAudioBuffer();
    debugPrint('🔍 [SAVE] 13. stopLiveTranscriptionAndSave 完成');
  }

  /// 添加待办事项
  Future<void> addTodoItem(String meetingId, String text) async {
    final todo = TodoItem(text: text);
    await _db.insertTodoItem(todo, meetingId);

    // 更新当前会议
    if (_currentMeeting?.id == meetingId) {
      final updatedTodos = [..._currentMeeting!.todoItems, todo];
      _currentMeeting = _currentMeeting!.copyWith(todoItems: updatedTodos);
      notifyListeners();
    }
  }

  /// 切换待办事项状态
  Future<void> toggleTodoItem(String meetingId, String todoId) async {
    if (_currentMeeting == null) return;

    final index = _currentMeeting!.todoItems.indexWhere((t) => t.id == todoId);
    if (index == -1) return;

    final todo = _currentMeeting!.todoItems[index];
    final updatedTodo = todo.copyWith(isCompleted: !todo.isCompleted);

    await _db.updateTodoItem(updatedTodo, meetingId);

    final updatedTodos = List<TodoItem>.from(_currentMeeting!.todoItems);
    updatedTodos[index] = updatedTodo;
    _currentMeeting = _currentMeeting!.copyWith(todoItems: updatedTodos);
    notifyListeners();
  }

  /// 更新实时文本
  void updateLiveText(String text) {
    _liveText = text;
    notifyListeners();
  }

  /// 确认实时文本
  void confirmLiveText() {
    if (_liveText.isNotEmpty) {
      if (_confirmedText.isNotEmpty) {
        _confirmedText += '\n';
      }
      _confirmedText += _liveText;
      _liveText = '';
      notifyListeners();
    }
  }

  /// 清除实时转录
  void clearLiveTranscription() {
    _liveText = '';
    _confirmedText = '';
    notifyListeners();
  }

  /// 获取完整的实时转录文本
  String getFullLiveTranscription() {
    if (_confirmedText.isEmpty && _liveText.isEmpty) return '';
    if (_confirmedText.isEmpty) return _liveText;
    if (_liveText.isEmpty) return _confirmedText;
    return '$_confirmedText\n$_liveText';
  }

  // ============ LLM 相关方法 ============

  /// 生成会议总结
  Future<String?> generateMeetingSummary(String meetingId) async {
    final meeting = _meetings.firstWhere((m) => m.id == meetingId);
    if (meeting.transcripts.isEmpty) {
      print('❌ 会议没有转录内容');
      return null;
    }

    // 加载 LLM 模型（如果未加载）
    if (!_llamaService.isModelLoaded) {
      final loaded = await _llamaService.loadModel(LLMModelConfig.tinyLlama);
      if (!loaded) {
        print('❌ 无法加载 LLM 模型');
        return null;
      }
    }

    // 生成总结
    final transcript = meeting.fullTranscript;
    final summary = await _llamaService.generateSummary(transcript);

    if (summary != null) {
      // 更新会议
      final updatedMeeting = meeting.copyWith(summary: summary);
      await updateMeeting(updatedMeeting);

      // 更新当前会议
      if (_currentMeeting?.id == meetingId) {
        _currentMeeting = updatedMeeting;
        notifyListeners();
      }
    }

    return summary;
  }

  /// 从会议提取待办事项
  Future<List<TodoItem>> extractTodosFromMeeting(String meetingId) async {
    final meeting = _meetings.firstWhere((m) => m.id == meetingId);
    if (meeting.transcripts.isEmpty) {
      print('❌ 会议没有转录内容');
      return [];
    }

    // 加载 LLM 模型（如果未加载）
    if (!_llamaService.isModelLoaded) {
      final loaded = await _llamaService.loadModel(LLMModelConfig.tinyLlama);
      if (!loaded) {
        print('❌ 无法加载 LLM 模型');
        return [];
      }
    }

    // 提取待办
    final transcript = meeting.fullTranscript;
    final todoTexts = await _llamaService.extractTodos(transcript);

    if (todoTexts.isEmpty) {
      return [];
    }

    // 创建 TodoItem 并保存
    final newTodos = <TodoItem>[];
    for (final text in todoTexts) {
      final todo = TodoItem(text: text);
      await _db.insertTodoItem(todo, meetingId);
      newTodos.add(todo);
    }

    // 更新当前会议
    if (_currentMeeting?.id == meetingId) {
      final updatedTodos = [..._currentMeeting!.todoItems, ...newTodos];
      _currentMeeting = _currentMeeting!.copyWith(todoItems: updatedTodos);
      notifyListeners();
    }

    return newTodos;
  }

  /// 一键生成总结和待办
  Future<void> processMeetingWithLLM(String meetingId) async {
    // 先生成总结
    await generateMeetingSummary(meetingId);

    // 再提取待办
    await extractTodosFromMeeting(meetingId);
  }

  /// 检查 LLM 是否可用
  bool get isLLMAvailable => _llamaService.isAvailable;

  /// 检查 LLM 是否正在处理
  bool get isLLMProcessing => _llamaService.isProcessing;

  @override
  void dispose() {
    _whisperService.dispose();
    _recordingService.dispose();
    _llamaService.dispose();
    super.dispose();
  }
}
