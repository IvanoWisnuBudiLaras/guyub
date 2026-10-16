// Callable responses travel as JSON, and a Date does not survive that trip:
// the Firebase serializer turns it into `{}`. A client reading a timestamp
// then gets an empty object and rejects the whole payload as malformed — which
// is exactly what happened to `createResidentSession`, making enrollment
// impossible from the app while every unit test still passed.
//
//   node --test functions/test/wire_serialization.test.js

const test = require('node:test');
const assert = require('node:assert/strict');

const { toWire } = require('../src/app');

test('a Date becomes an ISO string, not an empty object', () => {
  const when = new Date('2026-10-15T12:00:00.000Z');
  assert.equal(toWire({ expiresAt: when }).expiresAt, '2026-10-15T12:00:00.000Z');
});

test('a Date is not silently dropped from the payload', () => {
  const wire = toWire({ expiresAt: new Date(0) });
  assert.notDeepEqual(wire.expiresAt, {});
  assert.equal(typeof wire.expiresAt, 'string');
});

test('nested Dates inside arrays and objects are converted', () => {
  const wire = toWire({
    items: [{ deadline: new Date('2026-01-02T03:04:05.000Z') }],
    nested: { deep: { at: new Date('2026-06-07T08:09:10.000Z') } },
  });
  assert.equal(wire.items[0].deadline, '2026-01-02T03:04:05.000Z');
  assert.equal(wire.nested.deep.at, '2026-06-07T08:09:10.000Z');
});

test('ordinary values pass through unchanged', () => {
  const payload = { a: 1, b: 'x', c: true, d: null, e: ['y', 2] };
  assert.deepEqual(toWire(payload), payload);
});

test('a Date inside an array element is converted', () => {
  assert.deepEqual(toWire([new Date(0)]), ['1970-01-01T00:00:00.000Z']);
});

test('a non-plain object is left for the serializer', () => {
  // Firestore Timestamps and Buffers are not plain objects; rewriting them
  // here would corrupt what the Firebase serializer already knows how to
  // encode.
  class Opaque {
    constructor() {
      this.seconds = 5;
    }
  }
  const opaque = new Opaque();
  assert.equal(toWire({ t: opaque }).t, opaque);
});
