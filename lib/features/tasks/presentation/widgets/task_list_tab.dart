import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../application/task_response.dart';
import '../../application/task_response_boundary.dart';
import 'task_card.dart';

/// Tab Daftar Tugas
class TaskListTab extends StatelessWidget {
  const TaskListTab({
    required this.taskList,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.onTaskTap,
    this.onTaskJoin,
    super.key,
  });

  final ResidentTaskList? taskList;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final void Function(ResidentTaskRecord) onTaskTap;
  final void Function(ResidentTaskRecord)? onTaskJoin;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: context.appColors.danger,
              ),
              const SizedBox(height: 16),
              Text(
                error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.appColors.danger),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Coba Lagi'),
              ),
            ],
          ),
        ),
      );
    }

    final tasks = taskList?.items ?? [];

    if (tasks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 64,
                color: context.appColors.textSecondary.withOpacity(0.5),
              ),
              const SizedBox(height: 16),
              Text(
                'Belum Ada Tugas Aktif',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Tugas kesiapsiagaan dari RT Anda akan muncul di sini.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: context.appColors.textSecondary,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: tasks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final task = tasks[index];
        return TaskCard(
          task: task,
          onTap: () => onTaskTap(task),
          onJoin: task.participation == ParticipationState.unresponded && onTaskJoin != null
              ? () => onTaskJoin!(task)
              : null,
        );
      },
    );
  }
}
