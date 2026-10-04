import 'task_campaign.dart';

/// Voluntary choice made by a resident for an active task.
enum ParticipationChoice { join, decline }

/// Persisted participation state. There is intentionally no penalty/ranking state.
enum ParticipationState { unresponded, joined, declined }

/// Completion state; resident submission is not official completion.
enum CompletionState { notSubmitted, pendingRtVerification, verifiedComplete }

/// State for one resident's response to one community task.
///
/// These methods enforce valid domain transitions only. A production backend
/// must authenticate the participant/operator and enforce RT scope itself.
final class TaskResponse {
  const TaskResponse._({
    required this.taskId,
    required this.communityId,
    required this.residentId,
    required this.participation,
    required this.completion,
    this.completionNote,
    this.completionSubmittedAt,
    this.verifiedByOperatorId,
    this.verifiedAt,
  });

  static const int maxCompletionNoteLength = 500;

  final String taskId;
  final String communityId;
  final String residentId;
  final ParticipationState participation;
  final CompletionState completion;
  final String? completionNote;
  final DateTime? completionSubmittedAt;
  final String? verifiedByOperatorId;
  final DateTime? verifiedAt;

  factory TaskResponse.unresponded({
    required String taskId,
    required String communityId,
    required String residentId,
  }) {
    _requireText(taskId, 'taskId');
    _requireText(communityId, 'communityId');
    _requireText(residentId, 'residentId');
    return TaskResponse._(
      taskId: taskId,
      communityId: communityId,
      residentId: residentId,
      participation: ParticipationState.unresponded,
      completion: CompletionState.notSubmitted,
    );
  }

  TaskResponse chooseParticipation(
    ParticipationChoice choice, {
    required TaskCampaign campaign,
  }) {
    _validateCampaignScope(campaign, taskId, communityId);
    final nextState = switch (choice) {
      ParticipationChoice.join => ParticipationState.joined,
      ParticipationChoice.decline => ParticipationState.declined,
    };
    if (participation == nextState) return this;
    if (campaign.status != TaskCampaignStatus.active) {
      throw StateError('Participation requires an active campaign.');
    }
    if (participation != ParticipationState.unresponded) {
      throw StateError('Participation has already been recorded.');
    }
    return TaskResponse._(
      taskId: taskId,
      communityId: communityId,
      residentId: residentId,
      participation: nextState,
      completion: completion,
    );
  }

  TaskResponse submitCompletion({
    required String participantId,
    required TaskCampaign campaign,
    required DateTime submittedAt,
    String? note,
  }) {
    _requireText(participantId, 'participantId');
    if (participantId != residentId) {
      throw StateError('A participant can only update their own response.');
    }
    _validateCampaignScope(campaign, taskId, communityId);
    if (participation != ParticipationState.joined) {
      throw StateError('Only a participating resident can submit completion.');
    }
    _validateNote(note);
    final normalizedNote = _normalizeOptionalText(note);
    if (completion == CompletionState.pendingRtVerification) {
      if (completionNote == normalizedNote) return this;
      throw StateError('A pending completion cannot be overwritten.');
    }
    if (campaign.status != TaskCampaignStatus.active) {
      throw StateError('Completion requires an active campaign.');
    }
    if (completion != CompletionState.notSubmitted) {
      throw StateError('Completion has already been verified.');
    }
    return TaskResponse._(
      taskId: taskId,
      communityId: communityId,
      residentId: residentId,
      participation: participation,
      completion: CompletionState.pendingRtVerification,
      completionNote: normalizedNote,
      completionSubmittedAt: submittedAt,
    );
  }

  /// Records RT verification after the operator boundary has authorized it.
  TaskResponse verifyCompletion({
    required String operatorId,
    required String operatorCommunityId,
    required DateTime verifiedAt,
  }) {
    _requireText(operatorId, 'operatorId');
    if (operatorCommunityId != communityId) {
      throw StateError('Operator community does not match the response.');
    }
    if (completion == CompletionState.verifiedComplete) return this;
    if (completion != CompletionState.pendingRtVerification) {
      throw StateError('Only pending completion can be verified.');
    }
    return TaskResponse._(
      taskId: taskId,
      communityId: communityId,
      residentId: residentId,
      participation: participation,
      completion: CompletionState.verifiedComplete,
      completionNote: completionNote,
      completionSubmittedAt: completionSubmittedAt,
      verifiedByOperatorId: operatorId,
      verifiedAt: verifiedAt,
    );
  }
}

void _validateCampaignScope(
  TaskCampaign campaign,
  String taskId,
  String communityId,
) {
  if (campaign.id != taskId || campaign.communityId != communityId) {
    throw StateError('Campaign scope does not match this response.');
  }
}

void _requireText(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'Must not be empty.');
  }
}

void _validateNote(String? note) {
  if (note != null &&
      note.trim().length > TaskResponse.maxCompletionNoteLength) {
    throw ArgumentError.value(
      note,
      'note',
      'Must be at most ${TaskResponse.maxCompletionNoteLength} chars.',
    );
  }
}

String? _normalizeOptionalText(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}
