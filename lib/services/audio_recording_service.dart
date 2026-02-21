import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:path/path.dart' as p;

// Note: dart:typed_data is kept as Uint8List is used in this file

/// 音频输入设备信息
class AudioInputDevice {
  final String id;
  final String label;

  AudioInputDevice({
    required this.id,
    required this.label,
  });

  @override
  String toString() => label;
}

/// 音频录制服务
class AudioRecordingService extends ChangeNotifier {
  final AudioRecorder _recorder = AudioRecorder();

  bool _isRecording = false;
  bool _isPaused = false;
  String? _currentRecordingPath;
  DateTime? _recordingStartTime;
  Duration _recordingDuration = Duration.zero;
  Timer? _durationTimer;

  // 音频电平
  double _audioLevel = 0.0;
  Timer? _levelTimer;
  StreamSubscription<RecordState>? _stateSubscription;

  // 流式音频数据
  final StreamController<Float32List> _audioStreamController = StreamController<Float32List>.broadcast();
  Stream<Float32List> get audioStream => _audioStreamController.stream;

  // 实时转录用的音频缓冲
  final List<Float32List> _audioBuffer = [];
  static const int _sampleRate = 16000;
  static const int _chunkDurationSeconds = 3; // 每3秒处理一次
  static const int _samplesPerChunk = _sampleRate * _chunkDurationSeconds;

  // PCM 数据缓冲（用于保存录音文件）
  List<int> _pcmBuffer = [];

  // 文件写入流（边录边写）
  IOSink? _fileSink;
  int _totalBytesWritten = 0;

  // 实时转录回调
  void Function(Float32List samples)? onAudioChunkReady;

  // 流订阅
  StreamSubscription<Uint8List>? _streamSubscription;

  // 音频输入设备
  List<AudioInputDevice> _inputDevices = [];
  AudioInputDevice? _selectedDevice;

  // Getters
  bool get isRecording => _isRecording;
  bool get isPaused => _isPaused;
  String? get currentRecordingPath => _currentRecordingPath;
  Duration get recordingDuration => _recordingDuration;
  double get audioLevel => _audioLevel;
  List<AudioInputDevice> get inputDevices => _inputDevices;
  AudioInputDevice? get selectedDevice => _selectedDevice;

  /// 获取可用的音频输入设备列表
  Future<List<AudioInputDevice>> getInputDevices() async {
    try {
      final devices = await _recorder.listInputDevices();
      _inputDevices = devices.map((device) {
        return AudioInputDevice(
          id: device.id,
          label: device.label.isNotEmpty ? device.label : 'Unknown Device',
        );
      }).toList();

      // 如果没有选中设备，选择第一个设备
      if (_selectedDevice == null && _inputDevices.isNotEmpty) {
        _selectedDevice = _inputDevices.first;
      }

      notifyListeners();
      return _inputDevices;
    } catch (e) {
      print('❌ 获取输入设备列表失败: $e');
      return [];
    }
  }

  /// 选择音频输入设备
  void selectDevice(AudioInputDevice device) {
    _selectedDevice = device;
    notifyListeners();
  }

  /// 检查并请求麦克风权限
  Future<bool> requestPermission() async {
    try {
      // 使用 record 包的权限检查，在 macOS 上更可靠
      final hasPermission = await _recorder.hasPermission();
      return hasPermission;
    } catch (e) {
      print('权限检查错误: $e');
      // 在 macOS 上，如果 entitlements 配置正确，直接返回 true
      if (Platform.isMacOS) {
        return true;
      }
      return false;
    }
  }

  /// 检查是否有麦克风权限
  Future<bool> hasPermission() async {
    try {
      return await _recorder.hasPermission();
    } catch (e) {
      // 在 macOS 上，如果 entitlements 配置正确，直接返回 true
      if (Platform.isMacOS) {
        return true;
      }
      return false;
    }
  }

  /// 开始录音（支持实时转录）
  Future<bool> startRecording({String? outputPath}) async {
    if (_isRecording) {
      print('⚠️ 已经在录音中');
      return false;
    }

    // 检查权限
    if (!await requestPermission()) {
      print('❌ 麦克风权限被拒绝');
      return false;
    }

    try {
      // 确定输出路径
      if (outputPath == null) {
        final appDir = await getApplicationDocumentsDirectory();
        final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
        outputPath = p.join(appDir.path, 'recordings', 'recording_$timestamp.wav');
        await Directory(p.dirname(outputPath)).create(recursive: true);
      }

      _currentRecordingPath = outputPath;
      _pcmBuffer.clear();
      _audioBuffer.clear();
      _totalBytesWritten = 0;

      // 创建文件并写入 WAV 头部（预留44字节）
      final file = File(outputPath);
      _fileSink = file.openWrite();
      await _writeWavHeader(_fileSink!, 0); // 先写入占位头部

      // 配置录音参数，支持选择设备
      InputDevice? deviceConfig;
      if (_selectedDevice != null && _selectedDevice!.id.isNotEmpty) {
        deviceConfig = InputDevice(id: _selectedDevice!.id, label: _selectedDevice!.label);
      }

      final config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: 1,
        device: deviceConfig,
      );

      print('🎤 录音设备: ${_selectedDevice?.label ?? "默认设备"}');

      // 使用流式录音以支持实时转录
      final stream = await _recorder.startStream(config);

      // 订阅音频流
      _streamSubscription = stream.listen(
        (data) {
          _handleAudioData(data);
        },
        onError: (error) {
          print('❌ 音频流错误: $error');
        },
      );

      _isRecording = true;
      _isPaused = false;
      _recordingStartTime = DateTime.now();
      _recordingDuration = Duration.zero;

      // 启动计时器
      _startDurationTimer();
      _startAudioLevelMonitor();

      print('✓ 开始录音（流式）');
      notifyListeners();
      return true;
    } catch (e) {
      print('❌ 开始录音失败: $e');
      // 确保错误时重置状态
      _isRecording = false;
      _isPaused = false;
      _streamSubscription?.cancel();
      _streamSubscription = null;
      await _fileSink?.close();
      _fileSink = null;
      notifyListeners();
      return false;
    }
  }

  /// 写入 WAV 文件头
  Future<void> _writeWavHeader(IOSink sink, int dataSize) async {
    final header = Uint8List(44);
    final headerData = ByteData.sublistView(header);

    // RIFF header
    header.setRange(0, 4, 'RIFF'.codeUnits);
    headerData.setUint32(4, 36 + dataSize, Endian.little);
    header.setRange(8, 12, 'WAVE'.codeUnits);

    // fmt chunk
    header.setRange(12, 16, 'fmt '.codeUnits);
    headerData.setUint32(16, 16, Endian.little);
    headerData.setUint16(20, 1, Endian.little);
    headerData.setUint16(22, 1, Endian.little);
    headerData.setUint32(24, _sampleRate, Endian.little);
    headerData.setUint32(28, _sampleRate * 2, Endian.little);
    headerData.setUint16(32, 2, Endian.little);
    headerData.setUint16(34, 16, Endian.little);

    // data chunk
    header.setRange(36, 40, 'data'.codeUnits);
    headerData.setUint32(40, dataSize, Endian.little);

    sink.add(header);
  }

  /// 处理音频数据
  void _handleAudioData(Uint8List data) {
    // 实时写入文件（避免内存缓冲过大）
    if (_fileSink != null) {
      _fileSink!.add(data);
      _totalBytesWritten += data.length;
    }

    // 同时保存到内存缓冲（用于实时转录）
    _pcmBuffer.addAll(data);

    // 转换为 Float32 用于实时转录
    final samples = _convertPcm16ToFloat32(data);

    // 发送到流
    _audioStreamController.add(samples);

    // 添加到缓冲区并检查是否需要处理
    _audioBuffer.add(samples);

    int totalSamples = _audioBuffer.fold(0, (sum, chunk) => sum + chunk.length);
    if (totalSamples >= _samplesPerChunk && onAudioChunkReady != null) {
      // 合并缓冲区中的所有数据
      final combinedSamples = Float32List(totalSamples);
      int offset = 0;
      for (final chunk in _audioBuffer) {
        combinedSamples.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
      }

      // 清空缓冲区
      _audioBuffer.clear();

      // 回调处理
      onAudioChunkReady!(combinedSamples);
    }

    // 更新音频电平
    _updateAudioLevelFromSamples(samples);
  }

  /// 将 16-bit PCM 转换为 Float32
  Float32List _convertPcm16ToFloat32(Uint8List data) {
    final sampleCount = data.length ~/ 2;
    final samples = Float32List(sampleCount);

    for (int i = 0; i < sampleCount; i++) {
      final int16 = data[i * 2] | (data[i * 2 + 1] << 8);
      // 处理有符号整数
      final signed = int16 > 32767 ? int16 - 65536 : int16;
      samples[i] = signed / 32768.0;
    }

    return samples;
  }

  /// 从音频样本更新电平
  void _updateAudioLevelFromSamples(Float32List samples) {
    if (samples.isEmpty) return;

    double maxAbs = 0;
    for (final sample in samples) {
      final abs = sample.abs();
      if (abs > maxAbs) maxAbs = abs;
    }

    _audioLevel = maxAbs.clamp(0.0, 1.0);
  }

  /// 暂停录音
  Future<bool> pauseRecording() async {
    if (!_isRecording || _isPaused) return false;

    try {
      await _recorder.pause();
      _isPaused = true;
      _stopDurationTimer();
      print('⏸ 录音已暂停');
      notifyListeners();
      return true;
    } catch (e) {
      print('❌ 暂停录音失败: $e');
      return false;
    }
  }

  /// 继续录音
  Future<bool> resumeRecording() async {
    if (!_isRecording || !_isPaused) return false;

    try {
      await _recorder.resume();
      _isPaused = false;
      _startDurationTimer();
      print('▶ 录音已继续');
      notifyListeners();
      return true;
    } catch (e) {
      print('❌ 继续录音失败: $e');
      return false;
    }
  }

  /// 停止录音
  Future<String?> stopRecording() async {
    debugPrint('🔍 [AUDIO] 1. stopRecording 开始');
    if (!_isRecording) return null;

    try {
      // 停止流订阅
      debugPrint('🔍 [AUDIO] 2. 停止流订阅');
      await _streamSubscription?.cancel();
      _streamSubscription = null;
      debugPrint('🔍 [AUDIO] 3. 流订阅已停止');

      // 停止录音器
      debugPrint('🔍 [AUDIO] 4. 停止录音器');
      await _recorder.stop();
      debugPrint('🔍 [AUDIO] 5. 录音器已停止');

      _isRecording = false;
      _isPaused = false;

      _stopDurationTimer();
      _stopAudioLevelMonitor();
      debugPrint('🔍 [AUDIO] 6. 计时器已停止');

      // 关闭文件流并更新 WAV 头部
      if (_fileSink != null) {
        debugPrint('🔍 [AUDIO] 7. 关闭文件流, 已写入: $_totalBytesWritten bytes');
        await _fileSink!.close();
        _fileSink = null;
        debugPrint('🔍 [AUDIO] 8. 文件流已关闭');

        // 更新 WAV 头部中的文件大小
        if (_currentRecordingPath != null) {
          debugPrint('🔍 [AUDIO] 9. 更新 WAV 头部');
          await _updateWavHeader(_currentRecordingPath!, _totalBytesWritten);
          debugPrint('🔍 [AUDIO] 10. WAV 头部已更新');
          print('⏹ 录音已停止: $_currentRecordingPath');
          print('   时长: ${_recordingDuration.inMinutes}:${(_recordingDuration.inSeconds % 60).toString().padLeft(2, '0')}');
          print('   文件大小: ${(_totalBytesWritten / 1024 / 1024).toStringAsFixed(2)} MB');
        }
      }

      // 清空缓冲区
      _pcmBuffer.clear();
      _audioBuffer.clear();
      _totalBytesWritten = 0;
      debugPrint('🔍 [AUDIO] 11. 缓冲区已清空');

      notifyListeners();
      debugPrint('🔍 [AUDIO] 12. stopRecording 完成');
      return _currentRecordingPath;
    } catch (e, stack) {
      print('❌ 停止录音失败: $e');
      debugPrint('❌ 堆栈: $stack');
      _isRecording = false;
      _isPaused = false;
      _pcmBuffer.clear();
      _audioBuffer.clear();
      await _fileSink?.close();
      _fileSink = null;
      notifyListeners();
      return null;
    }
  }

  /// 更新 WAV 文件头部的大小信息
  Future<void> _updateWavHeader(String path, int dataSize) async {
    debugPrint('🔍 [WAV] 开始更新 WAV 头部: $path, dataSize: $dataSize');
    try {
      final file = File(path);

      // 先检查文件是否存在
      if (!await file.exists()) {
        debugPrint('❌ [WAV] 文件不存在: $path');
        return;
      }

      final fileSize = await file.length();
      debugPrint('🔍 [WAV] 当前文件大小: $fileSize bytes');

      // 读取整个文件
      final bytes = await file.readAsBytes();
      debugPrint('🔍 [WAV] 文件已读取到内存');

      // 创建 ByteData 视图来修改
      final byteData = ByteData.sublistView(bytes);

      // 更新 RIFF chunk 大小 (位置 4)
      byteData.setUint32(4, 36 + dataSize, Endian.little);
      debugPrint('🔍 [WAV] RIFF 大小已更新: ${36 + dataSize}');

      // 更新 data chunk 大小 (位置 40)
      byteData.setUint32(40, dataSize, Endian.little);
      debugPrint('🔍 [WAV] Data 大小已更新: $dataSize');

      // 写回文件
      await file.writeAsBytes(bytes);
      debugPrint('🔍 [WAV] WAV 头部更新完成');

      // 验证文件
      final updatedSize = await file.length();
      debugPrint('🔍 [WAV] 验证文件大小: $updatedSize bytes');
    } catch (e, stack) {
      debugPrint('❌ [WAV] 更新 WAV 头部失败: $e');
      debugPrint('❌ [WAV] 堆栈: $stack');
    }
  }

  /// 取消录音
  Future<void> cancelRecording() async {
    if (!_isRecording) return;

    try {
      // 停止流订阅
      await _streamSubscription?.cancel();
      _streamSubscription = null;

      await _recorder.stop();

      // 关闭文件流
      await _fileSink?.close();
      _fileSink = null;

      // 删除录音文件
      if (_currentRecordingPath != null) {
        final file = File(_currentRecordingPath!);
        if (await file.exists()) {
          await file.delete();
        }
      }

      _isRecording = false;
      _isPaused = false;
      _currentRecordingPath = null;
      _recordingDuration = Duration.zero;
      _pcmBuffer.clear();
      _audioBuffer.clear();
      _totalBytesWritten = 0;

      _stopDurationTimer();
      _stopAudioLevelMonitor();

      print('✗ 录音已取消');
      notifyListeners();
    } catch (e) {
      print('❌ 取消录音失败: $e');
    }
  }

  /// 启动时长计时器
  void _startDurationTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_recordingStartTime != null) {
        _recordingDuration = DateTime.now().difference(_recordingStartTime!);
        notifyListeners();
      }
    });
  }

  /// 停止时长计时器
  void _stopDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = null;
  }

  /// 启动音频电平监控
  void _startAudioLevelMonitor() {
    // 音频电平现在从音频样本中直接计算
    // 这里只启动一个定时器来定期通知 UI 更新
    _levelTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!_isRecording || _isPaused) {
        _audioLevel = 0;
        notifyListeners();
      }
    });
  }

  /// 停止音频电平监控
  void _stopAudioLevelMonitor() {
    _levelTimer?.cancel();
    _levelTimer = null;
    _audioLevel = 0;
    notifyListeners();
  }

  /// 清空音频缓冲区
  void clearAudioBuffer() {
    _audioBuffer.clear();
    _pcmBuffer.clear();
  }

  /// 获取录音时长
  Duration getRecordingDuration() {
    return _recordingDuration;
  }

  /// 格式化时长显示
  String get formattedDuration {
    final minutes = _recordingDuration.inMinutes;
    final seconds = _recordingDuration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  /// 清理资源
  @override
  void dispose() {
    _stopDurationTimer();
    _stopAudioLevelMonitor();
    _stateSubscription?.cancel();
    _streamSubscription?.cancel();
    _recorder.dispose();
    _audioStreamController.close();
    super.dispose();
  }
}

/// 音频文件工具
class AudioFileUtils {
  /// 获取音频文件信息
  static Future<AudioFileInfo?> getAudioInfo(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;

      final stat = await file.stat();
      final size = stat.size;

      return AudioFileInfo(
        path: path,
        fileSize: size,
      );
    } catch (e) {
      return null;
    }
  }

  /// 删除音频文件
  static Future<bool> deleteAudioFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
}

/// 音频文件信息
class AudioFileInfo {
  final String path;
  final int fileSize;

  AudioFileInfo({
    required this.path,
    required this.fileSize,
  });

  String get fileSizeFormatted {
    if (fileSize < 1024) {
      return '$fileSize B';
    } else if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }
}
