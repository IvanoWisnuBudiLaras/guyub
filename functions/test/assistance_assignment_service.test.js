const test = require('node:test');
const assert = require('node:assert/strict');
const { AssistanceAssignmentService } = require('../src/assistance_assignment_service');

const RESIDENT = 'a'.repeat(40);
const HELPER = 'b'.repeat(40);
const ASSIGNMENT = 'c'.repeat(40);
const COMMAND = 'command-id-123456789012345678901234567890';
const OPERATOR = { operatorUid: 'operator-a', signInProvider: 'password' };
const SESSION = { residentId: HELPER, communityId: 'rt-a' };

class FakeSessions {
  async validateSession(token) {
    if (token !== 'valid-resident-token-1234567890123456') {
      const error = new Error('invalid session');
      error.code = 'permission-denied';
      throw error;
    }
    return SESSION;
  }
}
class FakeRepository {
  calls = [];
  async getVolunteerData(input) { this.calls.push(['get', input]); return { willingToHelp: false, assignments: [], isPartial: false }; }
  async updateVolunteerConsent(input) { this.calls.push(['consent', input]); return { willingToHelp: input.willingToHelp }; }
  async listVolunteerHelpers(input) { this.calls.push(['helpers', input]); return { items: [], isPartial: false }; }
  async createHelperAssignment(input) { this.calls.push(['assign', input]); return { assignmentId: ASSIGNMENT, state: 'OFFERED' }; }
  async respondToHelperAssignment(input) { this.calls.push(['respond', input]); return { assignmentId: input.assignmentId, state: input.decision }; }
}

test('helper opt-in and assignment require narrow, consent-attested requests', async () => {
  const repository = new FakeRepository();
  const service = new AssistanceAssignmentService(repository, new FakeSessions());
  await assert.rejects(service.updateVolunteerConsent({
    sessionToken: 'valid-resident-token-1234567890123456',
    willingToHelp: true, residentConsentConfirmed: false, commandId: COMMAND,
  }), { code: 'failed-precondition' });
  await assert.rejects(service.createHelperAssignment(OPERATOR, {
    residentId: RESIDENT, helperResidentId: HELPER, commandId: COMMAND, rtId: 'rt-b',
  }), { code: 'invalid-argument' });
  await assert.rejects(service.createHelperAssignment({
    ...OPERATOR, signInProvider: 'anonymous',
  }, { residentId: RESIDENT, helperResidentId: HELPER, commandId: COMMAND }), {
    code: 'permission-denied',
  });
  assert.equal(repository.calls.length, 0);
});

test('helper APIs scope through a validated resident session and hash command IDs', async () => {
  const repository = new FakeRepository();
  const service = new AssistanceAssignmentService(repository, new FakeSessions(), {
    clock: () => new Date(0),
  });
  const token = 'valid-resident-token-1234567890123456';
  await service.getVolunteerData({ sessionToken: token });
  const consent = await service.updateVolunteerConsent({
    sessionToken: token, willingToHelp: true,
    residentConsentConfirmed: true, commandId: COMMAND,
  });
  assert.equal(consent.willingToHelp, true);
  const assigned = await service.createHelperAssignment(OPERATOR, {
    residentId: RESIDENT, helperResidentId: HELPER, commandId: COMMAND,
  });
  assert.equal(assigned.state, 'OFFERED');
  const response = await service.respondToHelperAssignment({
    sessionToken: token, assignmentId: ASSIGNMENT, decision: 'DECLINED',
    residentConsentConfirmed: true, commandId: COMMAND,
  });
  assert.equal(response.state, 'DECLINED');
  assert.equal(repository.calls.find(([name]) => name === 'consent')[1].rtId, 'rt-a');
  assert.equal(repository.calls.find(([name]) => name === 'assign')[1].rtId, undefined);
  assert.notEqual(repository.calls.find(([name]) => name === 'assign')[1].commandHash, COMMAND);
});
