import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';
import '../providers/app_state.dart';
import '../models/models.dart';

/// 会议详情页面
class MeetingDetailScreen extends StatelessWidget {
  const MeetingDetailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final meeting = state.currentMeeting;

    if (meeting == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('会议不存在')),
      );
    }

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(meeting.title),
          bottom: const TabBar(
            tabs: [
              Tab(text: '转录'),
              Tab(text: '信息'),
              Tab(text: '总结'),
              Tab(text: '待办'),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: () => _shareMeeting(context, meeting),
            ),
          ],
        ),
        body: TabBarView(
          children: [
            _TranscriptionTab(meeting: meeting),
            _InfoTab(meeting: meeting),
            _SummaryTab(meeting: meeting),
            _TodoTab(meeting: meeting),
          ],
        ),
      ),
    );
  }

  void _shareMeeting(BuildContext context, Meeting meeting) {
    final text = '''
${meeting.title}
时间: ${meeting.formattedDate}
时长: ${meeting.formattedDuration}

转录内容:
${meeting.fullTranscript}
''';

    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制到剪贴板')),
    );
  }
}

/// 转录标签页
class _TranscriptionTab extends StatelessWidget {
  final Meeting meeting;

  const _TranscriptionTab({required this.meeting});

  @override
  Widget build(BuildContext context) {
    if (meeting.transcripts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.text_fields,
              size: 64,
              color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              '暂无转录内容',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: meeting.transcripts.length,
      itemBuilder: (context, index) {
        final transcript = meeting.transcripts[index];

        // 检测说话人标签
        String text = transcript.text;
        String? speakerLabel;

        if (text.startsWith('【说话人') && text.contains('】')) {
          final endIndex = text.indexOf('】');
          speakerLabel = text.substring(0, endIndex + 1);
          text = text.substring(endIndex + 1);
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (speakerLabel != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      speakerLabel,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                SelectableText(
                  text,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  transcript.formattedTimestamp,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 总结标签页
class _SummaryTab extends StatelessWidget {
  final Meeting meeting;

  const _SummaryTab({required this.meeting});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, child) {
        final isProcessing = state.isLLMProcessing;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 操作按钮 - 使用 Column 替代 Row + Expanded
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: meeting.transcripts.isEmpty || isProcessing
                          ? null
                          : () => _generateSummary(context, state),
                      icon: isProcessing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.auto_awesome),
                      label: Text(isProcessing ? '生成中...' : '生成总结'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: meeting.transcripts.isEmpty || isProcessing
                          ? null
                          : () => _extractTodos(context, state),
                      icon: const Icon(Icons.checklist),
                      label: const Text('提取待办'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: meeting.transcripts.isEmpty || isProcessing
                      ? null
                      : () => _processAll(context, state),
                  icon: const Icon(Icons.smart_toy),
                  label: const Text('一键生成总结和待办'),
                ),
              ),
              const SizedBox(height: 24),

              // 总结显示
              if (meeting.summary != null) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.summarize,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '会议总结',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        SelectableText(
                          meeting.summary!,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.summarize,
                            size: 48,
                            color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '暂无会议总结',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '点击上方按钮自动生成总结',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _generateSummary(BuildContext context, AppState state) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    final summary = await state.generateMeetingSummary(meeting.id);

    if (context.mounted) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(summary != null ? '总结已生成' : '生成总结失败'),
        ),
      );
    }
  }

  Future<void> _extractTodos(BuildContext context, AppState state) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    final todos = await state.extractTodosFromMeeting(meeting.id);

    if (context.mounted) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(todos.isNotEmpty ? '已提取 ${todos.length} 个待办事项' : '未检测到待办事项'),
        ),
      );
    }
  }

  Future<void> _processAll(BuildContext context, AppState state) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    await state.processMeetingWithLLM(meeting.id);

    if (context.mounted) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('总结和待办已生成')),
      );
    }
  }
}

/// 待办标签页
class _TodoTab extends StatelessWidget {
  final Meeting meeting;

  const _TodoTab({required this.meeting});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, child) {
        final todos = meeting.todoItems;

        return Column(
          children: [
            Expanded(
              child: todos.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.checklist,
                            size: 64,
                            color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '暂无待办事项',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: todos.length,
                      itemBuilder: (context, index) {
                        final todo = todos[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: Checkbox(
                              value: todo.isCompleted,
                              onChanged: (_) {
                                state.toggleTodoItem(meeting.id, todo.id);
                              },
                            ),
                            title: Text(
                              todo.text,
                              style: todo.isCompleted
                                  ? const TextStyle(decoration: TextDecoration.lineThrough)
                                  : null,
                            ),
                            subtitle: todo.assignedTo != null
                                ? Text('指派给: ${todo.assignedTo}')
                                : null,
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () {
                                // 删除待办
                              },
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton.icon(
                onPressed: () => _showAddTodoDialog(context, state, meeting.id),
                icon: const Icon(Icons.add),
                label: const Text('添加待办'),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showAddTodoDialog(BuildContext context, AppState state, String meetingId) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加待办'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '待办内容',
            hintText: '请输入待办事项',
          ),
          autofocus: true,
          maxLines: 2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                state.addTodoItem(meetingId, controller.text);
                Navigator.pop(context);
              }
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }
}

/// 信息标签页
class _InfoTab extends StatefulWidget {
  final Meeting meeting;

  const _InfoTab({required this.meeting});

  @override
  State<_InfoTab> createState() => _InfoTabState();
}

class _InfoTabState extends State<_InfoTab> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  bool _isLoading = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  @override
  void initState() {
    super.initState();
    _setupAudioPlayer();
  }

  void _setupAudioPlayer() {
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() {
        _isPlaying = state == PlayerState.playing;
        // In audioplayers 6.x, we don't have a loading state
        _isLoading = false;
      });
    });

    _audioPlayer.onDurationChanged.listen((duration) {
      if (!mounted) return;
      setState(() {
        _duration = duration;
      });
    });

    _audioPlayer.onPositionChanged.listen((position) {
      if (!mounted) return;
      setState(() {
        _position = position;
      });
    });

    _audioPlayer.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _position = Duration.zero;
      });
    });
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _playAudio() async {
    if (widget.meeting.audioFilePath == null) return;

    final file = File(widget.meeting.audioFilePath!);
    if (!await file.exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('音频文件不存在')),
        );
      }
      return;
    }

    if (_isPlaying) {
      await _audioPlayer.pause();
    } else if (_position > Duration.zero && _position < _duration) {
      await _audioPlayer.resume();
    } else {
      await _audioPlayer.play(DeviceFileSource(widget.meeting.audioFilePath!));
    }
  }

  Future<void> _stopAudio() async {
    await _audioPlayer.stop();
    setState(() {
      _position = Duration.zero;
    });
  }

  void _seekAudio(Duration position) {
    _audioPlayer.seek(position);
  }

  Future<void> _showRetranscribeDialog() async {
    final state = context.read<AppState>();
    WhisperModelSize? selectedModel = state.selectedModel;

    final result = await showDialog<WhisperModelSize>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('重新转录'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('选择转录模型：'),
              const SizedBox(height: 16),
              ...WhisperModelSize.values.map((model) => RadioListTile<WhisperModelSize>(
                title: Text('${model.displayName} (${model.sizeMB}MB)'),
                subtitle: Text(model.description),
                value: model,
                groupValue: selectedModel,
                onChanged: (value) {
                  setState(() {
                    selectedModel = value;
                  });
                },
              )),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, selectedModel),
              child: const Text('开始转录'),
            ),
          ],
        ),
      ),
    );

    if (result != null && mounted) {
      // 显示转录进度对话框
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => PopScope(
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
                    Text(
                      '正在转录...',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '请稍候，正在处理音频数据',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      final success = await state.retranscribeMeeting(widget.meeting.id, result);

      // 关闭进度对话框
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(success ? '重新转录完成' : '重新转录失败')),
        );
      }
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 音频播放器
        if (widget.meeting.audioFilePath != null) ...[
          _InfoCard(
            title: '录音文件',
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // 进度条
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 4,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      ),
                      child: Slider(
                        value: _position.inMilliseconds.toDouble(),
                        max: _duration.inMilliseconds.toDouble().clamp(0.0, double.maxFinite),
                        onChanged: (value) => _seekAudio(Duration(milliseconds: value.toInt())),
                      ),
                    ),
                    // 时间显示
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(_position),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            _formatDuration(_duration),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // 控制按钮
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.stop),
                          onPressed: _isPlaying || _position > Duration.zero ? _stopAudio : null,
                        ),
                        const SizedBox(width: 16),
                        FloatingActionButton(
                          heroTag: 'audio_play',
                          onPressed: _isLoading ? null : _playAudio,
                          child: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],

        _InfoCard(
          title: '基本信息',
          children: [
            _InfoRow(
              icon: Icons.title,
              label: '标题',
              value: widget.meeting.title,
            ),
            _InfoRow(
              icon: Icons.calendar_today,
              label: '创建时间',
              value: widget.meeting.formattedDate,
            ),
            _InfoRow(
              icon: Icons.timer,
              label: '时长',
              value: widget.meeting.formattedDuration,
            ),
            if (widget.meeting.usedModelSize != null)
              _InfoRow(
                icon: Icons.memory,
                label: '识别模型',
                value: widget.meeting.usedModelSize!.toUpperCase(),
              ),
          ],
        ),
        const SizedBox(height: 16),

        // 重新转录按钮
        if (widget.meeting.audioFilePath != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: OutlinedButton.icon(
              onPressed: _showRetranscribeDialog,
              icon: const Icon(Icons.refresh),
              label: const Text('重新转录'),
            ),
          ),

        _InfoCard(
          title: '统计',
          children: [
            _InfoRow(
              icon: Icons.text_fields,
              label: '转录段数',
              value: '${widget.meeting.transcripts.length}',
            ),
            _InfoRow(
              icon: Icons.checklist,
              label: '待办事项',
              value: '${widget.meeting.todoItems.length}',
            ),
            _InfoRow(
              icon: Icons.people,
              label: '说话人数',
              value: '${widget.meeting.speakers.length}',
            ),
          ],
        ),
        if (widget.meeting.summary != null) ...[
          const SizedBox(height: 16),
          _InfoCard(
            title: '摘要',
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  widget.meeting.summary!,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _InfoCard({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, size: 20),
      title: Text(label),
      trailing: Text(
        value,
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    );
  }
}
