const COPY = Object.freeze({
  TASK_REMINDER: Object.freeze({
    title: 'Pengingat tugas persiapan',
    body: 'Tugas dari RT tersedia di aplikasi Guyub.id. Keikutsertaan sukarela; lihat detail di aplikasi.',
  }),
  TASK_ESCALATION: Object.freeze({
    title: 'Tindak lanjut tugas komunitas',
    body: 'Ada tugas persiapan yang memerlukan tinjauan administratif. Buka Guyub.id.',
  }),
  TASK_VERIFICATION_NEEDED: Object.freeze({
    title: 'Penyelesaian menunggu tinjauan RT',
    body: 'Ada penyelesaian tugas yang menunggu tinjauan RT. Buka Guyub.id.',
  }),
  TASK_ACTIVATED: Object.freeze({
    title: 'Tugas persiapan dari RT',
    body: 'Tugas baru tersedia di Guyub.id. Keikutsertaan bersifat sukarela.',
  }),
  TASK_CANCELLED: Object.freeze({
    title: 'Perubahan tugas dari RT',
    body: 'Satu tugas persiapan tidak lagi aktif. Buka Guyub.id untuk melihat statusnya.',
  }),
  TASK_CLOSED: Object.freeze({
    title: 'Perubahan tugas dari RT',
    body: 'Satu tugas persiapan telah ditutup. Buka Guyub.id untuk melihat statusnya.',
  }),
});

function notificationCopy(eventType) {
  const copy = COPY[eventType];
  if (!copy) throw new Error('Unsupported task notification event type.');
  return copy;
}

class FirebaseMessagingDeliveryAdapter {
  constructor(messaging) {
    this.messaging = messaging;
  }

  async send({ token, event }) {
    if (typeof token !== 'string' || !token || !event ||
        !/^[a-f0-9]{40}$/u.test(event.eventId || '') ||
        !/^[a-f0-9]{40}$/u.test(event.campaignId || '')) {
      throw new Error('Invalid task notification delivery request.');
    }
    const copy = notificationCopy(event.eventType);
    return this.messaging.send({
      token,
      notification: { title: copy.title, body: copy.body },
      data: {
        notificationId: event.eventId,
        eventType: event.eventType,
        taskId: event.campaignId,
      },
      android: {
        priority: 'normal',
        notification: { tag: event.eventId },
      },
      apns: { headers: { 'apns-collapse-id': event.eventId } },
      webpush: { headers: { Topic: event.eventId } },
    });
  }
}

module.exports = { FirebaseMessagingDeliveryAdapter, notificationCopy };
