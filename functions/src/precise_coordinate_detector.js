// [deteksi-koordinat-dms]: Dukung hemisfer prefiks (S/LS/N/LU) dan sufiks agar koordinat tidak lolos filter teks.
const HEMISPHERES = String.raw`(?:N|S|E|W|LU|LS|BT|BB)`;
const DMS_CORE = String.raw`\d{1,3}\s*(?:°|º|deg(?:ree)?s?)\s*\d{1,2}(?:[.,]\d+)?\s*(?:['′’]|min(?:ute)?s?)(?:\s*\d{1,2}(?:[.,]\d+)?\s*(?:["″”]|sec(?:ond)?s?))?`;
const DMS_COMPONENT = String.raw`(?:(?:${HEMISPHERES}\s*)?[+-]?${DMS_CORE}(?:\s*${HEMISPHERES})?|[+-]?${DMS_CORE})`;

const DMS_COORDINATE_PAIR_PATTERN = new RegExp(
  String.raw`${DMS_COMPONENT}\s*(?:[,;/]|\s+)\s*${DMS_COMPONENT}`,
  'iu',
);

const SPACE_DMS_SUFFIX = String.raw`[+-]?\d{1,2}\s+\d{1,2}\s+\d{1,2}(?:[.,]\d+)?\s*${HEMISPHERES}\s*[,;/ ]+\s*[+-]?\d{1,3}\s+\d{1,2}\s+\d{1,2}(?:[.,]\d+)?\s*${HEMISPHERES}`;
const SPACE_DMS_PREFIX = String.raw`${HEMISPHERES}\s*[+-]?\d{1,2}\s+\d{1,2}\s+\d{1,2}(?:[.,]\d+)?\s*[,;/ ]+\s*${HEMISPHERES}\s*[+-]?\d{1,3}\s+\d{1,2}\s+\d{1,2}(?:[.,]\d+)?`;

const SPACE_DMS_PAIR_PATTERN = new RegExp(
  String.raw`(?:${SPACE_DMS_SUFFIX})|(?:${SPACE_DMS_PREFIX})`,
  'iu',
);

function containsDmsCoordinates(value) {
  if (typeof value !== 'string' || !value) return false;
  return DMS_COORDINATE_PAIR_PATTERN.test(value) ||
    SPACE_DMS_PAIR_PATTERN.test(value);
}

module.exports = { containsDmsCoordinates };
