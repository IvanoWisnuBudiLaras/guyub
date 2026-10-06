const test = require('node:test');
const assert = require('node:assert/strict');
const {
  taskWindowNotificationScheduleOptions,
  lifecycleNotificationScheduleOptions,
} = require('../src/task_notification_schedule');

test('deadline notification scans match the shortest supported policy window', () => {
  assert.equal(taskWindowNotificationScheduleOptions.schedule, 'every 1 minutes');
  assert.equal(lifecycleNotificationScheduleOptions.schedule, 'every 5 minutes');
});
