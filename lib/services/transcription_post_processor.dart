import 'whisper_service.dart' show TranscriptSegment;

/// 转录后处理配置
class PostProcessorConfig {
  final bool removeFillerWords;
  final bool fixPunctuation;
  final bool breakOnSpeakerChange;
  final bool breakOnConversationTurn;
  final bool addSpeakerLabels;
  final bool breakOnSentence;
  final Duration conversationTurnGap;

  const PostProcessorConfig({
    this.removeFillerWords = true,
    this.fixPunctuation = true,
    this.breakOnSpeakerChange = true,
    this.breakOnConversationTurn = true,
    this.addSpeakerLabels = true,
    this.breakOnSentence = true,
    this.conversationTurnGap = const Duration(seconds: 2),
  });

  static const defaultConfig = PostProcessorConfig();
  static const meetingConfig = PostProcessorConfig(
    removeFillerWords: true,
    fixPunctuation: true,
    breakOnSpeakerChange: true,
    breakOnConversationTurn: true,
    addSpeakerLabels: true,
    breakOnSentence: true,
    conversationTurnGap: Duration(seconds: 1, milliseconds: 500),
  );
}

/// 转录后处理器
class TranscriptionPostProcessor {
  // 填充词列表
  static const _fillerWords = [
    // 中文
    '嗯', '啊', '呃', '额', '这个', '那个', '就是', '然后',
    '其实', '对吧', '是吧', '对对对', '好的好的',
    // 英文
    'um', 'uh', 'er', 'ah', 'like', 'you know', 'so',
    'basically', 'actually',
  ];

  // 对话转折词
  static const _conversationMarkers = [
    '首先', '其次', '然后', '接下来', '最后', '总之',
    '第一', '第二', '第三', '另外', '此外',
    '关于', '对于', '至于',
  ];

  /// 处理转录文本
  ProcessedTranscription process(
    String text, {
    List<TranscriptSegment>? segments,
    PostProcessorConfig config = PostProcessorConfig.defaultConfig,
  }) {
    var processedText = text;
    var processedSegments = segments ?? <TranscriptSegment>[];

    // 1. 移除填充词
    if (config.removeFillerWords) {
      processedText = _removeFillerWords(processedText);
    }

    // 2. 修复标点
    if (config.fixPunctuation) {
      processedText = _fixPunctuation(processedText);
    }

    // 3. 清理空白
    processedText = _cleanWhitespace(processedText);

    // 4. 对话分段（说话人变化、时间间隔）
    if (config.breakOnConversationTurn || config.breakOnSpeakerChange) {
      processedText = _addConversationBreaks(
        processedText,
        segments: processedSegments,
        config: config,
      );
    }

    // 5. 句子分段
    if (config.breakOnSentence) {
      processedText = _breakBySentences(processedText);
    }

    // 6. 智能分段
    processedText = _smartParagraphBreak(processedText);

    return ProcessedTranscription(
      text: processedText,
      segments: processedSegments,
    );
  }

  /// 移除填充词
  String _removeFillerWords(String text) {
    var result = text;
    for (final filler in _fillerWords) {
      // 匹配独立的填充词
      final pattern = RegExp(
        r'(^|\s|[,，。！？])\s*' + RegExp.escape(filler) + r'\s*(?=$|\s|[,，。！？])',
        caseSensitive: false,
      );
      result = result.replaceAll(pattern, '');
    }
    return result;
  }

  /// 修复标点
  String _fixPunctuation(String text) {
    var result = text;

    // 修复重复标点
    result = result.replaceAll(RegExp(r'。+'), '。');
    result = result.replaceAll(RegExp(r'，+'), '，');
    result = result.replaceAll(RegExp(r'！+'), '！');
    result = result.replaceAll(RegExp(r'？+'), '？');
    result = result.replaceAll(RegExp(r'\.\.\.+' ), '...');

    // 移除标点前的空格
    result = result.replaceAll(RegExp(r'\s+([，。！？、；：])'), r'$1');

    // 移除标点后的多余空格
    result = result.replaceAll(RegExp(r'([，。！？、；：])\s+'), r'$1');

    return result;
  }

  /// 清理空白
  String _cleanWhitespace(String text) {
    var result = text;

    // 多个空格变为一个
    result = result.replaceAll(RegExp(r' {2,}'), ' ');

    // 多个换行变为两个
    result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return result.trim();
  }

  /// 添加对话分段
  String _addConversationBreaks(
    String text, {
    List<TranscriptSegment>? segments,
    required PostProcessorConfig config,
  }) {
    // 如果有片段信息，使用片段进行分段
    if (segments != null && segments.isNotEmpty) {
      return _breakBySegments(segments, config);
    }

    // 否则使用文本分析进行分段
    return _breakByText(text, config);
  }

  /// 基于片段分段
  String _breakBySegments(List<TranscriptSegment> segments, PostProcessorConfig config) {
    final buffer = StringBuffer();
    int? lastSpeakerId;
    double? lastEndTime;

    for (int i = 0; i < segments.length; i++) {
      final segment = segments[i];
      bool needsBreak = false;
      bool isSpeakerChange = false;

      // 说话人变化
      if (config.breakOnSpeakerChange && segment.speakerId != null && segment.speakerId != lastSpeakerId) {
        needsBreak = true;
        isSpeakerChange = true;
      }

      // 时间间隔（对话轮次）
      if (config.breakOnConversationTurn && lastEndTime != null) {
        final gap = segment.startTime - lastEndTime;
        if (gap >= config.conversationTurnGap.inSeconds) {
          needsBreak = true;
        }
      }

      if (needsBreak && buffer.isNotEmpty) {
        buffer.write('\n');
      }

      // 添加说话人标签
      if (isSpeakerChange && config.addSpeakerLabels && segment.speakerId != null) {
        buffer.write('【说话人${segment.speakerId}】');
      }

      buffer.write(segment.text);

      lastSpeakerId = segment.speakerId;
      lastEndTime = segment.endTime;
    }

    return buffer.toString();
  }

  /// 基于文本分段
  String _breakByText(String text, PostProcessorConfig config) {
    var result = text;

    // 在对话转折词前添加换行
    for (final marker in _conversationMarkers) {
      result = result.replaceAll(
        '。$marker',
        '。\n$marker',
      );
    }

    return result;
  }

  /// 句子分段 - 在句子结束后换行
  String _breakBySentences(String text) {
    var result = text;

    // 中文句子结束标点后换行（避免已有换行的重复）
    // 匹配：句子结束标点 + 非换行字符
    result = result.replaceAllMapped(
      RegExp(r'([。！？])([^\n」』】\s])'),
      (match) => '${match.group(1)}\n${match.group(2)}',
    );

    // 英文句子结束标点后换行（需要后面有空格或大写字母）
    // 匹配：. ! ? 后跟空格和大写字母
    result = result.replaceAllMapped(
      RegExp(r'([.!?])\s+([A-Z])'),
      (match) => '${match.group(1)}\n${match.group(2)}',
    );

    // 处理引号后的换行（中文引号）
    result = result.replaceAllMapped(
      RegExp(r'([。！？])」([^\n])'),
      (match) => '${match.group(1)}」\n${match.group(2)}',
    );

    return result;
  }

  /// 智能分段
  String _smartParagraphBreak(String text) {
    var result = text;

    // 在长文本中寻找分段点
    for (final marker in _conversationMarkers) {
      result = result.replaceAll(
        '。$marker',
        '。\n\n$marker',
      );
    }

    return result;
  }
}

/// 处理后的转录结果
class ProcessedTranscription {
  final String text;
  final List<TranscriptSegment> segments;

  const ProcessedTranscription({
    required this.text,
    required this.segments,
  });

  int get wordCount {
    return text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
  }

  int get characterCount {
    return text.length;
  }
}
