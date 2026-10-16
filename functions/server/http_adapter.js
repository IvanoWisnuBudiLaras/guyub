// HTTP adapter over the runtime-agnostic core in ../src/app.js.
//
// Same 46 callables, same service layer, same Firestore. Only the transport
// differs from Cloud Functions. Kept dependency-free (node:http) so the seam
// is visible and there is nothing to install.

const http = require('node:http');
const { getAuth } = require('firebase-admin/auth');
const {
  invoke,
  callableNames,
  scheduledTasks,
  scheduledTaskNames,
  toServiceError,
} = require('../src/app');

// 8787, not 8080: 8080 is the Firestore emulator's port and the adapter would
// answer for it.
const PORT = Number(process.env.PORT ?? 8787);
const MAX_BODY_BYTES = 8 * 1024 * 1024;

// gRPC status names -> HTTP status. The name travels back in the body so the
// client keeps matching on `permission-denied` rather than on a status code.
const HTTP_STATUS = {
  'invalid-argument': 400,
  'failed-precondition': 400,
  'out-of-range': 400,
  'unauthenticated': 401,
  'permission-denied': 403,
  'not-found': 404,
  'already-exists': 409,
  'aborted': 409,
  'resource-exhausted': 429,
  'cancelled': 499,
  'unimplemented': 501,
  'unavailable': 503,
  'deadline-exceeded': 504,
  'internal': 500,
};

function send(res, status, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(body),
  });
  res.end(body);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > MAX_BODY_BYTES) {
        reject(Object.assign(new Error('payload too large'), { code: 'resource-exhausted' }));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on('error', reject);
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
  });
}

// Mirrors Cloud Functions' request.auth: a verified ID token or nothing.
// Never trusts a uid sent in the body.
async function resolveAuth(req) {
  const header = req.headers.authorization;
  if (typeof header !== 'string' || !header.startsWith('Bearer ')) return undefined;
  const token = header.slice('Bearer '.length).trim();
  if (token.length === 0) return undefined;
  const decoded = await getAuth().verifyIdToken(token);
  return {
    uid: decoded.uid,
    signInProvider: decoded.firebase?.sign_in_provider,
  };
}

// The 5 scheduled jobs are declared in src/app.js so both runtimes share them.
// Here an external cron calls POST /tasks/<name> with the shared secret, in
// place of Cloud Scheduler invoking the deployed function.
function taskAuthorized(req) {
  const secret = process.env.GUYUB_TASK_SECRET;
  if (typeof secret !== 'string' || secret.length === 0) return false;
  return req.headers['x-guyub-task-secret'] === secret;
}

// App Check travels as a header, the way the Firebase SDK sends it.
function appCheckProof(req) {
  const token = req.headers['x-firebase-appcheck'];
  return typeof token === 'string' && token.trim().length > 0
    ? { token: token.trim() }
    : undefined;
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  const path = url.pathname;

  if (req.method === 'GET' && path === '/health') {
    return send(res, 200, { ok: true, callables: callableNames.length });
  }

  if (req.method !== 'POST') return send(res, 405, { error: 'method not allowed' });

  if (path.startsWith('/tasks/')) {
    if (!taskAuthorized(req)) {
      return send(res, 403, { error: { code: 'permission-denied', message: 'Ditolak.' } });
    }
    const task = scheduledTasks[path.slice('/tasks/'.length)];
    if (!task) return send(res, 404, { error: { code: 'not-found', message: 'Tidak ditemukan.' } });
    try {
      return send(res, 200, { data: await task() });
    } catch (error) {
      const mapped = toServiceError(error);
      return send(res, HTTP_STATUS[mapped.code] ?? 500, { error: mapped });
    }
  }

  const name = path.startsWith('/call/') ? path.slice('/call/'.length) : null;
  if (!name || !callableNames.includes(name)) {
    return send(res, 404, { error: { code: 'not-found', message: 'Tidak ditemukan.' } });
  }

  let raw;
  try {
    raw = await readBody(req);
  } catch (error) {
    return send(res, 413, { error: { code: 'resource-exhausted', message: 'Permintaan terlalu besar.' } });
  }

  let body;
  try {
    body = raw.length === 0 ? {} : JSON.parse(raw);
  } catch {
    return send(res, 400, { error: { code: 'invalid-argument', message: 'Format permintaan tidak valid.' } });
  }

  let auth;
  try {
    auth = await resolveAuth(req);
  } catch {
    // A bad or expired token is unauthenticated, not an internal error.
    return send(res, 401, {
      error: { code: 'unauthenticated', message: 'Sesi tidak valid. Masuk ulang.' },
    });
  }

  try {
    const data = await invoke(name, {
      data: body?.data,
      auth,
      appCheck: appCheckProof(req),
    });
    return send(res, 200, { data });
  } catch (error) {
    const mapped = toServiceError(error);
    return send(res, HTTP_STATUS[mapped.code] ?? 500, { error: mapped });
  }
});

if (require.main === module) {
  server.listen(PORT, () => {
    // eslint-disable-next-line no-console
    console.log(`guyub http adapter listening on ${PORT}`);
    // eslint-disable-next-line no-console
    console.log(`callables: ${callableNames.length}, tasks: ${scheduledTaskNames.length}`);
  });
}

module.exports = { server, HTTP_STATUS, scheduledTaskNames };
