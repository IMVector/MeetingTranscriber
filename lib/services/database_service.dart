import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/models.dart';

/// 数据库服务 - 管理本地数据存储
class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'meeting_transcriber.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    // 创建会议表
    await db.execute('''
      CREATE TABLE meetings (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        durationSeconds INTEGER DEFAULT 0,
        summary TEXT,
        audioFilePath TEXT,
        usedModelSize TEXT
      )
    ''');

    // 创建转录片段表
    await db.execute('''
      CREATE TABLE transcripts (
        id TEXT PRIMARY KEY,
        meetingId TEXT NOT NULL,
        text TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        durationSeconds INTEGER DEFAULT 0,
        isFinal INTEGER DEFAULT 1,
        speakerId INTEGER,
        confidence REAL,
        FOREIGN KEY (meetingId) REFERENCES meetings (id) ON DELETE CASCADE
      )
    ''');

    // 创建说话人表
    await db.execute('''
      CREATE TABLE speakers (
        id TEXT PRIMARY KEY,
        meetingId TEXT NOT NULL,
        name TEXT NOT NULL,
        color TEXT NOT NULL,
        speakerIndex INTEGER NOT NULL,
        FOREIGN KEY (meetingId) REFERENCES meetings (id) ON DELETE CASCADE
      )
    ''');

    // 创建待办事项表
    await db.execute('''
      CREATE TABLE todo_items (
        id TEXT PRIMARY KEY,
        meetingId TEXT NOT NULL,
        text TEXT NOT NULL,
        isCompleted INTEGER DEFAULT 0,
        assignedTo TEXT,
        dueDate TEXT,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (meetingId) REFERENCES meetings (id) ON DELETE CASCADE
      )
    ''');

    // 创建索引
    await db.execute('CREATE INDEX idx_transcripts_meeting ON transcripts (meetingId)');
    await db.execute('CREATE INDEX idx_speakers_meeting ON speakers (meetingId)');
    await db.execute('CREATE INDEX idx_todos_meeting ON todo_items (meetingId)');
    await db.execute('CREATE INDEX idx_meetings_created ON meetings (createdAt DESC)');
  }

  // MARK: - Meeting Operations

  Future<String> insertMeeting(Meeting meeting) async {
    final db = await database;
    await db.insert('meetings', meeting.toMap());
    return meeting.id;
  }

  Future<List<Meeting>> getAllMeetings() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'meetings',
      orderBy: 'createdAt DESC',
    );

    final meetings = <Meeting>[];
    for (final map in maps) {
      final transcripts = await getTranscriptsForMeeting(map['id']);
      final todoItems = await getTodoItemsForMeeting(map['id']);
      final speakers = await getSpeakersForMeeting(map['id']);
      meetings.add(Meeting.fromMap(
        map,
        transcripts: transcripts,
        todoItems: todoItems,
        speakers: speakers,
      ));
    }
    return meetings;
  }

  Future<Meeting?> getMeeting(String id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'meetings',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isEmpty) return null;

    final transcripts = await getTranscriptsForMeeting(id);
    final todoItems = await getTodoItemsForMeeting(id);
    final speakers = await getSpeakersForMeeting(id);

    return Meeting.fromMap(
      maps.first,
      transcripts: transcripts,
      todoItems: todoItems,
      speakers: speakers,
    );
  }

  Future<void> updateMeeting(Meeting meeting) async {
    final db = await database;
    await db.update(
      'meetings',
      meeting.toMap(),
      where: 'id = ?',
      whereArgs: [meeting.id],
    );
  }

  Future<void> deleteMeeting(String id) async {
    final db = await database;
    await db.delete(
      'meetings',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // MARK: - Transcript Operations

  Future<void> insertTranscript(Transcript transcript, String meetingId) async {
    final db = await database;
    await db.insert('transcripts', transcript.toMap(meetingId: meetingId));
  }

  Future<void> insertTranscripts(List<Transcript> transcripts, String meetingId) async {
    final db = await database;
    final batch = db.batch();
    for (final transcript in transcripts) {
      batch.insert('transcripts', transcript.toMap(meetingId: meetingId));
    }
    await batch.commit(noResult: true);
  }

  Future<List<Transcript>> getTranscriptsForMeeting(String meetingId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'transcripts',
      where: 'meetingId = ?',
      whereArgs: [meetingId],
      orderBy: 'timestamp ASC',
    );
    return maps.map((map) => Transcript.fromMap(map)).toList();
  }

  Future<void> deleteTranscripts(String meetingId) async {
    final db = await database;
    await db.delete(
      'transcripts',
      where: 'meetingId = ?',
      whereArgs: [meetingId],
    );
  }

  // MARK: - Speaker Operations

  Future<void> insertSpeaker(Speaker speaker, String meetingId) async {
    final db = await database;
    await db.insert('speakers', speaker.toMap(meetingId: meetingId));
  }

  Future<List<Speaker>> getSpeakersForMeeting(String meetingId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'speakers',
      where: 'meetingId = ?',
      whereArgs: [meetingId],
      orderBy: 'speakerIndex ASC',
    );
    return maps.map((map) => Speaker.fromMap(map)).toList();
  }

  // MARK: - Todo Operations

  Future<void> insertTodoItem(TodoItem todoItem, String meetingId) async {
    final db = await database;
    await db.insert('todo_items', todoItem.toMap(meetingId: meetingId));
  }

  Future<List<TodoItem>> getTodoItemsForMeeting(String meetingId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'todo_items',
      where: 'meetingId = ?',
      whereArgs: [meetingId],
      orderBy: 'createdAt ASC',
    );
    return maps.map((map) => TodoItem.fromMap(map)).toList();
  }

  Future<void> updateTodoItem(TodoItem todoItem, String meetingId) async {
    final db = await database;
    await db.update(
      'todo_items',
      todoItem.toMap(meetingId: meetingId),
      where: 'id = ?',
      whereArgs: [todoItem.id],
    );
  }

  Future<void> deleteTodoItem(String id) async {
    final db = await database;
    await db.delete(
      'todo_items',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
