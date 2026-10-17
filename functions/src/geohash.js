'use strict';

const BASE32 = '0123456789bcdefghjkmnpqrstuvwxyz';

/**
 * Encodes latitude and longitude into a geohash string and returns both
 * the cell hash and the approximate center point of the bounding box.
 * Precision 7 yields cells of approximately 153m x 153m.
 *
 * @param {number} latitude - Latitude in degrees [-90, 90]
 * @param {number} longitude - Longitude in degrees [-180, 180]
 * @param {number} precision - Geohash length (default: 7)
 * @returns {{ cellId: string, approximateLat: number, approximateLng: number }}
 */
function encodeGeohash(latitude, longitude, precision = 7) {
  if (typeof latitude !== 'number' || !Number.isFinite(latitude) || latitude < -90 || latitude > 90) {
    throw new TypeError('Invalid latitude');
  }
  if (typeof longitude !== 'number' || !Number.isFinite(longitude) || longitude < -180 || longitude > 180) {
    throw new TypeError('Invalid longitude');
  }

  let isEven = true;
  let latMin = -90.0;
  let latMax = 90.0;
  let lngMin = -180.0;
  let lngMax = 180.0;
  let bit = 0;
  let ch = 0;
  let geohash = '';

  while (geohash.length < precision) {
    if (isEven) {
      const mid = (lngMin + lngMax) / 2;
      if (longitude >= mid) {
        ch |= 1 << (4 - bit);
        lngMin = mid;
      } else {
        lngMax = mid;
      }
    } else {
      const mid = (latMin + latMax) / 2;
      if (latitude >= mid) {
        ch |= 1 << (4 - bit);
        latMin = mid;
      } else {
        latMax = mid;
      }
    }

    isEven = !isEven;
    if (bit < 4) {
      bit++;
    } else {
      geohash += BASE32[ch];
      bit = 0;
      ch = 0;
    }
  }

  const approximateLat = Number(((latMin + latMax) / 2).toFixed(6));
  const approximateLng = Number(((lngMin + lngMax) / 2).toFixed(6));

  return {
    cellId: geohash,
    approximateLat,
    approximateLng,
  };
}

module.exports = {
  encodeGeohash,
};
