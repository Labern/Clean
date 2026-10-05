// Sunrise/sunset (NOAA approximation) so the UI can go night/day like the car.

const rad = Math.PI / 180;

function dayOfYear(d) {
  const start = Date.UTC(d.getUTCFullYear(), 0, 0);
  return Math.floor((d.getTime() - start) / 86400000);
}

// Returns { sunrise, sunset } as Date for the given day and position, or null
// at polar latitudes where the sun doesn't cross the horizon.
export function sunTimes(date, lat, lng) {
  const N = dayOfYear(date);
  const lngHour = lng / 15;
  const calc = (rising) => {
    const t = N + ((rising ? 6 : 18) - lngHour) / 24;
    const M = 0.9856 * t - 3.289;
    let L = M + 1.916 * Math.sin(M * rad) + 0.020 * Math.sin(2 * M * rad) + 282.634;
    L = ((L % 360) + 360) % 360;
    let RA = Math.atan(0.91764 * Math.tan(L * rad)) / rad;
    RA = ((RA % 360) + 360) % 360;
    RA += (Math.floor(L / 90) - Math.floor(RA / 90)) * 90;
    RA /= 15;
    const sinDec = 0.39782 * Math.sin(L * rad);
    const cosDec = Math.cos(Math.asin(sinDec));
    const cosH = (Math.cos(90.833 * rad) - sinDec * Math.sin(lat * rad)) / (cosDec * Math.cos(lat * rad));
    if (cosH > 1 || cosH < -1) return null;
    let H = rising ? 360 - Math.acos(cosH) / rad : Math.acos(cosH) / rad;
    H /= 15;
    const T = H + RA - 0.06571 * t - 6.622;
    const UT = ((T - lngHour) % 24 + 24) % 24;
    const out = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
    out.setUTCMinutes(Math.round(UT * 60));
    return out;
  };
  const sunrise = calc(true), sunset = calc(false);
  if (!sunrise || !sunset) return null;
  return { sunrise, sunset };
}

export function isNight(date, lat, lng) {
  const t = sunTimes(date, lat, lng);
  if (!t) return date.getUTCMonth() < 3 || date.getUTCMonth() > 8; // polar winter guess
  return date < t.sunrise || date > t.sunset;
}
