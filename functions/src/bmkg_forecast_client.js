const { WeatherPipelineError, validateBmkgEndpoint } = require('./weather_suggestion_service');

const MAX_RESPONSE_BYTES = 1024 * 1024;
const REQUEST_TIMEOUT_MS = 10000;

function sourceFailure() {
  return new WeatherPipelineError('unavailable', 'Sumber prakiraan BMKG tidak tersedia.');
}

async function fetchBmkgPayload(source, {
  fetchImpl = globalThis.fetch,
  timeoutMs = REQUEST_TIMEOUT_MS,
  maxResponseBytes = MAX_RESPONSE_BYTES,
} = {}) {
  if (typeof fetchImpl !== 'function' || !Number.isInteger(timeoutMs) || timeoutMs < 1 ||
      !Number.isInteger(maxResponseBytes) || maxResponseBytes < 1) {
    throw new TypeError('BMKG fetch configuration is invalid.');
  }
  const endpoint = validateBmkgEndpoint(source?.endpoint);
  let response;
  try {
    response = await fetchImpl(endpoint, {
      method: 'GET',
      headers: { Accept: 'application/json' },
      redirect: 'error',
      signal: AbortSignal.timeout(timeoutMs),
    });
  } catch (_) {
    throw sourceFailure();
  }
  if (!response || response.ok !== true) throw sourceFailure();
  const declaredLength = Number(response.headers?.get?.('content-length'));
  if (Number.isFinite(declaredLength) && declaredLength > maxResponseBytes) {
    throw sourceFailure();
  }
  let body;
  try { body = await response.text(); } catch (_) { throw sourceFailure(); }
  if (Buffer.byteLength(body, 'utf8') > maxResponseBytes) throw sourceFailure();
  let payload;
  try { payload = JSON.parse(body); } catch (_) { throw sourceFailure(); }
  if (payload == null || typeof payload !== 'object' || Array.isArray(payload)) {
    throw sourceFailure();
  }
  return payload;
}

module.exports = { MAX_RESPONSE_BYTES, REQUEST_TIMEOUT_MS, fetchBmkgPayload };
