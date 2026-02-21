import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../models/models.dart';

/// 设置页面
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final whisperService = state.whisperService;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        children: [
          // 模型设置
          _SectionHeader(title: 'Whisper 模型'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: WhisperModelSize.values.map((size) {
                final isLoaded = whisperService.isModelLoaded &&
                    whisperService.currentModel == size;

                return ListTile(
                  leading: isLoaded
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : const Icon(Icons.circle_outlined),
                  title: Text(size.displayName),
                  subtitle: Text(size.description),
                  trailing: isLoaded
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${size.sizeMB} MB',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onPrimaryContainer,
                              fontSize: 12,
                            ),
                          ),
                        )
                      : TextButton(
                          onPressed: whisperService.isProcessing
                              ? null
                              : () => _loadModel(context, size),
                          child: const Text('加载'),
                        ),
                  onTap: isLoaded
                      ? null
                      : () => _loadModel(context, size),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 16),

          // 模型状态
          _SectionHeader(title: '模型状态'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    whisperService.isModelLoaded
                        ? Icons.storage
                        : Icons.storage_outlined,
                  ),
                  title: const Text('模型状态'),
                  trailing: Text(
                    whisperService.isModelLoaded ? '已加载' : '未加载',
                    style: TextStyle(
                      color: whisperService.isModelLoaded ? Colors.green : Colors.orange,
                    ),
                  ),
                ),
                if (whisperService.loadingStatus.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: const Text('状态'),
                    subtitle: Text(whisperService.loadingStatus),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 关于
          _SectionHeader(title: '关于'),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('版本'),
                  trailing: const Text('1.0.0'),
                ),
                ListTile(
                  leading: const Icon(Icons.code),
                  title: const Text('语音识别引擎'),
                  subtitle: Text(
                    'Whisper.cpp\n支持 Windows, macOS, Linux',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.language),
                  title: const Text('支持语言'),
                  subtitle: Text(
                    '中文、英语、日语、韩语等 100+ 语言',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadModel(BuildContext context, WhisperModelSize size) async {
    final state = context.read<AppState>();
    final success = await state.whisperService.loadModel(size);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? '${size.displayName} 模型加载成功'
                : '模型加载失败',
          ),
        ),
      );
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}
