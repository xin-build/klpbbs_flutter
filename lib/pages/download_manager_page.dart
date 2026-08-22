import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/download_service.dart';

/// 下载任务管理中心页面（兼容 PC 宽屏与手机端）
class DownloadManagerPage extends StatelessWidget {
  const DownloadManagerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('下载管理器'),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: '清理已完成/失败记录',
            icon: const Icon(Icons.cleaning_services_outlined),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('清理记录'),
                  content: const Text('是否清除所有已完成和已失败的下载记录？（本地文件不会被删除）'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('取消'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('清理'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await DownloadManager.instance.clearFinishedTasks();
              }
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: DownloadManager.instance,
        builder: (context, _) {
          final tasks = DownloadManager.instance.tasks;
          if (tasks.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.download_done_rounded,
                    size: 64,
                    color: colorScheme.outline.withAlpha(100),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '暂无下载任务',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '在帖子内点击附件即可高速多线程下载',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.outline.withAlpha(180),
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            itemCount: tasks.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final task = tasks[index];
              return _DownloadTaskCard(task: task);
            },
          );
        },
      ),
    );
  }
}

class _DownloadTaskCard extends StatelessWidget {
  final DownloadTask task;
  const _DownloadTaskCard({required this.task});

  Color _badgeColor(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'zip' || 'rar' || '7z':
        return const Color(0xFFF57C00);
      case 'apk':
        return const Color(0xFF43A047);
      case 'pdf':
        return const Color(0xFFE53935);
      case 'mcpack' || 'mcaddon' || 'mcworld':
        return const Color(0xFF7CB342);
      default:
        return const Color(0xFF1E88E5);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final color = _badgeColor(task.filename);

    final isDownloading = task.status == DownloadStatus.downloading;
    final isCompleted = task.status == DownloadStatus.completed;
    final isPaused = task.status == DownloadStatus.paused;
    final isFailed = task.status == DownloadStatus.failed;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDownloading
              ? colorScheme.primary.withAlpha(120)
              : colorScheme.outlineVariant.withAlpha(60),
          width: isDownloading ? 1.2 : 0.6,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withAlpha(25),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.insert_drive_file_outlined, color: color, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: _statusColor(task.status).withAlpha(30),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            task.status.label,
                            style: TextStyle(
                              fontSize: 11,
                              color: _statusColor(task.status),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          task.sizeText,
                          style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                        ),
                        if (isDownloading && task.speed > 0) ...[
                          const SizedBox(width: 8),
                          Text(
                            task.speedText,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                        if (task.threadCount > 1) ...[
                          const Spacer(),
                          Text(
                            '${task.threadCount} 线程',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: colorScheme.outline,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (isDownloading || isPaused) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: task.totalBytes > 0 ? task.progress : null,
                minHeight: 5,
                backgroundColor: colorScheme.surfaceContainerHighest,
              ),
            ),
          ],
          if (isFailed && task.error != null) ...[
            const SizedBox(height: 6),
            Text(
              task.error!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.redAccent),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (isCompleted) ...[
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: () => DownloadManager.openFile(task.savePath),
                  icon: const Icon(Icons.open_in_new_rounded, size: 15),
                  label: const Text('打开文件'),
                ),
                const SizedBox(width: 6),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: () => DownloadManager.openFolder(task.savePath),
                  icon: const Icon(Icons.folder_open_rounded, size: 15),
                  label: const Text('打开目录'),
                ),
              ],
              if (isDownloading) ...[
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: () => DownloadManager.instance.pauseDownload(task.id),
                  icon: const Icon(Icons.pause_rounded, size: 15),
                  label: const Text('暂停'),
                ),
                const SizedBox(width: 6),
                TextButton(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: () => DownloadManager.instance.cancelDownload(task.id),
                  child: const Text('取消'),
                ),
              ],
              if (isPaused || isFailed) ...[
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: () => DownloadManager.instance.resumeDownload(task.id),
                  icon: const Icon(Icons.play_arrow_rounded, size: 15),
                  label: const Text('继续'),
                ),
              ],
              const SizedBox(width: 4),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '复制下载链接',
                icon: const Icon(Icons.copy_rounded, size: 16),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: task.url));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已复制下载链接')),
                  );
                },
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: '删除记录',
                icon: const Icon(Icons.delete_outline_rounded, size: 16),
                onPressed: () => DownloadManager.instance.deleteTask(task.id),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _statusColor(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.completed:
        return const Color(0xFF43A047);
      case DownloadStatus.downloading:
        return const Color(0xFF1E88E5);
      case DownloadStatus.paused:
        return const Color(0xFFFB8C00);
      case DownloadStatus.failed:
        return const Color(0xFFE53935);
      default:
        return const Color(0xFF757575);
    }
  }
}
