import 'package:uuid/uuid.dart';

/// 会议记录模型
class Meeting {
  final String id;
  final String title;
  final DateTime createdAt;
  final Duration duration;
  final String? summary;
  final String? audioFilePath;
  final String? usedModelSize;
  final List<Transcript> transcripts;
  final List<TodoItem> todoItems;
  final List<Speaker> speakers;

  Meeting({
    String? id,
    required this.title,
    DateTime? createdAt,
    this.duration = Duration.zero,
    this.summary,
    this.audioFilePath,
    this.usedModelSize,
    List<Transcript>? transcripts,
    List<TodoItem>? todoItems,
    List<Speaker>? speakers,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        transcripts = transcripts ?? [],
        todoItems = todoItems ?? [],
        speakers = speakers ?? [];

  String get formattedDate {
    return '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')} '
        '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';
  }

  String get formattedDuration {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String get fullTranscript {
    return transcripts.map((t) => t.text).join('\n');
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'durationSeconds': duration.inSeconds,
      'summary': summary,
      'audioFilePath': audioFilePath,
      'usedModelSize': usedModelSize,
    };
  }

  factory Meeting.fromMap(Map<String, dynamic> map, {
    List<Transcript> transcripts = const [],
    List<TodoItem> todoItems = const [],
    List<Speaker> speakers = const [],
  }) {
    return Meeting(
      id: map['id'],
      title: map['title'],
      createdAt: DateTime.parse(map['createdAt']),
      duration: Duration(seconds: map['durationSeconds'] ?? 0),
      summary: map['summary'],
      audioFilePath: map['audioFilePath'],
      usedModelSize: map['usedModelSize'],
      transcripts: transcripts,
      todoItems: todoItems,
      speakers: speakers,
    );
  }

  Meeting copyWith({
    String? title,
    Duration? duration,
    String? summary,
    String? audioFilePath,
    String? usedModelSize,
    List<Transcript>? transcripts,
    List<TodoItem>? todoItems,
    List<Speaker>? speakers,
  }) {
    return Meeting(
      id: id,
      title: title ?? this.title,
      createdAt: createdAt,
      duration: duration ?? this.duration,
      summary: summary ?? this.summary,
      audioFilePath: audioFilePath ?? this.audioFilePath,
      usedModelSize: usedModelSize ?? this.usedModelSize,
      transcripts: transcripts ?? this.transcripts,
      todoItems: todoItems ?? this.todoItems,
      speakers: speakers ?? this.speakers,
    );
  }
}

/// 转录片段模型
class Transcript {
  final String id;
  final String text;
  final DateTime timestamp;
  final Duration duration;
  final bool isFinal;
  final int? speakerId;
  final double? confidence;

  Transcript({
    String? id,
    required this.text,
    DateTime? timestamp,
    this.duration = Duration.zero,
    this.isFinal = true,
    this.speakerId,
    this.confidence,
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now();

  String get formattedTimestamp {
    return '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toMap({required String meetingId}) {
    return {
      'id': id,
      'meetingId': meetingId,
      'text': text,
      'timestamp': timestamp.toIso8601String(),
      'durationSeconds': duration.inSeconds,
      'isFinal': isFinal ? 1 : 0,
      'speakerId': speakerId,
      'confidence': confidence,
    };
  }

  factory Transcript.fromMap(Map<String, dynamic> map) {
    return Transcript(
      id: map['id'],
      text: map['text'],
      timestamp: DateTime.parse(map['timestamp']),
      duration: Duration(seconds: map['durationSeconds'] ?? 0),
      isFinal: map['isFinal'] == 1,
      speakerId: map['speakerId'],
      confidence: map['confidence'],
    );
  }
}

/// 说话人模型
class Speaker {
  final String id;
  final String name;
  final String color;
  final int speakerIndex;

  Speaker({
    String? id,
    required this.name,
    required this.color,
    required this.speakerIndex,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toMap({required String meetingId}) {
    return {
      'id': id,
      'meetingId': meetingId,
      'name': name,
      'color': color,
      'speakerIndex': speakerIndex,
    };
  }

  factory Speaker.fromMap(Map<String, dynamic> map) {
    return Speaker(
      id: map['id'],
      name: map['name'],
      color: map['color'],
      speakerIndex: map['speakerIndex'],
    );
  }
}

/// 待办事项模型
class TodoItem {
  final String id;
  final String text;
  final bool isCompleted;
  final String? assignedTo;
  final DateTime? dueDate;
  final DateTime createdAt;

  TodoItem({
    String? id,
    required this.text,
    this.isCompleted = false,
    this.assignedTo,
    this.dueDate,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap({required String meetingId}) {
    return {
      'id': id,
      'meetingId': meetingId,
      'text': text,
      'isCompleted': isCompleted ? 1 : 0,
      'assignedTo': assignedTo,
      'dueDate': dueDate?.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory TodoItem.fromMap(Map<String, dynamic> map) {
    return TodoItem(
      id: map['id'],
      text: map['text'],
      isCompleted: map['isCompleted'] == 1,
      assignedTo: map['assignedTo'],
      dueDate: map['dueDate'] != null ? DateTime.parse(map['dueDate']) : null,
      createdAt: DateTime.parse(map['createdAt']),
    );
  }

  TodoItem copyWith({
    String? text,
    bool? isCompleted,
    String? assignedTo,
    DateTime? dueDate,
  }) {
    return TodoItem(
      id: id,
      text: text ?? this.text,
      isCompleted: isCompleted ?? this.isCompleted,
      assignedTo: assignedTo ?? this.assignedTo,
      dueDate: dueDate ?? this.dueDate,
      createdAt: createdAt,
    );
  }
}

/// Whisper 模型大小
enum WhisperModelSize {
  tiny('tiny', 'Tiny', '最快，约39MB', 39),
  base('base', 'Base', '平衡，约74MB', 74),
  small('small', 'Small', '最准确，约244MB', 244);

  final String code;
  final String displayName;
  final String description;
  final int sizeMB;

  const WhisperModelSize(this.code, this.displayName, this.description, this.sizeMB);
}

/// 转录引擎类型
enum TranscriptionEngine {
  whisperCpp('Whisper.cpp', '本地语音识别，支持多语言'),
  system('系统语音识别', '使用系统自带语音识别');

  final String displayName;
  final String description;

  const TranscriptionEngine(this.displayName, this.description);
}
