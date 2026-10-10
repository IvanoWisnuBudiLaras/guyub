// [deteksi-koordinat]: Dukung koordinat DMS, desimal berhemisfer (prefiks/sufiks), koma/titik desimal, dan koordinat berlabel.
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

const DECIMAL_DEGREE_WITH_HEMISPHERE = new RegExp(
  String.raw`(?:[+-]?\d{1,3}(?:[.,]\d+)?(?:°|º)?\s*${HEMISPHERES}\s*[,;/ ]+\s*[+-]?\d{1,3}(?:[.,]\d+)?(?:°|º)?\s*${HEMISPHERES})|` +
  String.raw`(?:${HEMISPHERES}\s*[+-]?\d{1,3}(?:[.,]\d+)?(?:°|º)?\s*[,;/ ]+\s*${HEMISPHERES}\s*[+-]?\d{1,3}(?:[.,]\d+)?(?:°|º)?)`,
  'iu',
);

const DECIMAL_COORDINATE_PAIR = /(?<![\d.,])\(?[+-]?\d{1,3}[.,]\d+\)?\s*(?:[,;/]|\s)\s*\(?[+-]?\d{1,3}[.,]\d+\)?(?![\d.,])/iu;

const LABELED_COORDINATE = /\b(?:lat(?:itude)?|lon(?:gitude)?|gps|koordinat(?:e)?)\s*[:=]?\s*[+-]?\d{1,3}(?:[.,]\d+)?\b/iu;

const NIK_PATTERN = /(?<!\d)(?:\d[\s().\/_,-]*){15}\d(?!\d)/u;

function containsPreciseCoordinates(value) {
  if (typeof value !== 'string' || !value) return false;
  return DMS_COORDINATE_PAIR_PATTERN.test(value) ||
    SPACE_DMS_PAIR_PATTERN.test(value) ||
    DECIMAL_DEGREE_WITH_HEMISPHERE.test(value) ||
    DECIMAL_COORDINATE_PAIR.test(value) ||
    LABELED_COORDINATE.test(value);
}

function containsDmsCoordinates(value) {
  return containsPreciseCoordinates(value);
}

function containsNik(value) {
  if (typeof value !== 'string' || !value) return false;
  return NIK_PATTERN.test(value);
}

module.exports = {
  containsDmsCoordinates,
  containsPreciseCoordinates,
  containsNik,
  NIK_PATTERN,
  DECIMAL_COORDINATE_PAIR,
  LABELED_COORDINATE,
};
