import 'task_template.dart';
import 'task_location_reference.dart';

/// Campaign lifecycle represented by the task domain.
enum TaskCampaignStatus { draft, active, closed, cancelled }

/// A task campaign whose historical copy of the controlled template is fixed.
///
/// [confirmAndActivate] models the explicit operator confirmation step. Its
/// identity and community checks are domain guards, not backend authorization.
/// A production repository must enforce the same command through an authorized
/// server-side boundary before making an active campaign resident-visible.
final class TaskCampaign {
  TaskCampaign._({
    required this.id,
    required this.communityId,
    required this.templateSnapshot,
    required this.createdByOperatorId,
    required this.createdAt,
    required this.deadline,
    required this.locationReference,
    required this.status,
    this.approvedByOperatorId,
    this.activatedAt,
    this.activationCommandId,
    this.closedByOperatorId,
    this.closedAt,
    this.closureCommandId,
  });

  final String id;
  final String communityId;
  final TaskTemplateSnapshot templateSnapshot;
  final String createdByOperatorId;
  final DateTime createdAt;
  final DateTime deadline;
  final String? locationReference;
  final TaskCampaignStatus status;
  final String? approvedByOperatorId;
  final DateTime? activatedAt;
  final String? activationCommandId;
  final String? closedByOperatorId;
  final DateTime? closedAt;
  final String? closureCommandId;

  factory TaskCampaign.createDraft({
    required String id,
    required String communityId,
    required TaskTemplate template,
    required String createdByOperatorId,
    required DateTime createdAt,
    required DateTime deadline,
    String? locationReference,
  }) {
    _requireText(id, 'id');
    _requireText(communityId, 'communityId');
    _requireText(createdByOperatorId, 'createdByOperatorId');
    if (!template.enabled) {
      throw ArgumentError.value(
        template.id,
        'template',
        'Template is disabled.',
      );
    }
    if (!deadline.isAfter(createdAt)) {
      throw ArgumentError.value(
        deadline,
        'deadline',
        'Must be after creation.',
      );
    }
    if (locationReference != null &&
        !TaskLocationReferences.allowed.contains(locationReference)) {
      throw ArgumentError.value(
        locationReference,
        'locationReference',
        'Must be a controlled general location reference.',
      );
    }

    return TaskCampaign._(
      id: id,
      communityId: communityId,
      templateSnapshot: template.snapshot(),
      createdByOperatorId: createdByOperatorId,
      createdAt: createdAt,
      deadline: deadline,
      locationReference: locationReference,
      status: TaskCampaignStatus.draft,
    );
  }

  /// Applies an explicit confirmation command and returns an ACTIVE campaign.
  ///
  /// The backend must independently authenticate the operator, check RT
  /// membership and validate the task template before persistence/distribution.
  TaskCampaign confirmAndActivate({
    required String operatorId,
    required String operatorCommunityId,
    required DateTime confirmedAt,
    required String commandId,
  }) {
    _requireText(operatorId, 'operatorId');
    _requireText(commandId, 'commandId');
    if (operatorCommunityId != communityId) {
      throw StateError('Operator community does not match the campaign.');
    }
    if (status == TaskCampaignStatus.active &&
        activationCommandId == commandId) {
      return this;
    }
    if (status != TaskCampaignStatus.draft) {
      throw StateError('Only a draft campaign can be activated.');
    }
    if (!deadline.isAfter(confirmedAt)) {
      throw StateError('The campaign deadline has passed.');
    }

    return TaskCampaign._(
      id: id,
      communityId: communityId,
      templateSnapshot: templateSnapshot,
      createdByOperatorId: createdByOperatorId,
      createdAt: createdAt,
      deadline: deadline,
      locationReference: locationReference,
      status: TaskCampaignStatus.active,
      approvedByOperatorId: operatorId,
      activatedAt: confirmedAt,
      activationCommandId: commandId,
    );
  }

  /// Applies an explicit same-community operator close command.
  ///
  /// Closing archives the active campaign; it does not verify resident
  /// completion. The server must independently authorize and audit the command.
  TaskCampaign close({
    required String operatorId,
    required String operatorCommunityId,
    required DateTime closedAt,
    required String commandId,
  }) {
    _requireText(operatorId, 'operatorId');
    _requireText(commandId, 'commandId');
    if (operatorCommunityId != communityId) {
      throw StateError('Operator community does not match the campaign.');
    }
    if (status == TaskCampaignStatus.closed &&
        closedByOperatorId == operatorId &&
        closureCommandId == commandId) {
      return this;
    }
    if (status != TaskCampaignStatus.active) {
      throw StateError('Only an active campaign can be closed.');
    }
    final activationTime = activatedAt;
    if (activationTime == null || closedAt.isBefore(activationTime)) {
      throw StateError('A campaign cannot close before activation.');
    }

    return TaskCampaign._(
      id: id,
      communityId: communityId,
      templateSnapshot: templateSnapshot,
      createdByOperatorId: createdByOperatorId,
      createdAt: createdAt,
      deadline: deadline,
      locationReference: locationReference,
      status: TaskCampaignStatus.closed,
      approvedByOperatorId: approvedByOperatorId,
      activatedAt: activatedAt,
      activationCommandId: activationCommandId,
      closedByOperatorId: operatorId,
      closedAt: closedAt,
      closureCommandId: commandId,
    );
  }
}

void _requireText(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'Must not be empty.');
  }
}
