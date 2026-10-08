const test = require('node:test');
const assert = require('node:assert/strict');
const { fetchBmkgPayload } = require('../src/bmkg_forecast_client');

const SOURCE = {
  endpoint: 'https://api.bmkg.go.id/publik/prakiraan-cuaca?adm4=31.71.01.1001',
};

function response(body, { status = 200, headers = {} } = {}) {
  return {
    ok: status >= 200 && status < 300,
    headers: new Headers(headers),
    text: async () => body,
  };
}

test('BMKG client uses a read-only HTTPS request and rejects redirects', async () => {
  let requested;
  const result = await fetchBmkgPayload(SOURCE, {
    fetchImpl: async (url, options) => {
      requested = { url, options };
      return response('{"data":[]}');
    },
  });
  assert.deepEqual(result, { data: [] });
  assert.equal(requested.url, SOURCE.endpoint);
  assert.equal(requested.options.method, 'GET');
  assert.equal(requested.options.redirect, 'error');
  assert.equal(requested.options.headers.Accept, 'application/json');
});

test('BMKG client rejects non-success responses, invalid JSON, and oversized responses', async () => {
  await assert.rejects(fetchBmkgPayload(SOURCE, {
    fetchImpl: async () => response('service unavailable', { status: 503 }),
  }), { code: 'unavailable' });
  await assert.rejects(fetchBmkgPayload(SOURCE, {
    fetchImpl: async () => response('<html>bad</html>'),
  }), { code: 'unavailable' });
  await assert.rejects(fetchBmkgPayload(SOURCE, {
    fetchImpl: async () => response('123456', { headers: { 'content-length': '6' } }),
    maxResponseBytes: 5,
  }), { code: 'unavailable' });
});

test('BMKG client rejects non-BMKG hosts, endpoints, and invalid location codes', async () => {
  for (const endpoint of [
    'http://api.bmkg.go.id/publik/prakiraan-cuaca?adm4=31.71.01.1001',
    'https://example.invalid/publik/prakiraan-cuaca?adm4=31.71.01.1001',
    'https://api.bmkg.go.id/other?adm4=31.71.01.1001',
    'https://api.bmkg.go.id/publik/prakiraan-cuaca?adm4=not-an-area',
    'https://user:password@api.bmkg.go.id/publik/prakiraan-cuaca?adm4=31.71.01.1001',
  ]) {
    await assert.rejects(fetchBmkgPayload({ endpoint }, {
      fetchImpl: async () => { throw new Error('must not fetch'); },
    }), { code: 'failed-precondition' });
  }
});
