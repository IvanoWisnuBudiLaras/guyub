import 'package:flutter/material.dart';

import '../../application/task_template.dart';

/// Prominent display of reviewed instructions; this widget has no edit inputs.
final class LockedTaskInstructionsCard extends StatelessWidget {
  const LockedTaskInstructionsCard({required this.snapshot, super.key});

  final TaskTemplateSnapshot snapshot;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_outline),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Instruksi template terkunci',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(snapshot.coreInstruction),
          const SizedBox(height: 12),
          Text(
            'KESELAMATAN',
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            snapshot.safetyInstruction,
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );
}
