import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/models.dart';
import '../services/audio_recording_service.dart';

/// 录音页面
class RecordingScreen extends StatefulWidget {
  final String title;

  const RecordingScreen({
    super.key,
    required this.title,
  });

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  Timer? _durationTimer;
  Timer? _audioLevelTimer;  // 存储音频电平计时器引用
  Duration _duration = Duration.zero;
  bool _isRecording = false;
  bool _isPaused = false;
  bool _isTranscribing = false;
  String _transcriptionText = '';

  // 音频电平动画
  final List<double> _audioLevels = List.generate(30, (_) => 0.0);

  // 模型选择
  WhisperModelSize _selectedModel = WhisperModelSize.base;

  // 音频设备列表
  List<AudioInputDevice> _inputDevices = [];
  AudioInputDevice? _selectedDevice;
  bool _isLoadingDevices = false;

  @override
  void initState() {
    super.initState();
    // 使用 addPostFrameCallback 避免在 initState 中使用 context
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInputDevices();
    });
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _audioLevelTimer?.cancel();
    super.dispose();
  }

  /// 加载输入设备列表
  Future<void> _loadInputDevices() async {
    if (!mounted) return;

    setState(() {
      _isLoadingDevices = true;
    });

    try {
      final state = context.read<AppState>();
      final devices = await state.recordingService.getInputDevices();

      if (!mounted) return;

      // 去重：根据 id 去重
      final uniqueDevices = <String, AudioInputDevice>{};
      for (final device in devices) {
        uniqueDevices[device.id] = device;
      }
      final dedupedDevices = uniqueDevices.values.toList();

      setState(() {
        _inputDevices = dedupedDevices;
        // 确保 selectedDevice 在列表中存在
        final selected = state.recordingService.selectedDevice;
        if (selected != null && dedupedDevices.any((d) => d.id == selected.id)) {
          _selectedDevice = dedupedDevices.firstWhere((d) => d.id == selected.id);
        } else if (dedupedDevices.isNotEmpty) {
          _selectedDevice = dedupedDevices.first;
        } else {
          _selectedDevice = null;
        }
        _isLoadingDevices = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingDevices = false;
      });
      debugPrint('加载输入设备失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return PopScope(
      canPop: !_isRecording,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isRecording) {
          _showCancelDialog(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          automaticallyImplyLeading: !_isRecording,
          actions: [
            if (!_isRecording && _transcriptionText.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.save),
                onPressed: () => _saveAndExit(context),
              ),
          ],
        ),
        body: Column(
          children: [
            // 模型选择（录音前显示）
            if (!_isRecording) _buildModelSelector(context, state),

            // 音频设备选择（录音前显示）
            if (!_isRecording) _buildDeviceSelector(context, state),

            // 状态区域
            _buildStatusArea(context),

            // 音频电平
            if (_isRecording) _buildAudioLevelIndicator(context),

            // 转录文本区域
            Expanded(
              child: _buildTranscriptionArea(context),
            ),

            // 控制按钮
            _buildControlButtons(context, state),
          ],
        ),
      ),
    );
  }

  Widget _buildModelSelector(BuildContext context, AppState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.model_training, size: 20),
          const SizedBox(width: 12),
          const Text('转录模型：'),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<WhisperModelSize>(
              value: _selectedModel,
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              items: WhisperModelSize.values.map((model) {
                return DropdownMenuItem(
                  value: model,
                  child: Text('${model.displayName} (${model.sizeMB}MB)'),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedModel = value;
                  });
                  state.setSelectedModel(value);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceSelector(BuildContext context, AppState state) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.mic, size: 20),
              const SizedBox(width: 12),
              const Text('音频源：'),
              const SizedBox(width: 8),
              Expanded(
                child: _isLoadingDevices
                    ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                    : DropdownButtonFormField<AudioInputDevice>(
                        value: _selectedDevice != null && _inputDevices.any((d) => d.id == _selectedDevice!.id)
                            ? _selectedDevice
                            : null,
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        items: _inputDevices.map((device) {
                          return DropdownMenuItem(
                            value: device,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  device.label.toLowerCase().contains('blackhole') ||
                                          device.label.toLowerCase().contains('loopback')
                                      ? Icons.speaker
                                      : Icons.mic,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  device.label,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() {
                              _selectedDevice = value;
                            });
                            state.recordingService.selectDevice(value);
                          }
                        },
                      ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadInputDevices,
                tooltip: '刷新设备列表',
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 系统音频提示
          InkWell(
            onTap: () => _showSystemAudioHelp(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '如何录制系统音频（如腾讯会议声音）？',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSystemAudioHelp(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('录制系统音频'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('要录制电脑系统声音（如腾讯会议、Zoom 等），请按以下步骤操作：'),
              SizedBox(height: 16),
              Text(
                '方法一：安装虚拟音频驱动（推荐）',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('1. 下载安装 BlackHole（免费）：\n   https://existential.audio/blackhole/'),
              SizedBox(height: 8),
              Text('2. 安装后在"音频源"下拉框中选择 BlackHole'),
              SizedBox(height: 8),
              Text('3. 在系统设置中设置输出设备为 BlackHole'),
              SizedBox(height: 16),
              Text(
                '方法二：使用多输出设备',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('1. 打开"音频 MIDI 设置"应用程序'),
              SizedBox(height: 8),
              Text('2. 点击左下角"+"创建"多输出设备"'),
              SizedBox(height: 8),
              Text('3. 勾选扬声器和 BlackHole'),
              SizedBox(height: 8),
              Text('4. 系统输出选择该多输出设备'),
              SizedBox(height: 16),
              Text(
                '提示：',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('• 安装 BlackHole 后需要重启应用才能看到新设备'),
              Text('• 录制系统音频时无法听到声音，建议使用多输出设备'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusArea(BuildContext context) {
    String statusText;
    Color statusColor;
    IconData statusIcon;

    if (_isTranscribing) {
      statusText = '正在转录...';
      statusColor = Colors.orange;
      statusIcon = Icons.hourglass_empty;
    } else if (_isPaused) {
      statusText = '已暂停';
      statusColor = Colors.orange;
      statusIcon = Icons.pause;
    } else if (_isRecording) {
      statusText = '正在录音';
      statusColor = Colors.red;
      statusIcon = Icons.fiber_manual_record;
    } else {
      statusText = '准备就绪';
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(statusIcon, color: statusColor, size: 16),
          const SizedBox(width: 8),
          Text(
            statusText,
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (_isRecording || _duration > Duration.zero) ...[
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                _formatDuration(_duration),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
          if (_isTranscribing) ...[
            const SizedBox(width: 16),
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAudioLevelIndicator(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(30, (index) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 4,
            height: 8 + _audioLevels[index] * 40,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.7),
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildTranscriptionArea(BuildContext context) {
    final state = context.watch<AppState>();

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '转录内容',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              if (state.liveText.isNotEmpty || state.confirmedText.isNotEmpty)
                TextButton.icon(
                  onPressed: () {
                    final text = state.getFullLiveTranscription();
                    Clipboard.setData(ClipboardData(text: text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已复制到剪贴板')),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('复制'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 已确认文本
                  if (state.confirmedText.isNotEmpty)
                    Text(
                      state.confirmedText,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  // 实时文本
                  if (state.liveText.isNotEmpty)
                    Text(
                      state.liveText,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: _isRecording ? Theme.of(context).colorScheme.primary : null,
                          ),
                    ),
                  // 空状态
                  if (state.liveText.isEmpty && state.confirmedText.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Text(
                          '开始录音后，转录内容将显示在这里...',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButtons(BuildContext context, AppState state) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_isRecording) ...[
            // 暂停/继续按钮
            FloatingActionButton(
              heroTag: 'pause',
              onPressed: _isTranscribing
                  ? null
                  : () {
                      setState(() {
                        _isPaused = !_isPaused;
                      });
                      if (_isPaused) {
                        state.recordingService.pauseRecording();
                        _durationTimer?.cancel();
                      } else {
                        state.recordingService.resumeRecording();
                        _startDurationTimer();
                      }
                    },
              backgroundColor: _isPaused ? Colors.green : Colors.orange,
              child: Icon(_isPaused ? Icons.play_arrow : Icons.pause),
            ),
            const SizedBox(width: 24),
            // 停止按钮
            FloatingActionButton.large(
              heroTag: 'stop',
              onPressed: _isTranscribing ? null : _stopRecording,
              backgroundColor: Colors.red,
              child: const Icon(Icons.stop),
            ),
          ] else ...[
            // 开始按钮
            FloatingActionButton.large(
              heroTag: 'start',
              onPressed: () => _startRecording(state),
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: const Icon(Icons.mic),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _startRecording(AppState state) async {
    // 检查权限
    if (!await state.recordingService.requestPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(this.context).showSnackBar(
          const SnackBar(content: Text('需要麦克风权限才能录音')),
        );
      }
      return;
    }

    // 显示加载对话框（模型加载需要时间）
    if (mounted) {
      showDialog(
        context: this.context,
        barrierDismissible: false,
        builder: (dialogContext) => PopScope(
          canPop: false,
          child: Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 24),
                    const Text(
                      '正在准备录音...',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      state.whisperService.isModelLoaded
                          ? '正在初始化录音...'
                          : '正在加载模型，请稍候...',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    // 等待一帧让对话框渲染
    await Future.delayed(const Duration(milliseconds: 50));

    // 使用实时转录模式开始录音
    try {
      await state.startLiveTranscription(widget.title);
    } catch (e) {
      debugPrint('开始录音失败: $e');
    }

    // 关闭加载对话框
    if (mounted) {
      Navigator.of(this.context, rootNavigator: true).pop();
    }

    if (!mounted) return;

    setState(() {
      _isRecording = true;
      _isPaused = false;
    });
    _startDurationTimer();
    _startAudioLevelTimer(state);
  }

  void _startDurationTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _duration += const Duration(seconds: 1);
      });
    });
  }

  void _startAudioLevelTimer(AppState state) {
    _audioLevelTimer?.cancel(); // 确保先取消旧的计时器
    _audioLevelTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!_isRecording || _isPaused) {
        timer.cancel();
        return;
      }
      if (!mounted) return; // 检查 widget 是否仍在树中
      final level = state.recordingService.audioLevel;
      setState(() {
        _audioLevels.removeAt(0);
        _audioLevels.add(level);
      });
    });
  }

  void _stopAudioLevelTimer() {
    _audioLevelTimer?.cancel();
    _audioLevelTimer = null;
  }

  Future<void> _stopRecording() async {
    debugPrint('🔍 [STOP] 1. _stopRecording 开始');
    _durationTimer?.cancel();
    _stopAudioLevelTimer();
    debugPrint('🔍 [STOP] 2. 计时器已停止');

    final state = context.read<AppState>();

    // 先显示保存进度对话框
    debugPrint('🔍 [STOP] 3. 准备显示对话框');
    showDialog(
      context: this.context,
      barrierDismissible: false,
      builder: (dialogContext) => WillPopScope(
        onWillPop: () async => false,
        child: Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 24),
                  const Text(
                    '正在保存...',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '请稍候，正在保存录音数据',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    debugPrint('🔍 [STOP] 4. 对话框已显示');

    // 设置状态并让 UI 更新
    if (mounted) {
      setState(() {
        _isTranscribing = true;
      });
    }
    debugPrint('🔍 [STOP] 5. 状态已更新');

    // 等待对话框显示
    await Future.delayed(const Duration(milliseconds: 50));
    debugPrint('🔍 [STOP] 6. 准备调用 stopLiveTranscriptionAndSave');

    // 执行保存
    try {
      await state.stopLiveTranscriptionAndSave();
      debugPrint('🔍 [STOP] 7. stopLiveTranscriptionAndSave 完成');
    } catch (e, stack) {
      debugPrint('❌ [STOP] 保存失败: $e');
      debugPrint('❌ [STOP] 堆栈: $stack');
    }

    // 关闭进度对话框
    if (mounted) {
      Navigator.of(this.context, rootNavigator: true).pop();
      debugPrint('🔍 [STOP] 8. 对话框已关闭');
    }

    if (!mounted) return;

    setState(() {
      _isRecording = false;
      _isTranscribing = false;
      _transcriptionText = state.getFullLiveTranscription();
    });
    debugPrint('🔍 [STOP] 9. _stopRecording 完成');
  }

  void _saveAndExit(BuildContext context) {
    Navigator.pop(context, true);
  }

  void _showCancelDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('取消录音'),
        content: const Text('确定要取消当前录音吗？录音内容将不会保存。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('继续录音'),
          ),
          FilledButton(
            onPressed: () {
              context.read<AppState>().recordingService.cancelRecording();
              Navigator.pop(context);
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('取消录音'),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
