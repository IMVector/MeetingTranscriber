import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/models.dart';
import 'recording_screen.dart';
import 'meeting_detail_screen.dart';

/// 主页面 - 会议列表
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('会议转录'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.pushNamed(context, '/settings');
            },
          ),
        ],
      ),
      body: Consumer<AppState>(
        builder: (context, state, child) {
          if (!state.isInitialized) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (state.meetings.isEmpty) {
            return _buildEmptyState(context);
          }

          return _buildMeetingList(context, state);
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          _showNewMeetingDialog(context);
        },
        icon: const Icon(Icons.mic),
        label: const Text('新建会议'),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.mic_none,
            size: 80,
            color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
          ),
          const SizedBox(height: 24),
          Text(
            '暂无会议记录',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            '点击下方按钮开始录制新会议',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildMeetingList(BuildContext context, AppState state) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: state.meetings.length,
      itemBuilder: (context, index) {
        final meeting = state.meetings[index];
        return _MeetingCard(
          meeting: meeting,
          onTap: () {
            state.selectMeeting(meeting);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const MeetingDetailScreen(),
              ),
            );
          },
          onDelete: () {
            _showDeleteConfirmDialog(context, state, meeting);
          },
        );
      },
    );
  }

  void _showNewMeetingDialog(BuildContext context) {
    final controller = TextEditingController(text: '新会议');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建会议'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '会议标题',
            hintText: '请输入会议标题',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => RecordingScreen(
                    title: controller.text,
                  ),
                ),
              );
            },
            child: const Text('开始'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmDialog(BuildContext context, AppState state, Meeting meeting) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除会议'),
        content: Text('确定要删除 "${meeting.title}" 吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              state.deleteMeeting(meeting.id);
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

/// 会议卡片
class _MeetingCard extends StatelessWidget {
  final Meeting meeting;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _MeetingCard({
    required this.meeting,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(meeting.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: Theme.of(context).colorScheme.error,
        child: const Icon(
          Icons.delete,
          color: Colors.white,
        ),
      ),
      onDismissed: (_) => onDelete(),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: ListTile(
          onTap: onTap,
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Icon(
              Icons.event_note,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
          title: Text(
            meeting.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    meeting.formattedDate,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    Icons.timer_outlined,
                    size: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    meeting.formattedDuration,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              if (meeting.transcripts.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  meeting.fullTranscript,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ],
          ),
          trailing: meeting.usedModelSize != null
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    meeting.usedModelSize!.toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
