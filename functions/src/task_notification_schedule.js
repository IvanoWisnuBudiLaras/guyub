const scheduleOptions = {
  region: 'asia-southeast2',
  timeZone: 'Etc/UTC',
  maxInstances: 1,
  timeoutSeconds: 120,
};

const taskWindowNotificationScheduleOptions = {
  ...scheduleOptions,
  schedule: 'every 1 minutes',
};
const lifecycleNotificationScheduleOptions = {
  ...scheduleOptions,
  schedule: 'every 5 minutes',
};

module.exports = {
  taskWindowNotificationScheduleOptions,
  lifecycleNotificationScheduleOptions,
};
