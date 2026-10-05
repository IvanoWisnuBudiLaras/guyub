const crypto = require('node:crypto');
const { TaskNotificationError, validateToken } = require('./firestore_task_notification_repository');
const { TaskCampaignError } = require('./task_campaign_service');
const { cohortMatches, toDate } = require('./task_notification_policy');
const { tokenDocumentId } = require('./task_notification_id');
const { hashSessionToken } = require('./resident_session_service');

const TASK_ID_PATTERN = /^[a-f0-9]{40}$/u;

function onlyKeys(value, allowed) {
  if (!value || typeof value !== 'object' || Array.isArray(value) ||
      Object.keys(value).some((key) => !allowed.includes(key))) {
    throw new TaskNotificationError('invalid-argument', 'Permintaan notifikasi tidak valid.');
  }
}
function requirePasswordOperator(auth) {
  if (typeof auth?.operatorUid !== 'string' || !auth.operatorUid.trim() ||
      auth.signInProvider !== 'password') {
    throw new TaskNotificationError('permission-denied', 'Akses operator tidak valid.');
  }
}
function due(now, deadline, offsetMinutes) {
  const deadlineDate = toDate(deadline);
  if (!deadlineDate || now >= deadlineDate) return false;
  return now.getTime() >= deadlineDate.getTime() - offsetMinutes * 60_000;
}
function errorCode(error) {
  const code = typeof error?.code === 'string' ? error.code : '';
  if (code === 'messaging/registration-token-not-registered' ||
      code === 'messaging/invalid-registration-token') return code;
  return 'delivery-failed';
}

class TaskNotificationService {
  constructor(repository, delivery, sessions, options = {}) {
    this.repository = repository;
    this.delivery = delivery;
    this.sessions = sessions;
    this.clock = options.clock ?? (() => new Date());
    this.idFactory = options.idFactory ?? (() => crypto.randomUUID());
  }

  async sendTaskReminders(options = {}) {
    const now = options.now ?? this.clock();
    const policies = await this.repository.listEnabledPolicies();
    let scheduled = 0;
    for (const policy of policies) {
      let campaigns;
      try {
        campaigns = await this.repository.listActiveCampaigns(policy.rtId);
      } catch (error) {
        this._warn('reminder-campaign-scan-failed', policy.rtId, error);
        continue;
      }
      for (const campaign of campaigns) {
        if (campaign.notificationPolicyDocumentId !== policy.policyDocumentId ||
            campaign.notificationPolicyVersion !== policy.version ||
            campaign.notificationPolicyFingerprint !== policy.fingerprint ||
            !toDate(campaign.deadline) || toDate(campaign.deadline) <= now) continue;
        const dueWindows = policy.reminderWindows.filter((window) =>
          due(now, campaign.deadline, window.minutesBeforeDeadline));
        if (dueWindows.length === 0) continue;
        let residents;
        try {
          residents = await this.repository.listResidentStates(policy.rtId, campaign.campaignId);
        } catch (error) {
          this._warn('reminder-resident-scan-failed', policy.rtId, error);
          continue;
        }
        for (const window of dueWindows) {
          for (const resident of residents) {
            if (!resident.valid || !cohortMatches(window.cohort, resident.response)) continue;
            const result = await this.repository.createReminderEvent({
              rtId: policy.rtId,
              campaignId: campaign.campaignId,
              policy,
              window,
              residentId: resident.residentId,
              recipientHash: resident.recipientHash,
              now,
            });
            if (result.created) scheduled += 1;
          }
        }
      }
    }
    const delivery = await this._dispatchDue('TASK_REMINDER', now);
    return { scheduled, ...delivery };
  }

  async escalateUnrespondedTasks(options = {}) {
    const now = options.now ?? this.clock();
    const policies = await this.repository.listEnabledPolicies();
    let scheduled = 0;
    for (const policy of policies) {
      if (!policy.escalation.enabled) continue;
      let campaigns;
      try {
        campaigns = await this.repository.listActiveCampaigns(policy.rtId);
      } catch (error) {
        this._warn('escalation-campaign-scan-failed', policy.rtId, error);
        continue;
      }
      for (const campaign of campaigns) {
        const rule = policy.escalation;
        if (campaign.notificationPolicyDocumentId !== policy.policyDocumentId ||
            campaign.notificationPolicyVersion !== policy.version ||
            campaign.notificationPolicyFingerprint !== policy.fingerprint ||
            !due(now, campaign.deadline, rule.minutesBeforeDeadline)) continue;
        let residents;
        try {
          residents = await this.repository.listResidentStates(policy.rtId, campaign.campaignId);
        } catch (error) {
          this._warn('escalation-resident-scan-failed', policy.rtId, error);
          continue;
        }
        const eligibleCount = residents.filter((resident) => resident.valid &&
          cohortMatches(rule.cohort, resident.response)).length;
        if (eligibleCount < rule.minimumCohortSize) continue;
        const result = await this.repository.createEscalationEvent({
          rtId: policy.rtId,
          campaignId: campaign.campaignId,
          policy,
          escalation: rule,
          now,
        });
        if (result.created) scheduled += 1;
      }
    }
    const delivery = await this._dispatchDue('TASK_ESCALATION', now);
    return { scheduled, ...delivery };
  }

  async registerResidentPushToken(data) {
    onlyKeys(data, ['sessionToken', 'token', 'platform']);
    const session = await this.sessions.validateSession(data.sessionToken);
    const token = validateToken(data.token);
    if (data.platform !== 'ANDROID') {
      throw new TaskNotificationError('invalid-argument', 'Platform perangkat tidak didukung.');
    }
    await this.repository.registerResidentToken({
      token,
      tokenId: tokenDocumentId(token),
      platform: data.platform,
      sessionIdHash: hashSessionToken(data.sessionToken),
      residentId: session.residentId,
      rtId: session.communityId,
      now: this.clock(),
    });
    return { registered: true };
  }

  async unregisterResidentPushToken(data) {
    onlyKeys(data, ['sessionToken', 'token']);
    const session = await this.sessions.validateSession(data.sessionToken);
    const token = validateToken(data.token);
    await this.repository.unregisterResidentToken({
      tokenId: tokenDocumentId(token),
      sessionIdHash: hashSessionToken(data.sessionToken),
      residentId: session.residentId,
      rtId: session.communityId,
      now: this.clock(),
    });
    return { unregistered: true };
  }

  async registerPendampingPushToken(auth, data) {
    requirePasswordOperator(auth);
    onlyKeys(data, ['token', 'platform']);
    const token = validateToken(data.token);
    if (data.platform !== 'ANDROID') {
      throw new TaskNotificationError('invalid-argument', 'Platform perangkat tidak didukung.');
    }
    await this.repository.registerOperatorToken({
      operatorUid: auth.operatorUid,
      token,
      tokenId: tokenDocumentId(token),
      platform: data.platform,
      now: this.clock(),
    });
    return { registered: true };
  }

  async unregisterPendampingPushToken(auth, data) {
    requirePasswordOperator(auth);
    onlyKeys(data, ['token']);
    const token = validateToken(data.token);
    await this.repository.unregisterOperatorToken({
      operatorUid: auth.operatorUid,
      tokenId: tokenDocumentId(token),
      now: this.clock(),
    });
    return { unregistered: true };
  }

  async listAuditEvents(auth, data) {
    requirePasswordOperator(auth);
    onlyKeys(data, ['campaignId']);
    if (typeof data.campaignId !== 'string' || !TASK_ID_PATTERN.test(data.campaignId)) {
      throw new TaskNotificationError('invalid-argument', 'Identitas tugas tidak valid.');
    }
    const events = await this.repository.listAuditEvents({
      operatorUid: auth.operatorUid,
      campaignId: data.campaignId,
    });
    return { events };
  }

  async _dispatchDue(eventType, now) {
    const dueEvents = await this.repository.listDueEvents(eventType, now);
    let delivered = 0;
    let failed = 0;
    let skipped = 0;
    for (const candidate of dueEvents) {
      const leaseId = this.idFactory();
      const event = await this.repository.claimEvent({
        eventId: candidate.eventId,
        eventType,
        now,
        leaseId,
      });
      if (!event) continue;
      const resolution = await this.repository.resolveDeliveryTargets(event, now);
      if (!resolution.valid) {
        await this.repository.markEventSkipped({
          eventId: event.eventId, leaseId, now, reason: 'no-longer-eligible',
        });
        skipped += 1;
        continue;
      }
      if (resolution.targets.length === 0) {
        await this.repository.markEventAttemptFailed({
          eventId: event.eventId, leaseId, now, errorCode: 'recipient-unavailable',
        });
        failed += 1;
        continue;
      }
      let accepted = 0;
      let failedCode = 'delivery-failed';
      await Promise.all(resolution.targets.map(async (target) => {
        try {
          await this.delivery.send({ token: target.token, event });
          accepted += 1;
        } catch (error) {
          const code = errorCode(error);
          failedCode = code;
          if (code.startsWith('messaging/')) {
            await this.repository.disableToken(target.tokenKind, target.tokenId, now);
          }
        }
      }));
      if (accepted > 0) {
        await this.repository.markEventSent({ eventId: event.eventId, leaseId, now });
        delivered += 1;
      } else {
        await this.repository.markEventAttemptFailed({
          eventId: event.eventId, leaseId, now, errorCode: failedCode,
        });
        failed += 1;
      }
    }
    return { delivered, failed, skipped };
  }

  _warn(code, rtId, error) {
    const safeCode = error instanceof TaskNotificationError || error instanceof TaskCampaignError
      ? error.code : 'internal';
    console.warn('Task notification scan deferred.', { code, rtId, errorCode: safeCode });
  }
}

module.exports = { TaskNotificationService, due };
