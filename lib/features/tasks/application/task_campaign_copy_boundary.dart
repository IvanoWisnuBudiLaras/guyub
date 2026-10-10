/// Platform boundary for copying a reviewed, active task summary.
abstract interface class TaskCampaignCopyBoundary {
  Future<void> copy(String text);
}
